
from nesm import serializable
from streams import setPosition
import helpers.rnw
import unittest
from macros import hint

suite "Enumerates":
  test "Simple enum":
    serializable:
      static:
        type SimpleEnum {.pure.} = enum
          A = 5'u32
          B = 7000'u32
          C

    static:
      hint $SimpleEnum.sizeof
    let rnw = get_reader_n_writer()
    let a = SimpleEnum.A
    a.serialize(rnw)
    rnw.setPosition(0)
    let da = SimpleEnum.deserialize(rnw)
    check(a == da)
  test "Nesting":
    # This test might fail due to uncertancy in the enum correctness checking
    # necesity, so it should be fixed as soon as the correctness checking
    # will be introduced
    serializable:
      static:
        type NestedEnum {.pure.} = enum
          A = 5
          B
        type TypeWithEnum = object
          b: int32
          a: NestedEnum
          c: int32
    let rnw = get_random_reader_n_writer()
    let da = TypeWithEnum.deserialize(rnw)
    rnw.setPosition(0)
    da.serialize(rnw)

