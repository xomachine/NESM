import macros
from typesinfo import TypeChunk, Context


proc getCount*(declaration: NimNode): uint64 {.compileTime.}
proc genEnum*(context:Context, declaration: NimNode): TypeChunk {.compileTime.}

from basics import genBasic

proc getCount(declaration: NimNode): uint64 =
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
        result = c[1].intVal.uint64 + 1
      of nnkPar:
        result = c[1][0].intVal.uint64 + 1
      else:
        result += 1
    of nnkIdent, nnkSym:
      result += 1
    of nnkEmpty: discard
    else:
      error("Unexpected AST: " & c.treeRepr)

proc estimateEnumSize(highest: uint64): int {.compileTime.} =
  let maxvalue = ((highest) shr 1).int64
  if maxvalue in 0'i64..int8.high.int64: 1
  elif maxvalue in (int8.high.int64+1)..int16.high.int64: 2
  elif maxvalue in (int16.high.int64+1)..int32.high.int64: 4
  elif maxvalue in (int32.high.int64+1)..int64.high: 8
  else: 0

proc genEnum(context: Context, declaration: NimNode): TypeChunk =
  let count = getCount(declaration)
  let sizeOverrides = len(context.overrides.size)
  const intErrorMsg = "Only plain int literals allowed in size pragma " &
                      "under serializable macro, not "
  let estimated =
    if sizeOverrides == 0:
      estimateEnumSize(count)
    elif sizeOverrides == 1:
      (let size = context.overrides.size[0][0];
       if size.kind != nnkIntLit: error(intErrorMsg & size.repr, size);
       size.intVal.int)
    else:
      (error("Incorrect amount of size options encountered", declaration); 0)
  if estimated == 0:
    error("Internal error while estimating enum size", declaration)
  result = context.genBasic(estimated)
  result.nodekind = nnkEnumTy
  result.maxcount = count
  when not defined(disableEnumChecks):
    let olddeser = result.deserialize
    let enumdecl = newStrLitNode(declaration.repr)
    result.deserialize = proc (source: NimNode): NimNode =
      let check = quote do:
        if $(`source`) == $(ord(`source`)) & " (invalid data!)":
          raise newException(ValueError, "Enum value is out of range: " &
            $(`source`) & "\nCorrect values are:\n" & `enumdecl`)
      newTree(nnkStmtList, olddeser(source), check)

