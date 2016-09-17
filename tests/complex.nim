
import unittest
import nesm


suite "Complex tests":
  test "Simple object":
    serializable:
      type
        MyObj = object
          a: bool
          b: array[0..5, int16]

    let mo = MyObj()
    let smo = mo.serialize()
    let dsmo = MyObj.deserialize(@smo)
    require(mo.repr == dsmo.repr)

  test "Nested array object":
    serializable:
      type
        MyObj = object
          a: bool
          b: array[0..5, array[0..5, int16]]

    let mo = MyObj()
    let smo = mo.serialize()
    let dsmo = MyObj.deserialize(@smo)
    require(mo.repr == dsmo.repr)
  
  test "Nested object":
    serializable:
      type
        MyNestedObj = object
          a: array[0..7, float32]
          b: char
        MyObj = object
          a: bool
          b: MyNestedObj

    let mo = MyObj()
    let smo = mo.serialize()
    let dsmo = MyObj.deserialize(@smo)
    require(mo.repr == dsmo.repr)