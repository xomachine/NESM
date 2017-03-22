
from macros import error
from tables import Table

const basic_types = [
  "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64",
    "bool", "char", "byte", "float32", "float64"
]

type
  TypeChunk* = object
    size*: proc(source: NimNode): NimNode
    serialize*: proc(source: NimNode): NimNode
    deserialize*: proc(source: NimNode): NimNode
    dynamic*: bool
    has_hidden*: bool

  Context* = object
    declared*: Table[string, TypeChunk]
    is_static*: bool
    swapEndian*: bool

proc isBasic*(thetype: string): bool =
  thetype in basic_types

proc estimateBasicSize*(thetype: string): int {.compileTime.} =
  case thetype
  of "char", "byte", "uint8", "int8", "bool": sizeof(int8)
  of "uint16", "int16": sizeof(int16)
  of "uint32", "int32", "float32": sizeof(int32)
  of "uint64", "int64", "float64": sizeof(int64)
  of "uint", "int", "float":
    error(thetype & "'s size is undecided and depends from architecture." &
      " Consider using " & thetype & "32 or other specific type.")
    0
  else:
    error("Can not estimate size of type " & thetype)
    0
