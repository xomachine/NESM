import macros
from typesinfo import isBasic, estimateBasicSize
from typesinfo import TypeChunk, Context
from tables import Table, contains, `[]`, `[]=`, initTable,
                   pairs
from strutils import `%`
from sequtils import mapIt, foldl, toSeq, filterIt

proc genTypeChunk*(context: Context, thetype: NimNode): TypeChunk {.compileTime.}
proc correct_sum*(part_size: NimNode): NimNode {.compileTime.}

static:
  let STREAM_NAME* = !"thestream"

from objects import genObject
from basics import genBasic
from periodic import genPeriodic, genCStringDeserialize, genCStringSerialize
from enums import genEnum


proc correct_sum(part_size: NimNode): NimNode =
  let result_node = newIdentNode("result")
  if part_size.kind in [nnkStmtList, nnkCaseStmt]:
    part_size
  else:
    result_node.infix("+=", part_size)

proc genTypeChunk(context: Context, thetype: NimNode): TypeChunk =
  result.has_hidden = false
  case thetype.kind
  of nnkIdent, nnkSym:
    # It's a type, declared as identifier. Might be a basic
    # type or
    # some of previously declared type in serializable block
    let plaintype = $thetype
    if plaintype.isBasic():
      let size = estimateBasicSize(plaintype)
      result = context.genBasic(size)
    elif plaintype in context.declared:
      let declared_type = context.declared[plaintype]
      if declared_type.dynamic and context.is_static:
        error("Only static objects can be nested into" &
              " static objects, but '" & plaintype &
              "' is not a static object!")
      if declared_type.has_hidden:
        warning("Seems like the " & plaintype &
          " (at " & thetype.lineinfo() & ")" &
          " have hidden fields inside. This may lead to" &
          " compile error if the " & plaintype & " was " &
          "imported from another module. Consider including" &
          " imported module or sharing " & plaintype & "'s" &
          " fields via '*' postfix")
      return context.declared[plaintype]
    elif thetype.repr == "string" and not context.is_static:
      let len_proc = proc (s: NimNode):NimNode =
        (quote do: len(`s`)).last
      result = context.genPeriodic(newEmptyNode(), len_proc)
    elif thetype.repr == "cstring" and not context.is_static:
      result.serialize = proc (s: NimNode): NimNode =
        genCStringSerialize(s)
      result.deserialize = proc (s: NimNode): NimNode =
        genCStringDeserialize(s)
      result.size = proc (s: NimNode): NimNode =
        (quote do: len(`s`) + 1).last
    else:
      error(("Type $1 is not a basic " % plaintype) &
            "type nor a complex type under 'serializable'" &
            " block!")
  of nnkBracketExpr:
    # The template type. typename[someargs].
    expectMinLen(thetype, 2)
    let name = $thetype[0]
    case name
    of "array":
      expectMinLen(thetype, 3)
      let elemType = thetype[2]
      let sizeDecl = thetype[1]
      let arrayLen =
        if sizeDecl.kind == nnkInfix and
           sizeDecl[0].repr == "..":
          newTree(nnkPar,
                  sizeDecl[2].infix("+", newIntLitNode(1)))
        else:
          sizeDecl
      let sizeproc = proc (source: NimNode): NimNode =
        arrayLen
      result = context.genPeriodic(elemType, sizeproc)
    of "seq":
      if context.is_static:
        error("Dynamic types not supported in static" &
              " structures")
      let elem = thetype[1]
      let seqLen = proc (source: NimNode): NimNode =
        (quote do: len(`source`)).last
      result = context.genPeriodic(elem, seqLen)
    else:
      error("Type $1 is not supported!" % name)
  of nnkTupleTy, nnkRecList:
    result = context.genObject(thetype)
  of nnkObjectTy:
    expectMinLen(thetype, 3)
    assert(thetype[1].kind == nnkEmpty,
           "Inheritence not supported in serializable")
    return context.genTypeChunk(thetype[2])
  of nnkRefTy:
    expectMinLen(thetype, 1)
    let objectchunk = context.genTypeChunk(thetype[0])
    result.has_hidden = objectchunk.has_hidden
    result.size = objectchunk.size
    result.serialize = objectchunk.serialize
    result.deserialize = proc(source: NimNode): NimNode =
      result = newStmtList(parseExpr("new(result)"))
      result.add(objectchunk.deserialize(source))
  of nnkEnumTy:
    result = context.genEnum(thetype)
  of nnkDistinctTy:
    expectMinLen(thetype, 1)
    let basetype = thetype[0]
    let distincted = context.genTypeChunk(basetype)
    let tmp = nskVar.genSym("tmp")
    result.has_hidden = true
    result.size = distincted.size
    result.serialize = proc(source: NimNode): NimNode =
      let serialization = distincted.serialize(tmp)
      quote do:
        var `tmp` = cast[`basetype`](`source`)
        `serialization`
    result.deserialize = proc(source: NimNode): NimNode =
      let deserialization = distincted.deserialize(tmp)
      let r = !"result"
      quote do:
        var `tmp` = cast[`basetype`](`source`)
        `deserialization`
        cast[type(`r`)](`tmp`)
  else:
    discard
    error("Unexpected AST")
  result.dynamic = not context.is_static


