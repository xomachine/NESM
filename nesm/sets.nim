import macros
from typesinfo import TypeChunk, Context

proc genSet*(context: Context, declaration: NimNode): TypeChunk {.compileTime.}

from strutils import `%`
from tables import contains, `[]`
from typesinfo import isBasic, estimateBasicSize
from basics import genBasic

proc genSet(context: Context, declaration: NimNode): TypeChunk =
  declaration.expectMinLen(2)
  let undertype = $declaration[1]
  if undertype.isBasic():
    let size = estimateBasicSize(undertype)
    result = context.genBasic(1 shl (size * 8 - 3))
  elif undertype in context.declared:
    let enumtype = context.declared[undertype]
    if enumtype.nodekind != nnkEnumTy:
      error("The type '$1' neither of enum or basic type!" % undertype)
    result = context.genBasic(int(enumtype.maxcount + 7) div 8)
  else:
    error("Impossible type under the set: " & declaration.repr)

