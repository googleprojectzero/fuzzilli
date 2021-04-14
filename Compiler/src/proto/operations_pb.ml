[@@@ocaml.warning "-27-30-39"]

type load_integer_mutable = {
  mutable value : int64;
}

let default_load_integer_mutable () : load_integer_mutable = {
  value = 0L;
}

type load_big_int_mutable = {
  mutable value : int64;
}

let default_load_big_int_mutable () : load_big_int_mutable = {
  value = 0L;
}

type load_float_mutable = {
  mutable value : float;
}

let default_load_float_mutable () : load_float_mutable = {
  value = 0.;
}

type load_string_mutable = {
  mutable value : string;
}

let default_load_string_mutable () : load_string_mutable = {
  value = "";
}

type load_boolean_mutable = {
  mutable value : bool;
}

let default_load_boolean_mutable () : load_boolean_mutable = {
  value = false;
}

type load_reg_exp_mutable = {
  mutable value : string;
  mutable flags : int32;
}

let default_load_reg_exp_mutable () : load_reg_exp_mutable = {
  value = "";
  flags = 0l;
}

type create_object_mutable = {
  mutable property_names : string list;
}

let default_create_object_mutable () : create_object_mutable = {
  property_names = [];
}

type create_object_with_spread_mutable = {
  mutable property_names : string list;
}

let default_create_object_with_spread_mutable () : create_object_with_spread_mutable = {
  property_names = [];
}

type create_array_with_spread_mutable = {
  mutable spreads : bool list;
}

let default_create_array_with_spread_mutable () : create_array_with_spread_mutable = {
  spreads = [];
}

type load_builtin_mutable = {
  mutable builtin_name : string;
}

let default_load_builtin_mutable () : load_builtin_mutable = {
  builtin_name = "";
}

type load_property_mutable = {
  mutable property_name : string;
}

let default_load_property_mutable () : load_property_mutable = {
  property_name = "";
}

type store_property_mutable = {
  mutable property_name : string;
}

let default_store_property_mutable () : store_property_mutable = {
  property_name = "";
}

type delete_property_mutable = {
  mutable property_name : string;
}

let default_delete_property_mutable () : delete_property_mutable = {
  property_name = "";
}

type load_element_mutable = {
  mutable index : int64;
}

let default_load_element_mutable () : load_element_mutable = {
  index = 0L;
}

type store_element_mutable = {
  mutable index : int64;
}

let default_store_element_mutable () : store_element_mutable = {
  index = 0L;
}

type delete_element_mutable = {
  mutable index : int64;
}

let default_delete_element_mutable () : delete_element_mutable = {
  index = 0L;
}

type begin_plain_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_plain_function_definition_mutable () : begin_plain_function_definition_mutable = {
  signature = None;
}

type begin_strict_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_strict_function_definition_mutable () : begin_strict_function_definition_mutable = {
  signature = None;
}

type begin_arrow_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_arrow_function_definition_mutable () : begin_arrow_function_definition_mutable = {
  signature = None;
}

type begin_generator_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_generator_function_definition_mutable () : begin_generator_function_definition_mutable = {
  signature = None;
}

type begin_async_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_async_function_definition_mutable () : begin_async_function_definition_mutable = {
  signature = None;
}

type begin_async_arrow_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_async_arrow_function_definition_mutable () : begin_async_arrow_function_definition_mutable = {
  signature = None;
}

type begin_async_generator_function_definition_mutable = {
  mutable signature : Typesystem_types.function_signature option;
}

let default_begin_async_generator_function_definition_mutable () : begin_async_generator_function_definition_mutable = {
  signature = None;
}

type call_method_mutable = {
  mutable method_name : string;
}

let default_call_method_mutable () : call_method_mutable = {
  method_name = "";
}

type call_function_with_spread_mutable = {
  mutable spreads : bool list;
}

let default_call_function_with_spread_mutable () : call_function_with_spread_mutable = {
  spreads = [];
}

