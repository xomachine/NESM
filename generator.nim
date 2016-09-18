import macros
from typesinfo import isBasic, estimateBasicSize
from typesinfo import TypeChunk
from tables import Table, contains, `[]`, `[]=`, initTable, pairs
from strutils import `%`

const DESERIALIZER_DATA_NAME* = "data"
const basic_serialize_pattern = "copyMem(result[$2].unsafeAddr, $1.unsafeAddr, $3)"
const basic_deserialize_pattern = "copyMem($1.unsafeAddr, " & DESERIALIZER_DATA_NAME &
                                  "[$2].unsafeAddr, $3)"



proc genTypeChunk*(declared: Table[string, TypeChunk], thetype: NimNode): TypeChunk =
  result.size = 0
  case thetype.kind
  of nnkIdent:
    let plaintype = $thetype
    if plaintype.isBasic():
      let size = estimateBasicSize(plaintype)
      result.size = size
      result.serialize = proc(source: string, index: int): seq[NimNode] =
        result = newSeq[NimNode]()
        result.add(parseExpr(basic_serialize_pattern %
                             [source, $index, $size]))
      result.deserialize = proc(source: string, index: int): seq[NimNode] =
        result = newSeq[NimNode]()
        result.add(parseExpr(basic_deserialize_pattern %
                           [source, $index, $size]))
    elif plaintype in declared:
      return declared[plaintype]
    else:
      if plaintype in ["float", "int", "uint"]:
        error(("The type $1 is not allowed due to ambiguity. Consider using $1" %
              plaintype) & "32.")
      error(("Type $1 is not a basic " % plaintype) &
            "type nor a complex type under 'serializable' block!")
  of nnkBracketExpr:
    expectMinLen(thetype, 2)
    let name = $thetype[0]
    case name
    of "array":
      expectMinLen(thetype, 3)
      let elemType = thetype[2]
      let sizeDecl = thetype[1]
      let arrayLen =
        case sizeDecl.kind
        of nnkIntLit:
          int(sizeDecl.intVal)
        of nnkInfix:
          expectLen(thetype, 3)
          int(sizeDecl[2].intVal) + 1
        else:
          0
      let onechunk = declared.genTypeChunk(elemType)
      result.size = onechunk.size * arrayLen
      result.serialize = proc(source: string, index: int): seq[NimNode] =
        result = newSeq[NimNode]()
        for i in 0..<arrayLen:
          result &= onechunk.serialize(source & "[$1]" % $i, index + i*onechunk.size)
      result.deserialize = proc(source: string, index: int): seq[NimNode] =
        result = newSeq[NimNode]()
        for i in 0..<arrayLen:
          result &= onechunk.deserialize(source & "[$1]" % $i, index + i*onechunk.size)
    else:
      error("Type $1 is not supported!" % name)
  of nnkTupleTy, nnkRecList:
    var elems = initTable[string, TypeChunk]()
    for decl in thetype.children():
      expectKind(decl, nnkIdentDefs)
      expectMinLen(decl, 2)
      let name = $decl[0].basename
      let subtype = decl[1]
      let elem = declared.genTypeChunk(subtype)
      result.size += elem.size
      elems[name] = elem
    result.serialize = proc(source: string, index: int): seq[NimNode] =
      result = newSeq[NimNode]()
      var shift = 0
      for n, e in elems.pairs():
        result &= e.serialize("$1.$2" % [source, n], index+shift)
        shift += e.size
    result.deserialize = proc(source: string, index: int): seq[NimNode] =
      result = newSeq[NimNode]()
      var shift = 0
      let pat =
        if source.len > 0:
          source & ".$1"
        else:
          "$1"
      for n, e in elems.pairs():
        result &= e.deserialize(pat % n, index+shift)
        shift += e.size
  of nnkObjectTy:
    expectMinLen(thetype, 3)
    assert(thetype[1].kind == nnkEmpty, "Inheritence not supported in serializable")
    return declared.genTypeChunk(thetype[2])
  of nnkRefTy:
    expectMinLen(thetype, 1)
    let objectchunk = declared.genTypeChunk(thetype[0])
    result.size = objectchunk.size
    result.serialize = objectchunk.serialize
    result.deserialize = proc(source: string, index: int): seq[NimNode] =
      result = newSeq[NimNode]()
      result.add(parseExpr("new(result)"))
      result &= objectchunk.deserialize(source, index)
  of nnkDistinctTy:
    expectMinLen(thetype, 1)
    let basetype = thetype[0]
    let distincted = declared.genTypeChunk(basetype)
    result.size = distincted.size
    result.serialize = proc(source: string, index: int): seq[NimNode] =
      result = newSeq[NimNode]()
      result &= parseExpr("let tmp = cast[$1]($2)" % [basetype.repr, source])
      result &= distincted.serialize("tmp" % [source, basetype.repr], index)
      result = @[newBlockStmt(newStmtList(result))]
    result.deserialize = proc(source: string, index: int): seq[NimNode] =
      result = newSeq[NimNode]()
      result &= parseExpr("var tmp = cast[$1]($2)" % [basetype.repr, source])
      result &= distincted.deserialize("tmp" % [source, basetype.repr], index)
      result &= parseExpr("result = cast[type(result)](tmp)")
      result = @[newBlockStmt(newStmtList(result))]
  else:
    error("Unexpected AST")
