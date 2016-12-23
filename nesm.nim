
## **NESM** is a tool that generates serialization and deserialization code for
## given object. This library provides a macro called `serializable` inside which
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
## In this example you could notice that `int32` and `float32` declarations are used
## instead of just `int` and `float`. It is necessary to avoid ambiguity in
## declarations on different platforms.
##
## The code in example will be transformed into the following code (the resulting
## code can be seen when **-d:debug** is passed to Nim compiler):
##
## .. code-block:: nim
##    type
##      Ball = object
##        weight: float32
##        diameter: int32
##        isHollow: bool
##  
##    proc size(q: typedesc[Ball]): int =
##      9
##  
##    proc serialize(obj: Ball): array[0 .. 8, byte] =
##      copyMem(result[0].unsafeAddr, obj.weight.unsafeAddr, 4)
##      copyMem(result[4].unsafeAddr, obj.diameter.unsafeAddr, 4)
##      copyMem(result[8].unsafeAddr, obj.isHollow.unsafeAddr, 1)
##  
##    proc deserialize(q: typedesc[Ball];
##                     data: string | seq[byte | char | int8 | uint8]): Ball =
##      assert(data.len() >= 9, "Given sequence should contain at least 9 bytes!")
##      copyMem(result.weight.unsafeAddr, data[0].unsafeAddr, 4)
##      copyMem(result.diameter.unsafeAddr, data[4].unsafeAddr, 4)
##      copyMem(result.isHollow.unsafeAddr, data[8].unsafeAddr, 1)
##
## As you can see from the code above, each memory region of variable is copied
## to the resulting array back-to-back. This approach achieves both of smallest
## serialized object size and independence from the compilator specific object
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
## - Nested objects if they are previously defined
##   in the same `serializable` block:
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
##

when defined(js):
  error("Non C-like targets non supported yet.")

import macros
when not defined(nimdoc):
  from typesinfo import TypeChunk
  from generator import genTypeChunk, DESERIALIZER_DATA_NAME,
    DESERIALIZER_RECEIVER_NAME
else:
  type TypeChunk = object

from strutils import `%`
from sequtils import toSeq
from tables import Table, initTable, contains, `[]`, `[]=`

const SERIALIZER_INPUT_NAME = "obj"
const SERIALIZE_DECLARATION = """proc serialize$1(""" &
  SERIALIZER_INPUT_NAME & """: $2): seq[byte] = discard"""
const SERIALIZE_WRITER_CONVERSION = """
var index: uint = 0
result = newSeq[byte]($1.size())
let r_ptr = cast[uint](result[0].unsafeAddr)
var writer = proc(a: pointer, size: Natural) =
  copyMem(cast[pointer](r_ptr + index), a, size)
  index += size
serialize(""" & SERIALIZER_INPUT_NAME & """, writer)
"""
const SERIALIZE_WRITER_DECLARATION = "proc serialize$1(" &
  SERIALIZER_INPUT_NAME & ": $2, writer: proc(a:pointer, s:Natural))" &
  " = discard"
const DESERIALIZE_DECLARATION = """proc deserialize$1""" &
  """(thetype: typedesc[$2], """ & DESERIALIZER_DATA_NAME &
  """: seq[byte | char | int8 | uint8] | string):""" &
  """$2 = discard"""
const DESERIALIZE_OBTAINER_CONVERSION = """
let datalen = """ & DESERIALIZER_DATA_NAME &
  """.len
assert(datalen >= $1.size(), "Given sequence should contain at""" &
  """least $1 bytes!")
var index = 0
proc obtain(count: Natural): seq[byte] =
  let lastindex =
    if index + count < datalen: index + count
    else: datalen
  result = cast[seq[byte]](""" & DESERIALIZER_DATA_NAME &
  """[index..<lastindex])
  index = lastindex
result = deserialize(type(result), obtain)
"""
const DESERIALIZE_OBTAINER_DECLARATION = "proc deserialize$1" &
  "(thetype: typedesc[$2], " & DESERIALIZER_RECEIVER_NAME &
  ": proc (count: Natural): (seq[byte | int8 | uint8 | char] | string)" &
  "): $2 = discard"
