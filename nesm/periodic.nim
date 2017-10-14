from nesm.typesinfo import Context, TypeChunk, estimateBasicSize, isBasic
from nesm.basics import genSerialize, genDeserialize
from nesm.generator import genTypeChunk, STREAM_NAME, correct_sum
from streams import writeData, write, readChar
import macros

proc genCStringDeserialize*(name: NimNode): NimNode {.compileTime.} =
  quote do:
    block:
      var str = "" & `STREAM_NAME`.readChar()
      var index = 0
      while str[index] != '\x00':
        str &= `STREAM_NAME`.readChar()
        index += 1
      `name` = str[0..<index]

proc genCStringSerialize*(name: NimNode): NimNode {.compileTime.} =
  quote do:
    `STREAM_NAME`.writeData(`name`[0].unsafeAddr,
                            `name`.len)
    `STREAM_NAME`.write('\x00')

proc findInChilds(a, b: NimNode): bool =
  if a == b: return true
  else:
    for ac in a.children():
      if ac.findInChilds(b):
        return true
    return false

proc genPeriodic*(context: Context, elem: NimNode,
                  length: proc (s:NimNode): NimNode,
                  ): TypeChunk =
  let elemString = elem.repr
  let lencheck = length(newEmptyNode())
  let is_array = lencheck.kind != nnkCall
  let lenvarname =
    if is_array: lencheck
    else: nskVar.genSym("length")
  if (elemString.isBasic() or elem.kind == nnkEmpty) and
     not context.swapEndian:
    # For seqs or arrays of trivial objects
    let element =
      if elem.kind == nnkEmpty: "char"
      else: elemString
    let elemSize = estimateBasicSize(element)
    let eSize = newIntLitNode(elemSize)
    result.size = proc (s: NimNode): NimNode =
      let arraylen = length(s)
      arraylen.infix("*", newIntLitNode(elemSize))
    result.serialize = proc (s: NimNode): NimNode =
      let lens = length(s)
      let size = (quote do: `lens` * `eSize`)
      let newsource = (quote do: `s`[0])
      let serialization = genSerialize(newsource, size)
      quote do:
        if `lens` > 0: `serialization`
    result.deserialize = proc (s: NimNode): NimNode =
      let lens = length(s)
      let size = (quote do: `lens` * `eSize`)
      let newsource = (quote do: `s`[0])
      let deserialization = genDeserialize(newsource, size)
      quote do:
        if `lens` > 0: `deserialization`
    result.dynamic = not context.is_static
    result.has_hidden = false
  else:
    # Complex subtypes
    let onechunk = context.genTypeChunk(elem)
    let index_letter = nskForVar.genSym("index")
    result.size = proc (s: NimNode): NimNode =
      let periodic_len = length(s)
      let newsource = (quote do: `s`[`index_letter`])
      let chunk_size = one_chunk.size(newsource)
      if not chunk_size.findInChilds(index_letter):
        periodic_len.infix("*", chunk_size)
      else:
        let chunk_expr = correct_sum(chunk_size)
        quote do:
          for `index_letter` in 0..<(`periodic_len`):
            `chunk_expr`
    result.serialize = proc(s: NimNode): NimNode =
      let periodic_len = length(s)
      let newsource = (quote do: `s`[`index_letter`])
      let chunk_expr = onechunk.serialize(newsource)
      quote do:
        for `index_letter` in 0..<(`periodic_len`):
          `chunk_expr`
    result.deserialize = proc(s: NimNode): NimNode =
      let lens = length(s)
      let newsource = (quote do: `s`[`index_letter`])
      let chunk_expr = onechunk.deserialize(newsource)
      quote do:
        for `index_letter` in 0..<(`lens`):
          `chunk_expr`
  if not is_array:
    let size_header_chunk = context.genTypeChunk(
      newIdentNode("int32"))
    let preresult = result
    result.size = proc(s:NimNode):NimNode =
      let presize = preresult.size(s)
      let headersize = size_header_chunk.size(s)
      let r = !"result"
      if presize.kind notin [nnkInfix, nnkIntLit, nnkCall]:
        quote do:
          `presize`
          `r` += `headersize`
      else:
        headersize.infix("+", presize)
    result.serialize = proc(s:NimNode): NimNode =
      let lens = length(s)
      let shc_ser = size_header_chunk.serialize(lenvarname)
      let pr_ser = preresult.serialize(s)
      quote do:
        var `lenvarname` = `lens`
        `shc_ser`
        `pr_ser`
    result.deserialize = proc(s:NimNode): NimNode =
      let init_template =
        if elem.kind == nnkEmpty: (quote do: newString)
        else: (quote do: newSeq[`elem`])
      let sd = size_header_chunk.deserialize(lenvarname)
      let deserialization = preresult.deserialize(s)
      quote do:
        var `lenvarname`: int32
        `sd`
        `s` = `init_template`(`lenvarname`)
        `deserialization`

