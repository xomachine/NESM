from streams import StreamObj, Stream

type
  ByteCollection* = string | seq[ int8 | uint8 | char ]

  ByteStream* = ref ByteStreamObj
  ByteStreamObj = object of StreamObj
    data*: seq[char]
    pos: int


proc bsAtEnd(s: Stream): bool =
  return ByteStream(s).pos >= ByteStream(s).data.len

proc bsGetPos(s: Stream): int =
  ByteStream(s).pos

proc bsSetPos(s: Stream, pos: int) =
  var bs = ByteStream(s)
  bs.pos = clamp(pos, 0, bs.data.len)

proc bsClose(s: Stream) =
  var bs = ByteStream(s)
  bs.pos = 0
  reset(bs.data)

proc bsPeekData(s: Stream, buffer: pointer, length: int): int =
  let bs = ByteStream(s)
  let realLength = min(length, bs.data.len - bs.pos)
  if realLength <= 0:
    0
  else:
    when defined(js):
      let dt = bs.data
      for i in 0..<reallength:
        let j = bs.pos + i
        {.emit: """`buffer`[`i`] = `dt`[`j`];""".}
    else:
      copyMem(buffer, bs.data[bs.pos].unsafeAddr, realLength)
    realLength

proc bsReadData(s: Stream, buffer: pointer, length: int): int =
  result = s.bsPeekData(buffer, length)
  var bs = ByteStream(s)
  bs.pos += result

proc bsWriteData(s: Stream, buffer: pointer, length: int) =
  if length <= 0:
    return
  var bs = ByteStream(s)
  let newLength = bs.pos + length
  if newLength > bs.data.len:
    setLen(bs.data, newLength)
  when defined(js):
    let dt = bs.data
    for i in 0..<length:
      let j = bs.pos + i
      {.emit: """`dt`[`j`] = `buffer`[`i`];""".}
  else:
    copyMem(bs.data[bs.pos].unsafeAddr, buffer, newLength)
  bs.pos += newLength

proc setVTable(): ByteStream =
  new(result)
  result.closeImpl = bsClose
  result.atEndImpl = bsAtEnd
  result.setPositionImpl = bsSetPos
  result.getPositionImpl = bsGetPos
  result.readDataImpl = bsReadData
  result.peekDataImpl = bsPeekData
  result.writeDataImpl = bsWriteData

proc newByteStream*(x: ByteCollection): ByteStream =
  result = setVTable()
  when defined(js):
    result.data = newSeq[char](x.len)
    for i in 0..<x.len:
      result.data[i] = char(x[i])
  else:
    result.data = cast[seq[char]](x)
  result.pos = 0

