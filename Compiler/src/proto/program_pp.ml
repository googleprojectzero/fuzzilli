[@@@ocaml.warning "-27-30-39"]

let rec pp_instruction_operation fmt (v:Program_types.instruction_operation) =
  match v with
  | Program_types.Op_idx x -> Format.fprintf fmt "@[Op_idx(%a)@]" Pbrt.Pp.pp_int32 x
  | Program_types.Load_integer x -> Format.fprintf fmt "@[Load_integer(%a)@]" Operations_pp.pp_load_integer x
  | Program_types.Load_big_int x -> Format.fprintf fmt "@[Load_big_int(%a)@]" Operations_pp.pp_load_big_int x
  | Program_types.Load_float x -> Format.fprintf fmt "@[Load_float(%a)@]" Operations_pp.pp_load_float x
  | Program_types.Load_string x -> Format.fprintf fmt "@[Load_string(%a)@]" Operations_pp.pp_load_string x
  | Program_types.Load_boolean x -> Format.fprintf fmt "@[Load_boolean(%a)@]" Operations_pp.pp_load_boolean x
  | Program_types.Load_undefined  -> Format.fprintf fmt "Load_undefined"
  | Program_types.Load_null  -> Format.fprintf fmt "Load_null"
  | Program_types.Load_reg_exp x -> Format.fprintf fmt "@[Load_reg_exp(%a)@]" Operations_pp.pp_load_reg_exp x
  | Program_types.Create_object x -> Format.fprintf fmt "@[Create_object(%a)@]" Operations_pp.pp_create_object x
  | Program_types.Create_array  -> Format.fprintf fmt "Create_array"
  | Program_types.Create_object_with_spread x -> Format.fprintf fmt "@[Create_object_with_spread(%a)@]" Operations_pp.pp_create_object_with_spread x
  | Program_types.Create_array_with_spread x -> Format.fprintf fmt "@[Create_array_with_spread(%a)@]" Operations_pp.pp_create_array_with_spread x
  | Program_types.Load_builtin x -> Format.fprintf fmt "@[Load_builtin(%a)@]" Operations_pp.pp_load_builtin x
  | Program_types.Load_property x -> Format.fprintf fmt "@[Load_property(%a)@]" Operations_pp.pp_load_property x
  | Program_types.Store_property x -> Format.fprintf fmt "@[Store_property(%a)@]" Operations_pp.pp_store_property x
  | Program_types.Delete_property x -> Format.fprintf fmt "@[Delete_property(%a)@]" Operations_pp.pp_delete_property x
  | Program_types.Load_element x -> Format.fprintf fmt "@[Load_element(%a)@]" Operations_pp.pp_load_element x
  | Program_types.Store_element x -> Format.fprintf fmt "@[Store_element(%a)@]" Operations_pp.pp_store_element x
  | Program_types.Delete_element x -> Format.fprintf fmt "@[Delete_element(%a)@]" Operations_pp.pp_delete_element x
  | Program_types.Load_computed_property  -> Format.fprintf fmt "Load_computed_property"
  | Program_types.Store_computed_property  -> Format.fprintf fmt "Store_computed_property"
  | Program_types.Delete_computed_property  -> Format.fprintf fmt "Delete_computed_property"
  | Program_types.Type_of  -> Format.fprintf fmt "Type_of"
  | Program_types.Instance_of  -> Format.fprintf fmt "Instance_of"
  | Program_types.In  -> Format.fprintf fmt "In"
  | Program_types.Begin_plain_function_definition x -> Format.fprintf fmt "@[Begin_plain_function_definition(%a)@]" Operations_pp.pp_begin_plain_function_definition x
  | Program_types.End_plain_function_definition  -> Format.fprintf fmt "End_plain_function_definition"
  | Program_types.Begin_strict_function_definition x -> Format.fprintf fmt "@[Begin_strict_function_definition(%a)@]" Operations_pp.pp_begin_strict_function_definition x
  | Program_types.End_strict_function_definition  -> Format.fprintf fmt "End_strict_function_definition"
  | Program_types.Begin_arrow_function_definition x -> Format.fprintf fmt "@[Begin_arrow_function_definition(%a)@]" Operations_pp.pp_begin_arrow_function_definition x
  | Program_types.End_arrow_function_definition  -> Format.fprintf fmt "End_arrow_function_definition"
  | Program_types.Begin_generator_function_definition x -> Format.fprintf fmt "@[Begin_generator_function_definition(%a)@]" Operations_pp.pp_begin_generator_function_definition x
  | Program_types.End_generator_function_definition  -> Format.fprintf fmt "End_generator_function_definition"
  | Program_types.Begin_async_function_definition x -> Format.fprintf fmt "@[Begin_async_function_definition(%a)@]" Operations_pp.pp_begin_async_function_definition x
  | Program_types.End_async_function_definition  -> Format.fprintf fmt "End_async_function_definition"
  | Program_types.Begin_async_arrow_function_definition x -> Format.fprintf fmt "@[Begin_async_arrow_function_definition(%a)@]" Operations_pp.pp_begin_async_arrow_function_definition x
  | Program_types.End_async_arrow_function_definition  -> Format.fprintf fmt "End_async_arrow_function_definition"
  | Program_types.Begin_async_generator_function_definition x -> Format.fprintf fmt "@[Begin_async_generator_function_definition(%a)@]" Operations_pp.pp_begin_async_generator_function_definition x
  | Program_types.End_async_generator_function_definition  -> Format.fprintf fmt "End_async_generator_function_definition"
  | Program_types.Return  -> Format.fprintf fmt "Return"
  | Program_types.Yield  -> Format.fprintf fmt "Yield"
  | Program_types.Yield_each  -> Format.fprintf fmt "Yield_each"
  | Program_types.Await  -> Format.fprintf fmt "Await"
  | Program_types.Call_method x -> Format.fprintf fmt "@[Call_method(%a)@]" Operations_pp.pp_call_method x
  | Program_types.Call_function  -> Format.fprintf fmt "Call_function"
  | Program_types.Construct  -> Format.fprintf fmt "Construct"
  | Program_types.Call_function_with_spread x -> Format.fprintf fmt "@[Call_function_with_spread(%a)@]" Operations_pp.pp_call_function_with_spread x
  | Program_types.Unary_operation x -> Format.fprintf fmt "@[Unary_operation(%a)@]" Operations_pp.pp_unary_operation x
  | Program_types.Binary_operation x -> Format.fprintf fmt "@[Binary_operation(%a)@]" Operations_pp.pp_binary_operation x
  | Program_types.Dup  -> Format.fprintf fmt "Dup"
  | Program_types.Reassign  -> Format.fprintf fmt "Reassign"
  | Program_types.Compare x -> Format.fprintf fmt "@[Compare(%a)@]" Operations_pp.pp_compare x
  | Program_types.Eval x -> Format.fprintf fmt "@[Eval(%a)@]" Operations_pp.pp_eval x
  | Program_types.Begin_class_definition x -> Format.fprintf fmt "@[Begin_class_definition(%a)@]" Operations_pp.pp_begin_class_definition x
  | Program_types.Begin_method_definition x -> Format.fprintf fmt "@[Begin_method_definition(%a)@]" Operations_pp.pp_begin_method_definition x
  | Program_types.End_class_definition  -> Format.fprintf fmt "End_class_definition"
  | Program_types.Call_super_constructor  -> Format.fprintf fmt "Call_super_constructor"
  | Program_types.Call_super_method x -> Format.fprintf fmt "@[Call_super_method(%a)@]" Operations_pp.pp_call_super_method x
  | Program_types.Load_super_property x -> Format.fprintf fmt "@[Load_super_property(%a)@]" Operations_pp.pp_load_super_property x
  | Program_types.Store_super_property x -> Format.fprintf fmt "@[Store_super_property(%a)@]" Operations_pp.pp_store_super_property x
  | Program_types.Begin_with  -> Format.fprintf fmt "Begin_with"
  | Program_types.End_with  -> Format.fprintf fmt "End_with"
  | Program_types.Load_from_scope x -> Format.fprintf fmt "@[Load_from_scope(%a)@]" Operations_pp.pp_load_from_scope x
  | Program_types.Store_to_scope x -> Format.fprintf fmt "@[Store_to_scope(%a)@]" Operations_pp.pp_store_to_scope x
  | Program_types.Begin_if  -> Format.fprintf fmt "Begin_if"
  | Program_types.Begin_else  -> Format.fprintf fmt "Begin_else"
  | Program_types.End_if  -> Format.fprintf fmt "End_if"
  | Program_types.Begin_while x -> Format.fprintf fmt "@[Begin_while(%a)@]" Operations_pp.pp_begin_while x
  | Program_types.End_while  -> Format.fprintf fmt "End_while"
  | Program_types.Begin_do_while x -> Format.fprintf fmt "@[Begin_do_while(%a)@]" Operations_pp.pp_begin_do_while x
  | Program_types.End_do_while  -> Format.fprintf fmt "End_do_while"
  | Program_types.Begin_for x -> Format.fprintf fmt "@[Begin_for(%a)@]" Operations_pp.pp_begin_for x
  | Program_types.End_for  -> Format.fprintf fmt "End_for"
  | Program_types.Begin_for_in  -> Format.fprintf fmt "Begin_for_in"
  | Program_types.End_for_in  -> Format.fprintf fmt "End_for_in"
  | Program_types.Begin_for_of  -> Format.fprintf fmt "Begin_for_of"
  | Program_types.End_for_of  -> Format.fprintf fmt "End_for_of"
  | Program_types.Break  -> Format.fprintf fmt "Break"
  | Program_types.Continue  -> Format.fprintf fmt "Continue"
  | Program_types.Begin_try  -> Format.fprintf fmt "Begin_try"
  | Program_types.Begin_catch  -> Format.fprintf fmt "Begin_catch"
  | Program_types.End_try_catch  -> Format.fprintf fmt "End_try_catch"
  | Program_types.Throw_exception  -> Format.fprintf fmt "Throw_exception"
  | Program_types.Begin_code_string  -> Format.fprintf fmt "Begin_code_string"
  | Program_types.End_code_string  -> Format.fprintf fmt "End_code_string"
  | Program_types.Begin_block_statement  -> Format.fprintf fmt "Begin_block_statement"
  | Program_types.End_block_statement  -> Format.fprintf fmt "End_block_statement"
  | Program_types.Nop  -> Format.fprintf fmt "Nop"

