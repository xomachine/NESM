
from nesm import serializable
from streams import setPosition
import helpers.rnw
import unittest
from macros import hint

{.hint[XDeclaredButNotUsed]:off.}

suite "Enumerates":
  test "Simple enum":
    serializable:
      static:
        type SimpleEnum {.pure.} = enum
          A = 5'u32
          B = 7000'u32
          C
    let rnw = get_reader_n_writer()
    let a = SimpleEnum.A
    a.serialize(rnw)
    rnw.setPosition(0)
    let da = SimpleEnum.deserialize(rnw)
    check(a == da)

  test "Invalid enum":
    serializable:
      static:
        type InvalidEnum = enum
          A
        type Filler = uint8
    let rnw = get_reader_n_writer()
    let a: Filler = random(1..250).uint8
    a.serialize(rnw)
    rnw.setPosition(0)
    expect(ValueError):
      discard InvalidEnum.deserialize(rnw)

  test "Enum of strings":
    serializable:
      static:
        type EOS {.pure.} = enum
          A = "a string"
          B = (1000, "b string")
    let rnw = get_reader_n_writer()
    let a = EOS.B
    a.serialize(rnw)
    rnw.setPosition(0)
    let da = EOS.deserialize(rnw)
    check(a == da)

  test "Nesting":
    serializable:
      static:
        type NestedEnum {.pure.} = enum
          A = 5
          B
        type TypeWithEnum = object
          b: int32
          a: NestedEnum
          c: int32
    let rnw = get_reader_n_writer()
    var da: TypeWithEnum
    da.a = NestedEnum.B
    da.b = random(1000).int32
    da.c = random(1000).int32
    da.serialize(rnw)
    rnw.setPosition(0)
    let a = TypeWithEnum.deserialize(rnw)
    check(a.a == da.a)
    check(a.b == da.b)
    check(a.c == da.c)
  test "Cases":
    serializable:
      static:
        type CEnum = enum
          A, B
        type CType = object
          case kind: CEnum
          of A:
            a: int32
          of B:
            b: int16
    let rnw = get_reader_n_writer()
    let o = CType(kind:CEnum.A, a:random(10000).int32)
    let oo = CType(kind:CEnum.B, b:random(1000).int16)
    o.serialize(rnw)
    oo.serialize(rnw)
    rnw.setPosition(0)
    let dso = CType.deserialize(rnw)
    let dsoo = CType.deserialize(rnw)
    check(o.kind == dso.kind)
    check(oo.kind == dsoo.kind)
    check(o.a == dso.a)
    check(oo.b == dsoo.b)

