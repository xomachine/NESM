
import unittest
import nesm
import helpers.rnw

suite "Complex tests":
  test "Simple object":
    serializable:
      static:
        type
          MyObj = object
            a: bool
            b: array[0..5, int16]

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyObj.deserialize(random_rnw.reader)
    dsmo.serialize(random_rnw.writer)
    check(true)

  test "Nested array object":
    serializable:
      static:
        type
          MyObj = object
            a: bool
            b: array[0..5, array[0..5, int16]]

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyObj.deserialize(random_rnw.reader)
    dsmo.serialize(random_rnw.writer)
    check(true)
  
  test "Nested object":
    serializable:
      static:
        type
          MyNestedObj = object
            a: array[0..7, float32]
            b: char
          MyObj = object
            a: bool
            b: MyNestedObj

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyNestedObj.deserialize(random_rnw.reader)
    dsmo.serialize(random_rnw.writer)
    check(true)

  test "Array of tuples":
    serializable:
      static:
        type
          MyObj = object
            a: array[0..7, tuple[a: int32, b: array[5,char]]]
            b: char

    let random_rnw = get_random_reader_n_writer()
    let dsmo = MyObj.deserialize(random_rnw.reader)
    dsmo.serialize(random_rnw.writer)
    check(true)
