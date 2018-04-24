from typesinfo import TypeChunk, Context

type
  Field = tuple
    name: string
    chunk: TypeChunk
  FieldChunk = tuple
    entries: seq[Field]
    has_hidden: bool

proc genObject*(context: Context, thetype: NimNode): TypeChunk {.compileTime.}
proc genCase(context: Context, decl: NimNode): TypeChunk {.compileTime.}
proc caseWorkaround(tc: TypeChunk): TypeChunk {.compileTime.}
proc evalSize(e: NimNode): BiggestInt {.compileTime.}
proc genFields(context: Context, decl: NimNode): FieldChunk {.compileTime.}

from sequtils import toSeq, filterIt, mapIt
from generator import genTypeChunk
from utils import unfold, onlyname
from settings import applyOptions, splitSettingsExpr
import macros

proc caseWorkaround(tc: TypeChunk): TypeChunk =
  # st - type of field under case
  result = tc
  let oldser = tc.serialize
  let olddeser = tc.deserialize
  let tmpvar = nskVar.genSym("tmp")
  result.serialize = proc(s:NimNode): NimNode =
    let os = oldser(tmpvar)
    quote do:
      var `tmpvar` = `s`
      `os`
  result.deserialize = proc(s:NimNode): NimNode =
    let ods = olddeser(tmpvar)
    quote do:
      var `tmpvar`: type(`s`)
      `ods`
      `s` = `tmpvar`

proc genObject(context: Context, thetype: NimNode): TypeChunk =
  var elems = newSeq[Field]()
  var newContext = context
  let settingsKeyword = newIdentNode("set")
  for declaration in thetype.children():
    case declaration.kind
    of nnkNilLit:
      continue
    of nnkRecCase:
      expectMinLen(declaration, 2)
      # declaration[0]
      # A bad hackery to avoid expression without address
      # problem when accessing to field under case.
      let fchunk = newContext.genFields(declaration[0])
      result.has_hidden = result.has_hidden or fchunk.has_hidden
      assert fchunk.entries.len == 1
      let name = fchunk.entries[0].name
      let chunk = fchunk.entries[0].chunk
      elems.add((name, chunk.caseWorkaround()))
      let casechunk = newContext.genCase(declaration)
      elems.add(("", casechunk))
    of nnkIdentDefs:
      declaration.expectMinLen(2)
      if declaration[0] == settingsKeyword and
         declaration[1].kind == nnkTableConstr:
        # The set: {key:value} syntax encountered
        let paramslist = declaration[1]
        newContext = newContext.applyOptions(paramslist)
      else:
        let fchunk = newContext.genFields(declaration)
        elems &= fchunk.entries
        result.has_hidden = result.has_hidden or fchunk.has_hidden
    else:
      error("Unknown AST: \n" & declaration.repr & "\n" & declaration.treeRepr)
  if thetype.kind == nnkTupleTy:
    # There are no hidden entries in tuples
    result.has_hidden = false
  result.size = proc (source: NimNode): NimNode =
    # This variable is for `result += x` statements
    var result_list = newSeq[NimNode]()
    # All the static integers are collected here to and being summarized at
    # the compile time to reduce overhead
    var statics: NimNode = newIntLitNode(0)
    for i in elems.items():
      let n = newIdentNode(i.name)
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).unfold()
        else: source
      let e = i.chunk
      let part_size = e.size(newsource)
      case part_size.kind
      of nnkCaseStmt, nnkStmtList, nnkForStmt:
        # Statement lists, cases and loops are always contain `result += x`
        # expressions
        result_list.add(part_size)
      else:
        statics = statics.infix("+", part_size)
    if result_list.len == 0:
      # If there are no `result += x` statements -
      # just return resulting expression
      return newTree(nnkPar, statics)
    else:
      # In other case add `result += static expression` statement and return
      # a list of `result += x` statements
      result_list.add(newIdentNode("result").infix("+=", statics))
      return newTree(nnkStmtList, result_list)
  result.serialize = proc(source: NimNode): NimNode =
    result = newStmtList(parseExpr("discard"))
    for i in elems.items():
      let n = newIdentNode(i.name)
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).unfold()
        else: source
      let e = i.chunk
      result.add(e.serialize(newsource))
  result.deserialize = proc(source: NimNode): NimNode =
    result = newStmtList(parseExpr("discard"))
    for i in elems.items():
      let n = newIdentNode(i.name)
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).unfold()
        else: source
      let e = i.chunk
      result &= e.deserialize(newsource)

proc genFields(context: Context, decl: NimNode): FieldChunk =
  decl.expectKind(nnkIdentDefs)
  decl.expectMinLen(2)
  result.entries = newSeq[Field]()
  result.has_hidden = false
  let last =
    if decl[^1].kind == nnkEmpty: decl.len - 2
    else: decl.len - 1
  let subtype = decl[last]
  let (originalType, options) = subtype.splitSettingsExpr()
  let chunk = context.applyOptions(options).genTypeChunk(originalType)
  for i in 0..<last:
    if decl[i].kind != nnkPostfix:
      result.has_hidden = true
    let name = $decl[i].onlyname
    result.entries.add((name: name, chunk: chunk))

proc genCase(context: Context, decl: NimNode): TypeChunk =
  let checkable = decl[0][0].onlyname
  let eachbranch = proc(b: NimNode): auto =
    let children = toSeq(b.children)
    let conditions = children[0..^2]
    let branch = context.genTypeChunk(b.last)
    let size = proc(source: NimNode):NimNode =
      # All case branches by default are being wrapped with `result += val`
      # Except the case of statement list, another case or loop
      let casebody = branch.size(source)
      case casebody.kind
      of nnkStmtList, nnkForStmt, nnkCaseStmt:
        newTree(b.kind, conditions & @[casebody])
      else:
        newTree(b.kind, conditions & @[
          newTree(nnkStmtList,
                  @[newIdentNode("result").infix("+=", casebody)])
          ])
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
    (quote do: `source`.`checkable`).unfold()
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
    case $e[0]
    of "+":
      evalSize(e[1]) + evalSize(e[2])
    of "*":
      evalSize(e[1]) * evalSize(e[2])
    of "+=":
      # `result += x` should be handled as well
      evalSize(e[2])
    else:
      error("Unexpected operation: " & e.repr)
      0
  of nnkPar, nnkStmtList:
    e.expectLen(1)
    evalSize(e[0])
  of nnkOfBranch, nnkElse:
    evalSize(e.last)
  of nnkIdent:
    error("Constants are not supported in static object " &
          "variants: " & e.repr())
    0
  else:
    error("Unexpected node: " & e.treeRepr &
          ", non-static expression passed?")
    0



