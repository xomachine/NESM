
import macros
from strutils import `%`, parseInt
from tables import Table, initTable, contains, `[]`, `[]=`
from strscans import scanf

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
## The code in example will be transformed into the following code:
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
## - Nested tuples and objects if they are previously defined
##   in the same `serializable` block:
##     .. code-block:: nim
##       type MyNestedTuple = tuple[a: float64, b: int64]
##       type MyTuple = tuple[a: float32, b: MyNestedTuple]
##
## - Nested arrays of basic types:
##     .. code-block:: nim
##       type Matrix = array[0..4, array[0..4, int32]]
##
## Arrays of tuples or objects defined before are semantically correct and
## don't produce error but can lead to undefined behaviour.
##

when defined(js):
  error("Non C-like targets non supported yet.")

type
  ObjectInfo = tuple
    serializer: seq[NimNode]
    deserializer: seq[NimNode]
    size: int

const SERIALIZER_INPUT_NAME = "obj"
const DESERIALIZER_DATA_NAME = "data"

proc estimateSize(sizes: Table[string, int], thetype: string): int {.compileTime.} =
  case thetype
  of "char", "byte", "uint8", "int8", "bool": sizeof(int8)
  of "uint16", "int16": sizeof(int16)
  of "uint32", "int32", "float32": sizeof(int32)
  of "uint64", "int64", "float64": sizeof(int64)
  of "uint", "int", "float":
    error(thetype & "'s size is undecided and depends from architecture." &
      " Consider using " & thetype & "32 or other specific type.")
    0
  else:
    var arraylastidx: int
    var arraytype: string
    if scanf(thetype[0..^1], "array[0 .. $i, $*]", arraylastidx, arraytype):
      (arraylastidx + 1) * estimateSize(sizes, arraytype)
    elif thetype in sizes:
      sizes[thetype]
    else:
      assert(false, "Can not estimate size of type " & thetype)
      0    

proc generateSerializer(size: int, name: string,
                        shift: int = 0): NimNode {.compileTime.} =
    parseExpr("copyMem(result[$1].unsafeAddr, $2.unsafeAddr, $3)" %
              [$shift, name, $size])

proc buildBody(sizes: Table[string, int], selfname: string,
               objbody: NimNode): ObjectInfo {.compileTime.} =
  case objbody.kind
  of nnkIdent, nnkBracketExpr:
    let parent = objbody.repr
    result.size = estimateSize(sizes, parent)
    if parent in sizes:
      result.serializer = @[parseExpr("serialize($1($2))" %
                                      [parent, SERIALIZER_INPUT_NAME])]
      result.deserializer = @[parseExpr("$2(deserialize($1, $3))" %
                                        [parent, selfname, DESERIALIZER_DATA_NAME])]
    else:
      result.serializer = @[generateSerializer(result.size, SERIALIZER_INPUT_NAME)]
      result.deserializer = 
        @[parseExpr("copyMem(result.unsafeAddr, $1[0].unsafeAddr, $2)" % 
                    [DESERIALIZER_DATA_NAME, $result.size])]
  of nnkDistinctTy:
    assert(objbody.len() > 0, "What this object distinct of?")
    return buildBody(sizes, selfname, objbody[0])
  of nnkRefTy:
    expectMinLen(objbody, 1)
    let fieldlist = objbody[0]
    result = buildBody(sizes, selfname, fieldlist)
    result.deserializer.insert(parseExpr("new(result)"), 0)
  of nnkObjectTy:
    expectMinLen(objbody, 3)
    assert(objbody[1].kind == nnkEmpty, "Inheritence not supported in serializable")
    let fieldlist = objbody[2]
    return buildBody(sizes, selfname, fieldlist)
  of nnkTupleTy, nnkRecList:
    result.size = 0
    result.serializer = newSeq[NimNode]()
    result.deserializer = newSeq[NimNode]()
    
    for f in objbody.children():
      expectKind(f, nnkIdentDefs)
      expectMinLen(f, 2)
      let fieldname = $f[0]
      let fieldtype = f[1].repr
      let size = estimateSize(sizes, fieldtype)
      if fieldtype in sizes:
        result.serializer.add(newBlockStmt(newStmtList(
          parseExpr("let tmp = serialize($1.$2)" % [SERIALIZER_INPUT_NAME, fieldname]),
          generateSerializer(size, "tmp[0]" , result.size))))
        result.deserializer.add(
          parseExpr("result.$2 = deserialize($5, $4[$1..$1+$3])" % 
                    [$result.size, fieldname, $size, DESERIALIZER_DATA_NAME, fieldtype]))
      else:
        result.serializer.add(
          generateSerializer(size, "$1.$2" % [SERIALIZER_INPUT_NAME, fieldname],
                             result.size))
        result.deserializer.add(
          parseExpr("copyMem(result.$2.unsafeAddr, $4[$1].unsafeAddr, $3)" %
                    [$result.size, fieldname, $size, DESERIALIZER_DATA_NAME]))
      result.size += size
    result.deserializer.insert(parseExpr(
      "assert($1.len() >= $2, \"Given sequence should contain at least $2 bytes!\")" %
      [DESERIALIZER_DATA_NAME, $result.size]))
  else:
    error("Illformed AST")

proc generateProcs(sizes: var Table[string, int],
                    obj: NimNode): NimNode {.compileTime.} =
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
  let info = buildBody(sizes, name, body)
  let serializer_return = parseExpr("array[0..$1, byte]" % $(info.size-1))
  let deserializer_return = newIdentNode(name)
  let deserializer_type = newIdentDefs(newIdentNode("q"), 
                                       parseExpr("typedesc[$1]" % name))
  let deserializer_input = newIdentDefs(newIdentNode(DESERIALIZER_DATA_NAME), 
                                        parseExpr("seq[byte]"))
  let serializer_input = newIdentDefs(newIdentNode(SERIALIZER_INPUT_NAME),
                                      deserializer_return)
  sizes[name] = info.size
  let sizeProc = parseExpr("""proc size$1(q: typedesc[$2]): int = $3""" %
                           [ast, name, $info.size])
  let serializer = newProc(makeName("serialize"), 
    @[serializer_return, serializer_input], newStmtList(info.serializer))
  let deserializer = newProc(makeName("deserialize"),
    @[deserializer_return, deserializer_type, deserializer_input],
    newStmtList(info.deserializer))
  newStmtList(sizeProc, serializer, deserializer)
  
  

proc prepare(sizes: var Table[string, int],
             statements: NimNode): NimNode {.compileTime.} =
  when defined(debug):
    hint(statements.treeRepr)
  result = newStmtList()
  case statements.kind
  of nnkStmtList, nnkTypeSection:
    for child in statements.children():
      result.add(prepare(sizes, child))
  of nnkTypeDef:
    result.add(generateProcs(sizes, statements))
  else:
    error("Only type declarations can be serializable")
  

macro serializable*(typedecl: untyped): untyped =
  var sizes = initTable[string, int]()
  result = newStmtList(typedecl)
  result.add(prepare(sizes, typedecl))
  when defined(debug):
    hint(result.repr)
