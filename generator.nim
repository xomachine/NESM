import macros
from typesinfo import isBasic, estimateBasicSize
from typesinfo import TypeChunk
from tables import Table, contains, `[]`, `[]=`, initTable, pairs
from strutils import `%`
from sequtils import mapIt, foldl, toSeq, filterIt

const DESERIALIZER_DATA_NAME* = "data"
const DESERIALIZER_RECEIVER_NAME* = "obtain"
# $1 - target object field; $2 - size of data to obtain
const DESERIALIZE_PATTERN = """
let thedata = """ & DESERIALIZER_RECEIVER_NAME & """($2)
assert(len(thedata) == $2, """ &
  """"The length of received data is not equal to $2, but equal""" &
  """ to " & $$len(thedata))
copyMem($1.unsafeAddr, thedata[0].unsafeAddr, $2)
"""
const SERIALIZE_PATTERN = """
writer($1.unsafeAddr, $2)
"""

proc genPeriodic(declared: Table[string, TypeChunk],
                 elem: NimNode,
                 length: proc(source: string): NimNode,
                 is_static: bool): TypeChunk {.compileTime.}

proc genCase(declared: Table[string, TypeChunk],
             decl: NimNode): TypeChunk {.compileTime.}

proc caseWorkaround(tc: TypeChunk,
                    st: string): TypeChunk {.compileTime.} =
  # st - type of field under case
  var t = tc
  let oldser = t.serialize
  let olddeser = t.deserialize
  let tmpvar = "wa"
  t.serialize = proc(s:string):seq[NimNode] =
    let os = oldser(tmpvar)
    let list = parseExpr("var $1 = $2" % [tmpvar, s]) & os
    @[newBlockStmt(newStmtList(list))]
  t.deserialize = proc(s:string):seq[NimNode] =
    let list = @[parseExpr("var $1:$2" % [tmpvar, st])] &
      olddeser(tmpvar) &
      @[parseExpr("$1 = $2" % [s, tmpvar])]
    @[newBlockStmt(newStmtList(list))]
  t

proc makeNimNode(pattern: string, target: string,
                 size: string): NimNode {.compileTime.} =
  let list = parseStmt(pattern % [target, size])
  result = newBlockStmt(newStmtList(list))

proc correct_sum(part_size: NimNode): NimNode =
  let result_node = newIdentNode("result")
  if part_size.kind in [nnkStmtList, nnkCaseStmt]:
    part_size
  else:
    result_node.infix("+=", part_size)

