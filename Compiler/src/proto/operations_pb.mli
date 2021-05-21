(** operations.proto Binary Encoding *)


(** {2 Protobuf Encoding} *)

val encode_load_integer : Operations_types.load_integer -> Pbrt.Encoder.t -> unit
(** [encode_load_integer v encoder] encodes [v] with the given [encoder] *)

val encode_load_big_int : Operations_types.load_big_int -> Pbrt.Encoder.t -> unit
(** [encode_load_big_int v encoder] encodes [v] with the given [encoder] *)

val encode_load_float : Operations_types.load_float -> Pbrt.Encoder.t -> unit
(** [encode_load_float v encoder] encodes [v] with the given [encoder] *)

val encode_load_string : Operations_types.load_string -> Pbrt.Encoder.t -> unit
(** [encode_load_string v encoder] encodes [v] with the given [encoder] *)

val encode_load_boolean : Operations_types.load_boolean -> Pbrt.Encoder.t -> unit
(** [encode_load_boolean v encoder] encodes [v] with the given [encoder] *)

val encode_load_reg_exp : Operations_types.load_reg_exp -> Pbrt.Encoder.t -> unit
(** [encode_load_reg_exp v encoder] encodes [v] with the given [encoder] *)

val encode_create_object : Operations_types.create_object -> Pbrt.Encoder.t -> unit
(** [encode_create_object v encoder] encodes [v] with the given [encoder] *)

val encode_create_object_with_spread : Operations_types.create_object_with_spread -> Pbrt.Encoder.t -> unit
(** [encode_create_object_with_spread v encoder] encodes [v] with the given [encoder] *)

val encode_create_array_with_spread : Operations_types.create_array_with_spread -> Pbrt.Encoder.t -> unit
(** [encode_create_array_with_spread v encoder] encodes [v] with the given [encoder] *)

val encode_load_builtin : Operations_types.load_builtin -> Pbrt.Encoder.t -> unit
(** [encode_load_builtin v encoder] encodes [v] with the given [encoder] *)

val encode_load_property : Operations_types.load_property -> Pbrt.Encoder.t -> unit
(** [encode_load_property v encoder] encodes [v] with the given [encoder] *)

val encode_store_property : Operations_types.store_property -> Pbrt.Encoder.t -> unit
(** [encode_store_property v encoder] encodes [v] with the given [encoder] *)

val encode_delete_property : Operations_types.delete_property -> Pbrt.Encoder.t -> unit
(** [encode_delete_property v encoder] encodes [v] with the given [encoder] *)

val encode_load_element : Operations_types.load_element -> Pbrt.Encoder.t -> unit
(** [encode_load_element v encoder] encodes [v] with the given [encoder] *)

val encode_store_element : Operations_types.store_element -> Pbrt.Encoder.t -> unit
(** [encode_store_element v encoder] encodes [v] with the given [encoder] *)

val encode_delete_element : Operations_types.delete_element -> Pbrt.Encoder.t -> unit
(** [encode_delete_element v encoder] encodes [v] with the given [encoder] *)

val encode_begin_plain_function_definition : Operations_types.begin_plain_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_plain_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_strict_function_definition : Operations_types.begin_strict_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_strict_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_arrow_function_definition : Operations_types.begin_arrow_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_arrow_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_generator_function_definition : Operations_types.begin_generator_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_generator_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_async_function_definition : Operations_types.begin_async_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_async_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_async_arrow_function_definition : Operations_types.begin_async_arrow_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_async_arrow_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_async_generator_function_definition : Operations_types.begin_async_generator_function_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_async_generator_function_definition v encoder] encodes [v] with the given [encoder] *)

val encode_call_method : Operations_types.call_method -> Pbrt.Encoder.t -> unit
(** [encode_call_method v encoder] encodes [v] with the given [encoder] *)

val encode_call_function_with_spread : Operations_types.call_function_with_spread -> Pbrt.Encoder.t -> unit
(** [encode_call_function_with_spread v encoder] encodes [v] with the given [encoder] *)

val encode_unary_operator : Operations_types.unary_operator -> Pbrt.Encoder.t -> unit
(** [encode_unary_operator v encoder] encodes [v] with the given [encoder] *)

val encode_unary_operation : Operations_types.unary_operation -> Pbrt.Encoder.t -> unit
(** [encode_unary_operation v encoder] encodes [v] with the given [encoder] *)

val encode_binary_operator : Operations_types.binary_operator -> Pbrt.Encoder.t -> unit
(** [encode_binary_operator v encoder] encodes [v] with the given [encoder] *)

val encode_binary_operation : Operations_types.binary_operation -> Pbrt.Encoder.t -> unit
(** [encode_binary_operation v encoder] encodes [v] with the given [encoder] *)

val encode_comparator : Operations_types.comparator -> Pbrt.Encoder.t -> unit
(** [encode_comparator v encoder] encodes [v] with the given [encoder] *)

val encode_compare : Operations_types.compare -> Pbrt.Encoder.t -> unit
(** [encode_compare v encoder] encodes [v] with the given [encoder] *)

