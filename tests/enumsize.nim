import unittest
include nesm/enums

{.hint[XDeclaredButNotUsed]:off.}
macro store_enum_size(q: untyped, d: untyped): untyped =
  result = newStmtList()
  let val = estimateEnumSize(d.last.last[2].getCount())
  result.add(d)
  let assign = quote do:
    let `q` = `val`
  result.add(assign)

template simple_test(val: Natural) =
  block:
    store_enum_size(someval):
      type sometype = enum
        somefield = val
    if sometype.sizeof != someval:
      echo $sometype.sizeof & " != " & $someval & " on test with val=" & $val
      check(false)

suite "Simple enum size evaluation":
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

template increment_test(val: Natural) =
  block:
    store_enum_size(someval):
      type sometype = enum
        somefield = val
        secondfield
    if sometype.sizeof != someval:
      echo $sometype.sizeof & " != " & $someval & " on test with val=" & $val
      check(false)

suite "Enum size evaluation with increment":
  test "1->2 byte enum":
    increment_test(253)
    increment_test(254)
    increment_test(255)
    increment_test(256)
    increment_test(257)
  test "2->4 byte enum":
    increment_test(65533)
    increment_test(65534)
    increment_test(65535)
    increment_test(65536)
    increment_test(65537)
  test "4->8 byte enum":
    increment_test(4294967293)
    increment_test(4294967294)
    increment_test(4294967295)
    increment_test(4294967296)
    increment_test(4294967297)

from nesm import serializable, toSerializable

template pragma_test(val: Natural) =
  block:
    serializable:
      static:
        type sometype {.size: 1.} = enum
          somefield = val
    if sometype.sizeof != size(sometype):
      echo $sometype.sizeof & " != " & $size(sometype) & " on test with val=" &
           $val
      check(false)

suite "Explicitly set size of enum":
  test "1 byte enum":
    pragma_test(253)
    pragma_test(254)
    pragma_test(255)
    pragma_test(256)
    pragma_test(257)

  test "toSerializable test":
    type myenum {.size: 1.} = enum
      a = 255
    when NimMajor * 10000 + NimMinor * 100 + NimPatch < 1801:
    # In Nim compiler prior 0.18.1 there is a bug that makes impossible to use
    # size pragma to detect enum size from toSerializable proc
    # getTypeImpl was not return any pragmas
      toSerializable(myenum, dynamic: false, size: 1)
    else:
      toSerializable(myenum, dynamic: false)
    check(size(myenum) == 1)
