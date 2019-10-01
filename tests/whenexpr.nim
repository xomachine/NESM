
import unittest
import helpers/rnw
from streams import setPosition
from nesm import serializable

suite "When expression":
  test "Trivia":
    serializable:
      static:
        type WhenTest = object
          when true:
            x: int8
          else:
            y: int16

    require(WhenTest.size() == 1)
    let rrnw = get_random_reader_n_writer()
    let dso = WhenTest.deserialize(rrnw)
    rrnw.setPosition(0)
    dso.serialize(rrnw)
    require(true)

  test "No else":
    serializable:
      static:
        type WhenOnly = object
          when true:
            x: int8

    require(WhenOnly.size() == 1)
    let rrnw = get_random_reader_n_writer()
    let dso = WhenOnly.deserialize(rrnw)
    rrnw.setPosition(0)
    dso.serialize(rrnw)
    require(true)

  test "Else branch":
    serializable:
      static:
        type WhenElse = object
          when false:
            x: int8
          else:
            y: int16

    require(WhenElse.size() == 2)
    let rrnw = get_random_reader_n_writer()
    let dso = WhenElse.deserialize(rrnw)
    rrnw.setPosition(0)
    dso.serialize(rrnw)
    require(true)

  test "Semi-dynamic static":
    serializable:
      type WhenSD = object
        when true:
          x: int8
        else:
          y: string

    let rrnw = get_random_reader_n_writer()
    let dso = WhenSD.deserialize(rrnw)
    require(dso.size() == 1)
    rrnw.setPosition(0)
    dso.serialize(rrnw)
    require(true)

  test "Semi-dynamic dynamic":
    serializable:
      type WhenSDD = object
        when false:
          x: int8
        else:
          y: string

    let rnw = get_reader_n_writer()
    let o = WhenSDD(y: get_random_string())
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = WhenSDD.deserialize(rnw)
    require(dso.size() == o.size())
    require(o.y == dso.y)
