from sequtils import toSeq, filterIt, mapIt
from generator import genTypeChunk, correct_sum
from typesinfo import TypeChunk, Context
import macros

proc genObject*(context: Context, thetype: NimNode): TypeChunk {.compileTime.}
proc genCase(context: Context, decl: NimNode): TypeChunk {.compileTime.}
proc caseWorkaround(tc: TypeChunk, st: NimNode): TypeChunk {.compileTime.}
proc evalSize(e: NimNode): BiggestInt {.compileTime.}

proc caseWorkaround(tc: TypeChunk, st: NimNode): TypeChunk =
  # st - type of field under case
  var t = tc
  let oldser = t.serialize
  let olddeser = t.deserialize
  let tmpvar = nskVar.genSym("tmp")
  t.serialize = proc(s:NimNode): NimNode =
    let os = oldser(tmpvar)
    quote do:
      var `tmpvar` = `s`
      `os`
  t.deserialize = proc(s:NimNode): NimNode =
    let ods = olddeser(tmpvar)
    quote do:
      var `tmpvar`: `st`
      `ods`
      `s` = `tmpvar`
  t

proc genObject(context: Context, thetype: NimNode): TypeChunk =
  var elems =
    newSeq[tuple[key:string, val:TypeChunk]](thetype.len())
  var index = 0
  var newContext = context
  let settingsKeyword = newIdentNode("set").postfix("!")
  for declaration in thetype.children():
    let decl =
      case declaration.kind
      of nnkRecCase:
        expectMinLen(declaration, 2)
        declaration[0]
      else:
        declaration
    if decl.kind == nnkNilLit:
      elems.del(index)
      continue
    elif decl[0] == settingsKeyword:
      let command = decl[1]
      case command.kind
      of nnkIdent:
        let strcommand = $command
        if strcommand in ["bigEndian", "littleEndian"]:
          newContext.swapEndian = strcommand != $cpuEndian
        else:
          error("Unknown setting: " & strcommand)
      else:
        error("Unknown setting: " & $command.repr)
      elems.del(index)
      continue
    decl.expectMinLen(2)
    if decl[0].kind != nnkPostfix and
       thetype.kind == nnkRecList:
      result.has_hidden = true
    let name = $decl[0].basename
    let subtype = decl[1]
    let tc = newContext.genTypeChunk(subtype)
    let elem =
      case declaration.kind
      of nnkRecCase:
        # A bad hackery to avoid expression without address
        # problem when accessing to field under case.
        tc.caseWorkaround(subtype)
      else:
        tc
    elems[index] = (name, elem)
    index += 1
    if declaration.kind == nnkRecCase:
      let casechunk = newContext.genCase(declaration)
      elems.add(("", TypeChunk()))
      elems[index] = ("", casechunk)
      index += 1
  result.size = proc (source: NimNode): NimNode =
    result = newIntLitNode(0)
    var result_list = newSeq[NimNode]()
    for i in elems.items():
      let n = !i.key
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).last
        else: source
      let e = i.val
      let part_size = e.size(newsource)
      if context.is_static and not
        (part_size.kind in [nnkStmtList, nnkCaseStmt]):
        result = result.infix("+", part_size)
      else:
        result_list.add(correct_sum(part_size))
    if not context.is_static:
      result_list.add(correct_sum(result))
      result = newStmtList(result_list)
    else:
      result = newTree(nnkPar, result)
  result.serialize = proc(source: NimNode): NimNode =
    result = newStmtList(parseExpr("discard"))
    for i in elems.items():
      let n = !i.key
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).last
        else: source
      let e = i.val
      result.add(e.serialize(newsource))
  result.deserialize = proc(source: NimNode): NimNode =
    result = newStmtList(parseExpr("discard"))
    for i in elems.items():
      let n = !i.key
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).last
        else: source
      let e = i.val
      result &= e.deserialize(newsource)


proc genCase(context: Context, decl: NimNode): TypeChunk =
  let checkable = decl[0][0].basename
  let eachbranch = proc(b: NimNode): auto =
    let conditions = toSeq(b.children)
      .filterIt(it.kind != nnkRecList)
    let branch = context.genTypeChunk(b.last)
    let size = proc(source: NimNode):NimNode =
      let casebody = branch.size(source)
      newTree(b.kind, conditions & @[casebody])
    let serialize = proc(source: NimNode): NimNode =
      let casebody = newStmtList(branch.serialize(source))
      newTree(b.kind, conditions & @[casebody])
    let deserialize = proc(source: NimNode): NimNode =
      let casebody = newStmtList(branch.deserialize(source))
      newTree(b.kind, conditions & @[casebody])
    (size, serialize, deserialize)
  let branches = toSeq(decl.children())
    .filterIt(it.kind in [nnkElse, nnkOfBranch])
    .mapIt(eachbranch(it))
  let sizes = branches.mapIt(it[0])
  let serializes = branches.mapIt(it[1])
  let deserializes = branches.mapIt(it[2])
  result.dynamic = true
  let condition = proc (source: NimNode): NimNode =
    (quote do: `source`.`checkable`).last
  result.size = proc(source: NimNode):NimNode =
    let sizenodes:seq[NimNode] = sizes.mapIt(it(source))
    if context.is_static:
      newIntLitNode(sizenodes.mapIt(evalSize(it)).max)
    else:
      newTree(nnkCaseStmt, condition(source) & sizenodes)
  result.serialize = proc(source: NimNode): NimNode =
    let sernodes:seq[NimNode] = serializes.mapIt(it(source))
    newTree(nnkCaseStmt, condition(source) & sernodes)
  result.deserialize = proc(source: NimNode): NimNode =
    let desernodes:seq[NimNode] =
      deserializes.mapIt(it(source))
    newTree(nnkCaseStmt, condition(source) & desernodes)

proc evalSize(e: NimNode): BiggestInt =
  case e.kind
  of nnkIntLit:
    e.intVal
  of nnkInfix:
    e.expectLen(3)
    let first = evalSize(e[1])
    let second = evalSize(e[2])
    case $e[0]
    of "+":
      first + second
    of "*":
      first * second
    else:
      error("Unexpected operation: " & e.repr)
      0
  of nnkPar:
    e.expectLen(1)
    evalSize(e[0])
  of nnkStmtList:
    e.expectLen(1)
    evalSize(e[0])
  of nnkOfBranch, nnkElse:
    evalSize(e.last)
  of nnkIdent:
    error("Constants are not supported in static object " &
          "variants")
    0
  else:
    error("Unexpected node: " & e.treeRepr &
          ", non-static expression passed?")
    0



