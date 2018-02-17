
from sequtils import newSeqWith
when NimMajor > 0 or NimMinor > 17 or (NimMinor == 17 and NimPatch > 2):
  from random import rand
else:
  from random import random
  proc rand[T](a: T): int = random(a)
from streams import Stream, StringStream, newStringStream

export rand

type
  RandomStream = ref RandomStreamObj
  RandomStreamObj = object of Stream
    index: int
    buffer*: seq[char]

proc random_char(): char =
  return chr(rand(ord('A')..ord('Z')))

proc get_random_reader_n_writer*(): RandomStream =
  new(result)
  result.buffer = newSeq[char]()
  result.index = 0
  result.setPositionImpl = proc(s:Stream, p: int) =
    RandomStream(s).index = p
  result.getPositionImpl = proc(s:Stream): int =
    RandomStream(s).index
  result.readDataImpl = proc(s:Stream,b:pointer,c:int):int =
    var s = RandomStream(s)
    s.buffer &= newSeqWith(c, random_char())
    copyMem(b, s.buffer[s.index].addr, c)
    s.index += c
    c
  result.peekDataImpl = proc(s:Stream,b:pointer,c:int):int =
    var s = RandomStream(s)
    s.buffer &= newSeqWith(c, random_char())
    copyMem(b, s.buffer[s.index].addr, c)
    c
  result.writeDataImpl = proc(s:Stream,b:pointer,c:int) =
    var s = RandomStream(s)
    assert(equalMem(b, s.buffer[s.index].addr, c))
    s.index += c

proc get_reader_n_writer*(): StringStream =
  newStringStream()

template random_seq_with*(elem: untyped): untyped =
  let size = rand(1..100)
  newSeqWith(size, elem)

proc get_random_string*(): string =
  var char_seq = random_seq_with(random_char())
  return cast[string](char_seq)
