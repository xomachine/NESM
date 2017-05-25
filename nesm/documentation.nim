
## **NESM** is a tool that generates serialization and deserialization
## code for a given object. This library provides a macro called
## `serializable` inside which
## the object description should be placed.
##
## For example:
##
## .. code-block:: nim
##   serializable:
##     type Ball = object
##       weight: float32
##       diameter: int32
##       isHollow: bool
##
## In this example you could notice that `int32` and `float32`
## declarations are used
## instead of just `int` and `float`. It is necessary to avoid
## an ambiguity in
## declarations on different platforms.
##
## The code in example will be transformed into the following code
## (the resulting
## code can be seen when **-d:debug** is passed to Nim compiler):
##
## .. code-block:: nim
##  type
##    Ball = object
##      weight: float32
##      diameter: int32
##      isHollow: bool
##
##  proc size(obj: Ball): int =
##    result += 4
##    result += 4
##    result += 1
##    result += 0
##
##  proc serialize(obj: Ball; thestream: Stream) =
##     discard
##     thestream.writeData(obj.weight.unsafeAddr, 4)
##     thestream.writeData(obj.diameter.unsafeAddr, 4)
##     thestream.writeData(obj.isHollow.unsafeAddr, 1)
##
##   proc serialize(obj: Ball): string =
##     let ss142002 = newStringStream()
##     serialize(obj, ss142002)
##     ss142002.data
##
##   proc deserialize(thetype142004: typedesc[Ball]; thestream: Stream): Ball =
##     discard
##     assert(4 ==
##         thestream.readData(result.weight.unsafeAddr, 4),
##            "Stream was not provided enough data")
##     assert(4 ==
##         thestream.readData(result.diameter.unsafeAddr, 4),
##            "Stream was not provided enough data")
##     assert(1 ==
##         thestream.readData(result.isHollow.unsafeAddr, 1),
##            "Stream was not provided enough data")
##
## As you may see from the code above, the macro generates three kinds
## of procedures: serializer, deserializer and size estimator.
## The serialization is being performed in a following way:
## each memory region of variable is copied
## to the resulting stream back-to-back.
## This approach achieves both of smallest
## serialized object size and independence from the compilator
## specific object representation.
##
## At the moment the following types of object are supported:
## - Aliases from basic types or previously defined in this block:
##     .. code-block:: nim
##       type MyInt = int16
##
## - Distinct types from basic types or previously defined in this block:
##     .. code-block:: nim
##       type MyInt = distinct int16
##
## - Tuples, objects and arrays:
##     .. code-block:: nim
##       type MyTuple = tuple[a: float64, b: int64]
##
## - Nested objects defined in *serializable* block:
##     .. code-block:: nim
##       type MyNestedObject = object
##         a: float64
##         b: int64
##       type MyObject = object
##         a: float32
##         b: MyNestedObject
##
## - Nested arrays and tuples:
##     .. code-block:: nim
##       type Matrix = array[0..4, array[0..4, int32]]
##
## - Sequencies and strings:
##     .. code-block:: nim
##       type MySeq = object
##         data: seq[string]
##
## - Null terminated strings (3-byte smaller but slower than strings):
##     .. code-block:: nim
##       type NTString = cstring
##
## - Object variants with nested case statements:
##     .. code-block:: nim
##       type Variant = object
##         case has_sign: bool
##         of true:
##           a: int32
##         else:
##           case bits: uint8
##           of 32:
##             b: uint32
##           of 16:
##             c: uint16
##           else:
##             d: seq[uint8]
##
## - Enumerates:
##     .. code-block:: nim
##       type Enumerate = enum
##         A
##         B = "It's B"
##         C = (233, "C is here")
##         D = 455
##
## - Sets:
##     .. code-block:: nim
##       type CharSet = set[char]
##
## Static types
## ------------
##
## There is also a special keyword exists for structures which size
## is known at compile time. The type declarations placed under the
## `static` section inside the `serializable` section will get
## three key differences from the regular declarations:
##
## - the `size` procedure will be receiving typedesc parameter
##   instead of instance of the
##   object and can be used at compile time
##
## - a new `deserialize` procedure will be generated that receives
##   a data containers (like a seq[byte] or a string) in addition
##   to receiver closure procedure.
##
## - any dynamic structures like sequencies or strings will lead
##   to compile time errors (because their size can not be
##   estimated at compile time)
##
## The example above with `static` section will be look like:
##
## .. code-block:: nim
##   serializable:
##     static :
##         type
##           Ball = object
##             weight: float32
##             diameter: int32
##             isHollow: bool
##
## And the differeces will occur in following procedures:
##
## .. code-block:: nim
##   proc size(thetype: typedesc[Ball]): int =
##     (0 + 4 + 4 + 1)
##   
##   proc deserialize(thetype: typedesc[Ball];
##                   data: seq[byte | char | int8 | uint8] | string): Ball =
##     assert(data.len >= type(result).size(), "Given sequence should contain at least " &
##         $ (type(result).size()) & " bytes!")
##     let ss142004 = newStringStream(cast[string](data))
##     deserialize(type(result), ss142004)
##
## Serialization options
## ---------------------
## The serialization process can be controlled via the special syntax
## **{<key>: <value>, <key>: <value>,...}**. There are three ways of
## using this syntax:
##
## * From invocation to the end of object or another invocation
##
##   .. code-block:: nim
##     serializable:
##       type MyType = object
##         set: {<options>}
##         ... # all fields until the end of object will be affected
##         ... # another set: {<options>} can override previous one
##
## * For converted structure
##
##   .. code-block:: nim
##     toSerializable(TheType, <options>)
##     # NOTE: curly braces are not required here
##
## * For particular field (inline)
##
##   .. code-block:: nim
##     serializable:
##       type MyType = object
##         typical_field: string
##         field_with_special_rules: int32 {<options>} # inline options
##         # NOTE: inline options have highest priority
##         another_typical_field: float32
##
## The serialization options themself are described in the paragraphs they are
## related.
##
## Endianness switching
## -----------------
## There is a way exists to set which endian should be used
## while [de]serialization particular structure or part of
## the structure. A special keyword **endian** in serialization options
## allows to set the endian.
## E.g.:
##
## .. code-block:: nim
##   serializable:
##     type Ball = object
##       weight: float32        # This value will be serialized in *cpuEndian* endian
##       set: {endian: bigEndian}
##       diameter: int32        # This value will be serialized in big endian regardless of *cpuEndian*
##       set: {endian: littleEndian}     # Only "bigEndian" and "littleEndian" values allowed
##       color: array[3, int16] # Values in this array will be serialized in little endian
##
## The generated code will use the **swapEndian{16|32|64}()**
## calls from the endians module to change endianness.
##
## Usage of int, float, uint types without size specifier
## ------------------------------------------------------
## By default the serializable macro throws an error when the type
## under the macro contains basic type description without size specification.
## For example, the following code will cause an error:
##
## .. code-block:: nim
##   serializable:
##     type MyInt = distinct int
##
## To avoid this behaviour one can tell the macro to allow all basic type
## description without size specification
## by using **-d:allow_undefined_type_size** compiler switch.
## You must avoid to use this switch as far as possible because when
## the switch enabled the library can not guarantee proper deserialization
## of objects on devices with different architectures.
##
## Converting existent types to serializable
## -----------------------------------------
## In case when the type to be serialized cannot be rewriten under the
## *serializable* macro, there is **toSerializable** macro exist.
## The type description given to this macro produces exactly the same
## effect as the type declaration placed under the *serializable* macro.
## Do not forget to make fields of the type visible for serialization
## procedures generated by using asteriks notation or by including
## (not importing) module with type declaration.
## E.g.:
##
## .. code-block:: nim
##   from basic2d import Point2d
##   # Point2d already have all the fields visible, so including not required
##   toSerializable(Point2d) # Generation of serialization procedures
##   ...
##   include oids # Oid's fields are visible only inside the module, so including is necessary
##   toSerializable(Oid)
##
## Enum correctness checking
## -------------------------
## **NESM** is checking enum correctness after deserialization by default.
## If deserialized value is not one of enum ordinals then the **ValueError**
## will be raised. To disable such a behaviour user may use the
## **-d:disableEnumChecks** compiler switch.
##
## Future ideas
## ------------
## The following will not necessarily be done but may be
## realized on demand
## * the data aligning support
##   (useful for reading custom data, not created by
##   this macro. can be partially done at client side
##   via modification of writer/obtainer)
## * implement some dynamic dictonary type
##   (not required actually because it can be
##   easily implemented on client side)
##
type TheType* = object
  ## This type will be used as example to show which procedures will be generated
  ## by the **serializable** macro.
