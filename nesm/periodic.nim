from typesinfo import Context, TypeChunk, estimateBasicSize, isBasic, BodyGenerator
import macros

proc genCStringDeserialize*(name: NimNode): NimNode {.compileTime.}
proc genCStringSerialize*(name: NimNode): NimNode {.compileTime.}
proc genPeriodic*(context: Context, elem: NimNode,
                  length: BodyGenerator): TypeChunk {.compileTime.}

from basics import genSerialize, genDeserialize
from generator import genTypeChunk, getStreamName
from utils import unfold
from streams import writeData, write, readChar

# Another workaround for https://github.com/nim-lang/Nim/issues/7889
proc writeData() = discard

proc genCStringDeserialize(name: NimNode): NimNode =
  let STREAM_NAME = getStreamName()
  quote do:
    block:
      var str = "" & `STREAM_NAME`.readChar()
      var index = 0
      while str[index] != '\x00':
        str &= `STREAM_NAME`.readChar()
        index += 1
      `name` = str[0..<index]

proc genCStringSerialize(name: NimNode): NimNode =
  let STREAM_NAME = getStreamName()
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

proc addSizeHeader(context: Context, length: BodyGenerator, mkExpr: NimNode, bodychunk: var TypeChunk) =
  let size_header_chunk = context.genTypeChunk(newIdentNode("int32"))
  let oldsize = bodychunk.size
  let lenvarname = newIdentNode("length" & $context.depth)
  bodychunk.size = proc(s:NimNode):NimNode =
    let presize = oldsize(s)
    let headersize = size_header_chunk.size(s)
    let r = newIdentNode("result")
    if presize.kind notin [nnkInfix, nnkIntLit, nnkCall]:
      quote do:
        `presize`
        `r` += `headersize`
    else:
      headersize.infix("+", presize)
  let oldserialize = bodychunk.serialize
  bodychunk.serialize = proc(s:NimNode): NimNode =
    let lens = length(s)
    let shc_ser = size_header_chunk.serialize(lenvarname)
    let pr_ser = oldserialize(s)
    quote do:
      block:
        var `lenvarname`: int32 = int32(`lens`)
        `shc_ser`
        `pr_ser`
  let olddeserialize = bodychunk.deserialize
  bodychunk.deserialize = proc(s:NimNode): NimNode =
    let sd = size_header_chunk.deserialize(lenvarname)
    let deserialization = olddeserialize(s)
    quote do:
      block:
        var `lenvarname`: int32
        `sd`
        `s` = `mkExpr`(`lenvarname`)
        `deserialization`

proc genSimple(context: Context, elem: NimNode,
               length: BodyGenerator): TypeChunk =
  let element =
    if elem.kind == nnkEmpty: "char"
    else: elem.repr
  let elemSize = estimateBasicSize(element)
  let eSize = newIntLitNode(elemSize)
  proc filler(gen: proc(x:NimNode, y:NimNode): NimNode): proc(s:NimNode): NimNode =
    result = proc (s: NimNode): NimNode =
      let lens = length(s)
      let size = (quote do: `lens` * `eSize`).unfold()
      let newsource = (quote do: `s`[0]).unfold()
      let serialization = gen(newsource, size)
      quote do:
        if `lens` > 0: `serialization`
  result.size = proc (s: NimNode): NimNode =
    let arraylen = length(s)
    arraylen.infix("*", newIntLitNode(elemSize))
  result.serialize = filler(genSerialize)
  result.deserialize = filler(genDeserialize)
  result.dynamic = not context.is_static
  result.has_hidden = false

proc genPeriodic(context: Context, elem: NimNode,
                 length: BodyGenerator): TypeChunk =
  let elemString = elem.repr
  let is_dynamic = length(newEmptyNode()).kind == nnkCall
  let makeExpr =
    if elem.kind == nnkEmpty:
      newIdentNode("newString")
    else:
      newTree(nnkBracketExpr, newIdentNode("newSeq"), elem)
  if (elemString.isBasic() or elem.kind == nnkEmpty) and
     not context.swapEndian:
    # For seqs or arrays of trivial objects
    result = context.genSimple(elem, length)
  else:
    # Complex subtypes
    let onechunk = context.genTypeChunk(elem)
    let index_letter = newIdentNode("index")
    let generator = proc (f: proc(s:NimNode): NimNode): proc(s:NimNode):NimNode =
      result = proc(s: NimNode): NimNode =
        let periodic_len = length(s)
        let newsource = (quote do: `s`[`index_letter`]).unfold()
        let chunk_expr = f(newsource)
        quote do:
          for `index_letter` in 0..<(`periodic_len`):
            `chunk_expr`
    result.serialize = generator(onechunk.serialize)
    result.deserialize = generator(onechunk.deserialize)
    if onechunk.dynamic:
      let r = newIdentNode("result")
      let sizeproc = proc (s:NimNode):NimNode =
        let sz = onechunk.size(s)
        r.infix("+=", sz)
      result.size = generator(sizeproc)
    else:
      let independentSize = onechunk.size(newEmptyNode())
      result.size = proc (s: NimNode): NimNode =
        let periodic_len = length(s)
        periodic_len.infix("*", independentSize)
  # Does not detects arrays
  if is_dynamic:
    addSizeHeader(context, length, makeExpr, result)

