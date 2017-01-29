
## **NESM** is a tool that generates serialization and deserialization
## code for a given object. This library provides a macro called
## `serializable` inside which
## the object description should be placed.
##
## For example:
##
## .. code-block:: nim
##   serializable:
##     type Ball = object
##       weight: float32
##       diameter: int32
##       isHollow: bool
##
## In this example you could notice that `int32` and `float32`
## declarations are used
## instead of just `int` and `float`. It is necessary to avoid
## an ambiguity in
## declarations on different platforms.
##
## The code in example will be transformed into the following code
## (the resulting
## code can be seen when **-d:debug** is passed to Nim compiler):
##
## .. code-block:: nim
##  type
##    Ball = object
##      weight: float32
##      diameter: int32
##      isHollow: bool
##
##  proc size(obj: Ball): int =
##    result += 4
##    result += 4
##    result += 1
##    result += 0
##
##  proc serialize(obj: Ball; writer: proc (a: pointer; s: Natural)) =
##    writer(obj.weight.unsafeAddr, 4)
##    writer(obj.diameter.unsafeAddr, 4)
##    writer(obj.isHollow.unsafeAddr, 1)
##
##  proc serialize(obj: Ball): seq[byte] =
##    var index: uint = 0
##    result = newSeq[byte](obj.size())
##    let r_ptr = cast[uint](result[0].unsafeAddr)
##    var writer = proc (a: pointer; size: Natural) =
##      copyMem(cast[pointer](r_ptr + index), a, size)
##      index += size
##    serialize(obj, writer)
##
##  proc deserialize(thetype: typedesc[Ball]; obtain: proc (count: Natural): (
##      seq[byte | int8 | uint8 | char] | string)): Ball =
##    block:
##        let thedata = obtain(4)
##        assert(len(thedata) == 4, "The length of received data is not equal to 4, but equal to " &
##            $ len(thedata))
##        copyMem(result.weight.unsafeAddr, thedata[0].unsafeAddr, 4)
##    block:
##        let thedata = obtain(4)
##        assert(len(thedata) == 4, "The length of received data is not equal to 4, but equal to " &
##            $ len(thedata))
##        copyMem(result.diameter.unsafeAddr, thedata[0].unsafeAddr, 4)
##    block:
##        let thedata = obtain(1)
##        assert(len(thedata) == 1, "The length of received data is not equal to 1, but equal to " &
##            $ len(thedata))
##        copyMem(result.isHollow.unsafeAddr, thedata[0].unsafeAddr, 1)
##
## As you may see from the code above, the macro generates three kinds
## of procedures: serializer, deserializer and size estimator.
## The serialization is being performing in a following way:
## each memory region of variable is copied
## to the resulting array back-to-back. This approach achieves both
## of smallest
## serialized object size and independence from the compilator
## specific object
## representation.
##
## At the moment the following types of object are supported:
## - Aliases from basic types or previously defined in this block:
##     .. code-block:: nim
##       type MyInt = int16
##
## - Distinct types from basic types or previously defined in this block:
##     .. code-block:: nim
##       type MyInt = distinct int16
##
## - Tuples, objects and arrays:
##     .. code-block:: nim
##       type MyTuple = tuple[a: float64, b: int64]
##
## - Nested objects defined in *serializable* block:
##     .. code-block:: nim
##       type MyNestedObject = object
##         a: float64
##         b: int64
##       type MyObject = object
##         a: float32
##         b: MyNestedObject
##
## - Nested arrays and tuples:
##     .. code-block:: nim
##       type Matrix = array[0..4, array[0..4, int32]]
##
## - Sequencies and strings:
##     .. code-block:: nim
##       type MySeq = object
##         data: seq[string]
##
## - Null terminated strings (3-byte smaller but slower than strings):
##     .. code-block:: nim
##       type NTString = cstring
##
## - Object variants with nested case statements:
##     .. code-block:: nim
##       type Variant = object
##         case has_sign: bool
##         of true:
##           a: int32
##         else:
##           case bits: uint8
##           of 32:
##             b: uint32
##           of 16:
##             c: uint16
##           else:
##             d: seq[uint8]
##
## Static types
## ------------
##
## There is also a special keyword exists for structures which size
## is known at compile time. The type declarations placed under the
## `static` section inside the `serializable` section will get
## three key differences from the regular declarations:
##
## - the `size` procedure will be receiving typedesc parameter
##   instead of instance of the
##   object and can be used at compile time
##
## - a new `deserialize` procedure will be generated that receives
##   a data containers (like a seq[byte] or a string) in addition
##   to receiver closure procedure.
##
## - any dynamic structures like sequencies or strings will lead
##   to compile time errors (because their size can not be
##   estimated at compile time)
##
## The example above with `static` section will be look like:
##
## .. code-block:: nim
##   serializable:
##     static :
##         type
##           Ball = object
##             weight: float32
##             diameter: int32
##             isHollow: bool
##
## And the differeces will occur in following procedures:
##
## .. code-block:: nim
##   proc size(thetype: typedesc[Ball]): int =
##     (0 + 4 + 4 + 1)
##   
##   proc deserialize(thetype: typedesc[Ball];
##                     data: seq[byte | char | int8 | uint8] | string): Ball =
##       let datalen = data.len
##       assert(datalen >= type(result).size(),
##              "Given sequence should contain at least type(result) bytes!")
##       var index = 0
##       proc obtain(count: Natural): seq[byte] =
##         let lastindex = if index + count < datalen: index + count else: datalen
##         result = cast[seq[byte]](data[index ..< lastindex])
##         index = lastindex
##       result = deserialize(type(result), obtain)
##
##  Future ideas
## -------------
## The following will not necessarily be done but may be
## realized on demand
## * the data aligning support
##   (useful for reading custom data, not created by
##   this macro. can be partially done at client side
##   via modification of writer/obtainer)
## * implement some dynamic dictonary type
##   (not required actually because it can be
##   easily implemented on client side)
##

