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

template simple_test(val: Natural) =
  block:
    getsize(someval):
      type sometype = enum
        somefield = val
    if sometype.sizeof != someval:
      echo $sometype.sizeof & " != " & $someval & " on test with val=" & $val
      check(false)

suite "Enum size evaluation":
  test "1->2 byte enum":
    simple_test(254)
    simple_test(255)
    simple_test(256)
    simple_test(257)
  test "2->4 byte enum":
    simple_test(65534)
    simple_test(65535)
    simple_test(65536)
    simple_test(65537)
  test "4->8 byte enum":
    simple_test(4294967294)
    simple_test(4294967295)
    simple_test(4294967296)
    simple_test(4294967297)

