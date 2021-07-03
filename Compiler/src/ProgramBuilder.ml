open Program_types

module String_Set = Set.Make(struct type t = string let compare = compare end)

type var = int32

(* Keeps a mapping of ids to temps *)
type temp_map_t = (string, var, Core.String.comparator_witness) Core.Map.t


type inst = instruction

(* Keeps a mapping of ids that are still visible in Javascipt, but that Fuzzilli considers out of scope.
Used to determine if var should be loaded from scope, rather than accessed as a temp *)
type var_scope_map_t = (string, string, Core.String.comparator_witness) Core.Map.t

type builder = 
    { mutable next_index : var; 
      mutable local_maps : temp_map_t list;
      mutable hoisted_vars : String_Set.t;
      emit_builtins : bool;
      include_v8_natives : bool;
      use_placeholder: bool;
    }

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

(* TODO: Expand these into full constructors, similar to what is in TypeSystem.swift *)
let unknown_type_int = Int32.shift_left 1l 8
let anything_type_int = Int32.sub (Int32.shift_left 1l 12) 1l
let nothing_type_int = 0l

let translate_compare_op compare_op =
    let res : Operations_types.comparator = match compare_op with 
        Equal -> Equal
        | NotEqual -> Not_equal
        | StrictEqual -> Strict_equal
        | StrictNotEqual -> Strict_not_equal
        | LessThan -> Less_than
        | LessThanEqual -> Less_than_or_equal
        | GreaterThan -> Greater_than
        | GreaterThanEqual -> Greater_than_or_equal in
    res

let init_builder emit_builtins include_v8_natives use_placeholder = {
    next_index = 0l;
    local_maps = [Core.Map.empty (module Core.String)];
    hoisted_vars = String_Set.empty;
    emit_builtins = emit_builtins;
    include_v8_natives = include_v8_natives;
    use_placeholder = use_placeholder;
    }

(* Get a new intermediate id *)
let get_new_intermed_temp builder = 
    let ret_index = builder.next_index in
    builder.next_index <- Base.Int32.(+) builder.next_index 1l;
    (* Fuzzilli limits var numbers to fit within 16 bits*)
    if Core.Int32.(>) ret_index 65535l then
        raise (Invalid_argument "Too many variables for Fuzzilli. Must be <= 65535")
    else ();
    ret_index

let add_hoisted_var (var_name:string) builder = 
    let new_hoised_var_set = String_Set.add var_name builder.hoisted_vars in
    builder.hoisted_vars <- new_hoised_var_set

let is_hoisted_var (var_name:string) builder =
    String_Set.mem var_name builder.hoisted_vars

let clear_hoisted_vars builder =
    builder.hoisted_vars <- String_Set.empty

(* Associate an intermediate variable with an identifier, with specified visibility *)
let add_new_var_identifier name num builder =
    let curr_local_map, rest_maps  = match builder.local_maps with
        [] -> raise (Invalid_argument "Empty local scopes")
        | x :: tl -> x, tl 
        in
    let new_map = Core.Map.update curr_local_map name (fun _ -> num) in
    builder.local_maps <- new_map :: rest_maps

(* This group of functions manages variable scope*)
let push_local_scope builder =
    let new_map = Core.Map.empty (module Core.String) in
    builder.local_maps <- new_map :: builder.local_maps
    
let pop_local_scope builder =
    match (Core.List.tl builder.local_maps) with
        Some x -> builder.local_maps <- x
        | None -> raise (Invalid_argument "Tried to pop empty local scope")

let update_map m (i:(var * string) option) = 
    match i with
        Some (temp,name ) -> Core.Map.update m name (fun _ -> temp)
        | None -> m

let rec check_local_maps map_list name =
    match map_list with
        hd :: tl -> (match Core.Map.find hd name with
            Some x -> Some x
            | None -> check_local_maps tl name)
        | [] -> None

