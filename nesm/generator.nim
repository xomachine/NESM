import macros
from typesinfo import TypeChunk, Context

proc genTypeChunk*(immutableContext: Context,
                   thetype: NimNode): TypeChunk {.compileTime.}

static:
  let STREAM_NAME* = newIdentNode("thestream")

from tables import Table, contains, `[]`, `[]=`, initTable, pairs
from sequtils import mapIt, foldl, toSeq, filterIt
from strutils import `%`
from utils import unfold, correct_sum
from typesinfo import isBasic, estimateBasicSize
from objects import genObject
from basics import genBasic
from periodic import genPeriodic, genCStringDeserialize, genCStringSerialize
from enums import genEnum
from sets import genSet


proc dig(node: NimNode, depth: Natural): NimNode {.compileTime.} =
  if depth == 0:
    return node
  case node.kind
  of nnkDotExpr:
    node.expectMinLen(1)
    node[0].dig(depth - 1)
  of nnkCall:
    node.expectMinLen(2)
    node[1].dig(depth - 1)
  of nnkEmpty:
    node
  of nnkIdent, nnkSym:
    error("Too big depth to dig: " & $depth)
    newEmptyNode()
  else:
    error("Unknown symbol: " & node.treeRepr)
    newEmptyNode()

proc insert_source(length_declaration, source: NimNode,
                   depth: Natural): NimNode  =
  if length_declaration.kind == nnkCurly:
    if length_declaration.len == 1 and length_declaration[0].kind == nnkCurly:
      return length_declaration[0].insert_source(source, depth + 1)
    elif length_declaration.len == 0:
      return source.dig(depth)
  if length_declaration.len == 0:
    return length_declaration
  else:
    result = newNimNode(length_declaration.kind)
    for child in length_declaration.children():
      result.add(child.insert_source(source, depth))

proc incrementDepth(ctx: Context): Context {.compileTime.} =
  result = ctx
  result.depth += 1

proc handleSizeOption(context: Context, elem: NimNode = newEmptyNode()): TypeChunk =
  var subcontext = context
  let capture = subcontext.overrides.size.pop()
  let size = capture.size
  let relative_depth = context.depth - capture.depth
  let len_proc = proc (s: NimNode): NimNode =
    (quote do: (`s`.len())).unfold()
    # Parentesis is important because it forces genPeriodic to treat
    # data as array and do not generate length code for it
    # (it is not very elegant thougth)
  result = context.genPeriodic(elem, len_proc)
  let olddeser = result.deserialize
  result.deserialize = proc (s: NimNode): NimNode =
    let origin = size.insert_source(s, relative_depth)
    let deser = olddeser(s)
    if elem.kind == nnkEmpty:
      quote do:
        `s` = newString(`origin`)
        `deser`
    else:
      quote do:
        `s` = newSeq[`elem`](`origin`)
        `deser`

proc genTypeChunk(immutableContext: Context, thetype: NimNode): TypeChunk =
  let context = immutableContext.incrementDepth()
  result.has_hidden = false
  result.nodekind = thetype.kind
  case thetype.kind
  of nnkIdent, nnkSym:
    # It's a type, declared as identifier. Might be a basic
    # type or
    # some of previously declared type in serializable block
    let plaintype = $thetype
    if plaintype.isBasic():
      let size = estimateBasicSize(plaintype)
      result = context.genBasic(size)
      case context.overrides.sizeof.len:
      of 0: discard
      of 1:
        assert(not context.is_static,
               "Sizeof option is not allowed in the static context!")
        assert(plaintype[0..2] in ["uin", "int"],
               "The sizeof field must be an integer type!")
        let prev_serialize = result.serialize
        let capture = context.overrides.sizeof[0]
        let relative_depth = context.depth - capture.depth
        result.serialize = proc(source: NimNode): NimNode =
          let origin = capture.size.insert_source(source, relative_depth)
          let tmpvar = nskLet.genSym("seqLen")
          let preser = prev_serialize(tmpvar)
          quote do:
            let `tmpvar` = cast[`thetype`](`origin`.len)
            `preser`
      else:
        error("It is impossible to use more than one sizeof options at once!")
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
    elif thetype.repr == "string":
      if context.is_static:
        error("Strings are not allowed in static context")
      assert(context.overrides.size.len in 0..1, "To many 'size' options")
      if context.overrides.size.len > 0:
        result = context.handleSizeOption()
      else:
        let len_proc = proc (s: NimNode): NimNode =
            (quote do: len(`s`)).unfold()
        result = context.genPeriodic(newEmptyNode(), len_proc)
    elif thetype.repr == "cstring":
      if context.is_static:
        error("CStrings are not allowed in static context")
      result.serialize = proc (s: NimNode): NimNode =
        genCStringSerialize(s)
      result.deserialize = proc (s: NimNode): NimNode =
        genCStringDeserialize(s)
      result.size = proc (s: NimNode): NimNode =
        (quote do: len(`s`) + 1).unfold()
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
        error("Dynamic types are not supported in static" &
              " structures")
      let elem = thetype[1]
      if context.overrides.size.len > 0:
        result = context.handleSizeOption(elem)

      else:
        let seqLen = proc (source: NimNode): NimNode =
          (quote do: len(`source`)).unfold()
        result = context.genPeriodic(elem, seqLen)
    of "set":
      result = context.genSet(thetype)
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
      quote do:
        var `tmp` = cast[`basetype`](`source`)
        `deserialization`
        `source` = cast[type(`source`)](`tmp`)
  of nnkNilLit:
    result = context.genObject(newTree(nnkRecList, thetype))
  else:
    error("Unexpected AST: " & thetype.treeRepr & "\n at " & thetype.lineinfo())
  result.dynamic = not context.is_static


