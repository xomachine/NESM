import macros
from nesm.typesinfo import TypeChunk, Context
from nesm.basics import genBasic

proc estimateEnumSize(declaration: NimNode): int {.compileTime.} =
  var highest: uint64 = 0
  for c in declaration.children():
    case c.kind
    of nnkEnumFieldDef:
      c.expectMinLen(2)
      case c[1].kind
      of nnkPrefix:
        error("Negative values in enums are not supported due to unsertain" &
              " size evaluation mechanism.")
      of nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit,
         nnkUInt8Lit, nnkUInt16Lit, nnkUInt32Lit, nnkUInt64Lit:
        highest = c[1].intVal.uint64 + 1
      else:
        highest += 1
    of nnkIdent:
      highest += 1
    of nnkEmpty: discard
    else:
      error("Unexpected AST: " & c.treeRepr)
  let maxvalue = ((highest) shr 1).int64
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
  when not defined(disableEnumChecks):
    let olddeser = result.deserialize
    result.deserialize = proc (source: NimNode): NimNode =
      let check = quote do:
        if $(`source`) == $(ord(`source`)) & " (invalid data!)":
          raise newException(ValueError, "Enum value is out of range!")
      newTree(nnkStmtList, olddeser(source), check)


