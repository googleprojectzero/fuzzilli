(** typesystem.proto Types *)



(** {2 Types} *)

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


(** {2 Default values} *)

val default_type_ext : unit -> type_ext
(** [default_type_ext ()] is the default value for type [type_ext] *)

val default_type_ : 
  ?definite_type:int32 ->
  ?possible_type:int32 ->
  ?ext:type_ext ->
  unit ->
  type_
(** [default_type_ ()] is the default value for type [type_] *)

val default_type_extension : 
  ?properties:string list ->
  ?methods:string list ->
  ?group:string ->
  ?signature:function_signature option ->
  unit ->
  type_extension
(** [default_type_extension ()] is the default value for type [type_extension] *)

val default_function_signature : 
  ?input_types:type_ list ->
  ?output_type:type_ option ->
  unit ->
  function_signature
(** [default_function_signature ()] is the default value for type [function_signature] *)
