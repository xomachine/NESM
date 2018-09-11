from typesinfo import Context, TypeChunk
import macros

proc genBasic*(context: Context, size: int): TypeChunk {.compileTime.}
proc genSerialize*(name: NimNode, size: NimNode): NimNode {.compileTime.}
proc genDeserialize*(name: NimNode, size: NimNode): NimNode {.compileTime.}

from generator import getStreamName
from endians import swapEndian16, swapEndian32, swapEndian64
from streams import writeData, readData

proc genDeserialize*(name: NimNode, size: NimNode): NimNode =
  let STREAM_NAME = getStreamName()
  quote do:
    doAssert(`size` ==
           `STREAM_NAME`.readData(`name`.unsafeAddr, `size`),
           "Stream has not provided enough data")

proc genSwapCall(size: int): NimNode {.compileTime.} =
  case size
  of 2: bindSym("swapEndian16")
  of 4: bindSym("swapEndian32")
  of 8: bindSym("swapEndian64")
  else:
    error("The endian cannot be swapped due to no " &
          "implementation of swap for size = " & $size)
    newEmptyNode()

proc genDeserializeSwap(name: NimNode,
                        size: int): NimNode {.compileTime.} =
  let isize = newIntLitNode(size)
  let swapcall = genSwapCall(size)
  let STREAM_NAME = getStreamName()
  quote do:
    var thedata = newString(`isize`)
    doAssert(`STREAM_NAME`.readData(thedata.addr, `isize`) ==
           `isize`,
           "Stream has not provided enough data")
    `swapcall`(`name`.unsafeAddr, thedata.addr)

proc genSerialize*(name: NimNode, size: NimNode): NimNode =
  let STREAM_NAME = getStreamName()
  quote do:
    `STREAM_NAME`.writeData(`name`.unsafeAddr, `size`)

proc genSerializeSwap(name: NimNode,
                      size: int): NimNode {.compileTime.} =
  let isize = newIntLitNode(size)
  let swapcall = genSwapCall(size)
  let STREAM_NAME = getStreamName()
  quote do:
    var thedata = newString(`isize`)
    `swapcall`(thedata.addr, `name`.unsafeAddr)
    `STREAM_NAME`.writeData(thedata.unsafeAddr, `isize`)

proc genBasic*(context: Context, size: int): TypeChunk =
  result.size = proc (source: NimNode): NimNode =
    newIntLitNode(size)
  result.serialize = proc(source: NimNode): NimNode =
    if context.swapEndian and (size in [2, 4, 8]):
      genSerializeSwap(source, size)
    else:
      genSerialize(source, newIntLitNode(size))
  result.deserialize = proc(source: NimNode): NimNode =
    if context.swapEndian and (size in [2, 4, 8]):
      genDeserializeSwap(source, size)
    else:
      genDeserialize(source, newIntLitNode(size))