when defined(js):
  error("Non C-like targets non supported yet.")

import macros
when not defined(nimdoc):
  from typesinfo import TypeChunk, Context
  from generator import genTypeChunk, STREAM_NAME
else:
  import endians
  type TypeChunk = object

from strutils import `%`
from sequtils import toSeq
from tables import Table, initTable, contains, `[]`, `[]=`
from streams import Stream, newStringStream
const SERIALIZER_INPUT_NAME = "obj"
const DESERIALIZER_DATA_NAME = "data"
const SERIALIZE_DECLARATION = """proc serialize$1(""" &
  SERIALIZER_INPUT_NAME & """: $2): string = discard"""
const DESERIALIZE_DECLARATION = """proc deserialize$1""" &
  """(thetype: typedesc[$2], """ & DESERIALIZER_DATA_NAME &
  """: seq[byte | char | int8 | uint8] | string):""" &
  """$2 = discard"""

when not defined(nimdoc):
  proc makeSerializeStreamDeclaration(typename: string,
      is_exported: bool,
      body: seq[NimNode]): NimNode {.compileTime.} =
    let itn = !typename
    let fname =
      if is_exported: newIdentNode("serialize").postfix("*")
      else: newIdentNode("serialize")
    let isin = !SERIALIZER_INPUT_NAME
    let thebody = newStmtList(body)
    quote do:
      proc `fname`(`isin`: `itn`,
                   `STREAM_NAME`: Stream) = `thebody`

  proc makeDeserializeStreamDeclaration(typename: string,
      is_exported: bool,
      body: seq[NimNode]): NimNode {.compileTime.} =
    let itn = !typename
    let fname =
      if is_exported:
        newIdentNode("deserialize").postfix("*")
      else: newIdentNode("deserialize")
    let thebody = newStmtList(body)
    quote do:
      proc `fname`(thetype: typedesc[`itn`],
                   `STREAM_NAME`: Stream): `itn` = `thebody`

proc makeSerializeStreamConversion(): NimNode {.compileTime.} =
  let isin = !SERIALIZER_INPUT_NAME
  quote do:
    let ss = newStringStream()
    serialize(`isin`, ss)
    ss.data

proc makeDeserializeStreamConversion(name: string
    ): NimNode {.compileTime.} =
  let iname = !name
  let ddn = !DESERIALIZER_DATA_NAME
  quote do:
    assert(`ddn`.len >= type(`iname`).size(),
           "Given sequence should contain at least " &
           $(type(`iname`).size()) & " bytes!")
    let ss = newStringStream(cast[string](`ddn`))
    deserialize(type(`iname`), ss)

const STATIC_SIZE_DECLARATION =
  """proc size$1(thetype: typedesc[$2]): int = discard"""
const SIZE_DECLARATION = "proc size$1(" &
                         SERIALIZER_INPUT_NAME &
                         ": $2): int = discard"


when not defined(nimdoc):
  static:
    var ctx: Context
    ctx.declared = initTable[string, TypeChunk]()
  proc generateProc(pattern: string, name: string,
                    sign: string,
                    body: seq[NimNode] = @[]): NimNode =
    result = parseExpr(pattern % [sign, name])
    if len(body) > 0:
      result.body = newStmtList(body)

