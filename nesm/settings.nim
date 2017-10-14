from typesinfo import Context
from strutils import cmpIgnoreStyle
import macros
proc splitSettingsExpr*(node: NimNode): tuple[t: NimNode, s: NimNode]
  {.compileTime.}
proc applyOptions*(context: Context,
                   options: NimNode | seq[NimNode]): Context {.compileTime.}

proc applyOptions(context: Context, options: NimNode | seq[NimNode]): Context =
  ## Applies given options to the `context` and returns it without changing
  ## the original one.
  ## Options should be a NimNode or seq[NimNode] which contains nnkExprColonExpr
  ## nodes with key - value pairs.
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
      result.overrides.size.insert((option[1], context.depth), 0)
    of "sizeof":
      discard
    else:
      error("Unknown setting: " & key)

proc splitSettingsExpr(node: NimNode): tuple[t: NimNode, s: NimNode] =
  ## Checks if given ``node`` is the settings expression.
  ## If so, returns original type declaration and settings node.
  ## Otherwise returns node and empty TableConstr node.
  if node.kind == nnkInfix and node.len == 3 and $node[0] == "as" and
     node[2].kind == nnkTableConstr:
    return (t: node[1], s: node[2])
  else:
    return (t: node, s: newNimNode(nnkTableConstr))
