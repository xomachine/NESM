when defined(js):
  error("Non C-like targets non supported yet.")

import macros
from strutils import `%`
from sequtils import toSeq
from tables import Table, initTable, contains, `[]`, `[]=`
from streams import Stream, newStringStream

when not defined(nimdoc):
  from nesm.typesinfo import TypeChunk, Context
  from nesm.generator import genTypeChunk, STREAM_NAME
else:
  import endians
  type TypeChunk = object
  include nesm.documentation

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

proc makeDeserializeStreamConversion(name: string): NimNode {.compileTime.} =
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

  proc generateProcs(context: var Context,
                     obj: NimNode): NimNode {.compileTime.} =
    expectKind(obj, nnkTypeDef)
    expectMinLen(obj, 3)
    expectKind(obj[1], nnkEmpty)
    let typename = if obj[0].kind == nnkPragmaExpr: obj[0][0] else: obj[0]
    let is_shared = typename.kind == nnkPostfix
    let name = if is_shared: $typename.basename else: $typename
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
  let settingsKeyword = newIdentNode("set")
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
      elif c.len == 3 and c[0] == settingsKeyword and
           c[1].kind == nnkTableConstr:
        continue
      else:
        children.add(c)
    else:
      children.add(cleanupTypeDeclaration(c))
  newTree(declaration.kind, children)

macro toSerializable*(typedecl: typed, settings: varargs[untyped]): untyped =
  ## Generate [de]serialize procedures for existing type with given settings.
  ##
  ## Settings should be supplied in the **key: value, key:value** format.
  ##
  ## For example:
  ##
  ## .. code-block:: nim
  ##   toSerializable(TheType, endian: bigEndian, dynamic: false)
  ##
  ## Avalible options:
  ## * **endian** - set the endian of serialized object
  ## * **dynamic** - if set to 'false' then object treated as **static**
  result = newStmtList()
  when defined(debug):
    hint(typedecl.symbol.getImpl().treeRepr())
  var ast = typedecl.symbol.getImpl()
  for arg in settings:
    arg.expectKind(nnkExprColonExpr)
    arg.expectMinLen(2)
    let key = $arg[0]
    let value = $arg[1]
    case key
    of "dynamic":
      if value == "false":
        ctx.is_static = true
      elif value == "true":
        ctx.is_static = false
      else:
        error("'dynamic' property can be only 'true' or 'false', but not: " &
              value)
    else:
      let objnodekind = ast.last.last.kind
      let curlied = newTree(nnkTableConstr, arg)
      let settings_ast =
        newTree(nnkIdentDefs, newIdentNode("set"), curlied, newEmptyNode())
      if objnodekind in {nnkTupleTy, nnkRecList}:
        ast.last.last.insert(0, settings_ast)
      elif objnodekind == nnkObjectTy:
        ast.last.last.last.insert(0, settings_ast)
      else:
        warning("Cannot apply option: " & key)
  when defined(debug):
    hint(ast.treeRepr)
  result.add(ctx.prepare(ast))
  ctx.is_static = false

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

