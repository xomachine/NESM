
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
    check(another_obj.a.len == obj.a.len)
    check(equalMem(another_obj.a[0].unsafeAddr, obj.a[0].unsafeAddr,
          obj.a.len))

