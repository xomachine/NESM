import macros
from nesm.typesinfo import TypeChunk, Context
from nesm.basics import genBasic

proc estimateEnumSize(declaration: NimNode): int {.compileTime.} =
  var lowest: uint64 = 0
  var highest: uint64 = 0
  var residue: uint64 = 0
  for c in declaration.children():
    case c.kind
    of nnkEnumFieldDef:
      c.expectMinLen(2)
      case c[1].kind
      of nnkPrefix:
        residue = c[1][1].intVal.uint64
        if residue > lowest:
          lowest = residue
        highest = 0
      else:
        highest = c[1].intVal.uint64
        residue = 0
    of nnkIdent:
      if residue > 0'u64: residue -= 1
      else: highest += 1
    of nnkEmpty: discard
    else:
      error("Unexpected AST: " & c.repr)
  let maxvalue = (max(lowest, highest) shr 1).int64 + 1
  case maxvalue
  of 0..int8.high: 1
  of (-int8.low)..int16.high: 2
  of (-int16.low)..int32.high: 4
  of (-int32.low)..int64.high: 8
  else: 0


proc genEnum*(context:Context, declaration: NimNode): TypeChunk {.compileTime.}=
  let estimated = estimateEnumSize(declaration)
  if estimated == 0: error("Internal error while estimating enum size")
  result = context.genBasic(estimated)