type unary_operation_mutable = {
  mutable op : Operations_types.unary_operator;
}

let default_unary_operation_mutable () : unary_operation_mutable = {
  op = Operations_types.default_unary_operator ();
}

type binary_operation_mutable = {
  mutable op : Operations_types.binary_operator;
}

let default_binary_operation_mutable () : binary_operation_mutable = {
  op = Operations_types.default_binary_operator ();
}

type compare_mutable = {
  mutable op : Operations_types.comparator;
}

let default_compare_mutable () : compare_mutable = {
  op = Operations_types.default_comparator ();
}

type eval_mutable = {
  mutable code : string;
}

let default_eval_mutable () : eval_mutable = {
  code = "";
}

type begin_class_definition_mutable = {
  mutable has_superclass : bool;
  mutable constructor_parameters : Typesystem_types.type_ list;
  mutable instance_properties : string list;
  mutable instance_method_names : string list;
  mutable instance_method_signatures : Typesystem_types.function_signature list;
}

let default_begin_class_definition_mutable () : begin_class_definition_mutable = {
  has_superclass = false;
  constructor_parameters = [];
  instance_properties = [];
  instance_method_names = [];
  instance_method_signatures = [];
}

type begin_method_definition_mutable = {
  mutable num_parameters : int32;
}

let default_begin_method_definition_mutable () : begin_method_definition_mutable = {
  num_parameters = 0l;
}

type call_super_method_mutable = {
  mutable method_name : string;
}

let default_call_super_method_mutable () : call_super_method_mutable = {
  method_name = "";
}

type load_super_property_mutable = {
  mutable property_name : string;
}

let default_load_super_property_mutable () : load_super_property_mutable = {
  property_name = "";
}

type store_super_property_mutable = {
  mutable property_name : string;
}

let default_store_super_property_mutable () : store_super_property_mutable = {
  property_name = "";
}

type load_from_scope_mutable = {
  mutable id : string;
}

let default_load_from_scope_mutable () : load_from_scope_mutable = {
  id = "";
}

type store_to_scope_mutable = {
  mutable id : string;
}

let default_store_to_scope_mutable () : store_to_scope_mutable = {
  id = "";
}

type begin_while_mutable = {
  mutable comparator : Operations_types.comparator;
}

let default_begin_while_mutable () : begin_while_mutable = {
  comparator = Operations_types.default_comparator ();
}

type begin_do_while_mutable = {
  mutable comparator : Operations_types.comparator;
}

let default_begin_do_while_mutable () : begin_do_while_mutable = {
  comparator = Operations_types.default_comparator ();
}

type begin_for_mutable = {
  mutable comparator : Operations_types.comparator;
  mutable op : Operations_types.binary_operator;
}

let default_begin_for_mutable () : begin_for_mutable = {
  comparator = Operations_types.default_comparator ();
  op = Operations_types.default_binary_operator ();
}


let rec decode_load_integer d =
  let v = default_load_integer_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.value <- Pbrt.Decoder.int64_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_integer), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.value = v.value;
  } : Operations_types.load_integer)

let rec decode_load_big_int d =
  let v = default_load_big_int_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.value <- Pbrt.Decoder.int64_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_big_int), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.value = v.value;
  } : Operations_types.load_big_int)

let rec decode_load_float d =
  let v = default_load_float_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bits64) -> begin
      v.value <- Pbrt.Decoder.float_as_bits64 d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_float), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.value = v.value;
  } : Operations_types.load_float)

let rec decode_load_string d =
  let v = default_load_string_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.value <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_string), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.value = v.value;
  } : Operations_types.load_string)

let rec decode_load_boolean d =
  let v = default_load_boolean_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.value <- Pbrt.Decoder.bool d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_boolean), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.value = v.value;
  } : Operations_types.load_boolean)

