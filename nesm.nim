
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
##    proc deserialize(q: typedesc[Ball]; data: seq[byte]): Ball =
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
  from generator import genTypeChunk
else:
  type TypeChunk = object

from strutils import `%`
from tables import Table, initTable, contains, `[]`, `[]=`

const SERIALIZER_INPUT_NAME = "obj"
const DESERIALIZER_DATA_NAME = "data"
const predeserealize_assert = """assert(""" & DESERIALIZER_DATA_NAME &
  """.len >= $1, "Given sequence should contain at least $1 bytes!")"""


proc generateProcs(declared: var Table[string, TypeChunk],
                    obj: NimNode): NimNode {.compileTime.} =
  when not defined(nimdoc):
    expectKind(obj, nnkTypeDef)
    expectMinLen(obj, 3)
    expectKind(obj[1], nnkEmpty)
    let is_shared = obj[0].kind == nnkPostfix
    let ast = if is_shared: "*" else: ""
    proc makeName(q:string):NimNode =
      let name = newIdentNode(q)
      if is_shared:
        name.postfix("*")
      else:
        name
    let name = $obj[0].basename
    let body = obj[2]
    let info = declared.genTypeChunk(body)
    let serializer_return = parseExpr("array[0..$1, byte]" % $(info.size-1))
    let deserializer_return = newIdentNode(name)
    let deserializer_type = newIdentDefs(newIdentNode("q"),
                                         parseExpr("typedesc[$1]" % name))
    let deserializer_input = newIdentDefs(newIdentNode(DESERIALIZER_DATA_NAME),
                                          parseExpr("seq[byte]"))
    let serializer_input = newIdentDefs(newIdentNode(SERIALIZER_INPUT_NAME),
                                        deserializer_return)
    declared[name] = info
    let sizeProc = parseExpr("""proc size$1(q: typedesc[$2]): int = $3""" %
                             [ast, name, $info.size])
    let serializer = newProc(makeName("serialize"),
      @[serializer_return, serializer_input],
      newStmtList(info.serialize(SERIALIZER_INPUT_NAME, 0)))
    let deserializer = newProc(makeName("deserialize"),
      @[deserializer_return, deserializer_type, deserializer_input],
      newStmtList(@[parseExpr(predeserealize_assert % $info.size)] &
        info.deserialize("result", 0)))
    newStmtList(sizeProc, serializer, deserializer)
  else:
    discard

proc prepare(declared: var Table[string, TypeChunk],
             statements: NimNode): NimNode {.compileTime.} =
  when defined(debug):
    hint(statements.treeRepr)
  result = newStmtList()
  case statements.kind
  of nnkStmtList, nnkTypeSection:
    for child in statements.children():
      result.add(declared.prepare(child))
  of nnkTypeDef:
    result.add(declared.generateProcs(statements))
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
  result = newStmtList(typedecl)
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

  proc deserialize*(q: typedesc[TheType], data: seq[byte]): TheType
    {.raises: AssertionError.} =
    ## Interprets given sequence of data as serialized `TheType` and deserializes it
    ## then.
    discard
