type tracker

(* A identifier is either in_scope as a fuzzilli temp, needs to be loaded from scope (e.g. a var in an exited scope), or is not found *)
type lookup_result = InScope of int32
    | GetFromScope of string
    | NotFound

(* Initializes the variable tracker*)
val init_tracker : bool -> bool -> tracker

(* Gets a new temp variable number, for use in int32ermediate values*)
val get_new_intermed_temp : tracker -> int32

(* Adds a new variable name & temp to the tracker*)
val add_new_var_identifier_local : tracker -> string -> int32 -> bool -> unit

(* Adds a new scope to the stack*)
val push_local_scope : tracker -> unit

(* Removes the current scope from the stack*)
val pop_local_scope : tracker -> unit

(* Access if emit_builtins has been set*)
val should_emit_builtins : tracker -> bool

(* Looks up an existing variable name, and returns the associated variable number*)
val lookup_var_name : tracker -> string -> lookup_result

val include_v8_natives : tracker -> bool