let rec decode_load_reg_exp d =
  let v = default_load_reg_exp_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.value <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_reg_exp), field(1)" pk
    | Some (2, Pbrt.Varint) -> begin
      v.flags <- Pbrt.Decoder.int32_as_varint d;
    end
    | Some (2, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_reg_exp), field(2)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.value = v.value;
    Operations_types.flags = v.flags;
  } : Operations_types.load_reg_exp)

let rec decode_create_object d =
  let v = default_create_object_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.property_names <- List.rev v.property_names;
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_names <- (Pbrt.Decoder.string d) :: v.property_names;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(create_object), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_names = v.property_names;
  } : Operations_types.create_object)

let rec decode_create_object_with_spread d =
  let v = default_create_object_with_spread_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.property_names <- List.rev v.property_names;
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_names <- (Pbrt.Decoder.string d) :: v.property_names;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(create_object_with_spread), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_names = v.property_names;
  } : Operations_types.create_object_with_spread)

let rec decode_create_array_with_spread d =
  let v = default_create_array_with_spread_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.spreads <- List.rev v.spreads;
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.spreads <- Pbrt.Decoder.packed_fold (fun l d -> (Pbrt.Decoder.bool d)::l) [] d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(create_array_with_spread), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.spreads = v.spreads;
  } : Operations_types.create_array_with_spread)

let rec decode_load_builtin d =
  let v = default_load_builtin_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.builtin_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_builtin), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.builtin_name = v.builtin_name;
  } : Operations_types.load_builtin)

let rec decode_load_property d =
  let v = default_load_property_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_property), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_name = v.property_name;
  } : Operations_types.load_property)

let rec decode_store_property d =
  let v = default_store_property_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(store_property), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_name = v.property_name;
  } : Operations_types.store_property)

let rec decode_delete_property d =
  let v = default_delete_property_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(delete_property), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_name = v.property_name;
  } : Operations_types.delete_property)

let rec decode_load_element d =
  let v = default_load_element_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.index <- Pbrt.Decoder.int64_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_element), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.index = v.index;
  } : Operations_types.load_element)

let rec decode_store_element d =
  let v = default_store_element_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.index <- Pbrt.Decoder.int64_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(store_element), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.index = v.index;
  } : Operations_types.store_element)

let rec decode_delete_element d =
  let v = default_delete_element_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.index <- Pbrt.Decoder.int64_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(delete_element), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.index = v.index;
  } : Operations_types.delete_element)

let rec decode_begin_plain_function_definition d =
  let v = default_begin_plain_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_plain_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_plain_function_definition)

let rec decode_begin_strict_function_definition d =
  let v = default_begin_strict_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_strict_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_strict_function_definition)

let rec decode_begin_arrow_function_definition d =
  let v = default_begin_arrow_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_arrow_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_arrow_function_definition)

let rec decode_begin_generator_function_definition d =
  let v = default_begin_generator_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_generator_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_generator_function_definition)

let rec decode_begin_async_function_definition d =
  let v = default_begin_async_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_async_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_async_function_definition)

let rec decode_begin_async_arrow_function_definition d =
  let v = default_begin_async_arrow_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_async_arrow_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_async_arrow_function_definition)

let rec decode_begin_async_generator_function_definition d =
  let v = default_begin_async_generator_function_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.signature <- Some (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_async_generator_function_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.signature = v.signature;
  } : Operations_types.begin_async_generator_function_definition)

let rec decode_call_method d =
  let v = default_call_method_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.method_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(call_method), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.method_name = v.method_name;
  } : Operations_types.call_method)

let rec decode_call_function_with_spread d =
  let v = default_call_function_with_spread_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.spreads <- List.rev v.spreads;
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.spreads <- Pbrt.Decoder.packed_fold (fun l d -> (Pbrt.Decoder.bool d)::l) [] d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(call_function_with_spread), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.spreads = v.spreads;
  } : Operations_types.call_function_with_spread)

