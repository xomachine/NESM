
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
##   type
##     Ball = object
##       weight: float32
##       diameter: int32
##       isHollow: bool
##
##   proc size(obj169004: Ball): Natural =
##     (0 + 4 + 4 + 1)
##
##   proc serialize(obj169005: Ball; thestream: Stream) =
##     discard
##     thestream.writeData(obj169005.weight.unsafeAddr, 4)
##     thestream.writeData(obj169005.diameter.unsafeAddr, 4)
##     thestream.writeData(obj169005.isHollow.unsafeAddr, 1)
##
##   proc serialize(obj169010: Ball): string =
##     let ss169012 = newStringStream()
##     serialize(obj169010, ss169012)
##     ss169012.data
##
##   proc deserialize(obj169006: var Ball; thestream: Stream) =
##     discard
##     doAssert(4 ==
##         thestream.readData(obj169006.weight.unsafeAddr, 4),
##              "Stream has not provided enough data")
##     doAssert(4 ==
##         thestream.readData(obj169006.diameter.unsafeAddr, 4),
##              "Stream has not provided enough data")
##     doAssert(1 ==
##         thestream.readData(obj169006.isHollow.unsafeAddr, 1),
##              "Stream has not provided enough data")
##
##   proc deserialize(a169008: typedesc[Ball]; thestream: Stream): Ball =
##     deserialize(result, thestream)
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
##         field_with_special_rules: int32 as {<options>} # inline options
##         # NOTE: inline options have highest priority
##         another_typical_field: float32
##
## The serialization options themself are described in the paragraphs they are
## related.
##
## Endianness switching
## --------------------
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
##   ...
##   toSerializable(Point2d, dynamic: false) # The "dynamic: false" option
##                                           # is equal to "static:" for
##                                           # serializable macro
##
## Customizing seq and string serialization schemas
## ------------------------------------------------
## By default, NESM serializes seq's and string's in a following way:
## 1. Serialize the seq or string length as uint32
## 2. Serialize the seq or string content as an array[length, type]
## In other words seq and string types can be described in following
## pseudo-code:
##
## .. code-block:: nim
##   serializable:
##     type seq[T] = object
##       length: uint32
##       data: array[length, T]
##     type string = object
##       length: uint32
##       data: array[length, char]
##
## In some cases this scheme is being not flexible enough, say there is
## a structure:
##
## .. code-block:: nim
##   serializable:
##     type Matrix = object
##       lines: uint32
##       columns: uint32
##       data: array[lines, array[columns, int32]]
##
## This type is impossible in Nim due to static nature of array type.
## But how else the seq size may be controlled outside the common scheme?
## For this case the **size** keyword exists in serializable options:
##
## .. code-block:: nim
##   serializable:
##     type Matrix = object
##       lines: uint32 # the size specifier should be placed before it's usage in the 'size' option
##       columns: uint32
##       data: seq[seq[int32]] as {size: {}.lines, size: {}.columns}
##       # The seq's will be stored like array's but their sizes will be
##       # taken from 'lines' and 'columns' fields during deserialization
##
## Note that first 'size' option controls only outer seq, but the second
## one is related to inner seq. Honestly, any valid expression can be used as
## argument for the 'size' option. Empty curly braces mean an object itself
## at the level of invocation. Special case is a double, triple, etc empty
## curly braces. Take a look at the example:
##
## .. code-block:: nim
##   serializable:
##     type SpecialType = object
##       length: uint32 # <- this field will be used as length of subtype.a
##       subtype: tuple[length: string, a: seq[int32] as {size: {{}}.length}]
##
## The 'size' options invocation located inside the subtype field, and
## the only way to use field 'length' from the outer type without affecting
## inner string 'subtype.length' is the double curly braces notation.
##
## In oposite to `size` option there is `sizeof` option with can be used to
## set particular fields value to length of other periodic value instead of
## actual one during serialization. The previous example can be rewriten in
## following way to utilize the `sizeof` option:
##
## .. code-block:: nim
##   serializable:
##     type SpecialType = object
##       length: uint32 as {sizeof: {}.subtype.a}
##       subtype: tuple[length: string, a: seq[int32] as {size: {{}}.length}]
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
## Enum correctness checking
## -------------------------
## **NESM** is checking enum correctness after deserialization by default.
## If deserialized value is not one of enum ordinals then the **ValueError**
## will be raised. To disable such a behaviour user may use the
## **-d:disableEnumChecks** compiler switch.
##
## Default values and incomplete deserialization
## ---------------------------------------------
## **NESM** is able to perform incomplete deserialization. When the stream ends
## before the whole object is deserialized, **NESM** raises an exception.
## When you are using `(obj: var TheType, thestream: Stream)` variant of
## the `deserialize` proc you can get an incomplete serialization result
## in the object passed as the first parameter after handling the exception.
##
## Note that if the object already contain values before passing it to
## the deserialize proc those values will be overwriten only for data
## available in the stream. All other values will be left untouched.
##
## There are two edge cases in the incomplete deserialization behaviour:
## * incomplete seq or string with size available in the stream will be overwritten
##   by seq of that size with default elements then the available elements
##   will be filled and all others will be left as default values
##   (not the values passed in the original object)
## * incomplete cstring will not be overwritten until zero byte is encountered in the stream
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

proc deserialize*(obj: TheType,
                  stream: Stream): TheType
  {.raises: AssertionError.} =
  ## Interprets the data received from the `stream`
  ## as `TheType` and deserializes it then to the `obj`.
  ## The `obj` may be filled partially if the `stream`
  ## has not provided enough data.
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

