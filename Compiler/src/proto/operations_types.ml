[@@@ocaml.warning "-27-30-39"]


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

let rec default_load_integer 
  ?value:((value:int64) = 0L)
  () : load_integer  = {
  value;
}

let rec default_load_big_int 
  ?value:((value:int64) = 0L)
  () : load_big_int  = {
  value;
}

let rec default_load_float 
  ?value:((value:float) = 0.)
  () : load_float  = {
  value;
}

let rec default_load_string 
  ?value:((value:string) = "")
  () : load_string  = {
  value;
}

let rec default_load_boolean 
  ?value:((value:bool) = false)
  () : load_boolean  = {
  value;
}

let rec default_load_reg_exp 
  ?value:((value:string) = "")
  ?flags:((flags:int32) = 0l)
  () : load_reg_exp  = {
  value;
  flags;
}

let rec default_create_object 
  ?property_names:((property_names:string list) = [])
  () : create_object  = {
  property_names;
}

let rec default_create_object_with_spread 
  ?property_names:((property_names:string list) = [])
  () : create_object_with_spread  = {
  property_names;
}

let rec default_create_array_with_spread 
  ?spreads:((spreads:bool list) = [])
  () : create_array_with_spread  = {
  spreads;
}

let rec default_load_builtin 
  ?builtin_name:((builtin_name:string) = "")
  () : load_builtin  = {
  builtin_name;
}

let rec default_load_property 
  ?property_name:((property_name:string) = "")
  () : load_property  = {
  property_name;
}

let rec default_store_property 
  ?property_name:((property_name:string) = "")
  () : store_property  = {
  property_name;
}

let rec default_delete_property 
  ?property_name:((property_name:string) = "")
  () : delete_property  = {
  property_name;
}

let rec default_load_element 
  ?index:((index:int64) = 0L)
  () : load_element  = {
  index;
}

let rec default_store_element 
  ?index:((index:int64) = 0L)
  () : store_element  = {
  index;
}

let rec default_delete_element 
  ?index:((index:int64) = 0L)
  () : delete_element  = {
  index;
}

let rec default_begin_plain_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_plain_function_definition  = {
  signature;
}

let rec default_begin_strict_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_strict_function_definition  = {
  signature;
}

let rec default_begin_arrow_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_arrow_function_definition  = {
  signature;
}

let rec default_begin_generator_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_generator_function_definition  = {
  signature;
}

let rec default_begin_async_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_async_function_definition  = {
  signature;
}

let rec default_begin_async_arrow_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_async_arrow_function_definition  = {
  signature;
}

let rec default_begin_async_generator_function_definition 
  ?signature:((signature:Typesystem_types.function_signature option) = None)
  () : begin_async_generator_function_definition  = {
  signature;
}

let rec default_call_method 
  ?method_name:((method_name:string) = "")
  () : call_method  = {
  method_name;
}

let rec default_call_function_with_spread 
  ?spreads:((spreads:bool list) = [])
  () : call_function_with_spread  = {
  spreads;
}

let rec default_unary_operator () = (Pre_inc:unary_operator)

let rec default_unary_operation 
  ?op:((op:unary_operator) = default_unary_operator ())
  () : unary_operation  = {
  op;
}

let rec default_binary_operator () = (Add:binary_operator)

let rec default_binary_operation 
  ?op:((op:binary_operator) = default_binary_operator ())
  () : binary_operation  = {
  op;
}

let rec default_comparator () = (Equal:comparator)

let rec default_compare 
  ?op:((op:comparator) = default_comparator ())
  () : compare  = {
  op;
}

let rec default_eval 
  ?code:((code:string) = "")
  () : eval  = {
  code;
}

let rec default_begin_class_definition 
  ?has_superclass:((has_superclass:bool) = false)
  ?constructor_parameters:((constructor_parameters:Typesystem_types.type_ list) = [])
  ?instance_properties:((instance_properties:string list) = [])
  ?instance_method_names:((instance_method_names:string list) = [])
  ?instance_method_signatures:((instance_method_signatures:Typesystem_types.function_signature list) = [])
  () : begin_class_definition  = {
  has_superclass;
  constructor_parameters;
  instance_properties;
  instance_method_names;
  instance_method_signatures;
}

let rec default_begin_method_definition 
  ?num_parameters:((num_parameters:int32) = 0l)
  () : begin_method_definition  = {
  num_parameters;
}

let rec default_call_super_method 
  ?method_name:((method_name:string) = "")
  () : call_super_method  = {
  method_name;
}

let rec default_load_super_property 
  ?property_name:((property_name:string) = "")
  () : load_super_property  = {
  property_name;
}

let rec default_store_super_property 
  ?property_name:((property_name:string) = "")
  () : store_super_property  = {
  property_name;
}

let rec default_load_from_scope 
  ?id:((id:string) = "")
  () : load_from_scope  = {
  id;
}

let rec default_store_to_scope 
  ?id:((id:string) = "")
  () : store_to_scope  = {
  id;
}

let rec default_begin_while 
  ?comparator:((comparator:comparator) = default_comparator ())
  () : begin_while  = {
  comparator;
}

let rec default_begin_do_while 
  ?comparator:((comparator:comparator) = default_comparator ())
  () : begin_do_while  = {
  comparator;
}

let rec default_begin_for 
  ?comparator:((comparator:comparator) = default_comparator ())
  ?op:((op:binary_operator) = default_binary_operator ())
  () : begin_for  = {
  comparator;
  op;
}