when not defined(nimdoc):
  proc generateProcs(context: var Context,
                     obj: NimNode): NimNode {.compileTime.} =
    expectKind(obj, nnkTypeDef)
    expectMinLen(obj, 3)
    expectKind(obj[1], nnkEmpty)
    let typename = obj[0]
    let name = $typename.basename
    let is_shared = typename.kind == nnkPostfix
    let sign =
      if is_shared: "*"
      else: ""
    let body = obj[2]
    let info = context.genTypeChunk(body)
    let size_node = info.size(SERIALIZER_INPUT_NAME)
    let size_arg =
      if context.is_static: "type($1)"
      else: "$1"
    context.declared[name] = info
    let writer_conversion =
      @[makeSerializeStreamConversion()]
    let serializer = generateProc(SERIALIZE_DECLARATION,
                                  name, sign,
                                  writer_conversion)
    let serialize_stream =
      makeSerializeStreamDeclaration(name, is_shared,
        info.serialize(SERIALIZER_INPUT_NAME))
    let obtainer_conversion =
      if context.is_static:
        @[makeDeserializeStreamConversion("result")]
      else: @[]
    let deserializer =
      if context.is_static:
        generateProc(DESERIALIZE_DECLARATION, name, sign,
                     obtainer_conversion)
      else: newEmptyNode()
    let deserialize_stream =
      makeDeserializeStreamDeclaration(name, is_shared,
      info.deserialize("result"))
    let size_declaration =
      if context.is_static: STATIC_SIZE_DECLARATION
      else: SIZE_DECLARATION
    let sizeProc = generateProc(size_declaration, name, sign,
                                @[size_node])
    newStmtList(sizeProc, serialize_stream, serializer,
                deserialize_stream, deserializer)

  proc prepare(context: var Context, statements: NimNode
               ): NimNode {.compileTime.} =
    result = newStmtList()
    case statements.kind
    of nnkStmtList, nnkTypeSection, nnkStaticStmt:
      let oldstatic = context.is_static
      context.is_static = context.is_static or
        (statements.kind == nnkStaticStmt)
      for child in statements.children():
        result.add(context.prepare(child))
      context.is_static = oldstatic
    of nnkTypeDef:
      result.add(context.generateProcs(statements))
    else:
      error("Only type declarations can be serializable")

proc cleanupTypeDeclaration(declaration: NimNode): NimNode =
  var children = newSeq[NimNode]()
  let settingsKeyword = newIdentNode("set").postfix("!")
  if declaration.len == 0:
    return declaration
  for c in declaration.children():
    case c.kind
    of nnkStaticStmt:
      for cc in c.children():
        children.add(cleanupTypeDeclaration(cc))
    of nnkIdentDefs:
      if c[^2].repr == "cstring":
        var newID = newNimNode(nnkIdentDefs)
        copyChildrenTo(c, newID)
        newID[^2] = newIdentNode("string")
        children.add(newID)
      elif c[0] == settingsKeyword:
        continue
      else:
        children.add(c)
    else:
      children.add(cleanupTypeDeclaration(c))
  newTree(declaration.kind, children)

macro serializable*(typedecl: untyped): untyped =
  ## The main macro that generates code.
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   serializable:
  ##     # Type declaration
  ##
  result = cleanupTypeDeclaration(typedecl)
  when defined(debug):
    hint(typedecl.treeRepr)
  when not defined(nimdoc):
    result.add(ctx.prepare(typedecl))
  when defined(debug):
    hint(result.repr)

when defined(nimdoc):
  type TheType* = object
    ## This type will be used as example to show which procedures will be generated
    ## by the **serializable** macro.
  proc size*(q: typedesc[TheType]): int =
    ## Returns the size of serialized type. The type should be
    ## placed under the **static** section inside the
    ## **serializable** macro to access this procedure.
    ## The procedure could be used
    ## at compile time.
    0

  proc size*(q: TheType): int =
    ## Returns the size of serialized type. Available for types
    ## which declarations is not placed under the **static**
    ## section.
    discard

  proc serialize*(obj: TheType;
                 writer: proc (a: pointer; s: Natural)) =
    ## Serializes `TheType` and writes result using given
    ## `writer` procedure.
    ## The `writer` procedure should receive two arguments:
    ## a pointer with data to be written and the size of
    ## data to be written. The macro garantees that in
    ## memory between pointer and (pointer+size) will
    ## be placed readable data. Trying to read any other
    ## data around or attempts to write data at this location
    ## may lead to segmentation fault.
    discard

  proc serialize*(obj: TheType): seq[byte] =
    ## Serializes `TheType` to seq of bytes.
    ## More detailed description can be found
    ## in top level documentation.
    discard

  proc deserialize*(q: typedesc[TheType],
    obtain: proc (count: Natural): (
      seq[byte | int8 | uint8 | char] | string)): TheType
    {.raises: AssertionError.} =
    ## Interprets the data received by calling the `obtain` procedure
    ## as `TheType` and deserializes it then.
    ## The `obtain` procedure should receive one argument: the
    ## count of bytes to be deserialized and return the sequence
    ## or string with given length. When the `obtain` procedure
    ## will return anything other than expected, an `AssertionError`
    ## will be raised.
    discard
  proc deserialize*(q: typedesc[TheType],
    data: string | seq[byte | char | int8 | uint8]): TheType
    {.raises: AssertionError.} =
    ## Interprets given data as serialized `TheType` and
    ## deserializes it then. Only available for types which
    ## declarations are placed under the **static** section.
    ## When the `data` size is lesser than `TheType.size`,
    ## the AssertionError will be raised.
    discard
