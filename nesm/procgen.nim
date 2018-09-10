from typesinfo import BodyGenerator, Context
from streams import newStringStream, Stream
from tables import `[]=`
from generator import getStreamName, genTypeChunk
from settings import applyOptions
import macros
type
  ProcType = enum
    serialize
    deserialize
    size

proc makeDeclaration(typenode: NimNode, kind: ProcType, is_exported: bool,
                     is_static: bool, bodygen: BodyGenerator): NimNode {.compileTime.}
proc makeSerializeStreamConversion(typenode: NimNode,
                                   is_exported: bool): NimNode {.compileTime.}
proc makeDeserializeStreamConversion(typenode: NimNode,
                                     is_exported: bool): NimNode {.compileTime.}
proc generateProcs*(context: var Context, obj: NimNode): NimNode {.compileTime.}

proc makeDeclaration(typenode: NimNode, kind: ProcType, is_exported: bool,
                     is_static: bool, bodygen: BodyGenerator): NimNode =
  ## Makes declaration of size, serialize or deserialize procs
  let procname =
    if is_exported: newIdentNode($kind).postfix("*")
    else: newIdentNode($kind)
  let bgsource = case kind
    of deserialize: newIdentNode("result")
    else: nskParam.genSym("obj")
  let body = bodygen(bgsource)
  let STREAM_NAME = getStreamName()
  case kind
  of serialize:
    quote do:
      proc `procname`(`bgsource`: `typenode`, `STREAM_NAME`: Stream) = `body`
  of deserialize:
    quote do:
      proc `procname`(a: typedesc[`typenode`],
                      `STREAM_NAME`: Stream): `typenode` = `body`
  of size:
    if is_static:
      quote do:
        proc `procname`(`bgsource`: typedesc[`typenode`]): Natural = `body`
    else:
      quote do:
        proc `procname`(`bgsource`: `typenode`): Natural = `body`

proc makeSerializeStreamConversion(typenode: NimNode,
                                   is_exported: bool): NimNode =
  ## Makes overloaded serialize proc which returns ``string`` as input instead
  ## of writing data to the ``Stream``
  let rawprocname = newIdentNode("serialize")
  let procname = if is_exported: rawprocname.postfix("*") else: rawprocname
  quote do:
    proc `procname`(obj: `typenode`): string =
      let ss = newStringStream()
      `rawprocname`(obj, ss)
      ss.data

proc makeDeserializeStreamConversion(typenode: NimNode,
                                     is_exported: bool): NimNode =
  ## Makes overloaded deserialize proc which takes ``string`` as input instead
  ## of ``Stream``
  let rawprocname = newIdentNode("deserialize")
  let sizeident = newIdentNode("size")
  let procname = if is_exported: rawprocname.postfix("*") else: rawprocname
  quote do:
    proc `procname`(a: typedesc[`typenode`],
                    data: string | seq[byte|char|uint8|int8]): auto =
      doAssert(data.len >= `typenode`.`sizeident`(),
             "Given sequence should contain at least " &
             $(`typenode`.`sizeident`()) & " bytes!")
      let ss = newStringStream(cast[string](data))
      `rawprocname`(`typenode`, ss)

proc generateProcs(context: var Context, obj: NimNode): NimNode =
  ## Generates ``NimNode``s for serialize, deserialize and size procs related
  ## to given type declaration.
  expectKind(obj, nnkTypeDef)
  expectMinLen(obj, 3)
  expectKind(obj[1], nnkEmpty)
  let (newcontext, typedeclaration) =
    if obj[0].kind == nnkPragmaExpr:
      (context.applyOptions(obj[0][1]), obj[0][0])
    else:
      (context, obj[0])
  let is_shared = typedeclaration.kind == nnkPostfix
  let typenode = if is_shared: typedeclaration.basename else: typedeclaration
  let body = obj[2]
  let typeinfo = genTypeChunk(newcontext, body)
  context.declared[$typenode] = typeinfo
  let size_proc = makeDeclaration(typenode, size, is_shared, context.is_static,
                                  typeinfo.size)
  let stream_serializer = makeDeclaration(typenode, serialize, is_shared,
    context.is_static, typeinfo.serialize)
  let stream_deserializer =
    makeDeclaration(typenode, deserialize, is_shared, context.is_static,
                    typeinfo.deserialize)
  let string_serializer = makeSerializeStreamConversion(typenode, is_shared)
  let string_deserializer =
    if context.is_static: makeDeserializeStreamConversion(typenode ,is_shared)
    else: newEmptyNode()
  newStmtList(size_proc, stream_serializer, string_serializer,
              stream_deserializer, string_deserializer)


