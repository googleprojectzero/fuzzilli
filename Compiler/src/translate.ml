open ProgramBuilder

let flow_binaryassign_op_to_progbuilder_binop (op : Flow_ast.Expression.Assignment.operator) =
    let res : binary_op = match op with
        PlusAssign -> Plus
        | MinusAssign -> Minus
        | MultAssign -> Mult
        | DivAssign -> Div
        | ModAssign -> Mod
        | BitXorAssign -> Xor
        | LShiftAssign -> LShift
        | RShiftAssign -> RShift
        | ExpAssign -> Exp
        | RShift3Assign -> RShift3
        | BitAndAssign -> BitAnd
        | BitOrAssign -> BitOr in
    res

let hoist_id var_name builder =
    let result_temp, inst = build_load_undefined builder in
    add_new_var_identifier var_name result_temp builder;
    add_hoisted_var var_name builder;
    inst

let hoist_functions_to_top (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) =
    let partition_func (s:(Loc.t, Loc.t) Flow_ast.Statement.t) = match s with
        (_, Flow_ast.Statement.FunctionDeclaration _) -> true
        | _ -> false in
    let function_list, rest_list = List.partition partition_func statements in
    function_list @ rest_list

(* Designed to be called on the statements of a function *)
let handle_varHoist (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) (builder: builder) =
    let hoisted_functions = hoist_functions_to_top statements in
    let var_useData, func_useData = VariableScope.get_vars_to_hoist hoisted_functions in
    let is_not_builtin s = Util.is_supported_builtin s (include_v8_natives builder) |> not in
    let funcs_to_hoist = List.filter is_not_builtin func_useData in
    let hoist_func var = hoist_id var builder in
    let hoist_vars = List.map hoist_func var_useData in
    let hoist_funcs = List.map hoist_func funcs_to_hoist in
    hoist_vars @ hoist_funcs

