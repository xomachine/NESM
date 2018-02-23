import nesm
import helpers.rnw
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
    echo dt.data
