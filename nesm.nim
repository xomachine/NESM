when defined(js):
  error("Non C-like targets non supported yet.")
{.deadCodeElim: on.}
import macros
from strutils import `%`
from sequtils import toSeq
from tables import contains, `[]`, `[]=`
from streams import Stream

from nesm/typesinfo import TypeChunk, Context, initContext
from nesm/generator import genTypeChunk
from nesm/settings import applyOptions, splitSettingsExpr
when defined(nimdoc):
  # Workaround to make nimdoc happy
  proc generateProcs(ctx: Context, n: NimNode): NimNode = discard
  include nesm/documentation
else:
  from nesm/procgen import generateProcs

const NimCummulativeVersion = NimMajor * 10000 + NimMinor * 100 + NimPatch
when NimCummulativeVersion >= 1801:
  import macrocache
  const ctxTable = CacheTable("nesm.nesm.context")
  # Each entry in ctxTable contains a StmtList of 3 elements:
  # 0: block with the size proc implementation
  # 1: block with the serialize proc implementation
  # 2: block with the deserialize proc implementation
  let SOURCENAME = "aliassource"
  proc storeContext(context: Context) {.compileTime.} =
    let THESOURCENAME = newTree(nnkBracketExpr, newIdentNode(SOURCENAME))
    for newfield in context.newfields:
      let chunk = context.declared[newfield]
      let sizecode = chunk.size(THESOURCENAME)
      let serializecode = chunk.serialize(THESOURCENAME)
      let deserializecode = chunk.deserialize(THESOURCENAME)
      let dynamic = chunk.dynamic.int.newLit()
      let has_hidden = chunk.has_hidden.int.newLit()
      let maxcount =
        if chunk.nodekind == nnkEnumTy:
          chunk.maxcount.newLit()
        else:
          false.newLit()
      when declared(debug):
        hint("Adding key: " & newfield)
      ctxTable[newfield] = quote do:
        block:
          `sizecode`
        block:
          `serializecode`
        block:
          `deserializecode`
        `dynamic`
        `has_hidden`
        `maxcount`
  proc getContext(): Context {.compileTime.} =
    let THESOURCENAME = newIdentNode(SOURCENAME)
    result = initContext()
    for k, v in ctxTable:
      var tc: TypeChunk
      when declared(debug):
        hint("Extracting key: " & k)
      # >[0]<block "Name"[0]: >[1]<
      let sizecode = v[0][1]
      let serializecode = v[1][1]
      let deserializecode = v[2][1]
      tc.size = proc(source: NimNode): NimNode =
        quote do:
          block:
            let `THESOURCENAME` = `source`.unsafeAddr
            `sizecode`
      tc.deserialize = proc(source: NimNode): NimNode =
        quote do:
          block:
            let `THESOURCENAME` = `source`.unsafeAddr
            `deserializecode`
      tc.serialize = proc(source: NimNode): NimNode =
        quote do:
          block:
            let `THESOURCENAME` = `source`.unsafeAddr
            `serializecode`
      tc.dynamic = v[3].intVal.bool
      tc.has_hidden = v[4].intVal.bool
      if v[5].kind == nnkUInt64Lit:
        tc.nodekind = nnkEnumTy
        tc.maxcount = cast[uint64](v[5].intVal)
      result.declared[k] = tc
else:
  static:
    var ctx = initContext()
  proc storeContext(context: Context) {.compileTime.} =
    ctx = initContext()
    ctx.declared = context.declared
  proc getContext(): Context {.compileTime.} = ctx

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
      let last = if c[^1].kind == nnkEmpty: c.len - 2 else: c.len - 1
      let (originalType, options) = c[last].splitSettingsExpr()
      if options.len > 0:
        # newID need to be a NimNode that contains IdentDefs node
        # to utilze recursive call of cleanupTypeDeclaration
        var newID = newTree(nnkStmtList, c)
        #copyChildrenTo(c, newID[0])
        # first element of CurlyExpr is an actual type
        newID[0][last] = originalType
        children.add(newID.cleanupTypeDeclaration()[0])
      elif c[last].repr == "cstring":
        var newID = newNimNode(nnkIdentDefs)
        copyChildrenTo(c, newID)
        newID[last] = newIdentNode("string")
        children.add(newID)
      elif c.len == 3 and c[0] == settingsKeyword and
           c[1].kind == nnkTableConstr:
        continue
      elif c[last].kind == nnkTupleTy:
        var newID = newNimNode(c.kind)
        copyChildrenTo(c, newID)
        newID[last] = cleanupTypeDeclaration(c[last])
        children.add(newID)
      else:
        children.add(c)
    else:
      children.add(cleanupTypeDeclaration(c))
  newTree(declaration.kind, children)

macro nonIntrusiveBody(typename: typed, o: untyped, de: static[bool]): untyped =
  let typebody = getTypeImpl(typename)
  let ctx = getContext()
  when defined(debug):
    hint("Deserialize? " & $de)
    hint(typebody.treeRepr)
    hint(typebody.repr)
  let chunk = ctx.genTypeChunk(typebody)
  result = if de: chunk.deserialize(o) else: chunk.serialize(o)
  when defined(debug):
    hint(result.repr)

template nonIntrusiveTemplate[S](o: S, de: static[bool]) =
  nonIntrusiveBody(S, o, de)

proc serialize*[T](obj: T, thestream: Stream) =
  ## The non-intrusive serialize proc which allows to perform object
  ## serialization without special declaration.
  ## The negative side-effect of such approach is inability to pass any options
  ## (like `endian` or `dynamic`) to the serializer and lack of nested objects
  ## support. This proc should be imported directly.
  nonIntrusiveTemplate(obj, false)

proc deserialize*[T](thestream: Stream): T =
  ## The non-intrusive deserialize proc which allows to perform object
  ## deserialization without special declaration.
  ## The negative side-effect of such approach is inability to pass any options
  ## (like `endian` or `dynamic`) to the serializer and lack of nested objects
  ## support. This proc should be imported directly.
  nonIntrusiveTemplate(result, true)

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
  let ctx = getContext()
  when defined(debug):
    hint(typedecl.symbol.getImpl().treeRepr())
  var ast = typedecl.symbol.getImpl()
  var newctx = ctx.applyOptions(settings)
  when defined(debug):
    hint(ast.treeRepr)
  result.add(newctx.prepare(ast))
  newctx.storeContext()
  when defined(debug):
    hint(result.repr)

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
  var ctx = getContext()
  when defined(debug):
    hint(typedecl.treeRepr)
  when not defined(nimdoc):
    result.add(ctx.prepare(typedecl))
  when defined(debug):
    hint(result.repr)
  ctx.storeContext()