const STATIC_SIZE_DECLARATION =
  """proc size$1(thetype: typedesc[$2]): int = discard"""
const SIZE_DECLARATION = "proc size$1(" & SERIALIZER_INPUT_NAME &
                         ": $2): int = discard"

when not defined(nimdoc):
  proc generateProc(pattern: string, name: string, sign: string,
                body: seq[NimNode] = @[]): NimNode =
    result = parseExpr(pattern % [sign, name])
    if len(body) > 0:
      result.body = newStmtList(body)

proc generateProcs(declared: var Table[string, TypeChunk],
                 obj: NimNode,
                 is_static: bool = false): NimNode {.compileTime.} =
  when not defined(nimdoc):
    expectKind(obj, nnkTypeDef)
    expectMinLen(obj, 3)
    expectKind(obj[1], nnkEmpty)
    let typename = obj[0]
    let name = $typename.basename
    let sign =
      if typename.kind == nnkPostfix: "*"
      else: ""
    let body = obj[2]
    let info = declared.genTypeChunk(body, is_static)
    let size_node = info.size(SERIALIZER_INPUT_NAME)
    let size_arg =
      if is_static: "type($1)"
      else: "$1"
    declared[name] = info
    let writer_conversion =
      @[parseStmt(SERIALIZE_WRITER_CONVERSION % (size_arg %
        SERIALIZER_INPUT_NAME))]
    let serializer = generateProc(SERIALIZE_DECLARATION, name, sign,
      writer_conversion)
    let serialize_writer = generateProc(SERIALIZE_WRITER_DECLARATION,
      name, sign, info.serialize(SERIALIZER_INPUT_NAME))
    let obtainer_conversion =
      if is_static:
        @[parseStmt(DESERIALIZE_OBTAINER_CONVERSION % size_arg %
                    "result")]
      else: @[]
    let deserializer =
      if is_static:
        generateProc(DESERIALIZE_DECLARATION, name, sign,
                     obtainer_conversion)
      else: newEmptyNode()
    let deserialize_obtainer = generateProc(
      DESERIALIZE_OBTAINER_DECLARATION, name, sign,
      info.deserialize("result"))
    let size_declaration =
      if is_static: STATIC_SIZE_DECLARATION
      else: SIZE_DECLARATION
    let sizeProc = generateProc(size_declaration, name, sign,
                                @[size_node])
    newStmtList(sizeProc, serialize_writer, serializer,
                deserialize_obtainer, deserializer)
  else:
    discard

proc prepare(declared: var Table[string, TypeChunk],
             statements: NimNode,
             is_static: bool = false): NimNode {.compileTime.} =
  result = newStmtList()
  case statements.kind
  of nnkStmtList, nnkTypeSection, nnkStaticStmt:
    let not_dynamic = statements.kind == nnkStaticStmt or is_static
    for child in statements.children():
      result.add(declared.prepare(child, not_dynamic))
  of nnkTypeDef:
    result.add(declared.generateProcs(statements, is_static))
  else:
    error("Only type declarations can be serializable")

macro serializable*(typedecl: untyped): untyped =
  ## The main macro that generates code.
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   serializable:
  ##     # Type declaration
  ##
  var declared = initTable[string, TypeChunk]()
  result = newStmtList(toSeq(typedecl.children))
  when defined(debug):
    hint(typedecl.treeRepr)
  result.add(declared.prepare(typedecl))
  when defined(debug):
    hint(result.repr)

when defined(nimdoc):
  type TheType* = object
    ## This type will be used as example to show which procedures will be generated
    ## by the **serializable** macro.
  proc size*(q: typedesc[TheType]): int =
    ## Returns the size of serialized type. The type should be placed under
    ## **serializable** macro to access this procedure. The procedure could be used
    ## at compile time.
    0

  proc serialize*(obj: TheType): array[size(TheType), byte] =
    ## Serializes `TheType` to array of bytes. More detailed description can be found
    ## in top level documentation.
    discard

  proc deserialize*(q: typedesc[TheType],
    data: string | seq[byte | char | int8 | uint8]): TheType
    {.raises: AssertionError.} =
    ## Interprets given data as serialized `TheType` and deserializes it
    ## then.
    discard
