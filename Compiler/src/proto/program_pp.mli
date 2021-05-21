(** program.proto Pretty Printing *)


(** {2 Formatters} *)

val pp_instruction_operation : Format.formatter -> Program_types.instruction_operation -> unit 
(** [pp_instruction_operation v] formats v *)

val pp_instruction : Format.formatter -> Program_types.instruction -> unit 
(** [pp_instruction v] formats v *)

val pp_type_collection_status : Format.formatter -> Program_types.type_collection_status -> unit 
(** [pp_type_collection_status v] formats v *)

val pp_type_quality : Format.formatter -> Program_types.type_quality -> unit 
(** [pp_type_quality v] formats v *)

val pp_type_info : Format.formatter -> Program_types.type_info -> unit 
(** [pp_type_info v] formats v *)

val pp_program : Format.formatter -> Program_types.program -> unit 
(** [pp_program v] formats v *)
