from sequtils import toSeq, filterIt, mapIt
from strutils import cmpIgnoreStyle
from nesm.generator import genTypeChunk, correct_sum
from nesm.typesinfo import TypeChunk, Context
import macros

type
  Field = tuple
    name: string
    chunk: TypeChunk
  FieldChunk = tuple
    entries: seq[Field]
    has_hidden: bool

proc genObject*(context: Context, thetype: NimNode): TypeChunk {.compileTime.}
proc applyOptions*(context: Context,
                   options: NimNode | seq[NimNode]): Context {.compileTime.}
proc genCase(context: Context, decl: NimNode): TypeChunk {.compileTime.}
proc caseWorkaround(tc: TypeChunk): TypeChunk {.compileTime.}
proc evalSize(e: NimNode): BiggestInt {.compileTime.}
proc genFields(context: Context, decl: NimNode): FieldChunk {.compileTime.}

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

proc applyOptions(context: Context, options: NimNode | seq[NimNode]): Context =
  result = context
  for option in options.items():
    option.expectKind(nnkExprColonExpr)
    option.expectMinLen(2)
    let key = option[0].repr
    let val = option[1].repr
    case key
    of "endian":
      result.swapEndian = cmpIgnoreStyle(val, $cpuEndian) != 0
    of "dynamic":
      let code = int(cmpIgnoreStyle(val, "true") == 0) +
                 2*int(cmpIgnoreStyle(val, "false") == 0)
      case code
      of 0: error("The dynamic property can be only 'true' or 'false' but not" &
                  val)
      of 1: result.is_static = true
      of 2: result.is_static = false
      else: error("Unexpected error! dynamic is in superposition! WTF?")
    of "size":
      result.size_override.insert(!val, 0)
    else:
      error("Unknown setting: " & key)

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
    result = newIntLitNode(0)
    var result_list = newSeq[NimNode]()
    for i in elems.items():
      let n = !i.name
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).last
        else: source
      let e = i.chunk
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
      let n = !i.name
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).last
        else: source
      let e = i.chunk
      result.add(e.serialize(newsource))
  result.deserialize = proc(source: NimNode): NimNode =
    result = newStmtList(parseExpr("discard"))
    for i in elems.items():
      let n = !i.name
      let newsource =
        if ($n).len > 0: (quote do: `source`.`n`).last
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
  let chunk =
    if subtype.kind == nnkCurlyExpr:
      context.applyOptions(toSeq(subtype.children)[1..<subtype.len])
             .genTypeChunk(subtype[0])
    else: context.genTypeChunk(subtype)
  for i in 0..<last:
    if decl[i].kind != nnkPostfix:
      result.has_hidden = true
    let name = $decl[i].basename
    result.entries.add((name: name, chunk: chunk))


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
  of nnkPar, nnkStmtList:
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



