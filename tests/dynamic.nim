
import unittest
import nesm
import random
from sequtils import newSeqWith
type
  RnW = object
    reader: proc (c: Natural): seq[byte]
    writer: proc (s: pointer, c: Natural)


proc get_random_reader_n_writer(): RnW =
  var read_data = newSeq[byte]()
  var index = 0
  result.reader = proc(c:Natural): seq[byte] =
    result = newSeqWith(c, byte(random(ord('A')..ord('Z'))))
    read_data &= result

  result.writer = proc(s:pointer, c:Natural) =
    assert(equalMem(s, read_data[index].unsafeAddr, c),
           "Written memory not equals to read one")
    index += c

proc get_reader_n_writer(): RnW =
  var written_data = newSeq[byte]()
  var index = 0
  result.reader = proc(c:Natural): seq[byte] =
    result = written_data[index..<(index+c)]
    index += c

  result.writer = proc(s:pointer, c:Natural) =
    var data = newSeq[byte](c)
    copyMem(data[0].addr, s, c)
    written_data &= data

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
    obj.a = newSeqWith(random(1..50), int32(random(100)))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw.writer)
    let another_obj = MySeqObj.deserialize(rnw.reader)
    require(another_obj.a.len == obj.a.len)
    check(equalMem(another_obj.a[0].unsafeAddr, obj.a[0].unsafeAddr,
          obj.a.len))

  test "Sequence of sequences":
    serializable:
      type
        MyObj = object
          a: seq[seq[int32]]
    var obj: MyObj
    obj.a = newSeq[seq[int32]](random(1..11))
    for i in 0..<obj.a.len:
      obj.a[i] = newSeq[int32](random(1..11))
      for j in 0..<obj.a[i].len:
        obj.a[i][j] = random(100).int32
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
    var random_str = newSeqWith(random(1..100),
                                char(random(ord('A')..ord('Z'))))
    o.b = cast[string](random_str)
    let rnw = get_reader_n_writer()
    o.serialize(rnw.writer)
    let ao = MyObj.deserialize(rnw.reader)
    check(o.a == ao.a)
    require(o.b.len == ao.b.len)
    check(o.c == ao.c)
    check(equalMem(o.b[0].unsafeAddr, ao.b[0].unsafeAddr, o.b.len))