(* Fist looks through the local maps in appropriate order, then checks globals,
and then items declared as 'var' but outside the fuzzilli scope *)
let lookup_var_name builder name = 
    let local_map_res = check_local_maps builder.local_maps name in
    match local_map_res with 
        Some x -> InScope x
        | None -> NotFound

let should_emit_builtins builder =
    builder.emit_builtins

let include_v8_natives builder = 
    builder.include_v8_natives

let use_placeholder builder =
    builder.use_placeholder

let build_load_bigInt b builder = 
    let result_var = get_new_intermed_temp builder in
    (* TODO: Validate if this is right *)
    let is_int f = fst (Float.modf f) <= Float.epsilon in
    if is_int b && b <= (Base.Int64.to_float Int64.max_int) && b >= (Base.Int64.to_float Int64.min_int) then
        let op : Operations_types.load_big_int = Operations_types.{value = Int64.of_float b} in
        let inst = Program_types.{
            inouts = [result_var];
            operation = Load_big_int op;
        } in
        result_var, inst
    else
        raise (Invalid_argument ("Improper Bigint provided"))

let build_load_bool b builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [result_var];
        operation = Load_boolean Operations_types.{value = b};
    } in
    result_var, inst

let build_load_builtin name builder =
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts = [result_var];
        operation = Load_builtin Operations_types.{builtin_name = name};
    } in
    result_var, inst

let build_load_float f builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [result_var];
        operation = Load_float Operations_types.{value = f};
    } in
    result_var, inst

let build_load_from_scope name builder =
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts = [result_var];
        operation = Load_from_scope Operations_types.{id = name};
    } in
    result_var, inst

let build_load_integer i builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [result_var];
        operation = Load_integer Operations_types.{value = i};
    } in
    result_var, inst

let build_load_null builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [result_var];
        operation = Load_null;
    } in
    result_var, inst

let build_load_regex pattern flags builder = 
    let result_var = get_new_intermed_temp builder in
    let op = Operations_types.{value = pattern; flags = Util.regex_flag_str_to_int flags} in
    let inst_op = Load_reg_exp op in
    let inst = Program_types.{
        inouts = [result_var];
        operation = inst_op;
    } in
        result_var, inst

let build_load_string s builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [result_var];
        operation = Load_string Operations_types.{value = s};
    } in
    result_var, inst

let build_load_undefined builder = 
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts = [result_var];
        operation = Program_types.Load_undefined;
    } in
    result_var, inst

let build_delete_prop var name builder =
    let inst_op = Program_types.Delete_property Operations_types.{property_name = name} in
    let inst : Program_types.instruction = Program_types.{
        inouts = [var];
        operation = inst_op;
    } in
    var, inst

let build_delete_computed_prop obj_var exp_var builder = 
    let inst = Program_types.{
        inouts =  [obj_var; exp_var];
        operation = Delete_computed_property;
    } in
    obj_var, inst

let build_load_prop input_var name builder =
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts =  [input_var; result_var];
        operation = Load_property{property_name = name};
    } in
    result_var, inst

let build_load_computed_prop obj_var exp_var builder = 
    let result_var = get_new_intermed_temp builder in
    let load_inst = Program_types.{
        inouts =  [obj_var; exp_var; result_var];
        operation = Load_computed_property;
    } in
    result_var, load_inst

let build_store_prop obj_var value_var prop_name builder = 
    Program_types.{
        inouts =  [obj_var; value_var];
        operation = Store_property{property_name = prop_name }
    }

let build_store_computed_prop obj_var index_var value_var builder =
   Program_types.{
        inouts =  [obj_var; index_var; value_var];
        operation = Program_types.Store_computed_property;
    } 

let build_load_element array_var index builder =
    let result_var = get_new_intermed_temp builder in
    let load_inst = Program_types.{
        inouts = [array_var; result_var];
        operation = Load_element{index = Int64.of_int index};
    } in
    result_var, load_inst

