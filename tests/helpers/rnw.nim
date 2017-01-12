
from sequtils import newSeqWith
from random import random

export random

type
  RnW* = object
    reader*: proc (c: Natural): seq[byte]
    writer*: proc (s: pointer, c: Natural)

proc random_char(): int =
  return random(ord('A')..ord('Z'))

proc get_random_reader_n_writer*(): RnW =
  var read_data = newSeq[byte]()
  var index = 0
  result.reader = proc(c:Natural): seq[byte] =
    result = newSeqWith(c, byte(random_char()))
    read_data &= result

  result.writer = proc(s:pointer, c:Natural) =
    assert(equalMem(s, read_data[index].unsafeAddr, c),
           "Written memory not equals to read one")
    index += c

proc get_reader_n_writer*(): RnW =
  var written_data = newSeq[byte]()
  var index = 0
  result.reader = proc(c:Natural): seq[byte] =
    result = written_data[index..<(index+c)]
    index += c

  result.writer = proc(s:pointer, c:Natural) =
    var data = newSeq[byte](c)
    copyMem(data[0].addr, s, c)
    written_data &= data

template random_seq_with*(elem: untyped): untyped =
  let size = random(1..100)
  newSeqWith(size, elem)

proc get_random_string*(): string =
  var char_seq = random_seq_with(chr(random_char()))
  return cast[string](char_seq)
