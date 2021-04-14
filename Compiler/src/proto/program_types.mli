(** program.proto Types *)



(** {2 Types} *)

type instruction_operation =
  | Op_idx of int32
  | Load_integer of Operations_types.load_integer
  | Load_big_int of Operations_types.load_big_int
  | Load_float of Operations_types.load_float
  | Load_string of Operations_types.load_string
  | Load_boolean of Operations_types.load_boolean
  | Load_undefined
  | Load_null
  | Load_reg_exp of Operations_types.load_reg_exp
  | Create_object of Operations_types.create_object
  | Create_array
  | Create_object_with_spread of Operations_types.create_object_with_spread
  | Create_array_with_spread of Operations_types.create_array_with_spread
  | Load_builtin of Operations_types.load_builtin
  | Load_property of Operations_types.load_property
  | Store_property of Operations_types.store_property
  | Delete_property of Operations_types.delete_property
  | Load_element of Operations_types.load_element
  | Store_element of Operations_types.store_element
  | Delete_element of Operations_types.delete_element
  | Load_computed_property
  | Store_computed_property
  | Delete_computed_property
  | Type_of
  | Instance_of
  | In
  | Begin_plain_function_definition of Operations_types.begin_plain_function_definition
  | End_plain_function_definition
  | Begin_strict_function_definition of Operations_types.begin_strict_function_definition
  | End_strict_function_definition
  | Begin_arrow_function_definition of Operations_types.begin_arrow_function_definition
  | End_arrow_function_definition
  | Begin_generator_function_definition of Operations_types.begin_generator_function_definition
  | End_generator_function_definition
  | Begin_async_function_definition of Operations_types.begin_async_function_definition
  | End_async_function_definition
  | Begin_async_arrow_function_definition of Operations_types.begin_async_arrow_function_definition
  | End_async_arrow_function_definition
  | Begin_async_generator_function_definition of Operations_types.begin_async_generator_function_definition
  | End_async_generator_function_definition
  | Return
  | Yield
  | Yield_each
  | Await
  | Call_method of Operations_types.call_method
  | Call_function
  | Construct
  | Call_function_with_spread of Operations_types.call_function_with_spread
  | Unary_operation of Operations_types.unary_operation
  | Binary_operation of Operations_types.binary_operation
  | Dup
  | Reassign
  | Compare of Operations_types.compare
  | Eval of Operations_types.eval
  | Begin_class_definition of Operations_types.begin_class_definition
  | Begin_method_definition of Operations_types.begin_method_definition
  | End_class_definition
  | Call_super_constructor
  | Call_super_method of Operations_types.call_super_method
  | Load_super_property of Operations_types.load_super_property
  | Store_super_property of Operations_types.store_super_property
  | Begin_with
  | End_with
  | Load_from_scope of Operations_types.load_from_scope
  | Store_to_scope of Operations_types.store_to_scope
  | Begin_if
  | Begin_else
  | End_if
  | Begin_while of Operations_types.begin_while
  | End_while
  | Begin_do_while of Operations_types.begin_do_while
  | End_do_while
  | Begin_for of Operations_types.begin_for
  | End_for
  | Begin_for_in
  | End_for_in
  | Begin_for_of
  | End_for_of
  | Break
  | Continue
  | Begin_try
  | Begin_catch
  | End_try_catch
  | Throw_exception
  | Begin_code_string
  | End_code_string
  | Begin_block_statement
  | End_block_statement
  | Nop

and instruction = {
  inouts : int32 list;
  operation : instruction_operation;
}

type type_collection_status =
  | Success 
  | Error 
  | Timeout 
  | Notattempted 

type type_quality =
  | Inferred 
  | Runtime 

type type_info = {
  variable : int32;
  index : int32;
  type_ : Typesystem_types.type_ option;
  quality : type_quality;
}

type program = {
  uuid : bytes;
  code : instruction list;
  types : type_info list;
  type_collection_status : type_collection_status;
  comments : (int32 * string) list;
  parent : program option;
}


(** {2 Default values} *)

val default_instruction_operation : unit -> instruction_operation
(** [default_instruction_operation ()] is the default value for type [instruction_operation] *)

val default_instruction : 
  ?inouts:int32 list ->
  ?operation:instruction_operation ->
  unit ->
  instruction
(** [default_instruction ()] is the default value for type [instruction] *)

val default_type_collection_status : unit -> type_collection_status
(** [default_type_collection_status ()] is the default value for type [type_collection_status] *)

val default_type_quality : unit -> type_quality
(** [default_type_quality ()] is the default value for type [type_quality] *)

val default_type_info : 
  ?variable:int32 ->
  ?index:int32 ->
  ?type_:Typesystem_types.type_ option ->
  ?quality:type_quality ->
  unit ->
  type_info
(** [default_type_info ()] is the default value for type [type_info] *)

val default_program : 
  ?uuid:bytes ->
  ?code:instruction list ->
  ?types:type_info list ->
  ?type_collection_status:type_collection_status ->
  ?comments:(int32 * string) list ->
  ?parent:program option ->
  unit ->
  program
(** [default_program ()] is the default value for type [program] *)