let build_new_object obj_var arg_list builder = 
    let result_var = get_new_intermed_temp builder in
    let new_obj_inst = Program_types.{
        inouts =  [obj_var] @ arg_list @ [result_var];
        operation = Program_types.Construct;
    } in
    result_var, new_obj_inst

let build_binary_op lvar rvar (binary_op: binary_op) builder = 
    let result_var = get_new_intermed_temp builder in
    let op : Operations_types.binary_operation = match binary_op with
        Plus -> Operations_types.{op = Add}
        | Minus -> Operations_types.{op = Sub}
        | Mult -> Operations_types.{op = Mul}
        | Div -> Operations_types.{op = Div}
        | Mod -> Operations_types.{op = Mod}
        | Xor -> Operations_types.{op = Xor}
        | LShift -> Operations_types.{op = Lshift}
        | RShift -> Operations_types.{op = Rshift}
        | Exp -> Operations_types.{op = Exp}
        | RShift3 -> Operations_types.{op = Unrshift}
        | BitAnd -> Operations_types.{op = Bit_and}
        | BitOr -> Operations_types.{op = Bit_or} 
        | LogicalAnd -> Operations_types.{op = Logical_and}
        | LogicalOr -> Operations_types.{op = Logical_or} in
    let inst = Program_types.{
        inouts = [lvar; rvar; result_var];
        operation = Binary_operation op;
    } in
    result_var, inst

let build_compare_op lvar rvar (compare_op: compare_op) builder = 
    let result_var = get_new_intermed_temp builder in
    let op = translate_compare_op compare_op in 
    let inst = Program_types.{
        inouts = [lvar; rvar; result_var];
        operation = Compare Operations_types.{op = op};
    } in
    result_var, inst

let build_instanceof_op lvar rvar builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [lvar; rvar; result_var];
        operation = Instance_of;
    } in
    result_var, inst

let build_in_op lvar rvar builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [lvar; rvar; result_var];
        operation = In;
    } in
    result_var, inst


let build_unary_op var unary_op builder = 
    let result_var = get_new_intermed_temp builder in
    let op = match unary_op with
        Not -> Operations_types.Logical_not
        | BitNot -> Operations_types.Bitwise_not
        | Minus -> Operations_types.Minus
        | Plus -> Operations_types.Plus
        | PreInc -> Operations_types.Pre_inc
        | PostInc -> Operations_types.Post_inc
        | PreDec -> Operations_types.Pre_dec
        | PostDec -> Operations_types.Post_dec
        in
    let unary_inst = Program_types.{
        inouts = [var; result_var];
        operation = Unary_operation Operations_types.{op = op};
    } in
    result_var, unary_inst

let build_await_op var builder = 
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts = [var; result_var];
        operation = Await;
    } in
    result_var, inst

let build_typeof_op var builder = 
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts = [var; result_var];
        operation = Type_of;
    } in
    result_var, inst

(* Fuzzilli doesn't have a loadVoid operator. Execute the operation inst, and then load undefined*)
let build_void_op builder = 
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts = [result_var];
        operation = Load_undefined;
    } in
    result_var, inst

let build_yield_op var builder =
    Program_types.{
        inouts = [var];
        operation = Yield;
    }

let build_yield_each_op var builder =
    Program_types.{
        inouts = [var];
        operation = Yield_each;
    }

let build_continue builder = 
    Program_types.{
        inouts = [];
        operation = Program_types.Continue;
    }

let build_dup_op value builder = 
    let result_var = get_new_intermed_temp builder in 
    let inst : Program_types.instruction = Program_types.{
        inouts = [value; result_var];
        operation = Program_types.Dup;
    } in
    result_var, inst

let build_reassign_op dst src builder = 
    Program_types.{
        inouts = [dst; src];
        operation = Reassign;
    }

let build_begin_if var builder = 
    let begin_if_inst = Program_types.{
        inouts = [var];
        operation = Begin_if;
    } in
    begin_if_inst

