from nesm import toSerializable
from streams import setPosition
from basic2d import Point2d
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

