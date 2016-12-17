import macros
from typesinfo import isBasic, estimateBasicSize
from typesinfo import TypeChunk
from tables import Table, contains, `[]`, `[]=`, initTable, pairs
from strutils import `%`

const DESERIALIZER_DATA_NAME* = "data"
const DESERIALIZER_RECEIVER_NAME* = "obtain"
# $1 - target object field; $2 - size of data to obtain
const DESERIALIZE_PATTERN = """
let thedata = """ & DESERIALIZER_RECEIVER_NAME & """($2)
assert(len(thedata) == $2, """ &
  """"The length of received data is not equal to $2")
copyMem($1.unsafeAddr, thedata[0].unsafeAddr, $2)
"""
const SERIALIZE_PATTERN = """
writer($1.unsafeAddr, $2)
"""

proc makeNimNode(pattern: string, target: string,
                 size: string): NimNode {.compileTime.} =
  let list = parseStmt(pattern % [target, size])
  result = newTree(nnkBlockStmt, newEmptyNode(), list)


proc genTypeChunk*(declared: Table[string, TypeChunk], thetype: NimNode): TypeChunk {.compileTime.} =
  result.size = newEmptyNode()
  case thetype.kind
  of nnkIdent:
    # It's a type, declared as identifier. Might be a basic type or
    # some of previously declared type in serializable block
    let plaintype = $thetype
    if plaintype.isBasic():
      let size = estimateBasicSize(plaintype)
      result.size = newIntLitNode(size)
      result.serialize = proc(source: string): seq[NimNode] =
        result = newSeq[NimNode]()
        result.add(parseExpr(SERIALIZE_PATTERN % [source, size.repr]))
      result.deserialize = proc(source: string): seq[NimNode] =
        result = newSeq[NimNode]()
        result.add(makeNimNode(DESERIALIZE_PATTERN, source, size.repr))
    elif plaintype in declared:
      return declared[plaintype]
    else:
      if plaintype in ["float", "int", "uint"]:
        error(("The type $1 is not allowed due to ambiguity. Consider using $1" %
              plaintype) & "32.")
      error(("Type $1 is not a basic " % plaintype) &
            "type nor a complex type under 'serializable' block!")
  of nnkBracketExpr:
    # The template type. typename[someargs]. Only array supported
    # for now.
    expectMinLen(thetype, 2)
    let name = $thetype[0]
    case name
    of "array":
      expectMinLen(thetype, 3)
      let elemType = thetype[2]
      let elemTypeString = elemType.repr
      let sizeDecl = thetype[1]
      let arrayLen =
        if sizeDecl.kind == nnkInfix and sizeDecl[0].repr == "..":
          newTree(nnkPar, sizeDecl[2].infix("+", newIntLitNode(1)))
        else:
          sizeDecl
      let onechunk = declared.genTypeChunk(elemType)
      assert(elemTypeString.len in 1..52, "The length of " &
        ("expression $1 is too big and " % elemTypeString) &
        "it is confusing codegenerator. Please consider reducing" &
        " the length to values less than 52." )
      let indexlettershift =
        if not elemTypeString.len in 1..26:
          6
        else:
          0
      let indexletter = $chr(ord('@') + elemTypeString.len + indexlettershift)
      let rangeexpr = newIntLitNode(0).infix("..<",
        newTree(nnkPar, arrayLen))
      result.size = newTree(nnkPar, onechunk.size).infix("*", arrayLen)
      result.serialize = proc(source: string): seq[NimNode] =
        let chunk_expr =
          onechunk.serialize(source & "[$1]" % indexletter)
        let forloop = newTree(nnkForStmt, newIdentNode(indexletter),
          rangeexpr, newTree(nnkStmtList, chunk_expr))
        result = @[forloop]
      result.deserialize = proc(source: string): seq[NimNode] =
        let chunk_expr =
          onechunk.deserialize(source & "[$1]" % indexletter)
        let forloop = newTree(nnkForStmt, newIdentNode(indexletter),
          rangeexpr, newTree(nnkStmtList, chunk_expr))
        result = @[forloop]
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
      result.size = result.size.infix("+", newTree(nnkPar, elem.size))
      elems[name] = elem
    result.serialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      for n, e in elems.pairs():
        result &= e.serialize("$1.$2" % [source, n])
    result.deserialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      let pat =
        if source.len > 0:
          source & ".$1"
        else:
          "$1"
      for n, e in elems.pairs():
        result &= e.deserialize(pat % n)
  of nnkObjectTy:
    expectMinLen(thetype, 3)
    assert(thetype[1].kind == nnkEmpty, "Inheritence not supported in serializable")
    return declared.genTypeChunk(thetype[2])
  of nnkRefTy:
    expectMinLen(thetype, 1)
    let objectchunk = declared.genTypeChunk(thetype[0])
    result.size = objectchunk.size
    result.serialize = objectchunk.serialize
    result.deserialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      result.add(parseExpr("new(result)"))
      result &= objectchunk.deserialize(source)
  of nnkDistinctTy:
    expectMinLen(thetype, 1)
    let basetype = thetype[0]
    let distincted = declared.genTypeChunk(basetype)
    result.size = distincted.size
    result.serialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      result &= parseExpr("let tmp = cast[$1]($2)" %
        [basetype.repr, source])
      result &= distincted.serialize("tmp" % [source, basetype.repr])
      result = @[newBlockStmt(newStmtList(result))]
    result.deserialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      result &= parseExpr("var tmp = cast[$1]($2)" %
                          [basetype.repr, source])
      result &= distincted.deserialize("tmp" %
                                       [source, basetype.repr])
      result &= parseExpr("result = cast[type(result)](tmp)")
      result = @[newBlockStmt(newStmtList(result))]
  else:
    error("Unexpected AST")
