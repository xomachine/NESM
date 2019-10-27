import unittest
from nesm import serializable
from streams import setPosition
import helpers/rnw


suite "Default values tests":
  test "Basic":
    serializable:
      type
        IncompleteObj = object
          a: int32
        SimpleObj = object
          a: int32
          b: int32
    let rnw = get_reader_n_writer()
    let aval = rand(1000).int32
    let bval = rand(1001..2000).int32
    let x = IncompleteObj(a: aval)
    x.serialize(rnw)
    rnw.setPosition(0)
    var y = SimpleObj(a: rand(2001..3000).int32, b: bval)
    try:
      y.deserialize(rnw)
    except:
      discard
    check(aval == y.a)
    check(bval == y.b)

  test "Seq":
    serializable:
      type
        IncompleteSeqObj = object
          a: int32
          b: int32
          c: int32
        SeqObj = object
          a: int32
          b: seq[int32]
    let rnw = get_reader_n_writer()
    let aval = rand(1001..2000).int32
    let bval = random_seq_with(int32(rand(1000)))
    let cval = rand(4001..5000).int32
    let x = IncompleteSeqObj(a: aval, b: bval.len.int32,
                             c: cval)
    x.serialize(rnw)
    rnw.setPosition(0)
    var y = SeqObj(a: rand(2001..3000).int32, b: bval)
    try:
      y.deserialize(rnw)
    except:
      discard
    check(aval == y.a)
    require(bval.len == y.b.len)
    check(cval == y.b[0])
