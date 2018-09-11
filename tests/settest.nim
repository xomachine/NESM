import helpers/rnw
import unittest
from nesm import serializable
from streams import setPosition
{.hint[XDeclaredButNotUsed]:off.}

suite "Sets":
  test "Simple set":
    serializable:
      static:
        type CharSet = set[char]
    require(CharSet.sizeof == size(CharSet))
    let rnw = get_random_reader_n_writer()
    let o = CharSet.deserialize(rnw)
    rnw.setPosition(0)
    o.serialize(rnw)

  test "Enum set":
    serializable:
      static:
        type TEnum = enum
          A, B, C
          D = 1024
        type ESet = set[TEnum]
    require(ESet.sizeof == size(ESet))
    let rnw = get_random_reader_n_writer()
    let o = ESet.deserialize(rnw)
    rnw.setPosition(0)
    o.serialize(rnw)

  test "From #8":
    serializable:
      static:
        type
          Flag = enum
            Bit1 = 0
            Bit8 = 7
          Obj = object
            flags: set[Flag]
    require(Obj.sizeof == size(Obj))
    let rnw = get_random_reader_n_writer()
    let o = Obj.deserialize(rnw)
    rnw.setPosition(0)
    o.serialize(rnw)
