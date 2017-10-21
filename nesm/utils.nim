import macros

proc unfold*(node: NimNode): NimNode {.compileTime.}
proc correct_sum*(part_size: NimNode): NimNode {.compileTime.}

proc correct_sum(part_size: NimNode): NimNode =
  if part_size.kind == nnkInfix or part_size.len == 0:
    let result_node = newIdentNode("result")
    result_node.infix("+=", part_size)
  else:
    part_size

proc unfold(node: NimNode): NimNode =
  if node.kind == nnkStmtList and node.len == 1: node.last
  else: node
