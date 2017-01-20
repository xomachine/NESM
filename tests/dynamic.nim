
import unittest
import nesm
import helpers.rnw
from sequtils import newSeqWith

suite "Dynamic structure tests":
  test "Static object in dynamic context":
    serializable:
      type
        MyObj = object
          a: int32
          b: int32
    let rnd = get_random_reader_n_writer()
    let obj = MyObj.deserialize(rnd.reader)
    obj.serialize(rnd.writer)
  test "Sequence":
    serializable:
      type
        MySeqObj = object
          a: seq[int32]
    var obj: MySeqObj
    obj.a = random_seq_with(int32(random(100)))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw.writer)
    let another_obj = MySeqObj.deserialize(rnw.reader)
    require(another_obj.a.len == obj.a.len)
    check(equalMem(another_obj.a[0].unsafeAddr,
                   obj.a[0].unsafeAddr, obj.a.len))

  test "Sequence of sequences":
    serializable:
      type
        MyObj = object
          a: seq[seq[int32]]
    var obj: MyObj
    obj.a = random_seq_with(
              random_seq_with(int32(random(100))))
    let rnw = get_reader_n_writer()
    obj.serialize(rnw.writer)
    let another_obj = MyObj.deserialize(rnw.reader)
    require(obj.a.len == another_obj.a.len)
    for i in 0..<obj.a.len:
      require(obj.a[i].len == another_obj.a[i].len)
      check(equalMem(obj.a[i][0].unsafeAddr,
            another_obj.a[i][0].unsafeAddr, obj.a[i].len))

  test "String":
    serializable:
      type
        MyObj = object
          a: int32
          b: string
          c: int32
    var o: MyObj
    o.a = random(1000).int32
    o.c = random(1000).int32
    o.b = get_random_string()
    let rnw = get_reader_n_writer()
    o.serialize(rnw.writer)
    let ao = MyObj.deserialize(rnw.reader)
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
    o.serialize(rnw.writer)
    let ao = TwoStrings.deserialize(rnw.reader)
    require(o.a.len == ao.a.len)
    check(o.a == ao.a)
    require(o.b.len == ao.b.len)
    check(o.b == ao.b)

  test "Empty sequence":
    serializable:
      type
        MyObj = object
          a: seq[int32]
    var o: MyObj
    o.a = @[]
    let rnw = get_reader_n_writer()
    o.serialize(rnw.writer)
    let ao = MyObj.deserialize(rnw.reader)
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
    let thedata = ['\x03', '\x00', '\x00', '\x00', 'H', 'i',
                   '!', '\x07', '\x00', '\x10']
    require(so.len == thedata.len)
    require(cast[seq[char]](so) == @thedata)
    var index = 0
    let reader = proc (c: Natural): seq[char] =
      result = thedata[index..<index+c]
      index += c
    let o = MyPreserved.deserialize(reader)
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
      let o = Variant.deserialize(rnw.reader)
      if o.x in 0'u8..(high(int8)-50).uint8:
        check(o.size() == 9)
        locase = true
      else:
        check(o.size() == 7)
        hicase = true
      o.serialize(rnw.writer)

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
    let rnw = get_random_reader_n_writer()
    var tests: int8 = 0
    while tests < 7:
      let o = NestedVar.deserialize(rnw.reader)
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
      o.serialize(rnw.writer)
