
import unittest
import nesm
import helpers.rnw
from sequtils import newSeqWith

suite "Dynamic structure tests":
  test "Static object in dynamic context":
    serializable:
      type
        MyObj = object
          a: int32
          b: int32
    let rnd = get_random_reader_n_writer()
    let obj = MyObj.deserialize(rnd.reader)
    obj.serialize(rnd.writer)
  test "Sequence":
    serializable:
      type
        MySeqObj = object
          a: seq[int32]
    var obj: MySeqObj
    obj.a = random_seq_with(int32(random(100)))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw.writer)
    let another_obj = MySeqObj.deserialize(rnw.reader)
    require(another_obj.a.len == obj.a.len)
    check(equalMem(another_obj.a[0].unsafeAddr,
                   obj.a[0].unsafeAddr, obj.a.len))

  test "Sequence of sequences":
    serializable:
      type
        MyObj = object
          a: seq[seq[int32]]
    var obj: MyObj
    obj.a = random_seq_with(
              random_seq_with(int32(random(100))))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw.writer)
    let another_obj = MyObj.deserialize(rnw.reader)
    require(obj.a.len == another_obj.a.len)
    for i in 0..<obj.a.len:
      require(obj.a[i].len == another_obj.a[i].len)
      check(equalMem(obj.a[i][0].unsafeAddr,
            another_obj.a[i][0].unsafeAddr, obj.a[i].len))

  test "String":
    serializable:
      type
        MyObj = object
          a: int32
          b: string
          c: int32
    var o: MyObj
    o.a = random(1000).int32
    o.c = random(1000).int32
    o.b = get_random_string()
    let rnw = get_reader_n_writer()
    o.serialize(rnw.writer)
    let ao = MyObj.deserialize(rnw.reader)
    check(o.a == ao.a)
    require(o.b.len == ao.b.len)
    check(o.c == ao.c)
    check(equalMem(o.b[0].unsafeAddr, ao.b[0].unsafeAddr, o.b.len))

  test "Some strings":
    serializable:
      type
        TwoStrings = object
          a: string
          b: string

    var o: TwoStrings
    o.a = get_random_string()
    o.b = get_random_string()
    let rnw = get_reader_n_writer()
    o.serialize(rnw.writer)
    let ao = TwoStrings.deserialize(rnw.reader)
    require(o.a.len == ao.a.len)
    check(o.a == ao.a)
    require(o.b.len == ao.b.len)
    check(o.b == ao.b)

  test "Empty sequence":
    serializable:
      type
        MyObj = object
          a: seq[int32]
    var o: MyObj
    o.a = @[]
    let rnw = get_reader_n_writer()
    o.serialize(rnw.writer)
    let ao = MyObj.deserialize(rnw.reader)
    require(ao.a.len == o.a.len)
    require(ao.a.len == 0)
    check(ao.a == o.a)
