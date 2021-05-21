(** typesystem.proto Pretty Printing *)


(** {2 Formatters} *)

val pp_type_ext : Format.formatter -> Typesystem_types.type_ext -> unit 
(** [pp_type_ext v] formats v *)

val pp_type_ : Format.formatter -> Typesystem_types.type_ -> unit 
(** [pp_type_ v] formats v *)

val pp_type_extension : Format.formatter -> Typesystem_types.type_extension -> unit 
(** [pp_type_extension v] formats v *)

val pp_function_signature : Format.formatter -> Typesystem_types.function_signature -> unit 
(** [pp_function_signature v] formats v *)