let build_begin_else builder = 
    let begin_else_inst = Program_types.{
        inouts = [];
        operation = Begin_else;
    } in
    begin_else_inst

let build_end_if builder = 
    let end_if_inst = Program_types.{
        inouts = [];
        operation = End_if;
    } in
    end_if_inst

let build_begin_while lvar rvar compare_op builder = 
    let op = translate_compare_op compare_op in
    Program_types.{
        inouts =  [lvar; rvar];
        operation = Begin_while{comparator = op};
    }

let build_end_while builder = 
    Program_types.{
        inouts = [];
        operation = End_while;
    }

let build_begin_do_while lvar rvar compare_op builder = 
    let op = translate_compare_op compare_op in
    Program_types.{
        inouts =  [lvar; rvar];
        operation = Begin_do_while{comparator = op};
    }

let build_end_do_while builder = 
    Program_types.{
        inouts = [];
        operation = End_do_while;
    }

let build_begin_for_in_op left_temp right_var builder =
    let inst = Program_types.{
        inouts =  [right_var; left_temp];
        operation = Program_types.Begin_for_in;
    } in
    left_temp, inst

let build_end_for_in_op builder =
    Program_types.{
        inouts = [];
        operation = Program_types.End_for_in;
    }

let build_begin_for_of_op right_var builder =
    let left_temp = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts =  [right_var; left_temp];
        operation = Program_types.Begin_for_of;
    } in
    (left_temp, inst)

let build_end_for_of_op builder =
    Program_types.{
        inouts = [];
        operation = Program_types.End_for_of;
    }

let build_begin_try_op builder =
    Program_types.{
        inouts = [];
        operation = Program_types.Begin_try;
    }

let build_begin_catch_op name builder =
    let intermed_temp = get_new_intermed_temp builder in
    add_new_var_identifier name intermed_temp builder;
    Program_types.{
        inouts = [intermed_temp];
        operation = Program_types.Begin_catch;
    }

let build_end_try_catch_op builder =
    Program_types.{
        inouts = [];
        operation = Program_types.End_try_catch;
    }

let build_begin_with_op var builder =
    Program_types.{
        inouts = [var];
        operation = Program_types.Begin_with;
    }

let build_end_with_op builder =
    Program_types.{
        inouts = [];
        operation = Program_types.End_with;
    }

let build_throw_op var builder =
    Program_types.{
        inouts = [var];
        operation = Program_types.Throw_exception;
    }

let build_break_op builder = 
    Program_types.{
        inouts = [];
        operation = Program_types.Break;
    }

let build_create_array args builder =
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = args @ [result_var];
        operation = Create_array;
    } in
    result_var, inst

let build_create_array_with_spread args spread_args builder =
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = args @ [result_var];
        operation = Create_array_with_spread Operations_types.{spreads = spread_args};
    } in
    result_var, inst

let build_create_object name_list arg_list builder =
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = arg_list @ [result_var];
        operation = Create_object{property_names = name_list};
    } in
    result_var, inst

let build_create_object_with_spread name_list arg_list builder =
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = arg_list @ [result_var];
        operation = Create_object_with_spread{property_names = name_list};
    } in
    result_var, inst

let build_call func args builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [func] @ args @ [result_var];
        operation = Call_function;
    } in
    result_var, inst

let build_call_with_spread func args spread_list builder = 
    let result_var = get_new_intermed_temp builder in
    let inst = Program_types.{
        inouts = [func] @ args @ [result_var];
        operation = Call_function_with_spread Operations_types.{spreads = spread_list};
    } in
    result_var, inst

let build_call_method sub_exp_temp args method_name builder = 
    let result_var = get_new_intermed_temp builder in
    let inst : Program_types.instruction = Program_types.{
        inouts =  [sub_exp_temp] @ args @ [result_var];
        operation = Call_method{method_name = method_name};
    } in
    result_var, inst

let build_return_op var builder =
    Program_types.{
        inouts = [var];
        operation = Program_types.Return;
    }

