from nesm import serialize, deserialize
from nesm import toSerializable
from streams import Stream, setPosition
import unittest
import helpers.rnw

suite "Non-intrusive serializer":
  test "Simple case":
    type MyType = object
      a: int32
      b: string

    let rnw = get_reader_n_writer()
    let o = MyType(a: rand(1..1000).int32, b: "Hello!")
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = deserialize[MyType](rnw)
    check(o.a == dso.a)
    check(o.b == dso.b)
