import macros

proc unfold*(node: NimNode): NimNode {.compileTime.}
proc correct_sum*(part_size: NimNode): NimNode {.compileTime.}
proc onlyname*(node: NimNode): NimNode {.compileTime.}
proc dig*(node: NimNode, depth: Natural): NimNode {.compileTime.}

proc correct_sum(part_size: NimNode): NimNode =
  if part_size.kind == nnkInfix or part_size.len == 0:
    let result_node = newIdentNode("result")
    result_node.infix("+=", part_size)
  else:
    part_size

proc unfold(node: NimNode): NimNode =
  if node.kind == nnkStmtList and node.len == 1: node.last
  else: node

proc onlyname(node: NimNode): NimNode =
  case node.kind
  of nnkIdent, nnkPrefix, nnkPostfix: node.basename
  else: node

proc dig(node: NimNode, depth: Natural): NimNode {.compileTime.} =
  if depth == 0:
    return node
  case node.kind
  of nnkDotExpr:
    node.expectMinLen(1)
    node[0].dig(depth - 1)
  of nnkCall:
    node.expectMinLen(2)
    node[1].dig(depth - 1)
  of nnkEmpty:
    node
  of nnkIdent, nnkSym:
    error("Too big depth to dig: " & $depth)
    newEmptyNode()
  else:
    error("Unknown symbol: " & node.treeRepr)
    newEmptyNode()