let id_to_func_type id builder = 
    let temp = get_new_intermed_temp builder in
    let type_ext = Typesystem_types.{
        properties = [];
        methods = [];
        group = "";
        signature = None;
    } in
    let _type : Typesystem_types.type_ = Typesystem_types.{
        definite_type = nothing_type_int;
        possible_type = anything_type_int;
        ext = Extension type_ext;
    } in
    add_new_var_identifier id temp builder;
    (temp, _type)

(* TODO: Some of this functionality needs to be moved to translate.ml *)
let build_func_ops func_var arg_names rest_arg_name_opt is_arrow is_async is_generator builder =

    let temp_func x = id_to_func_type x builder in
    let proced_ids = List.map temp_func arg_names in
    let temps, types = List.split proced_ids in

    let rest_temp, rest_type = match rest_arg_name_opt with
        None -> [], []
        | Some rest_arg_name ->
            let rest_var = get_new_intermed_temp builder in
            let type_ext = Typesystem_types.{
                properties = [];
                methods = [];
                group = "";
                signature = None;
            } in
            let type_mess : Typesystem_types.type_ = Typesystem_types.{
                definite_type = nothing_type_int;
                possible_type = anything_type_int;
                ext = Extension type_ext;
            } in
            add_new_var_identifier rest_arg_name rest_var builder;
            [rest_var], [type_mess]
        in

    let all_temps = temps @ rest_temp in
    let all_types = types @ rest_type in
    let type_ext = Typesystem_types.{
        properties = [];
        methods = [];
        group = "";
        signature = None;
    } in

    (* Build start func inst*)
    let output_type : Typesystem_types.type_ = Typesystem_types.{
        definite_type = unknown_type_int;
        possible_type = unknown_type_int;
        ext = Extension type_ext;
    } in

    let func_signature : Typesystem_types.function_signature = Typesystem_types.{
        input_types = all_types;
        output_type = Some output_type;
    } in

    let begin_inst_op, end_inst_op = 
        if is_arrow then
            if is_async then
                let begin_func_op : Operations_types.begin_async_arrow_function_definition
                    = Operations_types.{signature = Some func_signature} in
                let inst_op = Program_types.Begin_async_arrow_function_definition begin_func_op in
                let end_op = Program_types.End_async_arrow_function_definition in
                inst_op, end_op
            else
                (* Norm arrow *)
                let begin_func_op : Operations_types.begin_arrow_function_definition
                    = Operations_types.{signature = Some func_signature} in
                let inst_op = Program_types.Begin_arrow_function_definition begin_func_op in
                let end_op = Program_types.End_arrow_function_definition in
                inst_op, end_op
        else
            if is_async then
                (* Norm Async*)
                let begin_func_op : Operations_types.begin_async_function_definition
                    = Operations_types.{signature = Some func_signature} in
                let inst_op = Program_types.Begin_async_function_definition begin_func_op in
                let end_op = Program_types.End_async_function_definition in
                inst_op, end_op
            else
                if is_generator then
                    (* Generator*)
                    let begin_func_op : Operations_types.begin_generator_function_definition
                        = Operations_types.{signature = Some func_signature} in
                    let inst_op = Program_types.Begin_generator_function_definition begin_func_op in
                    let end_op = Program_types.End_generator_function_definition in
                    inst_op, end_op
                else
                    let begin_func_op : Operations_types.begin_plain_function_definition
                        = Operations_types.{signature = Some func_signature} in
                    let inst_op = Program_types.Begin_plain_function_definition begin_func_op in
                    let end_op = Program_types.End_plain_function_definition in
                    inst_op, end_op
        in
    let begin_func_inst = Program_types.{
        inouts = func_var :: all_temps;
        operation = begin_inst_op;
    } in

    let end_func_inst = Program_types.{
        inouts = [];
        operation = end_inst_op;
    } in

    (func_var, begin_func_inst, end_func_inst)

let inst_to_prog_inst inst =
    inst