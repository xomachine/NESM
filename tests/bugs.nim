import nesm
import helpers/rnw
import unittest
import streams

type MNIST_imgs* = object
  magic_number*: int32
  n_imgs*: int32
  n_rows*: int32
  n_cols*: int32
  data*: seq[uint8]
toSerializable(MNIST_imgs, endian: bigEndian)
suite "Bugs":
  test "#5":
    var t: MNIST_imgs
    let rnw = getReaderNWriter()
    t.data = randomSeqWith(uint8(rand(100)))
    t.serialize(rnw)
    rnw.setPosition(0)
    let dt = MNIST_imgs.deserialize(rnw)
    require(dt.data.len == t.data.len)

  test "#7":
    serializable:
      type MyType = object
        kind: byte
        size: uint32
        data: seq[byte] as {size: {}.size}
    let rnw = getReaderNWriter()
    var t: MyType
    t.kind = rand(100).byte
    t.data = randomSeqWith(byte(rand(100)))
    t.size = uint32(max(1, t.data.len) - 1)
    t.serialize(rnw)
    rnw.setPosition(0)
    let dt = MyType.deserialize(rnw)
    require(dt.data.len == dt.size.int)

  test "#9":
    serializable:
      type
        SavedSector = object
          id: uint8
        SaveGame = object
          sectors: seq[SavedSector]
    let rnw = getReaderNWriter()
    var t: SaveGame
    t.sectors = randomSeqWith(SavedSector(id: rand(100).uint8))
    t.serialize(rnw)
    rnw.setPosition(0)
    let dt = SaveGame.deserialize(rnw)
    require(dt.sectors.len == t.sectors.len)
    check(dt.sectors == t.sectors)
