(** operations.proto Types *)



(** {2 Types} *)

type load_integer = {
  value : int64;
}

type load_big_int = {
  value : int64;
}

type load_float = {
  value : float;
}

type load_string = {
  value : string;
}

type load_boolean = {
  value : bool;
}

type load_reg_exp = {
  value : string;
  flags : int32;
}

type create_object = {
  property_names : string list;
}

type create_object_with_spread = {
  property_names : string list;
}

type create_array_with_spread = {
  spreads : bool list;
}

type load_builtin = {
  builtin_name : string;
}

type load_property = {
  property_name : string;
}

type store_property = {
  property_name : string;
}

type delete_property = {
  property_name : string;
}

type load_element = {
  index : int64;
}

type store_element = {
  index : int64;
}

type delete_element = {
  index : int64;
}

type begin_plain_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type begin_strict_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type begin_arrow_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type begin_generator_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type begin_async_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type begin_async_arrow_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type begin_async_generator_function_definition = {
  signature : Typesystem_types.function_signature option;
}

type call_method = {
  method_name : string;
}

type call_function_with_spread = {
  spreads : bool list;
}

type unary_operator =
  | Pre_inc 
  | Pre_dec 
  | Post_inc 
  | Post_dec 
  | Logical_not 
  | Bitwise_not 
  | Plus 
  | Minus 

type unary_operation = {
  op : unary_operator;
}

type binary_operator =
  | Add 
  | Sub 
  | Mul 
  | Div 
  | Mod 
  | Bit_and 
  | Bit_or 
  | Logical_and 
  | Logical_or 
  | Xor 
  | Lshift 
  | Rshift 
  | Exp 
  | Unrshift 

type binary_operation = {
  op : binary_operator;
}

type comparator =
  | Equal 
  | Strict_equal 
  | Not_equal 
  | Strict_not_equal 
  | Less_than 
  | Less_than_or_equal 
  | Greater_than 
  | Greater_than_or_equal 

type compare = {
  op : comparator;
}

type eval = {
  code : string;
}

type begin_class_definition = {
  has_superclass : bool;
  constructor_parameters : Typesystem_types.type_ list;
  instance_properties : string list;
  instance_method_names : string list;
  instance_method_signatures : Typesystem_types.function_signature list;
}

type begin_method_definition = {
  num_parameters : int32;
}

type call_super_method = {
  method_name : string;
}

type load_super_property = {
  property_name : string;
}

type store_super_property = {
  property_name : string;
}

type load_from_scope = {
  id : string;
}

type store_to_scope = {
  id : string;
}

type begin_while = {
  comparator : comparator;
}

type begin_do_while = {
  comparator : comparator;
}

type begin_for = {
  comparator : comparator;
  op : binary_operator;
}


(** {2 Default values} *)

val default_load_integer : 
  ?value:int64 ->
  unit ->
  load_integer
(** [default_load_integer ()] is the default value for type [load_integer] *)

val default_load_big_int : 
  ?value:int64 ->
  unit ->
  load_big_int
(** [default_load_big_int ()] is the default value for type [load_big_int] *)

val default_load_float : 
  ?value:float ->
  unit ->
  load_float
(** [default_load_float ()] is the default value for type [load_float] *)

val default_load_string : 
  ?value:string ->
  unit ->
  load_string
(** [default_load_string ()] is the default value for type [load_string] *)

val default_load_boolean : 
  ?value:bool ->
  unit ->
  load_boolean
(** [default_load_boolean ()] is the default value for type [load_boolean] *)

val default_load_reg_exp : 
  ?value:string ->
  ?flags:int32 ->
  unit ->
  load_reg_exp
(** [default_load_reg_exp ()] is the default value for type [load_reg_exp] *)

val default_create_object : 
  ?property_names:string list ->
  unit ->
  create_object
(** [default_create_object ()] is the default value for type [create_object] *)

val default_create_object_with_spread : 
  ?property_names:string list ->
  unit ->
  create_object_with_spread
(** [default_create_object_with_spread ()] is the default value for type [create_object_with_spread] *)

val default_create_array_with_spread : 
  ?spreads:bool list ->
  unit ->
  create_array_with_spread
(** [default_create_array_with_spread ()] is the default value for type [create_array_with_spread] *)

val default_load_builtin : 
  ?builtin_name:string ->
  unit ->
  load_builtin
(** [default_load_builtin ()] is the default value for type [load_builtin] *)

val default_load_property : 
  ?property_name:string ->
  unit ->
  load_property
(** [default_load_property ()] is the default value for type [load_property] *)

val default_store_property : 
  ?property_name:string ->
  unit ->
  store_property
(** [default_store_property ()] is the default value for type [store_property] *)

val default_delete_property : 
  ?property_name:string ->
  unit ->
  delete_property
(** [default_delete_property ()] is the default value for type [delete_property] *)

