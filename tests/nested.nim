import unittest
import helpers.rnw
from nesm import serializable
from helpers.serializeimport import ImportedType
from streams import setPosition

suite "Nested types":
  test "Nested type from other module":
    serializable:
      type
        MyNested = object
          a: ImportedType
          b: int32
    let rnw = get_reader_n_writer()
    var o:MyNested
    o.b = 42.int32
    o.a = ImportedType(a: get_random_string(),
                       b: rand(100).int32)
    o.serialize(rnw)
    rnw.setPosition(0)
    let d = MyNested.deserialize(rnw)
    require(o.a.a.len == d.a.a.len)
    check(o.a.a == d.a.a)
    check(o.a.b == d.a.b)
    check(o.b == d.b)

#  test "Static nested type":
#   #Should cause a compile-time error
#    serializable:
#      static:
#        type
#          StaticNested = object
#            a: int32
#            b: ImportedType
##   let rrnw = get_random_reader_n_writer()
#   let nested = StaticNested.deserialize(rrnw)
#    nested.serialize(rrnw)
#    check(true)