let rec decode_unary_operator d = 
  match Pbrt.Decoder.int_as_varint d with
  | 0 -> (Operations_types.Pre_inc:Operations_types.unary_operator)
  | 1 -> (Operations_types.Pre_dec:Operations_types.unary_operator)
  | 2 -> (Operations_types.Post_inc:Operations_types.unary_operator)
  | 3 -> (Operations_types.Post_dec:Operations_types.unary_operator)
  | 4 -> (Operations_types.Logical_not:Operations_types.unary_operator)
  | 5 -> (Operations_types.Bitwise_not:Operations_types.unary_operator)
  | 6 -> (Operations_types.Plus:Operations_types.unary_operator)
  | 7 -> (Operations_types.Minus:Operations_types.unary_operator)
  | _ -> Pbrt.Decoder.malformed_variant "unary_operator"

let rec decode_unary_operation d =
  let v = default_unary_operation_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.op <- decode_unary_operator d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(unary_operation), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.op = v.op;
  } : Operations_types.unary_operation)

let rec decode_binary_operator d = 
  match Pbrt.Decoder.int_as_varint d with
  | 0 -> (Operations_types.Add:Operations_types.binary_operator)
  | 1 -> (Operations_types.Sub:Operations_types.binary_operator)
  | 2 -> (Operations_types.Mul:Operations_types.binary_operator)
  | 3 -> (Operations_types.Div:Operations_types.binary_operator)
  | 4 -> (Operations_types.Mod:Operations_types.binary_operator)
  | 5 -> (Operations_types.Bit_and:Operations_types.binary_operator)
  | 6 -> (Operations_types.Bit_or:Operations_types.binary_operator)
  | 7 -> (Operations_types.Logical_and:Operations_types.binary_operator)
  | 8 -> (Operations_types.Logical_or:Operations_types.binary_operator)
  | 9 -> (Operations_types.Xor:Operations_types.binary_operator)
  | 10 -> (Operations_types.Lshift:Operations_types.binary_operator)
  | 11 -> (Operations_types.Rshift:Operations_types.binary_operator)
  | 12 -> (Operations_types.Exp:Operations_types.binary_operator)
  | 13 -> (Operations_types.Unrshift:Operations_types.binary_operator)
  | _ -> Pbrt.Decoder.malformed_variant "binary_operator"

let rec decode_binary_operation d =
  let v = default_binary_operation_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.op <- decode_binary_operator d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(binary_operation), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.op = v.op;
  } : Operations_types.binary_operation)

let rec decode_comparator d = 
  match Pbrt.Decoder.int_as_varint d with
  | 0 -> (Operations_types.Equal:Operations_types.comparator)
  | 1 -> (Operations_types.Strict_equal:Operations_types.comparator)
  | 2 -> (Operations_types.Not_equal:Operations_types.comparator)
  | 3 -> (Operations_types.Strict_not_equal:Operations_types.comparator)
  | 4 -> (Operations_types.Less_than:Operations_types.comparator)
  | 5 -> (Operations_types.Less_than_or_equal:Operations_types.comparator)
  | 6 -> (Operations_types.Greater_than:Operations_types.comparator)
  | 7 -> (Operations_types.Greater_than_or_equal:Operations_types.comparator)
  | _ -> Pbrt.Decoder.malformed_variant "comparator"

let rec decode_compare d =
  let v = default_compare_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.op <- decode_comparator d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(compare), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.op = v.op;
  } : Operations_types.compare)

let rec decode_eval d =
  let v = default_eval_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.code <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(eval), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.code = v.code;
  } : Operations_types.eval)

