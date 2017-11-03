from nesm import toSerializable, serializable
from streams import setPosition
from md5 import Md5digest
from endians import bigEndian32
import unittest
import helpers.rnw

suite "Converter tests":
  test "Simple object":
    toSerializable(MD5Digest)
    let rnw = get_random_reader_n_writer()
    let pnt = MD5Digest.deserialize(rnw)
    rnw.setPosition(0)
    pnt.serialize(rnw)
  test "Object with endian":
    toSerializable(MD5Digest, endian: bigEndian)
    let rnw = get_random_reader_n_writer()
    let pnt = MD5Digest.deserialize(rnw)
    rnw.setPosition(0)
    pnt.serialize(rnw)
  test "Static object":
    toSerializable(MD5Digest, dynamic: false)
    let rnw = get_random_reader_n_writer()
    let pnt = MD5Digest.deserialize(rnw)
    rnw.setPosition(0)
    pnt.serialize(rnw)
  test "Context restoration":
    # It's just a compilation test
    toSerializable(MD5Digest, dynamic: false)
    serializable:
      type A = object
        a: string
  test "Endians at aliases":
    type AInt = int32
    toSerializable(AInt, endian: bigEndian)
    let rnw = get_random_reader_n_writer()
    let a = AInt.deserialize(rnw)
    var b = 0.AInt
    bigEndian32(b.addr, rnw.buffer[0].addr)
    check(b == a)
  test "Reusage of static":
    toSerializable(MD5Digest, dynamic: false)
    serializable:
      static:
        type Reuser = object
          a: MD5Digest
    let rnw = get_random_reader_n_writer()
    let da = Reuser.deserialize(rnw)
    rnw.setPosition(0)
    da.serialize(rnw)
    check(true)
