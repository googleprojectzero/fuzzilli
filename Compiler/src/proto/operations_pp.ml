[@@@ocaml.warning "-27-30-39"]

let rec pp_load_integer fmt (v:Operations_types.load_integer) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "value" Pbrt.Pp.pp_int64 fmt v.Operations_types.value;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_big_int fmt (v:Operations_types.load_big_int) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "value" Pbrt.Pp.pp_int64 fmt v.Operations_types.value;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_float fmt (v:Operations_types.load_float) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "value" Pbrt.Pp.pp_float fmt v.Operations_types.value;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_string fmt (v:Operations_types.load_string) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "value" Pbrt.Pp.pp_string fmt v.Operations_types.value;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_boolean fmt (v:Operations_types.load_boolean) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "value" Pbrt.Pp.pp_bool fmt v.Operations_types.value;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_reg_exp fmt (v:Operations_types.load_reg_exp) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "value" Pbrt.Pp.pp_string fmt v.Operations_types.value;
    Pbrt.Pp.pp_record_field "flags" Pbrt.Pp.pp_int32 fmt v.Operations_types.flags;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_create_object fmt (v:Operations_types.create_object) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_names" (Pbrt.Pp.pp_list Pbrt.Pp.pp_string) fmt v.Operations_types.property_names;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_create_object_with_spread fmt (v:Operations_types.create_object_with_spread) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_names" (Pbrt.Pp.pp_list Pbrt.Pp.pp_string) fmt v.Operations_types.property_names;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_create_array_with_spread fmt (v:Operations_types.create_array_with_spread) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "spreads" (Pbrt.Pp.pp_list Pbrt.Pp.pp_bool) fmt v.Operations_types.spreads;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_builtin fmt (v:Operations_types.load_builtin) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "builtin_name" Pbrt.Pp.pp_string fmt v.Operations_types.builtin_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_property fmt (v:Operations_types.load_property) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_name" Pbrt.Pp.pp_string fmt v.Operations_types.property_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_store_property fmt (v:Operations_types.store_property) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_name" Pbrt.Pp.pp_string fmt v.Operations_types.property_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_delete_property fmt (v:Operations_types.delete_property) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_name" Pbrt.Pp.pp_string fmt v.Operations_types.property_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_element fmt (v:Operations_types.load_element) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "index" Pbrt.Pp.pp_int64 fmt v.Operations_types.index;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_store_element fmt (v:Operations_types.store_element) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "index" Pbrt.Pp.pp_int64 fmt v.Operations_types.index;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_delete_element fmt (v:Operations_types.delete_element) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "index" Pbrt.Pp.pp_int64 fmt v.Operations_types.index;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_plain_function_definition fmt (v:Operations_types.begin_plain_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_strict_function_definition fmt (v:Operations_types.begin_strict_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_arrow_function_definition fmt (v:Operations_types.begin_arrow_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_generator_function_definition fmt (v:Operations_types.begin_generator_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_async_function_definition fmt (v:Operations_types.begin_async_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_async_arrow_function_definition fmt (v:Operations_types.begin_async_arrow_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_async_generator_function_definition fmt (v:Operations_types.begin_async_generator_function_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option Typesystem_pp.pp_function_signature) fmt v.Operations_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_call_method fmt (v:Operations_types.call_method) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "method_name" Pbrt.Pp.pp_string fmt v.Operations_types.method_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_call_function_with_spread fmt (v:Operations_types.call_function_with_spread) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "spreads" (Pbrt.Pp.pp_list Pbrt.Pp.pp_bool) fmt v.Operations_types.spreads;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_unary_operator fmt (v:Operations_types.unary_operator) =
  match v with
  | Operations_types.Pre_inc -> Format.fprintf fmt "Pre_inc"
  | Operations_types.Pre_dec -> Format.fprintf fmt "Pre_dec"
  | Operations_types.Post_inc -> Format.fprintf fmt "Post_inc"
  | Operations_types.Post_dec -> Format.fprintf fmt "Post_dec"
  | Operations_types.Logical_not -> Format.fprintf fmt "Logical_not"
  | Operations_types.Bitwise_not -> Format.fprintf fmt "Bitwise_not"
  | Operations_types.Plus -> Format.fprintf fmt "Plus"
  | Operations_types.Minus -> Format.fprintf fmt "Minus"

