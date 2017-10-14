
import unittest
from nesm import serializable
import helpers.rnw
from sequtils import newSeqWith
from streams import setPosition, newStringStream

suite "Dynamic structure tests":
  test "Static object in dynamic context":
    serializable:
      type
        MyObj = object
          a: int32
          b: int32
    let rnw = get_random_reader_n_writer()
    let obj = MyObj.deserialize(rnw)
    rnw.setPosition(0)
    obj.serialize(rnw)

  test "Sequence":
    serializable:
      type
        MySeqObj = object
          a: seq[int32]
    var obj: MySeqObj
    obj.a = random_seq_with(int32(random(100)))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw)
    rnw.setPosition(0)
    let another_obj = MySeqObj.deserialize(rnw)
    require(another_obj.a.len == obj.a.len)
    check(equalMem(another_obj.a[0].unsafeAddr,
                   obj.a[0].unsafeAddr, obj.a.len))

  test "Sequence of sequences":
    serializable:
      type
        MySeqSeqObj = object
          a: seq[seq[int32]]
    var obj: MySeqSeqObj
    obj.a = random_seq_with(
              random_seq_with(int32(random(100))))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw)
    rnw.setPosition(0)
    let another_obj = MySeqSeqObj.deserialize(rnw)
    require(obj.a.len == another_obj.a.len)
    for i in 0..<obj.a.len:
      require(obj.a[i].len == another_obj.a[i].len)
      check(equalMem(obj.a[i][0].unsafeAddr,
            another_obj.a[i][0].unsafeAddr, obj.a[i].len))

  test "String":
    serializable:
      type
        MyStrObj = object
          a: int32
          b: string
          c: int32
    var o: MyStrObj
    o.a = random(1000).int32
    o.c = random(1000).int32
    o.b = get_random_string()
    let rnw = get_reader_n_writer()
    o.serialize(rnw)
    rnw.setPosition(0)
    let ao = MyStrObj.deserialize(rnw)
    check(o.a == ao.a)
    require(o.b.len == ao.b.len)
    check(o.c == ao.c)
    check(equalMem(o.b[0].unsafeAddr, ao.b[0].unsafeAddr, o.b.len))

  test "Some strings":
    serializable:
      type
        TwoStrings = object
          a: string
          b: string

    var o: TwoStrings
    o.a = get_random_string()
    o.b = get_random_string()
    let rnw = get_reader_n_writer()
    o.serialize(rnw)
    rnw.setPosition(0)
    let ao = TwoStrings.deserialize(rnw)
    require(o.a.len == ao.a.len)
    check(o.a == ao.a)
    require(o.b.len == ao.b.len)
    check(o.b == ao.b)

  test "Empty sequence":
    serializable:
      type
        MyEmptyObj = object
          a: seq[int32]
    var o: MyEmptyObj
    o.a = @[]
    let rnw = get_reader_n_writer()
    o.serialize(rnw)
    rnw.setPosition(0)
    let ao = MyEmptyObj.deserialize(rnw)
    require(ao.a.len == o.a.len)
    require(ao.a.len == 0)
    check(ao.a == o.a)

  test "Order preservation":
    serializable:
      type
        MyPreserved = object
          n: string
          q: uint16
          w: uint8

    let oo = MyPreserved(n: "Hi!", q: 7'u16, w: 16'u8)
    let so = oo.serialize()
    let thedata = "\x03\x00\x00\x00Hi!\x07\x00\x10"
    require(so.len == thedata.len)
    require(cast[string](so) == thedata)
    let str_stream = newStringStream(thedata)
    let o = MyPreserved.deserialize(str_stream)
    require(o.n.len == 3)
    check(o.n == "Hi!")
    check(o.q == 7'u16)
    check(o.w == 16'u8)

  test "Cased structure":
    serializable:
      type
        Variant = object
          k: int32
          case x: uint8
          of 0..(high(int8)-50).uint8:
            y: uint32
          else:
            z: uint16
    var locase = false
    var hicase = false
    while not (locase and hicase):
      let rnw = get_random_reader_n_writer()
      let o = Variant.deserialize(rnw)
      if o.x in 0'u8..(high(int8)-50).uint8:
        check(o.size() == 9)
        locase = true
      else:
        check(o.size() == 7)
        hicase = true
      rnw.setPosition(0)
      o.serialize(rnw)

  test "Empty cases":
    serializable:
      type
        ECases = object
          case x: char
          of 'A'..'N':
            y: int32
          else:
            discard
    var cases = 0'u8
    while cases < 3:
      let rnw = get_random_reader_n_writer()
      let o = ECases.deserialize(rnw)
      case o.x
      of 'A'..'N':
        cases = cases or 1'u8
      else:
        cases = cases or 2'u8
      rnw.setPosition(0)
      o.serialize(rnw)

  test "Static cases":
    serializable:
      static:
        type SCase = object
          case x: char
          of 'A'..'K':
            y: int64
          of 'N'..'Q':
            z: int16
          else:
            discard
    require(SCase.size() == 9)
    var cases = 0'u8
    while cases < 7:
      let rnw = get_random_reader_n_writer()
      let o = SCase.deserialize(rnw)
      case o.x
      of 'A'..'K':
        cases = cases or 1'u8
      of 'N'..'Q':
        cases = cases or 2'u8
      else:
        cases = cases or 4'u8
      rnw.setPosition(0)
      o.serialize(rnw)

  test "Nested variants":
    serializable:
      type
        NestedVar = object
          case x: char
          of 'Q'..'X', 'C'..'N':
            case y: char
            of 'A'..'K':
              i: int8
            else:
              j: int16
          else:
            k: int32
    var tests: int8 = 0
    while tests < 7:
      let rnw = get_random_reader_n_writer()
      let o = NestedVar.deserialize(rnw)
      case o.x
      of 'Q'..'X', 'C'..'N':
        case o.y
        of 'A'..'K':
          tests = tests or 2
          check(o.size() == 3)
        else:
          tests = tests or 4
          check(o.size() == 4)
      else:
        tests = tests or 1
        check(o.size() == 5)
      rnw.setPosition(0)
      o.serialize(rnw)

  test "Null-terminated string":
    serializable:
      type
        NTS = object
          u: int8
          s: cstring
          d: int8
    let rnw = get_reader_n_writer()
    let o = NTS(u: 10'i8, s: "hello!", d: 6'i8)
    o.serialize(rnw)
    rnw.setPosition(0)
    let d = NTS.deserialize(rnw)
    check(d.u == o.u)
    check(d.d == o.d)
    check(d.s == o.s)
    check(o.size() == 9)

  test "else: discard":
    serializable:
      type ED = object
        case a: uint8
        else: discard
    let rnw = get_random_reader_n_writer()
    let o = ED.deserialize(rnw)
    rnw.setPosition(0)
    o.serialize(rnw)
