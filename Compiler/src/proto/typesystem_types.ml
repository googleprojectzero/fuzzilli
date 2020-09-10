[@@@ocaml.warning "-27-30-39"]


type type_ext =
  | Extension_idx of int32
  | Extension of type_extension

and type_ = {
  definite_type : int32;
  possible_type : int32;
  ext : type_ext;
}

and type_extension = {
  properties : string list;
  methods : string list;
  group : string;
  signature : function_signature option;
}

and function_signature = {
  input_types : type_ list;
  output_type : type_ option;
}

let rec default_type_ext () : type_ext = Extension_idx (0l)

and default_type_ 
  ?definite_type:((definite_type:int32) = 0l)
  ?possible_type:((possible_type:int32) = 0l)
  ?ext:((ext:type_ext) = Extension_idx (0l))
  () : type_  = {
  definite_type;
  possible_type;
  ext;
}

and default_type_extension 
  ?properties:((properties:string list) = [])
  ?methods:((methods:string list) = [])
  ?group:((group:string) = "")
  ?signature:((signature:function_signature option) = None)
  () : type_extension  = {
  properties;
  methods;
  group;
  signature;
}

and default_function_signature 
  ?input_types:((input_types:type_ list) = [])
  ?output_type:((output_type:type_ option) = None)
  () : function_signature  = {
  input_types;
  output_type;
}
