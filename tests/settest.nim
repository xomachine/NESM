import helpers.rnw
import unittest
from nesm import serializable
from streams import setPosition
{.hint[XDeclaredButNotUsed]:off.}

suite "Sets":
  test "Simple set":
    serializable:
      static:
        type CharSet = set[char]
    let rnw = get_random_reader_n_writer()
    let o = CharSet.deserialize(rnw)
    rnw.setPosition(0)
    o.serialize(rnw)