let rec decode_begin_class_definition d =
  let v = default_begin_class_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.instance_method_signatures <- List.rev v.instance_method_signatures;
      v.instance_method_names <- List.rev v.instance_method_names;
      v.instance_properties <- List.rev v.instance_properties;
      v.constructor_parameters <- List.rev v.constructor_parameters;
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.has_superclass <- Pbrt.Decoder.bool d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_class_definition), field(1)" pk
    | Some (2, Pbrt.Bytes) -> begin
      v.constructor_parameters <- (Typesystem_pb.decode_type_ (Pbrt.Decoder.nested d)) :: v.constructor_parameters;
    end
    | Some (2, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_class_definition), field(2)" pk
    | Some (3, Pbrt.Bytes) -> begin
      v.instance_properties <- (Pbrt.Decoder.string d) :: v.instance_properties;
    end
    | Some (3, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_class_definition), field(3)" pk
    | Some (4, Pbrt.Bytes) -> begin
      v.instance_method_names <- (Pbrt.Decoder.string d) :: v.instance_method_names;
    end
    | Some (4, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_class_definition), field(4)" pk
    | Some (5, Pbrt.Bytes) -> begin
      v.instance_method_signatures <- (Typesystem_pb.decode_function_signature (Pbrt.Decoder.nested d)) :: v.instance_method_signatures;
    end
    | Some (5, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_class_definition), field(5)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.has_superclass = v.has_superclass;
    Operations_types.constructor_parameters = v.constructor_parameters;
    Operations_types.instance_properties = v.instance_properties;
    Operations_types.instance_method_names = v.instance_method_names;
    Operations_types.instance_method_signatures = v.instance_method_signatures;
  } : Operations_types.begin_class_definition)

let rec decode_begin_method_definition d =
  let v = default_begin_method_definition_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.num_parameters <- Pbrt.Decoder.int32_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_method_definition), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.num_parameters = v.num_parameters;
  } : Operations_types.begin_method_definition)

let rec decode_call_super_method d =
  let v = default_call_super_method_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.method_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(call_super_method), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.method_name = v.method_name;
  } : Operations_types.call_super_method)

let rec decode_load_super_property d =
  let v = default_load_super_property_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_super_property), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_name = v.property_name;
  } : Operations_types.load_super_property)

let rec decode_store_super_property d =
  let v = default_store_super_property_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.property_name <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(store_super_property), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.property_name = v.property_name;
  } : Operations_types.store_super_property)

let rec decode_load_from_scope d =
  let v = default_load_from_scope_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.id <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(load_from_scope), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.id = v.id;
  } : Operations_types.load_from_scope)

let rec decode_store_to_scope d =
  let v = default_store_to_scope_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.id <- Pbrt.Decoder.string d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(store_to_scope), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.id = v.id;
  } : Operations_types.store_to_scope)

let rec decode_begin_while d =
  let v = default_begin_while_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.comparator <- decode_comparator d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_while), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.comparator = v.comparator;
  } : Operations_types.begin_while)

let rec decode_begin_do_while d =
  let v = default_begin_do_while_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.comparator <- decode_comparator d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_do_while), field(1)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.comparator = v.comparator;
  } : Operations_types.begin_do_while)

let rec decode_begin_for d =
  let v = default_begin_for_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.comparator <- decode_comparator d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_for), field(1)" pk
    | Some (2, Pbrt.Varint) -> begin
      v.op <- decode_binary_operator d;
    end
    | Some (2, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(begin_for), field(2)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Operations_types.comparator = v.comparator;
    Operations_types.op = v.op;
  } : Operations_types.begin_for)

let rec encode_load_integer (v:Operations_types.load_integer) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int64_as_varint v.Operations_types.value encoder;
  ()

let rec encode_load_big_int (v:Operations_types.load_big_int) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int64_as_varint v.Operations_types.value encoder;
  ()

let rec encode_load_float (v:Operations_types.load_float) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bits64) encoder; 
  Pbrt.Encoder.float_as_bits64 v.Operations_types.value encoder;
  ()

let rec encode_load_string (v:Operations_types.load_string) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.value encoder;
  ()

let rec encode_load_boolean (v:Operations_types.load_boolean) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.bool v.Operations_types.value encoder;
  ()

