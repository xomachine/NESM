from nesm import serializable
from endians import bigEndian32, littleEndian32
import helpers/rnw
import unittest

suite "Endianness support":
  test "Syntax":
    serializable:
      type SynTest = object
        a: int32
        set: {endian:bigEndian}
        b: int32
        set: {endian: littleEndian}
        c: int32

  test "[de]serialize":
    serializable:
      static:
        type EndianTest = object
          set: {endian: littleEndian}
          a: uint64
          b: uint32
          c: uint16
          set: {endian: bigEndian}
          d: uint64
          e: uint32
          f: uint16

    let teststring = "\x10\x00\x00\x00\x00\x00\x00\x00" &
                     "\x25\x00\x00\x00" & "\x15\x00" &
                     "\x00\x00\x00\x00\x00\x00\x00\x12" &
                     "\x00\x00\x00\x22" & "\x00\x16"
    let o = EndianTest.deserialize(teststring)
    check(o.a == 16)    
    check(o.b == 37)    
    check(o.c == 21)    
    check(o.d == 18)    
    check(o.e == 34)    
    check(o.f == 22)    
    let so = o.serialize()
    check(so == teststring)

  test "Arrays":
    serializable:
      static:
        type SomeArrays = object
          set: {endian: bigEndian}
          data: array[2, int16]
          lilstring: array[3, char]
          set: {endian: littleEndian}
          set: array[2, int16]

    let teststring = "\x00\x11\x00\x12hi!\x13\x00\x14\x00"
    let o = SomeArrays.deserialize(teststring)
    check(o.data[0] == 17)
    check(o.data[1] == 18)
    check(o.lilstring == ['h', 'i', '!'])
    check(o.set[0] == 19)
    check(o.set[1] == 20)
    let so = o.serialize()
    check(so == teststring)

  test "Inline syntax":
    serializable:
      static:
        type SomeInline = object
          set: {endian: bigEndian}
          od: int32
          sd: int32 as {endian: littleEndian}
          od2: int32
    let rnw = get_random_reader_n_writer()
    let dso = SomeInline.deserialize(rnw)
    var a: SomeInline
    bigEndian32(a.od.addr, rnw.buffer[0].addr)
    littleEndian32(a.sd.addr, rnw.buffer[4].addr)
    bigEndian32(a.od2.addr, rnw.buffer[8].addr)
    check(dso.od == a.od)
    check(dso.sd == a.sd)
    check(dso.od2 == a.od2)