val encode_eval : Operations_types.eval -> Pbrt.Encoder.t -> unit
(** [encode_eval v encoder] encodes [v] with the given [encoder] *)

val encode_begin_class_definition : Operations_types.begin_class_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_class_definition v encoder] encodes [v] with the given [encoder] *)

val encode_begin_method_definition : Operations_types.begin_method_definition -> Pbrt.Encoder.t -> unit
(** [encode_begin_method_definition v encoder] encodes [v] with the given [encoder] *)

val encode_call_super_method : Operations_types.call_super_method -> Pbrt.Encoder.t -> unit
(** [encode_call_super_method v encoder] encodes [v] with the given [encoder] *)

val encode_load_super_property : Operations_types.load_super_property -> Pbrt.Encoder.t -> unit
(** [encode_load_super_property v encoder] encodes [v] with the given [encoder] *)

val encode_store_super_property : Operations_types.store_super_property -> Pbrt.Encoder.t -> unit
(** [encode_store_super_property v encoder] encodes [v] with the given [encoder] *)

val encode_load_from_scope : Operations_types.load_from_scope -> Pbrt.Encoder.t -> unit
(** [encode_load_from_scope v encoder] encodes [v] with the given [encoder] *)

val encode_store_to_scope : Operations_types.store_to_scope -> Pbrt.Encoder.t -> unit
(** [encode_store_to_scope v encoder] encodes [v] with the given [encoder] *)

val encode_begin_while : Operations_types.begin_while -> Pbrt.Encoder.t -> unit
(** [encode_begin_while v encoder] encodes [v] with the given [encoder] *)

val encode_begin_do_while : Operations_types.begin_do_while -> Pbrt.Encoder.t -> unit
(** [encode_begin_do_while v encoder] encodes [v] with the given [encoder] *)

val encode_begin_for : Operations_types.begin_for -> Pbrt.Encoder.t -> unit
(** [encode_begin_for v encoder] encodes [v] with the given [encoder] *)


(** {2 Protobuf Decoding} *)

val decode_load_integer : Pbrt.Decoder.t -> Operations_types.load_integer
(** [decode_load_integer decoder] decodes a [load_integer] value from [decoder] *)

val decode_load_big_int : Pbrt.Decoder.t -> Operations_types.load_big_int
(** [decode_load_big_int decoder] decodes a [load_big_int] value from [decoder] *)

val decode_load_float : Pbrt.Decoder.t -> Operations_types.load_float
(** [decode_load_float decoder] decodes a [load_float] value from [decoder] *)

val decode_load_string : Pbrt.Decoder.t -> Operations_types.load_string
(** [decode_load_string decoder] decodes a [load_string] value from [decoder] *)

val decode_load_boolean : Pbrt.Decoder.t -> Operations_types.load_boolean
(** [decode_load_boolean decoder] decodes a [load_boolean] value from [decoder] *)

val decode_load_reg_exp : Pbrt.Decoder.t -> Operations_types.load_reg_exp
(** [decode_load_reg_exp decoder] decodes a [load_reg_exp] value from [decoder] *)

val decode_create_object : Pbrt.Decoder.t -> Operations_types.create_object
(** [decode_create_object decoder] decodes a [create_object] value from [decoder] *)

val decode_create_object_with_spread : Pbrt.Decoder.t -> Operations_types.create_object_with_spread
(** [decode_create_object_with_spread decoder] decodes a [create_object_with_spread] value from [decoder] *)

val decode_create_array_with_spread : Pbrt.Decoder.t -> Operations_types.create_array_with_spread
(** [decode_create_array_with_spread decoder] decodes a [create_array_with_spread] value from [decoder] *)

val decode_load_builtin : Pbrt.Decoder.t -> Operations_types.load_builtin
(** [decode_load_builtin decoder] decodes a [load_builtin] value from [decoder] *)

val decode_load_property : Pbrt.Decoder.t -> Operations_types.load_property
(** [decode_load_property decoder] decodes a [load_property] value from [decoder] *)

val decode_store_property : Pbrt.Decoder.t -> Operations_types.store_property
(** [decode_store_property decoder] decodes a [store_property] value from [decoder] *)

val decode_delete_property : Pbrt.Decoder.t -> Operations_types.delete_property
(** [decode_delete_property decoder] decodes a [delete_property] value from [decoder] *)

val decode_load_element : Pbrt.Decoder.t -> Operations_types.load_element
(** [decode_load_element decoder] decodes a [load_element] value from [decoder] *)

val decode_store_element : Pbrt.Decoder.t -> Operations_types.store_element
(** [decode_store_element decoder] decodes a [store_element] value from [decoder] *)

val decode_delete_element : Pbrt.Decoder.t -> Operations_types.delete_element
(** [decode_delete_element decoder] decodes a [delete_element] value from [decoder] *)