val default_load_element : 
  ?index:int64 ->
  unit ->
  load_element
(** [default_load_element ()] is the default value for type [load_element] *)

val default_store_element : 
  ?index:int64 ->
  unit ->
  store_element
(** [default_store_element ()] is the default value for type [store_element] *)

val default_delete_element : 
  ?index:int64 ->
  unit ->
  delete_element
(** [default_delete_element ()] is the default value for type [delete_element] *)

val default_begin_plain_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_plain_function_definition
(** [default_begin_plain_function_definition ()] is the default value for type [begin_plain_function_definition] *)

val default_begin_strict_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_strict_function_definition
(** [default_begin_strict_function_definition ()] is the default value for type [begin_strict_function_definition] *)

val default_begin_arrow_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_arrow_function_definition
(** [default_begin_arrow_function_definition ()] is the default value for type [begin_arrow_function_definition] *)

val default_begin_generator_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_generator_function_definition
(** [default_begin_generator_function_definition ()] is the default value for type [begin_generator_function_definition] *)

val default_begin_async_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_async_function_definition
(** [default_begin_async_function_definition ()] is the default value for type [begin_async_function_definition] *)

val default_begin_async_arrow_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_async_arrow_function_definition
(** [default_begin_async_arrow_function_definition ()] is the default value for type [begin_async_arrow_function_definition] *)

val default_begin_async_generator_function_definition : 
  ?signature:Typesystem_types.function_signature option ->
  unit ->
  begin_async_generator_function_definition
(** [default_begin_async_generator_function_definition ()] is the default value for type [begin_async_generator_function_definition] *)

val default_call_method : 
  ?method_name:string ->
  unit ->
  call_method
(** [default_call_method ()] is the default value for type [call_method] *)

val default_call_function_with_spread : 
  ?spreads:bool list ->
  unit ->
  call_function_with_spread
(** [default_call_function_with_spread ()] is the default value for type [call_function_with_spread] *)

val default_unary_operator : unit -> unary_operator
(** [default_unary_operator ()] is the default value for type [unary_operator] *)

val default_unary_operation : 
  ?op:unary_operator ->
  unit ->
  unary_operation
(** [default_unary_operation ()] is the default value for type [unary_operation] *)

val default_binary_operator : unit -> binary_operator
(** [default_binary_operator ()] is the default value for type [binary_operator] *)

val default_binary_operation : 
  ?op:binary_operator ->
  unit ->
  binary_operation
(** [default_binary_operation ()] is the default value for type [binary_operation] *)

val default_comparator : unit -> comparator
(** [default_comparator ()] is the default value for type [comparator] *)

val default_compare : 
  ?op:comparator ->
  unit ->
  compare
(** [default_compare ()] is the default value for type [compare] *)

val default_eval : 
  ?code:string ->
  unit ->
  eval
(** [default_eval ()] is the default value for type [eval] *)

val default_begin_class_definition : 
  ?has_superclass:bool ->
  ?constructor_parameters:Typesystem_types.type_ list ->
  ?instance_properties:string list ->
  ?instance_method_names:string list ->
  ?instance_method_signatures:Typesystem_types.function_signature list ->
  unit ->
  begin_class_definition
(** [default_begin_class_definition ()] is the default value for type [begin_class_definition] *)

val default_begin_method_definition : 
  ?num_parameters:int32 ->
  unit ->
  begin_method_definition
(** [default_begin_method_definition ()] is the default value for type [begin_method_definition] *)

val default_call_super_method : 
  ?method_name:string ->
  unit ->
  call_super_method
(** [default_call_super_method ()] is the default value for type [call_super_method] *)

val default_load_super_property : 
  ?property_name:string ->
  unit ->
  load_super_property
(** [default_load_super_property ()] is the default value for type [load_super_property] *)

val default_store_super_property : 
  ?property_name:string ->
  unit ->
  store_super_property
(** [default_store_super_property ()] is the default value for type [store_super_property] *)

val default_load_from_scope : 
  ?id:string ->
  unit ->
  load_from_scope
(** [default_load_from_scope ()] is the default value for type [load_from_scope] *)

val default_store_to_scope : 
  ?id:string ->
  unit ->
  store_to_scope
(** [default_store_to_scope ()] is the default value for type [store_to_scope] *)

val default_begin_while : 
  ?comparator:comparator ->
  unit ->
  begin_while
(** [default_begin_while ()] is the default value for type [begin_while] *)

val default_begin_do_while : 
  ?comparator:comparator ->
  unit ->
  begin_do_while
(** [default_begin_do_while ()] is the default value for type [begin_do_while] *)

val default_begin_for : 
  ?comparator:comparator ->
  ?op:binary_operator ->
  unit ->
  begin_for
(** [default_begin_for ()] is the default value for type [begin_for] *)