proc genTypeChunk*(declared: Table[string, TypeChunk],
                   thetype: NimNode,
                   is_static: bool = false): TypeChunk
                   {.compileTime.} =
  result.has_hidden = false
  case thetype.kind
  of nnkIdent:
    # It's a type, declared as identifier. Might be a basic
    # type or
    # some of previously declared type in serializable block
    let plaintype = $thetype
    if plaintype.isBasic():
      let size = estimateBasicSize(plaintype)
      result.size = proc (source: string): NimNode =
        newIntLitNode(size)
      result.serialize = proc(source: string): seq[NimNode] =
        result = newSeq[NimNode]()
        result.add(parseExpr(SERIALIZE_PATTERN %
                             [source, size.repr]))
      result.deserialize = proc(source: string): seq[NimNode] =
        result = newSeq[NimNode]()
        result.add(makeNimNode(DESERIALIZE_PATTERN,
                               source, size.repr))
    elif plaintype in declared:
      let declared_type = declared[plaintype]
      if declared_type.dynamic and is_static:
        error("Only static objects can be nested into" &
              " static objects, but '" & plaintype &
              "' is not a static object!")
      if declared_type.has_hidden:
        warning("Seems like the " & plaintype &
          " (at " & thetype.lineinfo() & ")" &
          " have hidden fields inside. This may lead to" &
          " compile error if the " & plaintype & " was " &
          "imported from another module. Consider including" &
          " imported module or sharing " & plaintype & "'s" &
          " fields via '*' postfix")
      return declared[plaintype]
    elif thetype.repr == "string" and not is_static:
      let len_proc = proc (s: string):NimNode =
        parseExpr("len($1)" % s)
      result = declared.genPeriodic(newEmptyNode(), len_proc,
                                    is_static)
    else:
      if plaintype in ["float", "int", "uint"]:
        error((("The type $1 is not allowed due to" &
                " ambiguity. Consider using $1") %
               plaintype) & "32.")
      error(("Type $1 is not a basic " % plaintype) &
            "type nor a complex type under 'serializable'" &
            " block!")
  of nnkBracketExpr:
    # The template type. typename[someargs].
    expectMinLen(thetype, 2)
    let name = $thetype[0]
    case name
    of "array":
      expectMinLen(thetype, 3)
      let elemType = thetype[2]
      let sizeDecl = thetype[1]
      let arrayLen =
        if sizeDecl.kind == nnkInfix and
           sizeDecl[0].repr == "..":
          newTree(nnkPar,
                  sizeDecl[2].infix("+", newIntLitNode(1)))
        else:
          sizeDecl
      let sizeproc = proc (source: string): NimNode =
        arrayLen
      result = declared.genPeriodic(elemType, sizeproc,
                                    is_static)
    of "seq":
      if is_static:
        error("Dynamic types not supported in static" &
              " structures")
      let elem = thetype[1]
      let seqLen = proc (source: string): NimNode =
        parseExpr("len($1)" % source)
      result = declared.genPeriodic(elem, seqLen, is_static)
    else:
      error("Type $1 is not supported!" % name)
  of nnkTupleTy, nnkRecList:
    var elems =
      newSeq[tuple[key:string, val:TypeChunk]](thetype.len())
    var index = 0
    for declaration in thetype.children():
      let decl =
        case declaration.kind
        of nnkRecCase:
          expectMinLen(declaration, 2)
          declaration[0]
        else:
          declaration
      expectMinLen(decl, 2)
      if decl[0].kind != nnkPostfix and
         thetype.kind == nnkRecList:
        result.has_hidden = true
      let name = $decl[0].basename
      let subtype = decl[1]
      let tc = declared.genTypeChunk(subtype, is_static)
      let elem =
        if declaration.kind == nnkRecCase:
          # A bad hackery to avoid expression without address
          # problem when accessing to field under case.
          tc.caseWorkaround(subtype.repr)
        else:
          tc
      elems[index] = (name, elem)
      index += 1
      if declaration.kind == nnkRecCase:
        let casechunk = declared.genCase(declaration)
        elems.add(("", TypeChunk()))
        elems[index] = ("", casechunk)
        index += 1
    result.size = proc (source: string): NimNode =
      result = newIntLitNode(0)
      var result_list = newSeq[NimNode]()
      for i in elems.items():
        let n = i.key
        let pat = if n.len > 0: "$1.$2" else: "$1"
        let e = i.val
        let part_size = e.size(pat % [source, n])
        if is_static and not
          (part_size.kind in [nnkStmtList, nnkCaseStmt]):
          result = result.infix("+", part_size)
        else:
          result_list.add(correct_sum(part_size))
      if result_list.len > 0:
        result_list.add(correct_sum(result))
        result = newStmtList(result_list)
      else:
        result = newTree(nnkPar, result)
    result.serialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      for i in elems.items():
        let n = i.key
        let pat = if n.len > 0: "$1.$2" else: "$1"
        let e = i.val
        result &= e.serialize(pat % [source, n])
    result.deserialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      let pat =
        if source.len > 0:
          source & ".$1"
        else:
          "$1"
      for i in elems.items():
        let n = i.key
        let ppat = if n.len > 0: pat else: source
        let e = i.val
        result &= e.deserialize(ppat % n)
  of nnkObjectTy:
    expectMinLen(thetype, 3)
    assert(thetype[1].kind == nnkEmpty,
           "Inheritence not supported in serializable")
    return declared.genTypeChunk(thetype[2], is_static)
  of nnkRefTy:
    expectMinLen(thetype, 1)
    let objectchunk = declared.genTypeChunk(thetype[0],
                                            is_static)
    result.has_hidden = objectchunk.has_hidden
    result.size = objectchunk.size
    result.serialize = objectchunk.serialize
    result.deserialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      result.add(parseExpr("new(result)"))
      result &= objectchunk.deserialize(source)
  of nnkDistinctTy:
    expectMinLen(thetype, 1)
    let basetype = thetype[0]
    let distincted = declared.genTypeChunk(basetype,
                                           is_static)
    result.has_hidden = true
    result.size = distincted.size
    result.serialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      result &= parseExpr("let tmp = cast[$1]($2)" %
        [basetype.repr, source])
      result &= distincted.serialize("tmp")
      result = @[newBlockStmt(newStmtList(result))]
    result.deserialize = proc(source: string): seq[NimNode] =
      result = newSeq[NimNode]()
      result &= parseExpr("var tmp = cast[$1]($2)" %
                          [basetype.repr, source])
      result &= distincted.deserialize("tmp")
      result &= parseExpr("result = cast[type(result)](tmp)")
      result = @[newBlockStmt(newStmtList(result))]
  else:
    discard
    error("Unexpected AST")
  result.dynamic = not is_static