let rec pp_unary_operation fmt (v:Operations_types.unary_operation) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "op" pp_unary_operator fmt v.Operations_types.op;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_binary_operator fmt (v:Operations_types.binary_operator) =
  match v with
  | Operations_types.Add -> Format.fprintf fmt "Add"
  | Operations_types.Sub -> Format.fprintf fmt "Sub"
  | Operations_types.Mul -> Format.fprintf fmt "Mul"
  | Operations_types.Div -> Format.fprintf fmt "Div"
  | Operations_types.Mod -> Format.fprintf fmt "Mod"
  | Operations_types.Bit_and -> Format.fprintf fmt "Bit_and"
  | Operations_types.Bit_or -> Format.fprintf fmt "Bit_or"
  | Operations_types.Logical_and -> Format.fprintf fmt "Logical_and"
  | Operations_types.Logical_or -> Format.fprintf fmt "Logical_or"
  | Operations_types.Xor -> Format.fprintf fmt "Xor"
  | Operations_types.Lshift -> Format.fprintf fmt "Lshift"
  | Operations_types.Rshift -> Format.fprintf fmt "Rshift"
  | Operations_types.Exp -> Format.fprintf fmt "Exp"
  | Operations_types.Unrshift -> Format.fprintf fmt "Unrshift"

let rec pp_binary_operation fmt (v:Operations_types.binary_operation) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "op" pp_binary_operator fmt v.Operations_types.op;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_comparator fmt (v:Operations_types.comparator) =
  match v with
  | Operations_types.Equal -> Format.fprintf fmt "Equal"
  | Operations_types.Strict_equal -> Format.fprintf fmt "Strict_equal"
  | Operations_types.Not_equal -> Format.fprintf fmt "Not_equal"
  | Operations_types.Strict_not_equal -> Format.fprintf fmt "Strict_not_equal"
  | Operations_types.Less_than -> Format.fprintf fmt "Less_than"
  | Operations_types.Less_than_or_equal -> Format.fprintf fmt "Less_than_or_equal"
  | Operations_types.Greater_than -> Format.fprintf fmt "Greater_than"
  | Operations_types.Greater_than_or_equal -> Format.fprintf fmt "Greater_than_or_equal"

let rec pp_compare fmt (v:Operations_types.compare) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "op" pp_comparator fmt v.Operations_types.op;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_eval fmt (v:Operations_types.eval) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "code" Pbrt.Pp.pp_string fmt v.Operations_types.code;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_class_definition fmt (v:Operations_types.begin_class_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "has_superclass" Pbrt.Pp.pp_bool fmt v.Operations_types.has_superclass;
    Pbrt.Pp.pp_record_field "constructor_parameters" (Pbrt.Pp.pp_list Typesystem_pp.pp_type_) fmt v.Operations_types.constructor_parameters;
    Pbrt.Pp.pp_record_field "instance_properties" (Pbrt.Pp.pp_list Pbrt.Pp.pp_string) fmt v.Operations_types.instance_properties;
    Pbrt.Pp.pp_record_field "instance_method_names" (Pbrt.Pp.pp_list Pbrt.Pp.pp_string) fmt v.Operations_types.instance_method_names;
    Pbrt.Pp.pp_record_field "instance_method_signatures" (Pbrt.Pp.pp_list Typesystem_pp.pp_function_signature) fmt v.Operations_types.instance_method_signatures;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_method_definition fmt (v:Operations_types.begin_method_definition) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "num_parameters" Pbrt.Pp.pp_int32 fmt v.Operations_types.num_parameters;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_call_super_method fmt (v:Operations_types.call_super_method) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "method_name" Pbrt.Pp.pp_string fmt v.Operations_types.method_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_super_property fmt (v:Operations_types.load_super_property) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_name" Pbrt.Pp.pp_string fmt v.Operations_types.property_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_store_super_property fmt (v:Operations_types.store_super_property) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "property_name" Pbrt.Pp.pp_string fmt v.Operations_types.property_name;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_load_from_scope fmt (v:Operations_types.load_from_scope) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "id" Pbrt.Pp.pp_string fmt v.Operations_types.id;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_store_to_scope fmt (v:Operations_types.store_to_scope) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "id" Pbrt.Pp.pp_string fmt v.Operations_types.id;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_while fmt (v:Operations_types.begin_while) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "comparator" pp_comparator fmt v.Operations_types.comparator;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_do_while fmt (v:Operations_types.begin_do_while) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "comparator" pp_comparator fmt v.Operations_types.comparator;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

let rec pp_begin_for fmt (v:Operations_types.begin_for) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "comparator" pp_comparator fmt v.Operations_types.comparator;
    Pbrt.Pp.pp_record_field "op" pp_binary_operator fmt v.Operations_types.op;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()
