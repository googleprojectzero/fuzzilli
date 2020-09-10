[@@@ocaml.warning "-27-30-39"]

let rec pp_type_ext fmt (v:Typesystem_types.type_ext) =
  match v with
  | Typesystem_types.Extension_idx x -> Format.fprintf fmt "@[Extension_idx(%a)@]" Pbrt.Pp.pp_int32 x
  | Typesystem_types.Extension x -> Format.fprintf fmt "@[Extension(%a)@]" pp_type_extension x

and pp_type_ fmt (v:Typesystem_types.type_) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "definite_type" Pbrt.Pp.pp_int32 fmt v.Typesystem_types.definite_type;
    Pbrt.Pp.pp_record_field "possible_type" Pbrt.Pp.pp_int32 fmt v.Typesystem_types.possible_type;
    Pbrt.Pp.pp_record_field "ext" pp_type_ext fmt v.Typesystem_types.ext;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

and pp_type_extension fmt (v:Typesystem_types.type_extension) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "properties" (Pbrt.Pp.pp_list Pbrt.Pp.pp_string) fmt v.Typesystem_types.properties;
    Pbrt.Pp.pp_record_field "methods" (Pbrt.Pp.pp_list Pbrt.Pp.pp_string) fmt v.Typesystem_types.methods;
    Pbrt.Pp.pp_record_field "group" Pbrt.Pp.pp_string fmt v.Typesystem_types.group;
    Pbrt.Pp.pp_record_field "signature" (Pbrt.Pp.pp_option pp_function_signature) fmt v.Typesystem_types.signature;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()

and pp_function_signature fmt (v:Typesystem_types.function_signature) = 
  let pp_i fmt () =
    Format.pp_open_vbox fmt 1;
    Pbrt.Pp.pp_record_field "input_types" (Pbrt.Pp.pp_list pp_type_) fmt v.Typesystem_types.input_types;
    Pbrt.Pp.pp_record_field "output_type" (Pbrt.Pp.pp_option pp_type_) fmt v.Typesystem_types.output_type;
    Format.pp_close_box fmt ()
  in
  Pbrt.Pp.pp_brk pp_i fmt ()