let rec encode_load_reg_exp (v:Operations_types.load_reg_exp) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.value encoder;
  Pbrt.Encoder.key (2, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int32_as_varint v.Operations_types.flags encoder;
  ()

let rec encode_create_object (v:Operations_types.create_object) encoder = 
  List.iter (fun x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.string x encoder;
  ) v.Operations_types.property_names;
  ()

let rec encode_create_object_with_spread (v:Operations_types.create_object_with_spread) encoder = 
  List.iter (fun x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.string x encoder;
  ) v.Operations_types.property_names;
  ()

let rec encode_create_array_with_spread (v:Operations_types.create_array_with_spread) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.nested (fun encoder ->
    List.iter (fun x -> 
      Pbrt.Encoder.bool x encoder;
    ) v.Operations_types.spreads;
  ) encoder;
  ()

let rec encode_load_builtin (v:Operations_types.load_builtin) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.builtin_name encoder;
  ()

let rec encode_load_property (v:Operations_types.load_property) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.property_name encoder;
  ()

let rec encode_store_property (v:Operations_types.store_property) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.property_name encoder;
  ()

let rec encode_delete_property (v:Operations_types.delete_property) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.property_name encoder;
  ()

let rec encode_load_element (v:Operations_types.load_element) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int64_as_varint v.Operations_types.index encoder;
  ()

let rec encode_store_element (v:Operations_types.store_element) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int64_as_varint v.Operations_types.index encoder;
  ()

let rec encode_delete_element (v:Operations_types.delete_element) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int64_as_varint v.Operations_types.index encoder;
  ()

let rec encode_begin_plain_function_definition (v:Operations_types.begin_plain_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_begin_strict_function_definition (v:Operations_types.begin_strict_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_begin_arrow_function_definition (v:Operations_types.begin_arrow_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_begin_generator_function_definition (v:Operations_types.begin_generator_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_begin_async_function_definition (v:Operations_types.begin_async_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_begin_async_arrow_function_definition (v:Operations_types.begin_async_arrow_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_begin_async_generator_function_definition (v:Operations_types.begin_async_generator_function_definition) encoder = 
  begin match v.Operations_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

let rec encode_call_method (v:Operations_types.call_method) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.method_name encoder;
  ()

let rec encode_call_function_with_spread (v:Operations_types.call_function_with_spread) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.nested (fun encoder ->
    List.iter (fun x -> 
      Pbrt.Encoder.bool x encoder;
    ) v.Operations_types.spreads;
  ) encoder;
  ()

let rec encode_unary_operator (v:Operations_types.unary_operator) encoder =
  match v with
  | Operations_types.Pre_inc -> Pbrt.Encoder.int_as_varint (0) encoder
  | Operations_types.Pre_dec -> Pbrt.Encoder.int_as_varint 1 encoder
  | Operations_types.Post_inc -> Pbrt.Encoder.int_as_varint 2 encoder
  | Operations_types.Post_dec -> Pbrt.Encoder.int_as_varint 3 encoder
  | Operations_types.Logical_not -> Pbrt.Encoder.int_as_varint 4 encoder
  | Operations_types.Bitwise_not -> Pbrt.Encoder.int_as_varint 5 encoder
  | Operations_types.Plus -> Pbrt.Encoder.int_as_varint 6 encoder
  | Operations_types.Minus -> Pbrt.Encoder.int_as_varint 7 encoder

let rec encode_unary_operation (v:Operations_types.unary_operation) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  encode_unary_operator v.Operations_types.op encoder;
  ()

let rec encode_binary_operator (v:Operations_types.binary_operator) encoder =
  match v with
  | Operations_types.Add -> Pbrt.Encoder.int_as_varint (0) encoder
  | Operations_types.Sub -> Pbrt.Encoder.int_as_varint 1 encoder
  | Operations_types.Mul -> Pbrt.Encoder.int_as_varint 2 encoder
  | Operations_types.Div -> Pbrt.Encoder.int_as_varint 3 encoder
  | Operations_types.Mod -> Pbrt.Encoder.int_as_varint 4 encoder
  | Operations_types.Bit_and -> Pbrt.Encoder.int_as_varint 5 encoder
  | Operations_types.Bit_or -> Pbrt.Encoder.int_as_varint 6 encoder
  | Operations_types.Logical_and -> Pbrt.Encoder.int_as_varint 7 encoder
  | Operations_types.Logical_or -> Pbrt.Encoder.int_as_varint 8 encoder
  | Operations_types.Xor -> Pbrt.Encoder.int_as_varint 9 encoder
  | Operations_types.Lshift -> Pbrt.Encoder.int_as_varint 10 encoder
  | Operations_types.Rshift -> Pbrt.Encoder.int_as_varint 11 encoder
  | Operations_types.Exp -> Pbrt.Encoder.int_as_varint 12 encoder
  | Operations_types.Unrshift -> Pbrt.Encoder.int_as_varint 13 encoder

let rec encode_binary_operation (v:Operations_types.binary_operation) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  encode_binary_operator v.Operations_types.op encoder;
  ()

let rec encode_comparator (v:Operations_types.comparator) encoder =
  match v with
  | Operations_types.Equal -> Pbrt.Encoder.int_as_varint (0) encoder
  | Operations_types.Strict_equal -> Pbrt.Encoder.int_as_varint 1 encoder
  | Operations_types.Not_equal -> Pbrt.Encoder.int_as_varint 2 encoder
  | Operations_types.Strict_not_equal -> Pbrt.Encoder.int_as_varint 3 encoder
  | Operations_types.Less_than -> Pbrt.Encoder.int_as_varint 4 encoder
  | Operations_types.Less_than_or_equal -> Pbrt.Encoder.int_as_varint 5 encoder
  | Operations_types.Greater_than -> Pbrt.Encoder.int_as_varint 6 encoder
  | Operations_types.Greater_than_or_equal -> Pbrt.Encoder.int_as_varint 7 encoder

let rec encode_compare (v:Operations_types.compare) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  encode_comparator v.Operations_types.op encoder;
  ()

let rec encode_eval (v:Operations_types.eval) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.code encoder;
  ()

let rec encode_begin_class_definition (v:Operations_types.begin_class_definition) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.bool v.Operations_types.has_superclass encoder;
  List.iter (fun x -> 
    Pbrt.Encoder.key (2, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_type_ x) encoder;
  ) v.Operations_types.constructor_parameters;
  List.iter (fun x -> 
    Pbrt.Encoder.key (3, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.string x encoder;
  ) v.Operations_types.instance_properties;
  List.iter (fun x -> 
    Pbrt.Encoder.key (4, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.string x encoder;
  ) v.Operations_types.instance_method_names;
  List.iter (fun x -> 
    Pbrt.Encoder.key (5, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (Typesystem_pb.encode_function_signature x) encoder;
  ) v.Operations_types.instance_method_signatures;
  ()

let rec encode_begin_method_definition (v:Operations_types.begin_method_definition) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int32_as_varint v.Operations_types.num_parameters encoder;
  ()

let rec encode_call_super_method (v:Operations_types.call_super_method) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.method_name encoder;
  ()

let rec encode_load_super_property (v:Operations_types.load_super_property) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.property_name encoder;
  ()

let rec encode_store_super_property (v:Operations_types.store_super_property) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.property_name encoder;
  ()

let rec encode_load_from_scope (v:Operations_types.load_from_scope) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.id encoder;
  ()

let rec encode_store_to_scope (v:Operations_types.store_to_scope) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Operations_types.id encoder;
  ()

let rec encode_begin_while (v:Operations_types.begin_while) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  encode_comparator v.Operations_types.comparator encoder;
  ()

let rec encode_begin_do_while (v:Operations_types.begin_do_while) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  encode_comparator v.Operations_types.comparator encoder;
  ()

let rec encode_begin_for (v:Operations_types.begin_for) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  encode_comparator v.Operations_types.comparator encoder;
  Pbrt.Encoder.key (2, Pbrt.Varint) encoder; 
  encode_binary_operator v.Operations_types.op encoder;
  ()
