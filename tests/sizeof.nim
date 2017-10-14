from nesm import serializable
from streams import setPosition
import unittest
import helpers.rnw


suite "{sizeof: x}":
  test "Basic":
    serializable:
      type Basic = object
        size: int32 {sizeof: {}.data}
        a: int32
        data: seq[int32]

    let rnw = get_reader_n_writer()
    var o: Basic
    o.data = random_seq_with(random(20000).int32)
    o.size = 0
    o.a = random(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = Basic.deserialize(rnw)
    check(o.a == dso.a)
    check(o.data == dso.data)
    check(o.data.len == dso.size)

