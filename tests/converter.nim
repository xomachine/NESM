from nesm import toSerializable, serializable
from streams import setPosition
from basic2d import Point2d
from endians import bigEndian32
import unittest
import helpers.rnw

suite "Converter tests":
  test "Simple object":
    toSerializable(Point2d)
    let rnw = get_random_reader_n_writer()
    let pnt = Point2d.deserialize(rnw)
    rnw.setPosition(0)
    pnt.serialize(rnw)
  test "Object with endian":
    toSerializable(Point2d, endian: bigEndian)
    let rnw = get_random_reader_n_writer()
    let pnt = Point2d.deserialize(rnw)
    rnw.setPosition(0)
    pnt.serialize(rnw)
  test "Static object":
    toSerializable(Point2d, dynamic: false)
    let rnw = get_random_reader_n_writer()
    let pnt = Point2d.deserialize(rnw)
    rnw.setPosition(0)
    pnt.serialize(rnw)
  test "Context restoration":
    # It's just a compilation test
    toSerializable(Point2d, dynamic: false)
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

