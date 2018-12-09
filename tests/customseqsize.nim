from nesm import serializable
from streams import setPosition
import unittest
import helpers/rnw

{.hint[XDeclaredButNotUsed]:off.}

suite "Custom periodic size":
  test "Seq":
    serializable:
      type
        MySeq = object
          size: int32
          a: int32
          data: seq[int32] as {size: {}.size}
 
    let rnw = get_reader_n_writer()
    var o: MySeq
    o.data = random_seq_with(rand(20000).int32)
    o.size = max(0, o.data.len.int32 - 1)
    o.a = rand(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = MySeq.deserialize(rnw)
    check(o.a == dso.a)
    require(o.size == dso.size)
    require(o.size.int == dso.data.len)
    for i in 0..<o.size:
      check(o.data[i] == dso.data[i])

  test "strings":
    serializable:
      type
        MyString = object
          size: int32
          a: int32
          data: string as {size: {}.size}
 
    let rnw = get_reader_n_writer()
    var o: MyString
    o.data = get_random_string()
    o.size = max(0, o.data.len.int32 - 1)
    o.a = rand(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = MyString.deserialize(rnw)
    check(o.a == dso.a)
    require(o.size == dso.size)
    require(o.size.int == dso.data.len)
    for i in 0..<o.size:
      check(o.data[i] == dso.data[i])

  test "Seq of strings":
    serializable:
      type MySeqStr = object
        s: int32
        a: int32
        data: seq[string] as {size: {}.s}

    let rnw = get_reader_n_writer()
    var o: MySeqStr
    o.data = random_seq_with(get_random_string())
    o.s = max(0, o.data.len.int32 - 1)
    o.a = rand(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = MySeqStr.deserialize(rnw)
    require(o.s.int == dso.data.len)
    require(dso.s == o.s)
    check(dso.a == o.a)
    for i in 0..<o.s:
      check(o.data[i] == dso.data[i])

  test "Matrix":
    serializable:
      type Matrix = object
        lines: int32
        columns: int32
        data: seq[seq[int32]] as {size: {}.lines, size: {}.columns}

    let rnw = get_reader_n_writer()
    var o: Matrix
    o.columns = rand(1..20).int32
    proc get_line(): seq[int32] =
      result = newSeq[int32](o.columns)
      for i in 0..<o.columns:
        result[i] = rand(20000).int32
    o.data = random_seq_with(get_line())
    o.lines = max(0, o.data.len.int32 - 1)
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = Matrix.deserialize(rnw)
    require(o.lines.int == dso.data.len)
    require(o.lines == dso.lines)
    require(o.columns == dso.columns)
    for i in 0..<o.lines:
      check(dso.data[i].len == o.columns.int)
      for j in 0..<o.columns:
        check(o.data[i][j] == dso.data[i][j])

  test "Nesting":
    serializable:
      type Nested = object
        dsize: int32
        a: int32
        data: seq[int32] as {size: {}.dsize}
      type Nester = object
        a: Nested

    let rnw = get_reader_n_writer()
    var o: Nester
    o.a.data = random_seq_with(rand(20000).int32)
    o.a.dsize = max(0, o.a.data.len.int32 - 1)
    o.a.a = rand(20000).int32
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = Nester.deserialize(rnw)
    check(o.a.a == dso.a.a)
    require(o.a.dsize.int == dso.a.data.len)
    require(o.a.dsize == dso.a.dsize)
    for i in 0..<o.a.dsize:
      check(o.a.data[i] == dso.a.data[i])

  test "From inside":
    serializable:
      type NestedTuple = object
        length: int32
        data: tuple[name: string, code: seq[int32] as {size: {{}}.length}]

    let rnw = get_reader_n_writer()
    var o: NestedTuple
    o.data.name = get_random_string()
    o.data.code = random_seq_with(rand(20000).int32)
    o.length = max(0, o.data.code.len.int32 - 1)
    o.serialize(rnw)
    rnw.setPosition(0)
    let dso = NestedTuple.deserialize(rnw)
    check(o.data.name == dso.data.name)
    require(o.length == dso.length)
    require(o.length.int == dso.data.code.len)
    for i in 0..<o.length:
      check(o.data.code[i] == dso.data.code[i])
