import macros
from typesinfo import TypeChunk, Context
from basics import genBasic

proc estimateEnumSize(declaration: NimNode): int {.compileTime.} =
  var maxvalue: int64 = 0
  for c in declaration.children():
    if c.kind == nnkEnumFieldDef:
      c.expectMinLen(2)
      let num = c[1].intVal
      let normalized: int64 =
        if num < 0: abs(num)
        else: (num shr 1).int64 + 1
      if normalized > maxvalue:
        maxvalue = normalized
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


