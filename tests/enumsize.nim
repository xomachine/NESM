import unittest
include nesm.enums

macro getsize(q:untyped, d: untyped): untyped =
  result = newStmtList()
  hint d.treeRepr
  let val = estimateEnumSize(d.last.last[2])
  result.add(d)
  let assign = quote do:
    let `q` = `val`
  result.add(assign)

suite "Enum size evaluation":
  test "1-byte enum":
    getsize(usize):
      type UBE = enum
        fube = 255
    getsize(ssize):
      type SBE = enum
        fsbe = -256
    check(UBE.sizeof == usize)
    check(SBE.sizeof == ssize)

