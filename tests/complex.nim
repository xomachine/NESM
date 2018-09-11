
import unittest
from nesm import serializable
import helpers/rnw
from streams import newStringStream, setPosition

suite "Complex tests":
  test "Simple object":
    serializable:
      static:
        type
          MyObj = object
            a: bool
            b: array[0..5, int16]

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyObj.deserialize(random_rnw)
    random_rnw.setPosition(0)
    dsmo.serialize(random_rnw)
    check(true)

  test "Field list of one type":
    serializable:
      static:
        type MyListObj = object
          a, b: int32
    let rnw = get_random_reader_n_writer()
    let dsmo = MyListObj.deserialize(rnw)
    rnw.setPosition(0)
    dsmo.serialize(rnw)
    check(true)

  test "Nested array object":
    serializable:
      static:
        type
          MyArrayObj = object
            a: bool
            b: array[0..5, array[0..5, int16]]

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyArrayObj.deserialize(random_rnw)
    random_rnw.setPosition(0)
    dsmo.serialize(random_rnw)
    check(true)
  
  test "Nested object":
    serializable:
      static:
        type
          MyNestedObj = object
            a: array[0..7, float32]
            b: char
          MyNObj = object
            a: bool
            b: MyNestedObj

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyNObj.deserialize(random_rnw)
    random_rnw.setPosition(0)
    dsmo.serialize(random_rnw)
    check(true)

  test "Array of tuples":
    serializable:
      static:
        type
          MyATObj = object
            a: array[0..7, tuple[a: int32, b: array[5,char]]]
            b: char

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyATObj.deserialize(random_rnw)
    random_rnw.setPosition(0)
    dsmo.serialize(random_rnw)
    check(true)

  test "Nested distinct":
    serializable:
      type
        DistinctType = distinct int32
        WDist = object
          a: int32
          subtype: DistinctType
    let rnw = get_random_reader_n_writer()
    let dsmo = WDist.deserialize(rnw)
    rnw.setPosition(0)
    dsmo.serialize(rnw)
    check(true)