proc size*(thetype: typedesc[TheType]): int =
  ## Returns the size of serialized type. The type should be
  ## placed under the **static** section inside the
  ## **serializable** macro to access this procedure.
  ## The procedure could be used
  ## at compile time.
  0

proc size*(thetype: TheType): int =
  ## Returns the size of serialized type. Available for types
  ## which declarations is not placed under the **static**
  ## section.
  discard

proc serialize*(obj: TheType; stream: Stream) =
  ## Serializes `TheType` and writes result to the
  ## given `stream`.
  discard

proc serialize*(obj: TheType): string =
  ## Serializes `TheType` to string.
  ## Underlying implementation uses StringStream and
  ## `serialize()` procedure above.
  ## More detailed description can be found
  ## in the top level documentation.
  discard

proc deserialize*(thetype: typedesc[TheType],
                  stream: Stream): TheType
  {.raises: AssertionError.} =
  ## Interprets the data received from the `stream`
  ## as `TheType` and deserializes it then.
  ## When the stream will not provide enough bytes
  ## an `AssertionError` will be raised.
  discard
proc deserialize*(thetype: typedesc[TheType],
  data: string | seq[byte | char | int8 | uint8]): TheType
  {.raises: AssertionError.} =
  ## Interprets given data as serialized `TheType` and
  ## deserializes it then. Only available for types which
  ## declarations are placed under the **static** section.
  ## When the `data` size is lesser than `TheType.size`,
  ## the AssertionError will be raised.
  discard

