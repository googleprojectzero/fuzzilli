type tracker

type var

type inst

(* A identifier is either in_scope as a fuzzilli temp, needs to be loaded from scope (e.g. a var in an exited scope), or is not found *)
type lookup_result = InScope of var
    | NotFound

type binary_op = Plus
    | Minus
    | Mult
    | Div
    | Mod
    | Xor
    | LShift
    | RShift
    | Exp
    | RShift3
    | BitAnd
    | BitOr
    | LogicalAnd
    | LogicalOr

type compare_op = Equal
    | NotEqual
    | StrictEqual
    | StrictNotEqual
    | LessThan
    | LessThanEqual
    | GreaterThan
    | GreaterThanEqual

type unary_op = Not
    | BitNot
    | Minus
    | Plus
    | PreInc
    | PostInc
    | PreDec
    | PostDec

(* Initializes the variable tracker *)
val init_tracker : bool -> bool -> bool -> tracker

(* Gets a new temp variable number, for use in int32ermediate values *)
val get_new_intermed_temp : tracker -> var

(* Support functions for variable hoisting *)
val add_hoisted_var : string -> tracker -> unit
val is_hoisted_var : string -> tracker -> bool
val clear_hoisted_vars : tracker -> unit

(* Adds a new variable name & temp to the tracker *)
val add_new_var_identifier : string -> var -> tracker -> unit

(* Adds a new scope to the stack *)
val push_local_scope : tracker -> unit

(* Removes the current scope from the stack *)
val pop_local_scope : tracker -> unit

(* Access if emit_builtins has been set *)
val should_emit_builtins : tracker -> bool

(* Looks up an existing variable name, and returns the associated variable number*)
val lookup_var_name : tracker -> string -> lookup_result

(* Whether to preprocess the hardcoded list of v8 natives, in order to remove the % *)
val include_v8_natives : tracker -> bool

(* Whether to replace unknown builtins with the placeholder builtin *)
val use_placeholder : tracker -> bool

(* Functions to build instructions in a manner similar to ProgramBuilder.swift *)
(* Note: Flow_Ast encodes BigInts as a float *)
val build_load_bigInt : float -> tracker -> (var * inst)
val build_load_bool : bool -> tracker -> (var * inst)
val build_load_builtin : string -> tracker -> (var * inst)
val build_load_float : float -> tracker -> (var * inst)
val build_load_from_scope : string -> tracker -> (var * inst)
val build_load_integer : int64 -> tracker -> (var * inst)
val build_load_null : tracker -> (var * inst)
val build_load_regex : string -> string -> tracker -> (var * inst)
val build_load_string : string -> tracker -> (var * inst)
val build_load_undefined : tracker -> (var * inst)

val build_delete_prop : var -> string -> tracker -> (var * inst)
val build_delete_computed_prop : var -> var -> tracker -> (var * inst)
val build_load_prop : var -> string -> tracker -> (var * inst)
val build_load_computed_prop : var -> var -> tracker -> (var * inst)
val build_store_prop : var -> var -> string -> tracker -> inst
val build_store_computed_prop : var -> var -> var -> tracker -> inst
val build_load_element : var -> int -> tracker -> (var * inst)
val build_new_object : var -> var list -> tracker -> (var * inst)

val build_binary_op : var -> var -> binary_op -> tracker -> (var * inst)
val build_compare_op : var -> var -> compare_op -> tracker -> (var * inst)
val build_instanceof_op : var -> var -> tracker -> (var * inst)
val build_in_op : var -> var -> tracker -> (var * inst)

val build_unary_op : var -> unary_op -> tracker -> (var * inst)
val build_await_op : var -> tracker -> (var * inst)
val build_typeof_op : var -> tracker -> (var * inst)
val build_void_op : tracker -> (var * inst)
val build_yield_op : var -> tracker -> inst
val build_yield_each_op : var -> tracker -> inst

val build_continue : tracker -> inst
val build_dup_op : var -> tracker -> (var * inst)
val build_reassign_op : var -> var -> tracker -> inst

val build_begin_if : var -> tracker -> inst
val build_begin_else : tracker -> inst
val build_end_if : tracker -> inst

val build_begin_while : var -> var -> compare_op -> tracker -> inst
val build_end_while : tracker -> inst
val build_begin_do_while : var -> var -> compare_op -> tracker -> inst
val build_end_do_while : tracker -> inst

val build_begin_for_in_op : var -> tracker -> (var * inst)
val build_end_for_in_op : tracker -> inst
val build_begin_for_of_op : var  -> tracker -> (var * inst)
val build_end_for_of_op : tracker -> inst


val build_begin_try_op : tracker -> inst
val build_begin_catch_op : string -> tracker -> inst
val build_end_try_catch_op : tracker -> inst

val build_begin_with_op : var -> tracker -> inst
val build_end_with_op : tracker -> inst

val build_throw_op : var -> tracker -> inst
val build_break_op : tracker -> inst


val build_create_array : var list -> tracker -> (var * inst)
val build_create_array_with_spread : var list -> bool list -> tracker -> (var * inst)
val build_create_object : string list -> var list -> tracker -> (var * inst)
val build_create_object_with_spread : string list -> var list -> tracker -> (var * inst)

val build_call : var -> var list -> tracker -> (var * inst)
val build_call_with_spread : var -> var list -> bool list-> tracker -> (var * inst)
val build_call_method : var -> var list -> string -> tracker -> (var * inst)
val build_return_op : var -> tracker -> inst

val build_func_ops : string option -> string list -> string option -> bool -> bool -> bool -> tracker -> (var * inst * inst)

val inst_to_prog_inst : inst -> Program_types.instruction