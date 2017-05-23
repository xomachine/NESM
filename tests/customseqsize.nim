from nesm import serializable
from streams import setPosition
import unittest
import helpers.rnw

{.hint[XDeclaredButNotUsed]:off.}

suite "Custom periodic size":
  test "Seq":
    serializable:
      type
        MySeq = object
          size: int32
          a: int32
          data: seq[int32] {size: size}
 
    let rnw = get_reader_n_writer()
    var o: MySeq
    o.data = random_seq_with(random(20000).int32)
    o.size = o.data.len.int32
    o.a = random(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = MySeq.deserialize(rnw)
    require(size(o) == size(dso))
    check(o.a == dso.a)
    require(o.size == dso.size)
    require(o.data.len == dso.data.len)
    for i in 0..<o.size:
      check(o.data[i] == dso.data[i])

  test "strings":
    serializable:
      type
        MyString = object
          size: int32
          a: int32
          data: string {size: size}
 
    let rnw = get_reader_n_writer()
    var o: MyString
    o.data = get_random_string()
    o.size = o.data.len.int32
    o.a = random(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = MyString.deserialize(rnw)
    require(size(o) == size(dso))
    check(o.a == dso.a)
    require(o.size == dso.size)
    require(o.data.len == dso.data.len)
    for i in 0..<o.size:
      check(o.data[i] == dso.data[i])

