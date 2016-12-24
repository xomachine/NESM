
import unittest
import nesm
import random
from sequtils import newSeqWith
type
  RnW = object
    reader: proc (c: Natural): seq[byte]
    writer: proc (s: pointer, c: Natural)

const ascii_range = ord('z') - ord('A')

proc get_random_reader_n_writer(): RnW =
  var read_data = newSeq[byte]()
  var index = 0
  result.reader = proc(c:Natural): seq[byte] =
    result = newSeqWith(c, byte(ord('A')+random(ascii_range)))
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
    obj.a = newSeqWith(1+random(50), int32(random(100)))
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
    obj.a = newSeq[seq[int32]](1+random(10))
    for i in 0..<obj.a.len:
      obj.a[i] = newSeq[int32](1+random(10))
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