and pp_instruction fmt (v:Program_types.instruction) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "inouts" (Pbrt.Pp.pp_list Pbrt.Pp.pp_int32) fmt v.Program_types.inouts;
    Pbrt.Pp.pp_record_field "operation" pp_instruction_operation fmt v.Program_types.operation;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_type_collection_status fmt (v:Program_types.type_collection_status) =
  match v with
  | Program_types.Success -> Format.fprintf fmt "Success"
  | Program_types.Error -> Format.fprintf fmt "Error"
  | Program_types.Timeout -> Format.fprintf fmt "Timeout"
  | Program_types.Notattempted -> Format.fprintf fmt "Notattempted"

let rec pp_type_quality fmt (v:Program_types.type_quality) =
  match v with
  | Program_types.Inferred -> Format.fprintf fmt "Inferred"
  | Program_types.Runtime -> Format.fprintf fmt "Runtime"

let rec pp_type_info fmt (v:Program_types.type_info) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "variable" Pbrt.Pp.pp_int32 fmt v.Program_types.variable;
    Pbrt.Pp.pp_record_field "index" Pbrt.Pp.pp_int32 fmt v.Program_types.index;
    Pbrt.Pp.pp_record_field "type_" (Pbrt.Pp.pp_option Typesystem_pp.pp_type_) fmt v.Program_types.type_;
    Pbrt.Pp.pp_record_field "quality" pp_type_quality fmt v.Program_types.quality;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_program fmt (v:Program_types.program) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "uuid" Pbrt.Pp.pp_bytes fmt v.Program_types.uuid;
    Pbrt.Pp.pp_record_field "code" (Pbrt.Pp.pp_list pp_instruction) fmt v.Program_types.code;
    Pbrt.Pp.pp_record_field "types" (Pbrt.Pp.pp_list pp_type_info) fmt v.Program_types.types;
    Pbrt.Pp.pp_record_field "type_collection_status" pp_type_collection_status fmt v.Program_types.type_collection_status;
    Pbrt.Pp.pp_record_field "comments" (Pbrt.Pp.pp_associative_list Pbrt.Pp.pp_int32 Pbrt.Pp.pp_string) fmt v.Program_types.comments;
    Pbrt.Pp.pp_record_field "parent" (Pbrt.Pp.pp_option pp_program) fmt v.Program_types.parent;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()
