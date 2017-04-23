
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
##  proc serialize(obj: Ball; thestream: Stream) =
##     discard
##     thestream.writeData(obj.weight.unsafeAddr, 4)
##     thestream.writeData(obj.diameter.unsafeAddr, 4)
##     thestream.writeData(obj.isHollow.unsafeAddr, 1)
##
##   proc serialize(obj: Ball): string =
##     let ss142002 = newStringStream()
##     serialize(obj, ss142002)
##     ss142002.data
##
##   proc deserialize(thetype142004: typedesc[Ball]; thestream: Stream): Ball =
##     discard
##     assert(4 ==
##         thestream.readData(result.weight.unsafeAddr, 4),
##            "Stream was not provided enough data")
##     assert(4 ==
##         thestream.readData(result.diameter.unsafeAddr, 4),
##            "Stream was not provided enough data")
##     assert(1 ==
##         thestream.readData(result.isHollow.unsafeAddr, 1),
##            "Stream was not provided enough data")
##
## As you may see from the code above, the macro generates three kinds
## of procedures: serializer, deserializer and size estimator.
## The serialization is being performed in a following way:
## each memory region of variable is copied
## to the resulting stream back-to-back.
## This approach achieves both of smallest
## serialized object size and independence from the compilator
## specific object representation.
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
##                   data: seq[byte | char | int8 | uint8] | string): Ball =
##     assert(data.len >= type(result).size(), "Given sequence should contain at least " &
##         $ (type(result).size()) & " bytes!")
##     let ss142004 = newStringStream(cast[string](data))
##     deserialize(type(result), ss142004)
##
## Endianness switching
## -----------------
## There is a way exists to set which endian should be used
## while [de]serialization particular structure or part of
## the structure. A special keyword **set!** allows to set
## the endian for all the fields of structure below until the
## end or other **set!** keyword. E.g.:
##
## .. code-block:: nim
##   serializable:
##     type Ball = object
##       weight: float32        # This value will be serialized in *cpuEndian* endian
##       set! :bigEndian        # The space between set! and :bigEndian is required!
##       diameter: int32        # This value will be serialized in big endian regardless of *cpuEndian*
##       set! :littleEndian     # Only "bigEndian" and "littleEndian" values allowed
##       color: array[3, int16] # Values in this array will be serialized in little endian
##
## The generated code will use the **swapEndian{16|32|64}()**
## calls from the endians module to change endianness.
##
## Future ideas
## ------------
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
  from private.typesinfo import TypeChunk, Context
  from private.generator import genTypeChunk, STREAM_NAME
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
      body: NimNode): NimNode {.compileTime.} =
    let itn = !typename
    let fname =
      if is_exported: newIdentNode("serialize").postfix("*")
      else: newIdentNode("serialize")
    let isin = !SERIALIZER_INPUT_NAME
    quote do:
      proc `fname`(`isin`: `itn`,
                   `STREAM_NAME`: Stream) = `body`

  proc makeDeserializeStreamDeclaration(typename: string,
      is_exported: bool,
      body: NimNode): NimNode {.compileTime.} =
    let itn = !typename
    let fname =
      if is_exported:
        newIdentNode("deserialize").postfix("*")
      else: newIdentNode("deserialize")
    quote do:
      proc `fname`(thetype: typedesc[`itn`],
                   `STREAM_NAME`: Stream): `itn` = `body`

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
                    body: NimNode = newEmptyNode()): NimNode =
    result = parseExpr(pattern % [sign, name])
    if body.kind != nnkEmpty:
      result.body = body

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
    let size_node =
      info.size(newIdentNode(SERIALIZER_INPUT_NAME))
    context.declared[name] = info
    let writer_conversion = makeSerializeStreamConversion()
    let serializer = generateProc(SERIALIZE_DECLARATION,
                                  name, sign,
                                  writer_conversion)
    let serialize_stream =
      makeSerializeStreamDeclaration(name, is_shared,
        info.serialize(newIdentNode(SERIALIZER_INPUT_NAME)))
    let obtainer_conversion =
      if context.is_static:
        makeDeserializeStreamConversion("result")
      else: newEmptyNode()
    let deserializer =
      if context.is_static:
        generateProc(DESERIALIZE_DECLARATION, name, sign,
                     obtainer_conversion)
      else: newEmptyNode()
    let deserialize_stream =
      makeDeserializeStreamDeclaration(name, is_shared,
      info.deserialize(newIdentNode("result")))
    let size_declaration =
      if context.is_static: STATIC_SIZE_DECLARATION
      else: SIZE_DECLARATION
    let sizeProc = generateProc(size_declaration, name, sign,
                                size_node)
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

macro toSerializable*(typedecl: typed): untyped =
  ## Generate [de]serialize procedures for existing type
  result = newStmtList()
  when defined(debug):
    hint(typedecl.symbol.getImpl().treeRepr())
    hint(typedecl.symbol.getImpl().repr())
  let ast = parseStmt("type " & typedecl.symbol.getImpl().repr())
  when defined(debug):
    hint(ast.treeRepr)
  result.add(ctx.prepare(ast))

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
  proc size*(thetype: typedesc[TheType]): int =
    ## Returns the size of serialized type. The type should be
    ## placed under the **static** section inside the
    ## **serializable** macro to access this procedure.
    ## The procedure could be used
    ## at compile time.
    0

  proc size*(thetype: TheType): int =
    ## Returns the size of serialized type. Available for types
    ## which declarations is not placed under the **static**
    ## section.
    discard

  proc serialize*(obj: TheType; stream: Stream) =
    ## Serializes `TheType` and writes result to the
    ## given `stream`.
    discard

  proc serialize*(obj: TheType): string =
    ## Serializes `TheType` to string.
    ## Underlying implementation uses StringStream and
    ## `serialize()` procedure above.
    ## More detailed description can be found
    ## in the top level documentation.
    discard

  proc deserialize*(thetype: typedesc[TheType],
                    stream: Stream): TheType
    {.raises: AssertionError.} =
    ## Interprets the data received from the `stream`
    ## as `TheType` and deserializes it then.
    ## When the stream will not provide enough bytes
    ## an `AssertionError` will be raised.
    discard
  proc deserialize*(thetype: typedesc[TheType],
    data: string | seq[byte | char | int8 | uint8]): TheType
    {.raises: AssertionError.} =
    ## Interprets given data as serialized `TheType` and
    ## deserializes it then. Only available for types which
    ## declarations are placed under the **static** section.
    ## When the `data` size is lesser than `TheType.size`,
    ## the AssertionError will be raised.
    discard