val decode_begin_plain_function_definition : Pbrt.Decoder.t -> Operations_types.begin_plain_function_definition
(** [decode_begin_plain_function_definition decoder] decodes a [begin_plain_function_definition] value from [decoder] *)

val decode_begin_strict_function_definition : Pbrt.Decoder.t -> Operations_types.begin_strict_function_definition
(** [decode_begin_strict_function_definition decoder] decodes a [begin_strict_function_definition] value from [decoder] *)

val decode_begin_arrow_function_definition : Pbrt.Decoder.t -> Operations_types.begin_arrow_function_definition
(** [decode_begin_arrow_function_definition decoder] decodes a [begin_arrow_function_definition] value from [decoder] *)

val decode_begin_generator_function_definition : Pbrt.Decoder.t -> Operations_types.begin_generator_function_definition
(** [decode_begin_generator_function_definition decoder] decodes a [begin_generator_function_definition] value from [decoder] *)

val decode_begin_async_function_definition : Pbrt.Decoder.t -> Operations_types.begin_async_function_definition
(** [decode_begin_async_function_definition decoder] decodes a [begin_async_function_definition] value from [decoder] *)

val decode_begin_async_arrow_function_definition : Pbrt.Decoder.t -> Operations_types.begin_async_arrow_function_definition
(** [decode_begin_async_arrow_function_definition decoder] decodes a [begin_async_arrow_function_definition] value from [decoder] *)

val decode_begin_async_generator_function_definition : Pbrt.Decoder.t -> Operations_types.begin_async_generator_function_definition
(** [decode_begin_async_generator_function_definition decoder] decodes a [begin_async_generator_function_definition] value from [decoder] *)

val decode_call_method : Pbrt.Decoder.t -> Operations_types.call_method
(** [decode_call_method decoder] decodes a [call_method] value from [decoder] *)

val decode_call_function_with_spread : Pbrt.Decoder.t -> Operations_types.call_function_with_spread
(** [decode_call_function_with_spread decoder] decodes a [call_function_with_spread] value from [decoder] *)

val decode_unary_operator : Pbrt.Decoder.t -> Operations_types.unary_operator
(** [decode_unary_operator decoder] decodes a [unary_operator] value from [decoder] *)

val decode_unary_operation : Pbrt.Decoder.t -> Operations_types.unary_operation
(** [decode_unary_operation decoder] decodes a [unary_operation] value from [decoder] *)

val decode_binary_operator : Pbrt.Decoder.t -> Operations_types.binary_operator
(** [decode_binary_operator decoder] decodes a [binary_operator] value from [decoder] *)

val decode_binary_operation : Pbrt.Decoder.t -> Operations_types.binary_operation
(** [decode_binary_operation decoder] decodes a [binary_operation] value from [decoder] *)

val decode_comparator : Pbrt.Decoder.t -> Operations_types.comparator
(** [decode_comparator decoder] decodes a [comparator] value from [decoder] *)

val decode_compare : Pbrt.Decoder.t -> Operations_types.compare
(** [decode_compare decoder] decodes a [compare] value from [decoder] *)

val decode_eval : Pbrt.Decoder.t -> Operations_types.eval
(** [decode_eval decoder] decodes a [eval] value from [decoder] *)

val decode_begin_class_definition : Pbrt.Decoder.t -> Operations_types.begin_class_definition
(** [decode_begin_class_definition decoder] decodes a [begin_class_definition] value from [decoder] *)

val decode_begin_method_definition : Pbrt.Decoder.t -> Operations_types.begin_method_definition
(** [decode_begin_method_definition decoder] decodes a [begin_method_definition] value from [decoder] *)

val decode_call_super_method : Pbrt.Decoder.t -> Operations_types.call_super_method
(** [decode_call_super_method decoder] decodes a [call_super_method] value from [decoder] *)

val decode_load_super_property : Pbrt.Decoder.t -> Operations_types.load_super_property
(** [decode_load_super_property decoder] decodes a [load_super_property] value from [decoder] *)

val decode_store_super_property : Pbrt.Decoder.t -> Operations_types.store_super_property
(** [decode_store_super_property decoder] decodes a [store_super_property] value from [decoder] *)

val decode_load_from_scope : Pbrt.Decoder.t -> Operations_types.load_from_scope
(** [decode_load_from_scope decoder] decodes a [load_from_scope] value from [decoder] *)

val decode_store_to_scope : Pbrt.Decoder.t -> Operations_types.store_to_scope
(** [decode_store_to_scope decoder] decodes a [store_to_scope] value from [decoder] *)

val decode_begin_while : Pbrt.Decoder.t -> Operations_types.begin_while
(** [decode_begin_while decoder] decodes a [begin_while] value from [decoder] *)

val decode_begin_do_while : Pbrt.Decoder.t -> Operations_types.begin_do_while
(** [decode_begin_do_while decoder] decodes a [begin_do_while] value from [decoder] *)

val decode_begin_for : Pbrt.Decoder.t -> Operations_types.begin_for
(** [decode_begin_for decoder] decodes a [begin_for] value from [decoder] *)
