from nesm import serializable
import unittest

suite "Endianness support":
  test "Syntax":
    serializable:
      type SynTest = object
        a: int32
        set! :bigEndian
        b: int32
        set! :littleEndian
        c: int32

  test "[de]serialize":
    serializable:
      static:
        type EndianTest = object
          set! :littleEndian
          a: uint64
          b: uint32
          c: uint16
          set! :bigEndian
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
