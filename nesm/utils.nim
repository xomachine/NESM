import macros

proc unfold*(node: NimNode): NimNode {.compileTime.}


proc unfold(node: NimNode): NimNode =
  if node.kind == nnkStmtList and node.len == 1: node.last
  else: node