proc genPeriodic(declared: Table[string, TypeChunk],
                 elem: NimNode,
                 length: proc (s:string): NimNode,
                 is_static: bool): TypeChunk =
  let elemString = elem.repr
  let onechunk =
    if elem.kind != nnkEmpty:
      declared.genTypeChunk(elem, is_static)
    else:
      declared.genTypeChunk(newIdentNode("char"), is_static)
  assert(elemString.len in 0..52, "The length of " &
    ("expression $1 is too big and " % elemString) &
    "it is confusing codegenerator. Please consider" &
    " reducing the length to values less than 52." )
  let indexlettershift =
    if elemString.len > 26:
      6
    elif elemString.len > 0:
      0
    else:
      ord('s') - ord('@')
  let if_string =
    if elemString.len == 0:
      "tring_counter"
    else:
      ""
  let indexletter = $chr(ord('@') + elemString.len +
                         indexlettershift) & if_string
  let size_header_chunk = declared.genTypeChunk(
    newIdentNode("uint32"), is_static)
  result.size = proc (source: string): NimNode =
    let periodic_len = length(source)
    let chunk_size = one_chunk.size(source & "[$1]" %
                                    indexletter)
    if periodic_len.kind != nnkCall and
       chunk_size.kind != nnkStmtList:
      periodic_len.infix("*", chunk_size)
    else:
      let rangeexpr = newIntLitNode(0).infix("..<",
        newTree(nnkPar, periodic_len))
      let len_header =
        correct_sum(size_header_chunk.size(""))
      let chunk_expr = correct_sum(chunk_size)
      let forloop = newTree(nnkForStmt,
                            newIdentNode(indexletter),
                            rangeexpr,
                            newTree(nnkStmtList, chunk_expr))
      newStmtList(len_header, forloop)
  result.serialize = proc(source: string): seq[NimNode] =
    let periodic_len = length(source)
    result = newSeq[NimNode]()
    if periodic_len.kind == nnkCall:
      let periodic_len_varname = "$1_size" % indexletter
      let varname = newIdentNode(periodic_len_varname)
      result.add(newLetStmt(varname,
                            periodic_len))
      result &=
        size_header_chunk.serialize(periodic_len_varname)
    let rangeexpr = newIntLitNode(0).infix("..<",
      newTree(nnkPar, length(source)))
    let chunk_expr =
      onechunk.serialize(source & "[$1]" % indexletter)
    let forloop = newTree(nnkForStmt,
                          newIdentNode(indexletter),
                          rangeexpr,
                          newTree(nnkStmtList, chunk_expr))
    result.add(forloop)
    result = @[newBlockStmt(newStmtList(result))]
  result.deserialize = proc(source: string): seq[NimNode] =
    let periodic_len = length(source)
    result = newSeq[NimNode]()
    let periodic_len_varname = "$1_size" % indexletter
    if periodic_len.kind == nnkCall:
      let varname = newIdentNode(periodic_len_varname)
      let thevalue =
        newIntLitNode(0).newDotExpr(newIdentNode("uint32"))
      result.add(newVarStmt(varname, thevalue))
      result &=
        size_header_chunk.deserialize(periodic_len_varname)
    let array_len =
      if periodic_len.kind == nnkCall:
        newIdentNode(periodic_len_varname)
          .newDotExpr(newIdentNode("int"))
      else: periodic_len
    if periodic_len.kind == nnkCall:
      let init_template =
        if elemString.len == 0:
          "$1 = newString($3)"
        else:
          "$1 = newSeq[$2]($3)"
      result.add(parseExpr(init_template %
                 [source, elemString, array_len.repr]))
    let rangeexpr = newIntLitNode(0).infix("..<",
      newTree(nnkPar, array_len))
    let chunk_expr =
      onechunk.deserialize(source & "[$1]" % indexletter)
    let forloop = newTree(nnkForStmt,
                          newIdentNode(indexletter),
      rangeexpr, newTree(nnkStmtList, chunk_expr))
    result.add(forloop)
    result = @[newBlockStmt(newStmtList(result))]

proc genCase(declared: Table[string, TypeChunk],
             decl: NimNode): TypeChunk =
  let checkable = $decl[0][0].basename
  let eachbranch = proc(b: NimNode): auto =
    let conditions = toSeq(b.children)
      .filterIt(it.kind != nnkRecList)
    let branch = declared.genTypeChunk(b.last, false)
    let size = proc(source: string):NimNode =
      let casebody = branch.size(source)
      newTree(b.kind, conditions & @[casebody])
    let serialize = proc(source: string):seq[NimNode] =
      let casebody = newStmtList(branch.serialize(source))
      @[newTree(b.kind, conditions & @[casebody])]
    let deserialize = proc(source: string):seq[NimNode] =
      let casebody = newStmtList(branch.deserialize(source))
      @[newTree(b.kind, conditions & @[casebody])]
    (size, serialize, deserialize)
  let branches = toSeq(decl.children())
    .filterIt(it.kind in [nnkElse, nnkOfBranch])
    .mapIt(eachbranch(it))
  let sizes = branches.mapIt(it[0])
  let serializes = branches.mapIt(it[1])
  let deserializes = branches.mapIt(it[2])
  result.dynamic = true
  let condition = proc (source: string): NimNode =
    parseExpr("$1.$2" % [source, checkable])
  result.size = proc(source:string):NimNode =
    let sizenodes:seq[NimNode] = sizes.mapIt(it(source))
    newTree(nnkCaseStmt, condition(source) & sizenodes)
  result.serialize = proc(source: string):seq[NimNode] =
    let sernodes:seq[NimNode] = serializes.mapIt(it(source))
      .foldl(a & b)
    @[newTree(nnkCaseStmt, condition(source) & sernodes)]
  result.deserialize = proc(source: string):seq[NimNode] =
    let desernodes:seq[NimNode] =
      deserializes.mapIt(it(source)).foldl(a & b)
    @[newTree(nnkCaseStmt, condition(source) & desernodes)]
