
from macros import error, warning
from macros import NimNodeKind, nnkEnumTy, NimIdent
from tables import Table, initTable

const basic_types = [
  "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64",
    "bool", "char", "byte", "float32", "float64", "int", "uint", "float"
]

type
  BodyGenerator* = proc (source: NimNode): NimNode
  TypeChunk* = object
    size*: BodyGenerator
    serialize*: BodyGenerator
    deserialize*: BodyGenerator
    dynamic*: bool
    has_hidden*: bool
    case nodekind*: NimNodeKind
    of nnkEnumTy:
      maxcount*: uint64
    else: discard

  SizeCapture* = tuple
    size: NimNode
    depth: Natural

  Overrides* = tuple
    size: seq[SizeCapture]
    sizeof: seq[SizeCapture]

  Context* = object
    declared*: Table[string, TypeChunk]
    newfields*: seq[string]
    overrides*: Overrides
    depth*: Natural
    is_static*: bool
    swapEndian*: bool

proc initContext*(): Context {.compileTime.} =
  result.overrides.size = newSeq[SizeCapture]()
  result.overrides.sizeof = newSeq[SizeCapture]()
  result.newfields = newSeq[string]()
  result.declared = initTable[string, TypeChunk]()
  result.depth = 0
  result.is_static = false
  result.swapEndian = false

proc isBasic*(thetype: string): bool {.compileTime.} =
  thetype in basic_types

proc estimateBasicSize*(thetype: string): int {.compileTime.} =
  case thetype
  of "char", "byte", "uint8", "int8", "bool": sizeof(int8)
  of "uint16", "int16": sizeof(int16)
  of "uint32", "int32", "float32": sizeof(int32)
  of "uint64", "int64", "float64": sizeof(int64)
  of "uint", "int", "float":
    when defined(allow_undefined_type_size):
      warning("You are using VERY dangerous option " &
          "'allow_undefined_type_size'." &
          " Please try to keep basic types size defined explicitly and " &
          "avoid this option. If it is impossible, well you are on your " &
          "own. The library can not guarantee that your objects will be " &
          "deserialized in proper way on devices with different arch.")
      case thetype
      of "uint": sizeof(uint)
      of "int": sizeof(int)
      of "float": sizeof(float)
      else: 0
    else:
      error(thetype & "'s size is undecided and depends from architecture." &
        " Consider using " & thetype & "32 or other specific type.")
      0
  else:
    error("Can not estimate size of type " & thetype)
    0
