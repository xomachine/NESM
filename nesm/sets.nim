import macros
from nesm.typesinfo import TypeChunk, Context
from nesm.typesinfo import isBasic, estimateBasicSize
from nesm.enums import estimateEnumSize
from nesm.basics import genBasic

proc genSet*(context: Context, declaration: NimNode): TypeChunk {.compileTime.}

proc genSet(context: Context, declaration: NimNode): TypeChunk =
  declaration.expectMinLen(2)
  let undertype = declaration[1]
  let size =
    if ($undertype).isBasic():
      estimateBasicSize($undertype)
    else:
      estimateEnumSize(getType(undertype).last.last[2])
  context.genBasic(1 shl (size * 8 - 3))