(* Handle the various types of literal*)
let proc_exp_literal (lit_val: ('T) Flow_ast.Literal.t) (builder: builder) =
    let (temp_val, inst) = match lit_val.value with 
        (Flow_ast.Literal.String s) ->
            (* TODO: This may be the cause of the issue where some files fail Fuzzilli import due to a UTF-8 error *)
            let newString = Util.encode_newline s in
            build_load_string newString builder
        | (Flow_ast.Literal.Boolean b) ->
            build_load_bool b builder
        | (Flow_ast.Literal.Null) ->
            build_load_null builder
        | (Flow_ast.Literal.Number num) ->
            (* Flow_ast only has one type for a number, while Fuzzilli has several, each with its own protobuf type*)
            if Float.is_integer num && not (String.contains lit_val.raw '.') && Int64.of_float num >= Int64.min_int && Int64.of_float num <= Int64.max_int then
                build_load_integer (Int64.of_float num) builder
            else
                build_load_float num builder
        | (Flow_ast.Literal.BigInt b) ->
            build_load_bigInt b builder
        | (Flow_ast.Literal.RegExp r) ->
            let pattern = r.pattern in
            let flags = r.flags in
            build_load_regex pattern flags builder in
    (temp_val, [inst])

(* Handle the various unary types*)
let rec proc_exp_unary (u_val: ('M, 'T) Flow_ast.Expression.Unary.t) (builder: builder) =
    match u_val.operator with
        Flow_ast.Expression.Unary.Not ->
            let arg_result_var, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_unary_op arg_result_var Not builder in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.BitNot ->
            let arg_result_var, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_unary_op arg_result_var BitNot builder in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Minus ->
            let arg_result_var, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_unary_op arg_result_var Minus builder in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Plus ->
            let arg_result_var, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_unary_op arg_result_var Plus builder in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Typeof ->
            let arg_result_var, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_typeof_op arg_result_var builder in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Await ->
            let arg_result_var, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_await_op arg_result_var builder in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Delete ->
            (* Need to determine between computed delete, and named delete*)
            let _, unwrapped_arg = u_val.argument in
            let del_temp, del_inst = match unwrapped_arg with
                Flow_ast.Expression.Member mem -> 
                    let obj_temp, obj_inst = proc_expression mem._object builder in
                    ( match mem.property with
                        Flow_ast.Expression.Member.PropertyIdentifier (_, id) ->
                            let name = id.name in
                            let obj, del_inst = build_delete_prop obj_temp name builder in
                            obj, obj_inst @ [del_inst]
                        | Flow_ast.Expression.Member.PropertyExpression exp ->
                            let sub_temp, sub_inst = proc_expression exp builder in
                            let (obj, com_del_inst) = build_delete_computed_prop obj_temp sub_temp builder in
                            obj_temp, obj_inst @ sub_inst @ [com_del_inst]
                        | _ -> raise (Invalid_argument "Unhandled delete member property") )
                | Identifier id -> raise (Invalid_argument "Deleting an ID isn't supported in Fuzzilli")
                | _ -> raise (Invalid_argument "Unsupported delete expression ") in
            del_temp, del_inst
        | Flow_ast.Expression.Unary.Void ->
            let _, argument = proc_expression u_val.argument builder in
            let result_var, inst = build_void_op builder in
            result_var, argument @ [inst]


(* First, check against various edge cases. Otherwise, check the context, and handle the result appropriately *)
and proc_exp_id (id_val: ('M, 'T) Flow_ast.Identifier.t) builder = 
    let (_, unwraped_id_val) = id_val in
    let name = unwraped_id_val.name in
    if String.equal name "Infinity" then (* TODO: What other values go here? *)
        let (result_var, inst) = build_load_float Float.infinity builder in
        result_var, [inst]
    else if String.equal name "undefined" then
        let result_var, inst = build_load_undefined builder in
        result_var, [inst]
    else match lookup_var_name builder name with
        InScope x -> (x, [])
        | NotFound ->
            if Util.is_supported_builtin name (include_v8_natives builder) then
                let (result_var, inst) = build_load_builtin name builder in
                if (should_emit_builtins builder) then print_endline ("Builtin: " ^ name) else ();
                (result_var, [inst])
            else if use_placeholder builder then 
                let (result_var, inst) = build_load_builtin "placeholder" builder in
                (result_var, [inst])
            else
                raise (Invalid_argument ("Unhandled builtin " ^ name))

and proc_exp_bin_op (bin_op: ('M, 'T) Flow_ast.Expression.Binary.t) builder =
    let (lvar, linsts) = proc_expression bin_op.left builder in
    let (rvar, rinsts) = proc_expression bin_op.right builder in
    let build_binary_op_func op = build_binary_op lvar rvar op builder in
    let build_compare_op_func op = build_compare_op lvar rvar op builder in
    let (result_var, inst) = match bin_op.operator with 
        Plus -> build_binary_op_func Plus
        | Minus -> build_binary_op_func Minus
        | Mult -> build_binary_op_func Mult 
        | Div -> build_binary_op_func Div 
        | Mod -> build_binary_op_func Mod 
        | Xor -> build_binary_op_func Xor 
        | LShift -> build_binary_op_func LShift 
        | RShift -> build_binary_op_func RShift 
        | Exp -> build_binary_op_func Exp 
        | RShift3 -> build_binary_op_func RShift3 
        | BitAnd -> build_binary_op_func BitAnd 
        | BitOr -> build_binary_op_func BitOr 
        | Equal -> build_compare_op_func Equal
        | NotEqual -> build_compare_op_func NotEqual 
        | StrictEqual -> build_compare_op_func StrictEqual 
        | StrictNotEqual -> build_compare_op_func StrictNotEqual 
        | LessThan -> build_compare_op_func LessThan 
        | LessThanEqual -> build_compare_op_func LessThanEqual
        | GreaterThan -> build_compare_op_func GreaterThan
        | GreaterThanEqual -> build_compare_op_func GreaterThanEqual
        | Instanceof -> build_instanceof_op lvar rvar builder
        | In -> build_in_op lvar rvar builder in
    (result_var, linsts @ rinsts @ [inst])

and proc_exp_logical (log_op: ('M, 'T) Flow_ast.Expression.Logical.t) builder =
    let (lvar, linsts) = proc_expression log_op.left builder in
    let (rvar, rinsts) = proc_expression log_op.right builder in
    let op = match log_op.operator with
        Flow_ast.Expression.Logical.And -> LogicalAnd
        | Flow_ast.Expression.Logical.Or -> LogicalOr
        | x -> raise (Invalid_argument ("Unhandled logical expression type" ^ (Util.trim_flow_ast_string (Util.print_logical_operator x)))) in
    let (result_var, inst) = build_binary_op lvar rvar op builder in
    (result_var, linsts @ rinsts @ [inst])

(* There are various different expression types, so pattern match on each time, and ccall the appropriate, more specific, function*)
and proc_exp_assignment (assign_exp: ('M, 'T) Flow_ast.Expression.Assignment.t) (builder: builder) = 
     match assign_exp.left with
        (_, (Flow_ast.Pattern.Identifier id)) -> proc_exp_assignment_norm_id assign_exp id.name builder 
        | (_, (Flow_ast.Pattern.Expression (_, exp))) -> 
            (match exp with
                Flow_ast.Expression.Member mem -> 
                    let obj = mem._object in
                    (match mem.property with
                        Flow_ast.Expression.Member.PropertyExpression pex -> proc_exp_assignment_prod_exp pex obj assign_exp.right assign_exp.operator builder
                        |  Flow_ast.Expression.Member.PropertyIdentifier pid -> proc_exp_assignment_prod_id pid obj assign_exp.right assign_exp.operator builder
                        | _ -> raise (Invalid_argument "Unhandled member property in exp assignment"))
                | _ -> raise (Invalid_argument "Unhandled assignment expression left member"))
        | _ -> raise (Invalid_argument "Unhandled assignment expressesion left ")

and proc_exp_assignment_prod_id
    (prop_id: (Loc.t, Loc.t) Flow_ast.Identifier.t)
    (obj: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (right_exp: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (op: Flow_ast.Expression.Assignment.operator option)
    (builder: builder) =
    let obj_temp, obj_inst = proc_expression obj builder in
    let (_, unwapped_id) = prop_id in
    let name = unwapped_id.name in
    let right_exp_temp, right_exp_inst = proc_expression right_exp builder in
    let (sugared_assignment_temp, assigment_insts) = match op with
        None -> (right_exp_temp, [])
        | Some op -> 
            let (initial_prop_var, load_inst) = build_load_prop obj_temp name builder in
            let bin_op = flow_binaryassign_op_to_progbuilder_binop op in
            let result_var, assignment_inst = build_binary_op initial_prop_var right_exp_temp bin_op builder in
            (result_var, [load_inst; assignment_inst]) in
    let store_inst = build_store_prop obj_temp sugared_assignment_temp name builder in
    (sugared_assignment_temp, obj_inst @ right_exp_inst @ assigment_insts @ [store_inst])

(* Handle assignments to property expressions *)
and proc_exp_assignment_prod_exp
    (prop_exp: (Loc.t, Loc.t) Flow_ast.Expression.t) 
    (obj: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (right_exp: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (op: Flow_ast.Expression.Assignment.operator option)
    (builder: builder) = 

    let obj_temp, obj_inst = proc_expression obj builder in
    let index_exp_temp, index_exp_inst = proc_expression prop_exp builder in
    let right_exp_temp, right_exp_inst = proc_expression right_exp builder in

    let (lval_var, assigment_insts) = match op with
        None -> (right_exp_temp, [])
        | Some op -> 
            let load_temp_var, load_inst = build_load_computed_prop obj_temp index_exp_temp builder in
            let bin_op = flow_binaryassign_op_to_progbuilder_binop op in
            let result_var, assignment_inst = build_binary_op load_temp_var right_exp_temp bin_op builder in
            (result_var, [load_inst; assignment_inst]) in
    let store_inst = build_store_computed_prop obj_temp index_exp_temp lval_var builder in
    (lval_var, obj_inst @ index_exp_inst @ right_exp_inst @ assigment_insts @ [store_inst])

(* Handle assignments to normal identifiers*)
and proc_exp_assignment_norm_id (assign_exp: ('M, 'T) Flow_ast.Expression.Assignment.t) (id: (Loc.t, Loc.t) Flow_ast.Identifier.t) builder = 
    let (_, act_name)  = id in
    let (exp_output_loc, exp_insts) = proc_expression assign_exp.right builder in

    let (sugared_assignment_temp, sugared_assigment_exp) = match assign_exp.operator with
        None -> (exp_output_loc, [])
        | Some op -> 
            let source, source_inst = match lookup_var_name builder act_name.name with
                InScope x -> (x, [])
                | NotFound -> 
                    raise (Invalid_argument "Variable not found") in
            let bin_op = flow_binaryassign_op_to_progbuilder_binop op in
            let result_var, assignment_inst = build_binary_op source exp_output_loc bin_op builder in

            (result_var, source_inst @ [assignment_inst])
            in
    let var_temp, add_inst = match lookup_var_name builder act_name.name with
        (* This case is where a variable is being declared, without a let/const/var.*)
        NotFound ->
            let result_var, inst = build_dup_op sugared_assignment_temp builder in
            add_new_var_identifier act_name.name result_var builder;
            (result_var, [inst])
        | InScope existing_temp -> 
            let inst = build_reassign_op existing_temp sugared_assignment_temp builder in
            (existing_temp, [inst])
        in
    (var_temp, exp_insts @ sugared_assigment_exp @ add_inst)
            
(* Handle a list of arguments to a function call*)
and proc_arg_list (arg_list: ('M, 'T) Flow_ast.Expression.ArgList.t) builder =
    let _, unwrapped = arg_list in
    let arguments = unwrapped.arguments in
    let proc_exp_or_spread (exp_or_spread: ('M, 'T) Flow_ast.Expression.expression_or_spread) = 
        match exp_or_spread with
            Expression exp -> 
                proc_expression exp builder
            | Spread spread -> 
                let (_, unwrapped) = spread in
                proc_expression unwrapped.argument builder in
    let reg_list, unflattened_inst_list = List.split (List.map proc_exp_or_spread arguments) in
    reg_list, List.flatten unflattened_inst_list

and arg_list_get_spread_list (arg_list: ('M, 'T) Flow_ast.Expression.ArgList.t) =
    let _, unwrapped = arg_list in
    let arguments = unwrapped.arguments in
    let proc_exp_or_spread (exp_or_spread: ('M, 'T) Flow_ast.Expression.expression_or_spread) = 
        match exp_or_spread with
            Expression exp -> false
            | Spread spread -> true in
    List.map proc_exp_or_spread arguments

and proc_exp_call (call_exp: ('M, 'T) Flow_ast.Expression.Call.t) builder =
    let _ : unit = match call_exp.targs with
        None -> ()
        | Some a -> raise (Invalid_argument "Unhandled targs in call") in
    let is_spread_list = arg_list_get_spread_list call_exp.arguments in
    let is_spread = List.fold_left (||) false is_spread_list in
    let (_, callee) = call_exp.callee in
    match callee with
        (* Handle the method call case explicity*)
        Flow_ast.Expression.Member member -> 
            (match member.property with
                (* Handle method calls seperately for all other cases *)
                Flow_ast.Expression.Member.PropertyIdentifier (_, id) -> 
                    let sub_exp_temp, sub_exp_inst = proc_expression member._object builder in
                    if is_spread then raise (Invalid_argument "Unhandled spread in member call") else ();
                    let arg_regs, arg_inst = proc_arg_list call_exp.arguments builder in
                    let result_var, inst = build_call_method sub_exp_temp arg_regs id.name builder in
                    (result_var, sub_exp_inst @ arg_inst @ [inst])
                | _ ->
                    let callee_reg, callee_inst = proc_expression call_exp.callee builder in
                    let arg_regs, arg_inst = proc_arg_list call_exp.arguments builder in
                    let result_reg, inst = if is_spread
                        then
                            build_call_with_spread callee_reg arg_regs is_spread_list builder 
                        else
                            build_call callee_reg arg_regs builder in
                    (result_reg, callee_inst @ arg_inst @ [inst]))
        (* Otherwise, run the callee sub expression as normal*)
        | _ ->  let callee_reg, callee_inst = proc_expression call_exp.callee builder in
                let arg_regs, arg_inst = proc_arg_list call_exp.arguments builder in
                let result_reg, inst = if is_spread
                    then
                        build_call_with_spread callee_reg arg_regs is_spread_list builder 
                    else
                        build_call callee_reg arg_regs builder in
                (result_reg, callee_inst @ arg_inst @ [inst])

and proc_array_elem (elem: ('M, 'T) Flow_ast.Expression.Array.element) (builder: builder) =
    match elem with
        Expression e -> 
            let temp, inst = proc_expression e builder in
            false, (temp, inst)
        | Spread spread -> 
            let _, unwrapped = spread in
            let temp, inst = proc_expression unwrapped.argument builder in
            true, (temp, inst)
        | Hole h ->
            (* Fuzzilli doesn't support array holes, so load undefined instead *)
            let result_var, inst = build_load_undefined builder in
            false, (result_var, [inst])

and proc_create_array (exp: ('M, 'T) Flow_ast.Expression.Array.t) (builder: builder) =
    let temp_func a = proc_array_elem a builder in
    let is_spread_list, temp_list = List.split (List.map temp_func exp.elements) in
    let arg_regs, arg_inst = List.split temp_list in
    let flat_inst = List.flatten arg_inst in
    let is_spread = List.fold_left (||) false is_spread_list in
    let result_var, create_array_inst = if is_spread
        then
            build_create_array_with_spread arg_regs is_spread_list builder
        else
            build_create_array arg_regs builder 
        in
    (result_var, flat_inst @ [create_array_inst])

and proc_create_object_property (prop_val: ('M, 'T) Flow_ast.Expression.Object.property) builder =
    match prop_val with
        Property (_, prop) ->
            let temp_reg, prop_name_key, inst = match prop with
                Init init_val ->
                    let temp, exp_inst = proc_expression init_val.value builder in
                    temp, init_val.key, exp_inst
                | Set func -> 
                    let _, act_func = func.value in
                    let temp, inst = proc_func act_func builder false in
                    temp, func.key, inst
                | Get func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func builder false in
                    temp, func.key, inst
                | Method func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func builder false in
                    temp, func.key, inst in
            let prop_name : string = match prop_name_key with
                Literal (_, l) -> l.raw
                | Identifier (_, i) -> i.name
                | PrivateName (_, p) -> let (_, i) = p.id in
                    i.name
                | Computed _ -> raise (Invalid_argument "Unhandled Object key type Computed Key in object creation") in
            (temp_reg, [prop_name]), inst
        | SpreadProperty (_, spreadProp) -> 
            let temp_reg, exp_inst = proc_expression spreadProp.argument builder in
            (temp_reg, []), exp_inst

and proc_create_object (exp : ('M, 'T) Flow_ast.Expression.Object.t) (builder: builder) =
    let props = exp.properties in
    let temp_func a = proc_create_object_property a builder in
    let obj_temp_tuple, create_obj_inst = List.split (List.map temp_func props) in
    let obj_temp_list, obj_key_list_unflattened = List.split obj_temp_tuple in
    let obj_key_list_flat = List.flatten obj_key_list_unflattened in
    let flat_inst = List.flatten create_obj_inst in
    let result_var, create_obj_inst = if List.length obj_key_list_flat == List.length obj_temp_list then
            build_create_object obj_key_list_flat obj_temp_list builder
        else
            build_create_object_with_spread obj_key_list_flat obj_temp_list builder
        in
    (result_var, flat_inst @ [create_obj_inst])

and proc_exp_member (memb_exp: ('M, 'T) Flow_ast.Expression.Member.t) (builder: builder) =
    let (sub_exp_temp, sub_exp_inst) = proc_expression memb_exp._object builder in
    let return_temp, insts = match memb_exp.property with
        PropertyIdentifier (_, i) ->
            let result_var, load_prop_inst = build_load_prop sub_exp_temp i.name builder in
            (result_var, [load_prop_inst])
        | PropertyPrivateName (_, p) -> 
            let (_, i) = p.id in
            let result_var, load_prop_inst = build_load_prop sub_exp_temp i.name builder in
            (result_var, [load_prop_inst])
        | PropertyExpression pe ->
            let (_, unwrapped) = pe in
            let opt_index = match unwrapped with
                Flow_ast.Expression.Literal l -> 
                    (match l.value with
                        Number n -> 
                            if Float.is_integer n then Some (Float.to_int n) else None
                        | _ -> None)
                | _ -> None in
            match opt_index with
                Some n -> (* Do a load element with the number*)
                    let result_var, load_element_inst = build_load_element sub_exp_temp n builder in
                    result_var, [load_element_inst]
                | _ -> 
                    (* Do a loadComputed with the expression*)
                    (* TODO: Is this the right operation here? *)
                    let member_exp_temp, member_exp_inst = proc_expression pe builder in
                    let result_var, load_computed_prop_inst = build_load_computed_prop sub_exp_temp member_exp_temp builder in
                    (result_var, member_exp_inst @ [load_computed_prop_inst]) in
    (return_temp, sub_exp_inst @ insts)

and proc_exp_new (new_exp: ('M, 'T) Flow_ast.Expression.New.t) (builder: builder) = 
    let callee = new_exp.callee in
    let (callee_reg, callee_inst) = proc_expression callee builder in
    let _ : unit = match new_exp.targs with
        None -> ()
        | Some a -> raise (Invalid_argument "Unhandled targs in call") in
    let arguments = new_exp.arguments in  
    let (arg_regs, arg_inst) = match arguments with
        None -> ([], [])
        | Some act_args -> 
            (let is_spread = List.fold_left (||) false ( arg_list_get_spread_list act_args ) in
            let temp, insts = proc_arg_list act_args builder in
            if is_spread then raise (Invalid_argument "Unhandled spread in new") 
            else temp, insts)
        in
    let result_var, create_obj_inst = build_new_object callee_reg arg_regs builder in
    (result_var, callee_inst @ arg_inst @ [create_obj_inst])

and proc_exp_this this_exp builder = 
    let (result_var, inst) = build_load_builtin "this" builder in
    result_var, [inst]

and proc_exp_update (update_exp: (Loc.t, Loc.t) Flow_ast.Expression.Update.t) (builder: builder) = 
    let (sub_exp_temp, sub_exp_inst) = proc_expression update_exp.argument builder in
    let update_op : unary_op = match update_exp.operator with
        Increment -> if update_exp.prefix then PreInc else PostInc
        | Decrement -> if update_exp.prefix then PreDec else PostDec in
    let result_var, update_inst = build_unary_op sub_exp_temp update_op builder in
    result_var, sub_exp_inst @ [update_inst]

and proc_exp_yield (yield_exp: (Loc.t, Loc.t) Flow_ast.Expression.Yield.t) (builder: builder) =
    let sub_exp_temp, sub_exp_insts = match yield_exp.argument with
        | Some exp -> proc_expression exp builder
        | _ -> raise (Invalid_argument "Unhandled yield without argument") in
    let yield_inst = if yield_exp.delegate
        then
            build_yield_each_op sub_exp_temp builder
        else
            build_yield_op sub_exp_temp builder
        in
    sub_exp_temp, sub_exp_insts @ [yield_inst]

(* Ternary expressions are not handled by Fuzzilli, so convert them to an if-else *)
and proc_exp_conditional (cond_exp: (Loc.t, Loc.t) Flow_ast.Expression.Conditional.t) (builder: builder) = 
    let result_temp, zero_temp_inst = build_load_integer 0L builder in
    let (test_temp, test_inst) = proc_expression cond_exp.test builder in
    let begin_if_inst = build_begin_if test_temp builder in
    let consequent_temp, consequest_inst = proc_expression cond_exp.consequent builder in
    let consequent_reassign_inst = build_reassign_op result_temp consequent_temp builder in
    let begin_else_inst = build_begin_else builder in
    let alternative_temp, alternative_inst = proc_expression cond_exp.alternate builder in
    let alternative_reassign_inst = build_reassign_op result_temp alternative_temp builder in
    let end_if_inst = build_end_if builder in
    (result_temp, [zero_temp_inst] @ test_inst @ [begin_if_inst] @ consequest_inst @ [consequent_reassign_inst] @ [begin_else_inst] @
        alternative_inst @ [alternative_reassign_inst; end_if_inst])

and proc_class_method class_proto_temp builder (m: (Loc.t, Loc.t) Flow_ast.Class.Method.t) =
    let _, unwrapped_method = m in
    let key = unwrapped_method.key in
    let method_name = match key with
        Literal (_, l) -> l.raw
        | Identifier (_, i) -> i.name
        | PrivateName (_, p) -> let (_, i) = p.id in
            i.name
        | Computed _ -> raise (Invalid_argument "Unhandled method name in class creation") in
    let _, func = unwrapped_method.value in
    let method_temp, method_inst = proc_func func builder false in
    (* TODO: Double check if this is the right operation *)
    let load_propotype_inst = build_store_prop class_proto_temp method_temp method_name builder in
    method_inst @ [load_propotype_inst]

and proc_expression (exp: ('M, 'T) Flow_ast.Expression.t) (builder: builder) = 
    let (_, unwrapped_exp) = exp in
    match unwrapped_exp with
        | (Flow_ast.Expression.Array array_op) ->
            proc_create_array array_op builder
        | (Flow_ast.Expression.ArrowFunction arrow_func) ->
            proc_func arrow_func builder true
        | (Flow_ast.Expression.Assignment assign_op) ->
            proc_exp_assignment assign_op builder
        | (Flow_ast.Expression.Binary bin_op) ->
            proc_exp_bin_op bin_op builder
        | (Flow_ast.Expression.Call call_op) ->
            proc_exp_call call_op builder
        | (Flow_ast.Expression.Conditional cond_exp) ->
            proc_exp_conditional cond_exp builder
        | (Flow_ast.Expression.Function func_exp) ->
            proc_func func_exp builder false
        | (Flow_ast.Expression.Identifier id_val) ->
            proc_exp_id id_val builder
        | (Flow_ast.Expression.Import _) -> 
            (* Fuzzilli doesn't support imports, so effectively nop this out *)
            let var, inst = build_load_undefined builder in
            var, [inst]
        | (Flow_ast.Expression.Literal lit_val) -> 
            proc_exp_literal lit_val builder
        | (Flow_ast.Expression.Logical log_op) ->
            proc_exp_logical log_op builder
        | (Flow_ast.Expression.Member memb_exp) ->
            proc_exp_member memb_exp builder
        | (Flow_ast.Expression.New new_exp) ->
            proc_exp_new new_exp builder
        | (Flow_ast.Expression.Object create_obj_op) ->
            proc_create_object create_obj_op builder
        | (Flow_ast.Expression.This this_exp) ->
            proc_exp_this this_exp builder
        | (Flow_ast.Expression.Unary u_val) ->
            proc_exp_unary u_val builder
        | (Flow_ast.Expression.Update update_exp) ->
            proc_exp_update update_exp builder
        | (Flow_ast.Expression.Yield yield_exp) ->
            proc_exp_yield yield_exp builder
        | x -> raise (Invalid_argument ("Unhandled expression type " ^ (Util.trim_flow_ast_string (Util.print_expression exp))))       

(* Process a single actual declaration *)
and proc_var_declaration_actual (var_name: string) (init: (Loc.t, Loc.t) Flow_ast.Expression.t option) (kind: Flow_ast.Statement.VariableDeclaration.kind) (builder : builder) =
    let temp_var_num, new_insts = match init with
        None -> 
            (* Handle a declaration without a definition *)
            (match kind with
                Flow_ast.Statement.VariableDeclaration.Var ->
                    let undef_temp, undef_inst = build_load_undefined builder in
                    let result_var, dup_inst = build_dup_op undef_temp builder in
                    add_new_var_identifier var_name result_var builder;
                    result_var, [undef_inst; dup_inst]
                | Flow_ast.Statement.VariableDeclaration.Let ->
                    let undef_temp, undef_inst = build_load_undefined builder in
                    add_new_var_identifier var_name undef_temp builder;
                    undef_temp, [undef_inst]
                | _ -> raise (Invalid_argument "Empty const declaration"))
        | Some exp -> proc_expression exp builder in
    let reassign_inst = (match kind with 
        Flow_ast.Statement.VariableDeclaration.Var ->
            let is_hoisted = is_hoisted_var var_name builder in
            if is_hoisted then
                    let hoisted_temp = lookup_var_name builder var_name in
                    match hoisted_temp with
                        NotFound -> raise (Invalid_argument "Unfound hoisted temp")
                        | InScope temp ->
                            let inst = build_reassign_op temp temp_var_num builder in
                            [inst]
                else
                    (add_new_var_identifier var_name temp_var_num builder;
                    [])
        | _ -> 
            add_new_var_identifier var_name temp_var_num builder;
            [])
        in
    new_insts @ reassign_inst

and proc_handle_single_var_declaration (dec : (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.Declarator.t') (kind: Flow_ast.Statement.VariableDeclaration.kind) (builder : builder) =
    let foo = match dec.id, dec.init with
        (_, (Flow_ast.Pattern.Identifier id)), exp ->
            let (_, act_name) = id.name in
            proc_var_declaration_actual act_name.name exp kind builder  
        | (_, (Flow_ast.Pattern.Array arr)), (Some (_, Flow_ast.Expression.Array exp)) -> 
            let get_name (a: ('M, 'T) Flow_ast.Pattern.Array.element) = 
                match a with 
                    Element (_, e) -> 
                        (match e.argument with
                         (_, (Flow_ast.Pattern.Identifier x)) -> 
                            let var_id = x.name in
                            let (_, act_name) = var_id in
                            act_name.name
                        | _ -> raise (Invalid_argument "Improper args in variable declaration"))
                    | _ -> raise (Invalid_argument "Improper args in variable declaration") in
            let id_elems = List.map get_name arr.elements in
            let get_elem (e: (Loc.t, Loc.t) Flow_ast.Expression.Array.element) = 
                match e with
                    Expression exp -> exp
                    | _ -> raise (Invalid_argument "Improper args in variable declaration") in
            let elems = List.map get_elem exp.elements in
            let process id elem = proc_var_declaration_actual id (Some elem) kind builder in
            List.map2 process id_elems elems |> List.flatten
        | _, _ -> raise (Invalid_argument "Improper args in variable declaration") in

    foo

(* Process a single variable declaration *)
and proc_var_dec_declarators (decs : (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.Declarator.t list) (kind: Flow_ast.Statement.VariableDeclaration.kind) (builder : builder) =
    match decs with
        [] -> []
        | (_, declarator) :: tl -> 
            proc_handle_single_var_declaration declarator kind builder @ (proc_var_dec_declarators tl kind builder)

(* Processes a variable declaration statement, which can be made up of multiple vars  *)
and proc_var_decl_statement (var_decl: (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.t) (builder: builder) =
    let decs = var_decl.declarations in
    let kind = var_decl.kind in
    proc_var_dec_declarators decs kind builder

and proc_if_statement (if_statement: (Loc.t, Loc.t) Flow_ast.Statement.If.t) (builder: builder) =
    let test = if_statement.test in 
    let (test_temp_val, test_inst) = proc_expression test builder in

    let begin_if_inst = build_begin_if test_temp_val builder in
    
    push_local_scope builder;
    let consequent_statements = proc_single_statement if_statement.consequent builder in
    pop_local_scope builder;

    (* Fuzzilli requires an else for each if, due to how AbstractInterpreter works *)
    let begin_else_inst = build_begin_else builder in 

    push_local_scope builder;
    let fin_statement = match if_statement.alternate with
        None -> []
        | Some (_, alt) ->
            let alt_inst = proc_single_statement alt.body builder in
            alt_inst in
    pop_local_scope builder;

    let end_if_inst = build_end_if builder in
    test_inst @ begin_if_inst :: consequent_statements @ [begin_else_inst] @ fin_statement @ [end_if_inst]    


(* TODO: Improve this. Puts all expressions into a temp, and compares with 0. Could be better*)
and proc_while (while_statement: (Loc.t, Loc.t) Flow_ast.Statement.While.t) (builder: builder) = 
    (* Build initial check, put into temp*)
    let test_exp_reg, test_exp_inst = proc_expression while_statement.test builder in
    let pre_loop_inst = test_exp_inst in

    (* Build begin while *)
    let zero_temp, zero_temp_inst = build_load_integer 0L builder in
    let begin_while_inst = build_begin_while test_exp_reg zero_temp NotEqual builder in
    let begin_loop_inst = zero_temp_inst :: [begin_while_inst] in

    push_local_scope builder;
    (* Build body *)
    let body_statement = proc_single_statement while_statement.body builder in
    pop_local_scope builder;
    
    (* Reexecute comparison, and load into temp*)
    let test_exp_reg_internal, test_exp_inst_internal = proc_expression while_statement.test builder in
    let reassign_inst = build_reassign_op test_exp_reg test_exp_reg_internal builder in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    let end_while_inst = build_end_while builder in
    pre_loop_inst @ begin_loop_inst @ body_statement @ re_exec_test_exp @ [end_while_inst]

and proc_do_while (do_while_statement: (Loc.t, Loc.t) Flow_ast.Statement.DoWhile.t) (builder: builder) =
    (* Build initial check, put into temp*)
    (* let test_exp_reg, test_exp_inst = proc_expression do_while_statement.test builder in *)
    let zero_temp, zero_temp_inst = build_load_integer 0L builder in
    let intermed, dup_inst = build_dup_op zero_temp builder in

    (* Build begin while *)
    let begin_while_inst = build_begin_do_while intermed zero_temp NotEqual builder in
    push_local_scope builder;
    (* Build body *)
    let body_statement = proc_single_statement do_while_statement.body builder in
    pop_local_scope builder;
    (* Execute comparison, and load into temp*)
    let test_exp_reg_internal, test_exp_inst_internal = proc_expression do_while_statement.test builder in
    let reassign_inst = build_reassign_op intermed test_exp_reg_internal builder in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    let end_while_inst = build_end_do_while builder in
    [zero_temp_inst; dup_inst; begin_while_inst] @ body_statement @ re_exec_test_exp @ [end_while_inst]
    
and proc_try (try_statement: (Loc.t, Loc.t) Flow_ast.Statement.Try.t) (builder: builder) = 
    let try_inst = build_begin_try_op builder in
    push_local_scope builder;
    let (_, try_block) = try_statement.block in
    let block_inst = proc_statements try_block.body builder in
    let catch_inst, catch_body_inst = match try_statement.handler with
        None -> raise (Invalid_argument "Empty catch")
        | Some (_, catch_clause) -> 
            let temp_name = match catch_clause.param with 
                | Some (_, (Flow_ast.Pattern.Identifier var_identifier)) ->
                    let (_, act_name) = var_identifier.name in
                    act_name.name
                | _ -> raise (Invalid_argument "Unsupported catch type")
                in
            let (_, catch_cause_block) = catch_clause.body in
            let catch_body_inst = proc_statements catch_cause_block.body builder in
            let catch_inst = build_begin_catch_op temp_name builder in
            (catch_inst, catch_body_inst)
        in
    let finalizer_inst = match try_statement.finalizer with
        None -> []
        | Some (_, fin_block) -> proc_statements fin_block.body builder in
    pop_local_scope builder;
    let end_try_catch_inst = build_end_try_catch_op builder in
    [try_inst] @ block_inst @ [catch_inst] @ catch_body_inst @  [end_try_catch_inst] @ finalizer_inst

and proc_func (func: (Loc.t, Loc.t) Flow_ast.Function.t) (builder : builder) (is_arrow: bool) =
    (* Get func name*)
    let func_name_opt = match func.id with 
        None -> None
        | Some (_, id) ->
            Some id.name
    in

    (* Unwraps a flow_ast paramter to a string identifier *)
    let param_to_id (input: ('M, 'T) Flow_ast.Function.Param.t) = 
        let (_, unwrapped_input) = input in
        let pattern = unwrapped_input.argument in
        let (_, act_name) = match pattern with
            (_, (Flow_ast.Pattern.Identifier x)) -> x.name
            | _ -> raise (Invalid_argument "Didn't get an Identifier when expected in function declaration") in
        act_name.name in

    (* Process function parameters*)
    let (_, unwrapped_param) = func.params in
    let param_ids = List.map param_to_id unwrapped_param.params in

    let rest_arg_name_opt = match unwrapped_param.rest with
        None -> None
        | Some (_, rest_id) -> 
            let act_id = rest_id.argument in
            let (_, id_string) = match act_id with
                (_, (Flow_ast.Pattern.Identifier x)) -> x.name
                | _ -> raise (Invalid_argument "Unhandled rest temp") in
            Some id_string.name
        in
    let func_temp = get_new_intermed_temp builder in
    (match func_name_opt with
        Some name -> 
            if is_hoisted_var name builder then
                ()
            else
                add_new_var_identifier name func_temp builder;
        | _ -> ());
    push_local_scope builder;
    let func_temp, begin_func_inst, end_func_inst = build_func_ops func_temp param_ids rest_arg_name_opt is_arrow func.async func.generator builder in
    (* Process func body*)
    let func_inst = match func.body with 
        BodyBlock body_block -> 
            let _, state_block = body_block in
            let hoisted_statements = handle_varHoist state_block.body builder in
            hoisted_statements @ proc_statements state_block.body builder
        | BodyExpression body_exp -> 
            let _, inst = proc_expression body_exp builder in
            inst
    in
    pop_local_scope builder;

    let reassign_inst = (match func_name_opt with
        Some name -> 
            if is_hoisted_var name builder then
                match (lookup_var_name builder name) with
                    NotFound -> raise (Invalid_argument "Hoisted func not found")
                    | InScope x -> [build_reassign_op x func_temp builder]
            else
                []
        | _ -> []) in
    func_temp, [begin_func_inst] @ func_inst @ [end_func_inst] @ reassign_inst

(* TODO: Fuzzilli return statements currently only allow variables. Add the ability to return without a value *)
and proc_return (ret_state: (Loc.t, Loc.t) Flow_ast.Statement.Return.t) (builder: builder) =
    let return_var, return_insts = match ret_state.argument with
        None -> 
            let temp, inst = build_load_undefined builder in
            temp, [inst]
        | Some exp -> 
            let temp_num, insts = proc_expression exp builder in
            temp_num, insts
        in
    let return_inst = build_return_op return_var builder in
    return_insts @ [return_inst]

and proc_with (with_state: (Loc.t, Loc.t) Flow_ast.Statement.With.t) (builder: builder) =
    let result_var, with_insts = proc_expression with_state._object builder in
    let begin_with_inst = build_begin_with_op result_var builder in
    let body_insts = proc_single_statement with_state.body builder in
    let end_with_inst = build_end_with_op builder in 
    with_insts @ [begin_with_inst] @ body_insts @ [end_with_inst]
 
and proc_throw (throw_state: (Loc.t, Loc.t) Flow_ast.Statement.Throw.t) (builder: builder) =
    let temp, inst = proc_expression throw_state.argument builder in
    let throw_inst = build_throw_op temp builder in
    inst @ [throw_inst]
 
and proc_break builder = 
    [build_break_op builder]

(* Both for-in and for-of only allow creation of a new variable on the left side *)
and proc_for_in (for_in_state: (Loc.t, Loc.t) Flow_ast.Statement.ForIn.t) (builder: builder) =
    let right_temp, right_inst = proc_expression for_in_state.right builder in
    push_local_scope builder;

    let var_temp, end_of_loop_cleanup_inst = match for_in_state.left with
        LeftDeclaration (_, d) -> 
            let decs = d.declarations in 
            (match decs with
                [(_, declarator)] -> ( match declarator.id with
                    (_, (Flow_ast.Pattern.Identifier id)) -> 
                        let (_, id_type) = id.name in
                        let left_temp = get_new_intermed_temp builder in
                        add_new_var_identifier id_type.name left_temp builder;
                        left_temp, []

                    | _ -> raise (Invalid_argument ("Improper declaration in for-in loop")))
                | _ -> raise (Invalid_argument "Improper declaration in for-in loop"))
        | LeftPattern p -> (match p with
            (_, (Flow_ast.Pattern.Identifier id)) -> 
                let (_, id_type) = id.name in
                let lookup = lookup_var_name builder id_type.name in
                (match lookup with
                    InScope x -> 
                        (* Fuzzilli does not support reusing a variable in a for-in loop, so we have to make a new one and reassign it*)
                        let left_temp = get_new_intermed_temp builder in
                        add_new_var_identifier id_type.name left_temp builder;
                        let reassign_inst = build_reassign_op x left_temp builder in
                        left_temp, [reassign_inst]
                    | NotFound ->
                        let left_temp = get_new_intermed_temp builder in
                        add_new_var_identifier id_type.name left_temp builder;
                        left_temp, [] )
            | _ -> raise (Invalid_argument ("Inproper left pattern in for-in loop"))) in

    let _, start_for_in_inst = build_begin_for_in_op var_temp right_temp builder in
    let body_inst = proc_single_statement for_in_state.body builder in
    let end_for_in = build_end_for_in_op builder in
    pop_local_scope builder;
    right_inst  @ [start_for_in_inst] @ body_inst @ end_of_loop_cleanup_inst @ [end_for_in];

and proc_for_of (for_of_state: (Loc.t, Loc.t) Flow_ast.Statement.ForOf.t) (builder: builder) = 
    let right_temp, right_inst = proc_expression for_of_state.right builder in
    push_local_scope builder;
    let var_id = match for_of_state.left with
        LeftDeclaration (_, d) -> 
            let decs = d.declarations in 
            (match decs with
                [(_, declarator)] -> ( match declarator.id with
                    (_, (Flow_ast.Pattern.Identifier x)) -> x
                    | _ -> raise (Invalid_argument ("Improper declaration in for-of loop")))
                | _ -> raise (Invalid_argument "Improper declaration in for-of loop"))
        | LeftPattern p -> (match p with
            (* TODO: Fuzzilli does not support reusing a variable in a for-of loop *)
            (_, (Flow_ast.Pattern.Identifier id)) -> id
            | _ -> raise (Invalid_argument ("Inproper left pattern in for-of loop"))) in
    let (_, act_name) = var_id.name in
    let left_temp, start_for_of_inst = build_begin_for_of_op right_temp builder in
    add_new_var_identifier act_name.name left_temp builder;

    let body_inst = proc_single_statement for_of_state.body builder in
    let end_for_of_inst = build_end_for_of_op builder in
    right_inst @ [start_for_of_inst] @ body_inst @ [end_for_of_inst];

(* Fuzzilli For loops in Fuzzilli only *)
and proc_for (for_state: (Loc.t, Loc.t) Flow_ast.Statement.For.t) (builder: builder) =
    let init_inst = match for_state.init with
        None -> []
        | Some (InitDeclaration (_, decl)) -> proc_var_decl_statement decl builder
        | Some (InitExpression exp) ->
            let (_, exp_insts) = proc_expression exp builder in
            exp_insts
        in
    (* Variables used in the condition need to be declared outside the while loop*)
    let test_exp_reg, test_exp_inst = match for_state.test with
        Some exp -> proc_expression exp builder
        | None -> raise (Invalid_argument "Unhandled empty for-loop test") in
    let pre_loop_inst = test_exp_inst in
    push_local_scope builder;

    (*start while loop*)
    let zero_temp, zero_temp_inst = build_load_integer 0L builder in
    let begin_while_inst  = build_begin_while test_exp_reg zero_temp NotEqual builder in
    let begin_loop_inst = zero_temp_inst :: [begin_while_inst] in

    (*Body instructions*)
    let body_insts = proc_single_statement for_state.body builder in

    (* Update*)
    let update_insts = match for_state.update with
        None -> []
        | Some exp ->
            let (_, exp_insts) = proc_expression exp builder
            in exp_insts in

    (* Redo the check*)
    let test_exp_reg_internal, test_exp_inst_internal = match for_state.test with
        Some exp -> proc_expression exp builder
        | None -> raise (Invalid_argument "Unhandled empty for-loop test") in
    let reassign_inst = build_reassign_op test_exp_reg test_exp_reg_internal builder in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    (* End while*)
    let end_while_inst = build_end_while builder in
    pop_local_scope builder;
    init_inst @ pre_loop_inst @ begin_loop_inst @ body_insts @ update_insts @ re_exec_test_exp @ [end_while_inst]

and proc_continue builder = 
    [build_continue builder]

and proc_single_statement (statement: (Loc.t, Loc.t) Flow_ast.Statement.t) builder = 
    match statement with 
        (_, Flow_ast.Statement.Block state_block) -> proc_statements state_block.body builder
        | (_, Flow_ast.Statement.Break _) -> proc_break builder
        | (_, Flow_ast.Statement.Continue state_continue) -> proc_continue builder
        | (_, Flow_ast.Statement.DoWhile state_do_while) -> proc_do_while state_do_while builder
        | (_, Flow_ast.Statement.Empty _) -> []
        | (_, Flow_ast.Statement.Expression state_exp) -> 
            let (_, inst) = proc_expression state_exp.expression builder in
            inst
        | (_, Flow_ast.Statement.For state_for) -> proc_for state_for builder
        | (_, Flow_ast.Statement.ForIn state_foin) -> proc_for_in state_foin builder
        | (_, Flow_ast.Statement.ForOf state_forof) -> proc_for_of state_forof builder
        | (_, Flow_ast.Statement.FunctionDeclaration func_def) -> 
            let (_, res) = proc_func func_def builder false in
            res
        | (_, Flow_ast.Statement.If state_if) -> proc_if_statement state_if builder
          (* Fuzzilli doesn't support imports *)
        | (_, Flow_ast.Statement.ImportDeclaration _) -> []
        | (_, Flow_ast.Statement.Return state_return) -> proc_return state_return builder
        | (_, Flow_ast.Statement.Throw state_throw) -> proc_throw state_throw builder
        | (_, Flow_ast.Statement.Try state_try) -> proc_try state_try builder
        | (_ , VariableDeclaration decl) -> proc_var_decl_statement decl builder
        | (_, Flow_ast.Statement.While state_while) -> proc_while state_while builder
        | (_, Flow_ast.Statement.With state_with) -> proc_with state_with builder
        | _ as s -> raise (Invalid_argument (Printf.sprintf "Unhandled statement type %s" (Util.trim_flow_ast_string (Util.print_statement s))))

and proc_statements (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) (var_builder: builder) = 
    match statements with
        [] -> []
        | hd :: tl ->
            let new_statement = proc_single_statement hd var_builder in
            new_statement @ proc_statements tl var_builder

let flow_ast_to_inst_list (prog: (Loc.t, Loc.t) Flow_ast.Program.t) emit_builtins include_v8_natives use_placeholder = 
    let init_var_builder = init_builder emit_builtins include_v8_natives use_placeholder in
    let (_, prog_t) = prog in
    let hoisted_funcs = handle_varHoist prog_t.statements init_var_builder in
    let proced_statements = hoisted_funcs @ proc_statements prog_t.statements init_var_builder in
    let proced_statements_converted = List.map inst_to_prog_inst proced_statements in
    proced_statements_converted
