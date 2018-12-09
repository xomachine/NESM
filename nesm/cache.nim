from typesinfo import Context, initContext, TypeChunk

proc getContext*(): Context {.compileTime.}
proc storeContext*(context: Context) {.compileTime.}

import macrocache
import macros
from tables import `[]`, `[]=`, pairs
const ctxTable = CacheTable("nesm.nesm.context")
const SOURCENAME = "aliassource"
type ContextEntry {.pure.} = enum
  size
  serialize
  deserialize
  dynamic
  has_hidden
  maxcount

proc contains(self: CacheTable, key: string): bool {.compileTime.} =
  for k, v in self:
    if k == key:
      return true
  return false

proc storeContext(context: Context) =
  let THESOURCENAME = newTree(nnkBracketExpr, newIdentNode(SOURCENAME))
  for newfield in context.newfields:
    let chunk = context.declared[newfield]
    let sizecode = chunk.size(THESOURCENAME)
    let serializecode = chunk.serialize(THESOURCENAME)
    let deserializecode = chunk.deserialize(THESOURCENAME)
    let dynamic = chunk.dynamic.int.newLit()
    let has_hidden = chunk.has_hidden.int.newLit()
    let maxcount =
      if chunk.nodekind == nnkEnumTy:
        chunk.maxcount.newLit()
      else:
        false.newLit()
    if newfield notin ctxTable:
      when declared(debug):
        hint("Adding key: " & newfield)
      ctxTable[newfield] = newStmtList()
      for i in ContextEntry:
        ctxTable[newfield].add(newEmptyNode())
    else:
      when declared(debug):
        hint("Modifying key: " & newfield)
    ctxTable[newfield][ContextEntry.size.ord] = newBlockStmt(sizecode)
    ctxTable[newfield][ContextEntry.serialize.ord] = newBlockStmt(serializecode)
    ctxTable[newfield][ContextEntry.deserialize.ord] = newBlockStmt(deserializecode)
    ctxTable[newfield][ContextEntry.dynamic.ord] = dynamic
    ctxTable[newfield][ContextEntry.has_hidden.ord] = has_hidden
    ctxTable[newfield][ContextEntry.maxcount.ord] = maxcount

proc getContext(): Context =
  let THESOURCENAME = newIdentNode(SOURCENAME)
  result = initContext()
  for k, v in ctxTable:
    var tc: TypeChunk
    when declared(debug):
      hint("Extracting key: " & k)
    # >[0]<block "Name"[0]: >[1]<
    let sizecode = v[ContextEntry.size.ord][1]
    let serializecode = v[ContextEntry.serialize.ord][1]
    let deserializecode = v[ContextEntry.deserialize.ord][1]
    tc.size = proc(source: NimNode): NimNode =
      quote do:
        block:
          let `THESOURCENAME` = `source`.unsafeAddr
          `sizecode`
    tc.deserialize = proc(source: NimNode): NimNode =
      quote do:
        block:
          let `THESOURCENAME` = `source`.unsafeAddr
          `deserializecode`
    tc.serialize = proc(source: NimNode): NimNode =
      quote do:
        block:
          let `THESOURCENAME` = `source`.unsafeAddr
          `serializecode`
    tc.dynamic = v[ContextEntry.dynamic.ord].intVal.bool
    tc.has_hidden = v[ContextEntry.has_hidden.ord].intVal.bool
    if v[ContextEntry.maxcount.ord].kind == nnkUInt64Lit:
      tc.nodekind = nnkEnumTy
      tc.maxcount = cast[uint64](v[ContextEntry.maxcount.ord].intVal)
    result.declared[k] = tc
