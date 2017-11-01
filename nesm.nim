when defined(js):
  error("Non C-like targets non supported yet.")
{.deadCodeElim: on.}
import macros
from strutils import `%`
from sequtils import toSeq
from tables import contains, `[]`, `[]=`
from streams import Stream

when not defined(nimdoc):
  from nesm.typesinfo import TypeChunk, Context, initContext
  from nesm.procgen import generateProcs
  from nesm.settings import applyOptions, splitSettingsExpr
else:
  import endians
  include nesm.documentation


static:
  var ctx = initContext()
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
        var newID = c
        newID[last] = cleanupTypeDeclaration(c[last])
        children.add(newID)
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
  ctx = ctx.applyOptions(settings)
  when defined(debug):
    hint(ast.treeRepr)
  result.add(ctx.prepare(ast))
  ctx.is_static = false
  ctx.swapEndian = false

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

