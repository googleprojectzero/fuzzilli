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

let hoist_var var_name tracker =
    let result_temp, inst = build_load_undefined tracker in
    add_new_var_identifier var_name result_temp tracker;
    add_hoisted_var var_name tracker;
    print_string ("Hosting " ^ var_name);
    inst

(* Designed to be called on the statements of a function *)
let handle_varHoist (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) (tracker: tracker) =
    let var_useData : string list = VariableScope.get_vars_to_hoist statements in
    let hoist_func var = hoist_var var tracker in
    List.map hoist_func var_useData

(* Handle the various types of literal*)
let proc_exp_literal (lit_val: ('T) Flow_ast.Literal.t) (tracker: tracker) =
    let (temp_val, inst) = match lit_val.value with 
        (Flow_ast.Literal.String s) ->
            (* TODO: This may be the cause of the issue where some files fail Fuzzilli import due to a UTF-8 error *)
            let newString = Util.encode_newline s in
            build_load_string newString tracker
        | (Flow_ast.Literal.Boolean b) ->
            build_load_bool b tracker
        | (Flow_ast.Literal.Null) ->
            build_load_null tracker
        | (Flow_ast.Literal.Number num) ->
            (* Flow_ast only has one type for a number, while Fuzzilli has several, each with its own protobuf type*)
            if Float.is_integer num && not (String.contains lit_val.raw '.') && Int64.of_float num >= Int64.min_int && Int64.of_float num <= Int64.max_int then
                build_load_integer (Int64.of_float num) tracker
            else
                build_load_float num tracker
        | (Flow_ast.Literal.BigInt b) ->
            build_load_bigInt b tracker
        | (Flow_ast.Literal.RegExp r) ->
            let pattern = r.pattern in
            let flags = r.flags in
            build_load_regex pattern flags tracker in
    (temp_val, [inst])

(* Handle the various unary types*)
let rec proc_exp_unary (u_val: ('M, 'T) Flow_ast.Expression.Unary.t) (tracker: tracker) =
    match u_val.operator with
        Flow_ast.Expression.Unary.Not ->
            let arg_result_var, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_unary_op arg_result_var Not tracker in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.BitNot ->
            let arg_result_var, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_unary_op arg_result_var BitNot tracker in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Minus ->
            let arg_result_var, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_unary_op arg_result_var Minus tracker in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Plus ->
            let arg_result_var, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_unary_op arg_result_var Plus tracker in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Typeof ->
            let arg_result_var, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_typeof_op arg_result_var tracker in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Await ->
            let arg_result_var, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_await_op arg_result_var tracker in
            result_var, argument @ [inst]
        | Flow_ast.Expression.Unary.Delete ->
            (* Need to determine between computed delete, and named delete*)
            let _, unwrapped_arg = u_val.argument in
            let del_temp, del_inst = match unwrapped_arg with
                Flow_ast.Expression.Member mem -> 
                    let obj_temp, obj_inst = proc_expression mem._object tracker in
                    ( match mem.property with
                        Flow_ast.Expression.Member.PropertyIdentifier (_, id) ->
                            let name = id.name in
                            let obj, del_inst = build_delete_prop obj_temp name tracker in
                            obj, obj_inst @ [del_inst]
                        | Flow_ast.Expression.Member.PropertyExpression exp ->
                            let sub_temp, sub_inst = proc_expression exp tracker in
                            let (obj, com_del_inst) = build_delete_computed_prop obj_temp sub_temp tracker in
                            obj_temp, obj_inst @ sub_inst @ [com_del_inst]
                        | _ -> raise (Invalid_argument "Unhandled delete member property") )
                | Identifier id -> raise (Invalid_argument "Deleting an ID isn't supported in Fuzzilli")
                | _ -> raise (Invalid_argument "Unsupported delete expression ") in
            del_temp, del_inst
        | Flow_ast.Expression.Unary.Void ->
            let _, argument = proc_expression u_val.argument tracker in
            let result_var, inst = build_void_op tracker in
            result_var, argument @ [inst]


(* First, check against various edge cases. Otherwise, check the context, and handle the result appropriately *)
and proc_exp_id (id_val: ('M, 'T) Flow_ast.Identifier.t) tracker = 
    let (_, unwraped_id_val) = id_val in
    let name = unwraped_id_val.name in
    if String.equal name "Infinity" then (* TODO: What other values go here? *)
        let (result_var, inst) = build_load_float Float.infinity tracker in
        result_var, [inst]
    else if String.equal name "undefined" then
        let result_var, inst = build_load_undefined tracker in
        result_var, [inst]
    else match lookup_var_name tracker name with
        InScope x -> (x, [])
        | NotFound ->
            (if Util.is_supported_builtin name (include_v8_natives tracker) || (not (use_placeholder tracker)) then
                let (result_var, inst) = build_load_builtin name tracker in
                (result_var, [inst])
            else
                let (result_var, inst) = build_load_builtin "placeholder" tracker in
                (result_var, [inst]))

and proc_exp_bin_op (bin_op: ('M, 'T) Flow_ast.Expression.Binary.t) tracker =
    let (lvar, linsts) = proc_expression bin_op.left tracker in
    let (rvar, rinsts) = proc_expression bin_op.right tracker in
    let build_binary_op_func op = build_binary_op lvar rvar op tracker in
    let build_compare_op_func op = build_compare_op lvar rvar op tracker in
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
        | Instanceof -> build_instanceof_op lvar rvar tracker
        | In -> build_in_op lvar rvar tracker in
    (result_var, linsts @ rinsts @ [inst])

and proc_exp_logical (log_op: ('M, 'T) Flow_ast.Expression.Logical.t) tracker =
    let (lvar, linsts) = proc_expression log_op.left tracker in
    let (rvar, rinsts) = proc_expression log_op.right tracker in
    let op = match log_op.operator with
        Flow_ast.Expression.Logical.And -> LogicalAnd
        | Flow_ast.Expression.Logical.Or -> LogicalOr
        | x -> raise (Invalid_argument ("Unhandled logical expression type" ^ (Util.trim_flow_ast_string (Util.print_logical_operator x)))) in
    let (result_var, inst) = build_binary_op lvar rvar op tracker in
    (result_var, linsts @ rinsts @ [inst])

(* There are various different expression types, so pattern match on each time, and ccall the appropriate, more specific, function*)
and proc_exp_assignment (assign_exp: ('M, 'T) Flow_ast.Expression.Assignment.t) (tracker: tracker) = 
     match assign_exp.left with
        (_, (Flow_ast.Pattern.Identifier id)) -> proc_exp_assignment_norm_id assign_exp id.name tracker 
        | (_, (Flow_ast.Pattern.Expression (_, exp))) -> 
            (match exp with
                Flow_ast.Expression.Member mem -> 
                    let obj = mem._object in
                    (match mem.property with
                        Flow_ast.Expression.Member.PropertyExpression pex -> proc_exp_assignment_prod_exp pex obj assign_exp.right assign_exp.operator tracker
                        |  Flow_ast.Expression.Member.PropertyIdentifier pid -> proc_exp_assignment_prod_id pid obj assign_exp.right assign_exp.operator tracker
                        | _ -> raise (Invalid_argument "Unhandled member property in exp assignment"))
                | _ -> raise (Invalid_argument "Unhandled assignment expression left member"))
        | _ -> raise (Invalid_argument "Unhandled assignment expressesion left ")

and proc_exp_assignment_prod_id
    (prop_id: (Loc.t, Loc.t) Flow_ast.Identifier.t)
    (obj: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (right_exp: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (op: Flow_ast.Expression.Assignment.operator option)
    (tracker: tracker) =
    let obj_temp, obj_inst = proc_expression obj tracker in
    let (_, unwapped_id) = prop_id in
    let name = unwapped_id.name in
    let right_exp_temp, right_exp_inst = proc_expression right_exp tracker in
    let (sugared_assignment_temp, assigment_insts) = match op with
        None -> (right_exp_temp, [])
        | Some op -> 
            let (initial_prop_var, load_inst) = build_load_prop obj_temp name tracker in
            let bin_op = flow_binaryassign_op_to_progbuilder_binop op in
            let result_var, assignment_inst = build_binary_op initial_prop_var right_exp_temp bin_op tracker in
            (result_var, [load_inst; assignment_inst]) in
    let store_inst = build_store_prop obj_temp sugared_assignment_temp name tracker in
    (sugared_assignment_temp, obj_inst @ right_exp_inst @ assigment_insts @ [store_inst])

(* Handle assignments to property expressions *)
and proc_exp_assignment_prod_exp
    (prop_exp: (Loc.t, Loc.t) Flow_ast.Expression.t) 
    (obj: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (right_exp: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (op: Flow_ast.Expression.Assignment.operator option)
    (tracker: tracker) = 

    let obj_temp, obj_inst = proc_expression obj tracker in
    let index_exp_temp, index_exp_inst = proc_expression prop_exp tracker in
    let right_exp_temp, right_exp_inst = proc_expression right_exp tracker in

    let (lval_var, assigment_insts) = match op with
        None -> (right_exp_temp, [])
        | Some op -> 
            let load_temp_var, load_inst = build_load_computed_prop obj_temp index_exp_temp tracker in
            let bin_op = flow_binaryassign_op_to_progbuilder_binop op in
            let result_var, assignment_inst = build_binary_op load_temp_var right_exp_temp bin_op tracker in
            (result_var, [load_inst; assignment_inst]) in
    let store_inst = build_store_computed_prop obj_temp index_exp_temp lval_var tracker in
    (lval_var, obj_inst @ index_exp_inst @ right_exp_inst @ assigment_insts @ [store_inst])

(* Handle assignments to normal identifiers*)
and proc_exp_assignment_norm_id (assign_exp: ('M, 'T) Flow_ast.Expression.Assignment.t) (id: (Loc.t, Loc.t) Flow_ast.Identifier.t) tracker = 
    let (_, act_name)  = id in
    let (exp_output_loc, exp_insts) = proc_expression assign_exp.right tracker in

    let (sugared_assignment_temp, sugared_assigment_exp) = match assign_exp.operator with
        None -> (exp_output_loc, [])
        | Some op -> 
            let source, source_inst = match lookup_var_name tracker act_name.name with
                InScope x -> (x, [])
                | NotFound -> 
                    raise (Invalid_argument "Variable not found") in
            let bin_op = flow_binaryassign_op_to_progbuilder_binop op in
            let result_var, assignment_inst = build_binary_op source exp_output_loc bin_op tracker in

            (result_var, source_inst @ [assignment_inst])
            in
    let var_temp, add_inst = match lookup_var_name tracker act_name.name with
        (* This case is where a variable is being declared, without a let/const/var.*)
        NotFound ->
            let result_var, inst = build_dup_op sugared_assignment_temp tracker in
            add_new_var_identifier act_name.name result_var tracker;
            (result_var, [inst])
        | InScope existing_temp -> 
            let inst = build_reassign_op existing_temp sugared_assignment_temp tracker in
            (existing_temp, [inst])
        in
    (var_temp, exp_insts @ sugared_assigment_exp @ add_inst)
            
(* Handle a list of arguments to a function call*)
and proc_arg_list (arg_list: ('M, 'T) Flow_ast.Expression.ArgList.t) tracker =
    let _, unwrapped = arg_list in
    let arguments = unwrapped.arguments in
    let proc_exp_or_spread (exp_or_spread: ('M, 'T) Flow_ast.Expression.expression_or_spread) = 
        match exp_or_spread with
            Expression exp -> 
                proc_expression exp tracker
            | Spread spread -> 
                let (_, unwrapped) = spread in
                proc_expression unwrapped.argument tracker in
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

and proc_exp_call (call_exp: ('M, 'T) Flow_ast.Expression.Call.t) tracker =
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
                    let sub_exp_temp, sub_exp_inst = proc_expression member._object tracker in
                    if is_spread then raise (Invalid_argument "Unhandled spread in member call") else ();
                    let arg_regs, arg_inst = proc_arg_list call_exp.arguments tracker in
                    let result_var, inst = build_call_method sub_exp_temp arg_regs id.name tracker in
                    (result_var, sub_exp_inst @ arg_inst @ [inst])
                | _ ->
                    let callee_reg, callee_inst = proc_expression call_exp.callee tracker in
                    let arg_regs, arg_inst = proc_arg_list call_exp.arguments tracker in
                    let result_reg, inst = if is_spread
                        then
                            build_call_with_spread callee_reg arg_regs is_spread_list tracker 
                        else
                            build_call callee_reg arg_regs tracker in
                    (result_reg, callee_inst @ arg_inst @ [inst]))
        (* Otherwise, run the callee sub expression as normal*)
        | _ ->  let callee_reg, callee_inst = proc_expression call_exp.callee tracker in
                let arg_regs, arg_inst = proc_arg_list call_exp.arguments tracker in
                let result_reg, inst = if is_spread
                    then
                        build_call_with_spread callee_reg arg_regs is_spread_list tracker 
                    else
                        build_call callee_reg arg_regs tracker in
                (result_reg, callee_inst @ arg_inst @ [inst])

and proc_array_elem (elem: ('M, 'T) Flow_ast.Expression.Array.element) (tracker: tracker) =
    match elem with
        Expression e -> 
            let temp, inst = proc_expression e tracker in
            false, (temp, inst)
        | Spread spread -> 
            let _, unwrapped = spread in
            let temp, inst = proc_expression unwrapped.argument tracker in
            true, (temp, inst)
        | Hole h ->
            (* Fuzzilli doesn't support array holes, so load undefined instead *)
            let result_var, inst = build_load_undefined tracker in
            false, (result_var, [inst])

and proc_create_array (exp: ('M, 'T) Flow_ast.Expression.Array.t) (tracker: tracker) =
    let temp_func a = proc_array_elem a tracker in
    let is_spread_list, temp_list = List.split (List.map temp_func exp.elements) in
    let arg_regs, arg_inst = List.split temp_list in
    let flat_inst = List.flatten arg_inst in
    let is_spread = List.fold_left (||) false is_spread_list in
    let result_var, create_array_inst = if is_spread
        then
            build_create_array_with_spread arg_regs is_spread_list tracker
        else
            build_create_array arg_regs tracker 
        in
    (result_var, flat_inst @ [create_array_inst])

and proc_create_object_property (prop_val: ('M, 'T) Flow_ast.Expression.Object.property) tracker =
    match prop_val with
        Property (_, prop) ->
            let temp_reg, prop_name_key, inst = match prop with
                Init init_val ->
                    let temp, exp_inst = proc_expression init_val.value tracker in
                    temp, init_val.key, exp_inst
                | Set func -> 
                    let _, act_func = func.value in
                    let temp, inst = proc_func act_func tracker false in
                    temp, func.key, inst
                | Get func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func tracker false in
                    temp, func.key, inst
                | Method func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func tracker false in
                    temp, func.key, inst in
            let prop_name : string = match prop_name_key with
                Literal (_, l) -> l.raw
                | Identifier (_, i) -> i.name
                | PrivateName (_, p) -> let (_, i) = p.id in
                    i.name
                | Computed _ -> raise (Invalid_argument "Unhandled Object key type Computed Key in object creation") in
            (temp_reg, [prop_name]), inst
        | SpreadProperty (_, spreadProp) -> 
            let temp_reg, exp_inst = proc_expression spreadProp.argument tracker in
            (temp_reg, []), exp_inst

and proc_create_object (exp : ('M, 'T) Flow_ast.Expression.Object.t) (tracker: tracker) =
    let props = exp.properties in
    let temp_func a = proc_create_object_property a tracker in
    let obj_temp_tuple, create_obj_inst = List.split (List.map temp_func props) in
    let obj_temp_list, obj_key_list_unflattened = List.split obj_temp_tuple in
    let obj_key_list_flat = List.flatten obj_key_list_unflattened in
    let flat_inst = List.flatten create_obj_inst in
    let result_var, create_obj_inst = if List.length obj_key_list_flat == List.length obj_temp_list then
            build_create_object obj_key_list_flat obj_temp_list tracker
        else
            build_create_object_with_spread obj_key_list_flat obj_temp_list tracker
        in
    (result_var, flat_inst @ [create_obj_inst])

and proc_exp_member (memb_exp: ('M, 'T) Flow_ast.Expression.Member.t) (tracker: tracker) =
    let (sub_exp_temp, sub_exp_inst) = proc_expression memb_exp._object tracker in
    let return_temp, insts = match memb_exp.property with
        PropertyIdentifier (_, i) ->
            let result_var, load_prop_inst = build_load_prop sub_exp_temp i.name tracker in
            (result_var, [load_prop_inst])
        | PropertyPrivateName (_, p) -> 
            let (_, i) = p.id in
            let result_var, load_prop_inst = build_load_prop sub_exp_temp i.name tracker in
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
                    let result_var, load_element_inst = build_load_element sub_exp_temp n tracker in
                    result_var, [load_element_inst]
                | _ -> 
                    (* Do a loadComputed with the expression*)
                    (* TODO: Is this the right operation here? *)
                    let member_exp_temp, member_exp_inst = proc_expression pe tracker in
                    let result_var, load_computed_prop_inst = build_load_computed_prop sub_exp_temp member_exp_temp tracker in
                    (result_var, member_exp_inst @ [load_computed_prop_inst]) in
    (return_temp, sub_exp_inst @ insts)

and proc_exp_new (new_exp: ('M, 'T) Flow_ast.Expression.New.t) (tracker: tracker) = 
    let callee = new_exp.callee in
    let (callee_reg, callee_inst) = proc_expression callee tracker in
    let _ : unit = match new_exp.targs with
        None -> ()
        | Some a -> raise (Invalid_argument "Unhandled targs in call") in
    let arguments = new_exp.arguments in  
    let (arg_regs, arg_inst) = match arguments with
        None -> ([], [])
        | Some act_args -> 
            (let is_spread = List.fold_left (||) false ( arg_list_get_spread_list act_args ) in
            let temp, insts = proc_arg_list act_args tracker in
            if is_spread then raise (Invalid_argument "Unhandled spread in new") 
            else temp, insts)
        in
    let result_var, create_obj_inst = build_new_object callee_reg arg_regs tracker in
    (result_var, callee_inst @ arg_inst @ [create_obj_inst])

and proc_exp_this this_exp tracker = 
    let (result_var, inst) = build_load_builtin "this" tracker in
    result_var, [inst]

and proc_exp_update (update_exp: (Loc.t, Loc.t) Flow_ast.Expression.Update.t) (tracker: tracker) = 
    let (sub_exp_temp, sub_exp_inst) = proc_expression update_exp.argument tracker in
    let update_op : unary_op = match update_exp.operator with
        Increment -> if update_exp.prefix then PreInc else PostInc
        | Decrement -> if update_exp.prefix then PreDec else PostDec in
    let result_var, update_inst = build_unary_op sub_exp_temp update_op tracker in
    result_var, sub_exp_inst @ [update_inst]

and proc_exp_yield (yield_exp: (Loc.t, Loc.t) Flow_ast.Expression.Yield.t) (tracker: tracker) =
    let sub_exp_temp, sub_exp_insts = match yield_exp.argument with
        | Some exp -> proc_expression exp tracker
        | _ -> raise (Invalid_argument "Unhandled yield without argument") in
    let yield_inst = if yield_exp.delegate
        then
            build_yield_each_op sub_exp_temp tracker
        else
            build_yield_op sub_exp_temp tracker
        in
    sub_exp_temp, sub_exp_insts @ [yield_inst]

(* Ternary expressions are not handled by Fuzzilli, so convert them to an if-else *)
and proc_exp_conditional (cond_exp: (Loc.t, Loc.t) Flow_ast.Expression.Conditional.t) (tracker: tracker) = 
    let result_temp, zero_temp_inst = build_load_integer 0L tracker in
    let (test_temp, test_inst) = proc_expression cond_exp.test tracker in
    let begin_if_inst = build_begin_if test_temp tracker in
    let consequent_temp, consequest_inst = proc_expression cond_exp.consequent tracker in
    let consequent_reassing_inst = build_reassign_op result_temp consequent_temp tracker in
    let begin_else_inst = build_begin_else tracker in
    let alternative_temp, alternative_inst = proc_expression cond_exp.alternate tracker in
    let alternative_reassign_inst = build_reassign_op result_temp alternative_temp tracker in
    let end_if_inst = build_end_if tracker in
    (result_temp, [zero_temp_inst] @ test_inst @ [begin_if_inst] @ consequest_inst @ [consequent_reassing_inst] @ [begin_else_inst] @
        alternative_inst @ [alternative_reassign_inst; end_if_inst])

and proc_class_method class_proto_temp tracker (m: (Loc.t, Loc.t) Flow_ast.Class.Method.t) =
    let _, unwrapped_method = m in
    let key = unwrapped_method.key in
    let method_name = match key with
        Literal (_, l) -> l.raw
        | Identifier (_, i) -> i.name
        | PrivateName (_, p) -> let (_, i) = p.id in
            i.name
        | Computed _ -> raise (Invalid_argument "Unhandled method name in class creation") in
    let _, func = unwrapped_method.value in
    let method_temp, method_inst = proc_func func tracker false in
    (* TODO: Double check if this is the right operation *)
    let load_propotype_inst = build_store_prop class_proto_temp method_temp method_name tracker in
    method_inst @ [load_propotype_inst]

and proc_expression (exp: ('M, 'T) Flow_ast.Expression.t) (tracker: tracker) = 
    let (_, unwrapped_exp) = exp in
    match unwrapped_exp with
        | (Flow_ast.Expression.Array array_op) ->
            proc_create_array array_op tracker
        | (Flow_ast.Expression.ArrowFunction arrow_func) ->
            proc_func arrow_func tracker true
        | (Flow_ast.Expression.Assignment assign_op) ->
            proc_exp_assignment assign_op tracker
        | (Flow_ast.Expression.Binary bin_op) ->
            proc_exp_bin_op bin_op tracker
        | (Flow_ast.Expression.Call call_op) ->
            proc_exp_call call_op tracker
        | (Flow_ast.Expression.Conditional cond_exp) ->
            proc_exp_conditional cond_exp tracker
        | (Flow_ast.Expression.Function func_exp) ->
            proc_func func_exp tracker false
        | (Flow_ast.Expression.Identifier id_val) ->
            proc_exp_id id_val tracker
        | (Flow_ast.Expression.Import _) -> 
            (* Fuzzilli doesn't support imports, so effectively nop this out *)
            let var, inst = build_load_undefined tracker in
            var, [inst]
        | (Flow_ast.Expression.Literal lit_val) -> 
            proc_exp_literal lit_val tracker
        | (Flow_ast.Expression.Logical log_op) ->
            proc_exp_logical log_op tracker
        | (Flow_ast.Expression.Member memb_exp) ->
            proc_exp_member memb_exp tracker
        | (Flow_ast.Expression.New new_exp) ->
            proc_exp_new new_exp tracker
        | (Flow_ast.Expression.Object create_obj_op) ->
            proc_create_object create_obj_op tracker
        | (Flow_ast.Expression.This this_exp) ->
            proc_exp_this this_exp tracker
        | (Flow_ast.Expression.Unary u_val) ->
            proc_exp_unary u_val tracker
        | (Flow_ast.Expression.Update update_exp) ->
            proc_exp_update update_exp tracker
        | (Flow_ast.Expression.Yield yield_exp) ->
            proc_exp_yield yield_exp tracker
        | x -> raise (Invalid_argument ("Unhandled expression type " ^ (Util.trim_flow_ast_string (Util.print_expression exp))))       

(* Process a single variable declaration *)
and proc_var_dec_declarators (decs : (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.Declarator.t list) (tracker : tracker) (kind: Flow_ast.Statement.VariableDeclaration.kind) =
    match decs with
        [] -> []
        | (_, declarator) :: tl -> 
            (* Get the variable name, and assign it as appropriate *)
            let var_identifier = match declarator.id with
                (_, (Flow_ast.Pattern.Identifier x)) -> x.name
                | _ -> raise (Invalid_argument "Left side of var decl isn't an identifier") in (* TODO: Make this not terrible *)
            let (_, act_name) = var_identifier in
            let var_name = act_name.name in
            (* Build the expression, and put it into a temp*)
            let init = declarator.init in 
            let temp_var_num, new_insts = match init with
                None -> 
                    (* Handle a declaration without a definition *)
                    (match kind with
                        Flow_ast.Statement.VariableDeclaration.Var ->
                            raise (Invalid_argument "Unimplemented var")
                            (* let undef_temp, undef_inst = build_load_undefined tracker in
                            let result_var, dup_inst = build_dup_op undef_temp tracker in
                            add_new_var_identifier_local var_name result_var true tracker;
                            result_var, [undef_inst; dup_inst] *)
                        | Flow_ast.Statement.VariableDeclaration.Let ->
                            let undef_temp, undef_inst = build_load_undefined tracker in
                            add_new_var_identifier var_name undef_temp tracker;
                            undef_temp, [undef_inst]
                        | _ -> raise (Invalid_argument "Empty const declaration"))
                | Some exp -> proc_expression exp tracker in
            let reassign_inst = (match kind with 
                Flow_ast.Statement.VariableDeclaration.Var ->
                    let is_hoisted = is_hoisted_var var_name tracker in
                    if is_hoisted then
                            let hoisted_temp = lookup_var_name tracker var_name in
                            match hoisted_temp with
                                NotFound -> raise (Invalid_argument "Unfound hoisted temp")
                                | InScope temp ->
                                    let inst = build_reassign_op temp temp_var_num tracker in
                                    [inst]
                        else
                            (add_new_var_identifier var_name temp_var_num tracker;
                            [])
                | _ -> add_new_var_identifier var_name temp_var_num tracker;
                []) in
            new_insts @ reassign_inst @ (proc_var_dec_declarators tl tracker kind)

(* Processes a variable declaration statement, which can be made up of multiple vars  *)
and proc_var_decl_statement (var_decl: (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.t) (tracker: tracker) =
    let decs = var_decl.declarations in
    let kind = var_decl.kind in
    proc_var_dec_declarators decs tracker kind

and proc_if_statement (if_statement: (Loc.t, Loc.t) Flow_ast.Statement.If.t) (tracker: tracker) =
    let test = if_statement.test in 
    let (test_temp_val, test_inst) = proc_expression test tracker in

    let begin_if_inst = build_begin_if test_temp_val tracker in
    
    push_local_scope tracker;
    let consequent_statements = proc_single_statement if_statement.consequent tracker in
    pop_local_scope tracker;

    (* Fuzzilli requires an else for each if, due to how AbstractInterpreter works *)
    let begin_else_inst = build_begin_else tracker in 

    push_local_scope tracker;
    let fin_statement = match if_statement.alternate with
        None -> []
        | Some (_, alt) ->
            let alt_inst = proc_single_statement alt.body tracker in
            alt_inst in
    pop_local_scope tracker;

    let end_if_inst = build_end_if tracker in
    test_inst @ begin_if_inst :: consequent_statements @ [begin_else_inst] @ fin_statement @ [end_if_inst]    


(* TODO: Improve this. Puts all expressions into a temp, and compares with 0. Could be better*)
and proc_while (while_statement: (Loc.t, Loc.t) Flow_ast.Statement.While.t) (tracker: tracker) = 
    (* Build initial check, put into temp*)
    let test_exp_reg, test_exp_inst = proc_expression while_statement.test tracker in
    let pre_loop_inst = test_exp_inst in

    (* Build begin while *)
    let zero_temp, zero_temp_inst = build_load_integer 0L tracker in
    let begin_while_inst = build_begin_while test_exp_reg zero_temp NotEqual tracker in
    let begin_loop_inst = zero_temp_inst :: [begin_while_inst] in

    push_local_scope tracker;
    (* Build body *)
    let body_statement = proc_single_statement while_statement.body tracker in
    pop_local_scope tracker;
    
    (* Reexecute comparison, and load into temp*)
    let test_exp_reg_internal, test_exp_inst_internal = proc_expression while_statement.test tracker in
    let reassign_inst = build_reassign_op test_exp_reg test_exp_reg_internal tracker in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    let end_while_inst = build_end_while tracker in
    pre_loop_inst @ begin_loop_inst @ body_statement @ re_exec_test_exp @ [end_while_inst]

and proc_do_while (do_while_statement: (Loc.t, Loc.t) Flow_ast.Statement.DoWhile.t) (tracker: tracker) =
    (* Build initial check, put into temp*)
    (* let test_exp_reg, test_exp_inst = proc_expression do_while_statement.test tracker in *)
    let zero_temp, zero_temp_inst = build_load_integer 0L tracker in
    let intermed, dup_inst = build_dup_op zero_temp tracker in

    (* Build begin while *)
    let begin_while_inst = build_begin_do_while intermed zero_temp NotEqual tracker in
    push_local_scope tracker;
    (* Build body *)
    let body_statement = proc_single_statement do_while_statement.body tracker in
    pop_local_scope tracker;
    (* Execute comparison, and load into temp*)
    let test_exp_reg_internal, test_exp_inst_internal = proc_expression do_while_statement.test tracker in
    let reassign_inst = build_reassign_op intermed test_exp_reg_internal tracker in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    let end_while_inst = build_end_do_while tracker in
    [zero_temp_inst; dup_inst; begin_while_inst] @ body_statement @ re_exec_test_exp @ [end_while_inst]
    
and proc_try (try_statement: (Loc.t, Loc.t) Flow_ast.Statement.Try.t) (tracker: tracker) = 
    let try_inst = build_begin_try_op tracker in
    push_local_scope tracker;
    let (_, try_block) = try_statement.block in
    let block_inst = proc_statements try_block.body tracker in
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
            let catch_body_inst = proc_statements catch_cause_block.body tracker in
            let catch_inst = build_begin_catch_op temp_name tracker in
            (catch_inst, catch_body_inst)
        in
    let finalizer_inst = match try_statement.finalizer with
        None -> []
        | Some (_, fin_block) -> proc_statements fin_block.body tracker in
    pop_local_scope tracker;
    let end_try_catch_inst = build_end_try_catch_op tracker in
    [try_inst] @ block_inst @ [catch_inst] @ catch_body_inst @  [end_try_catch_inst] @ finalizer_inst


and proc_func (func: (Loc.t, Loc.t) Flow_ast.Function.t) (tracker : tracker) (is_arrow: bool) =
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

    let func_temp, begin_func_inst, end_func_inst = build_func_ops func_name_opt param_ids rest_arg_name_opt is_arrow func.async func.generator tracker in
    (match func_name_opt with
        Some name -> add_new_var_identifier name func_temp tracker;
        | _ -> (););
    push_local_scope tracker;
    (* Process func body*)
    let func_inst = match func.body with 
        BodyBlock body_block -> 
            let _, state_block = body_block in
            let hoisted_statements = handle_varHoist state_block.body tracker in
            hoisted_statements @ proc_statements state_block.body tracker
        | BodyExpression body_exp -> 
            let _, inst = proc_expression body_exp tracker in
            inst
    in
    pop_local_scope tracker;
    func_temp, [begin_func_inst] @ func_inst @ [end_func_inst]

(* TODO: Fuzzilli return statements currently only allow variables. Add the ability to return without a value *)
and proc_return (ret_state: (Loc.t, Loc.t) Flow_ast.Statement.Return.t) (tracker: tracker) =
    let return_var, return_insts = match ret_state.argument with
        None -> 
            let temp, inst = build_load_undefined tracker in
            temp, [inst]
        | Some exp -> 
            let temp_num, insts = proc_expression exp tracker in
            temp_num, insts
        in
    let return_inst = build_return_op return_var tracker in
    return_insts @ [return_inst]

and proc_with (with_state: (Loc.t, Loc.t) Flow_ast.Statement.With.t) (tracker: tracker) =
    let result_var, with_insts = proc_expression with_state._object tracker in
    let begin_with_inst = build_begin_with_op result_var tracker in
    let body_insts = proc_single_statement with_state.body tracker in
    let end_with_inst = build_end_with_op tracker in 
    with_insts @ [begin_with_inst] @ body_insts @ [end_with_inst]
 
and proc_throw (throw_state: (Loc.t, Loc.t) Flow_ast.Statement.Throw.t) (tracker: tracker) =
    let temp, inst = proc_expression throw_state.argument tracker in
    let throw_inst = build_throw_op temp tracker in
    inst @ [throw_inst]
 
and proc_break tracker = 
    [build_break_op tracker]

and proc_for_in (for_in_state: (Loc.t, Loc.t) Flow_ast.Statement.ForIn.t) (tracker: tracker) =
    let right_temp, right_inst = proc_expression for_in_state.right tracker in
    push_local_scope tracker;
    let var_temp_name = match for_in_state.left with
        LeftDeclaration (_, d) -> 
            let decs = d.declarations in 
            (match decs with
                [(_, declarator)] -> ( match declarator.id with
                    (_, (Flow_ast.Pattern.Identifier id)) -> 
                        let (_, id_type) = id.name in
                        id_type.name
                    | _ -> raise (Invalid_argument ("Improper declaration in for-in loop")))
                | _ -> raise (Invalid_argument "Improper declaration in for-in loop"))
        | LeftPattern p -> (match p with
            (_, (Flow_ast.Pattern.Identifier id)) -> 
                (* TODO: Fuzzilli does not support reusing a variable in a for-in loop *)
                let (_, id_type) = id.name in
                id_type.name
            | _ -> raise (Invalid_argument ("Inproper left pattern in for-in loop"))) in
    
    let left_temp, start_for_in_inst = build_begin_for_in_op right_temp tracker in
    add_new_var_identifier var_temp_name left_temp tracker;
    let body_inst = proc_single_statement for_in_state.body tracker in
    let end_for_in = build_end_for_in_op tracker in
    pop_local_scope tracker;
    right_inst @ [start_for_in_inst] @ body_inst @ [end_for_in];

and proc_for_of (for_of_state: (Loc.t, Loc.t) Flow_ast.Statement.ForOf.t) (tracker: tracker) = 
    let right_temp, right_inst = proc_expression for_of_state.right tracker in
    push_local_scope tracker;
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
    let left_temp, start_for_of_inst = build_begin_for_of_op right_temp tracker in
    add_new_var_identifier act_name.name left_temp tracker;

    let body_inst = proc_single_statement for_of_state.body tracker in
    let end_for_of_inst = build_end_for_of_op tracker in
    right_inst @ [start_for_of_inst] @ body_inst @ [end_for_of_inst];

(* Fuzzilli For loops in Fuzzilli only *)
and proc_for (for_state: (Loc.t, Loc.t) Flow_ast.Statement.For.t) (tracker: tracker) =
    let init_inst = match for_state.init with
        None -> []
        | Some (InitDeclaration (_, decl)) -> proc_var_decl_statement decl tracker
        | Some (InitExpression exp) ->
            let (_, exp_insts) = proc_expression exp tracker in
            exp_insts
        in
    (* Variables used in the condition need to be declared outside the while loop*)
    let test_exp_reg, test_exp_inst = match for_state.test with
        Some exp -> proc_expression exp tracker
        | None -> raise (Invalid_argument "Unhandled empty for-loop test") in
    let pre_loop_inst = test_exp_inst in
    push_local_scope tracker;

    (*start while loop*)
    let zero_temp, zero_temp_inst = build_load_integer 0L tracker in
    let begin_while_inst  = build_begin_while test_exp_reg zero_temp NotEqual tracker in
    let begin_loop_inst = zero_temp_inst :: [begin_while_inst] in

    (*Body instructions*)
    let body_insts = proc_single_statement for_state.body tracker in

    (* Update*)
    let update_insts = match for_state.update with
        None -> []
        | Some exp ->
            let (_, exp_insts) = proc_expression exp tracker
            in exp_insts in

    (* Redo the check*)
    let test_exp_reg_internal, test_exp_inst_internal = match for_state.test with
        Some exp -> proc_expression exp tracker
        | None -> raise (Invalid_argument "Unhandled empty for-loop test") in
    let reassign_inst = build_reassign_op test_exp_reg test_exp_reg_internal tracker in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    (* End while*)
    let end_while_inst = build_end_while tracker in
    pop_local_scope tracker;
    init_inst @ pre_loop_inst @ begin_loop_inst @ body_insts @ update_insts @ re_exec_test_exp @ [end_while_inst]

and proc_continue tracker = 
    [build_continue tracker]

and proc_single_statement (statement: (Loc.t, Loc.t) Flow_ast.Statement.t) tracker = 
    match statement with 
        (_, Flow_ast.Statement.Block state_block) -> proc_statements state_block.body tracker
        | (_, Flow_ast.Statement.Break _) -> proc_break tracker
        | (_, Flow_ast.Statement.Continue state_continue) -> proc_continue tracker
        | (_, Flow_ast.Statement.DoWhile state_do_while) -> proc_do_while state_do_while tracker
        | (_, Flow_ast.Statement.Empty _) -> []
        | (_, Flow_ast.Statement.Expression state_exp) -> 
            let (_, inst) = proc_expression state_exp.expression tracker in
            inst
        | (_, Flow_ast.Statement.For state_for) -> proc_for state_for tracker
        | (_, Flow_ast.Statement.ForIn state_foin) -> proc_for_in state_foin tracker
        | (_, Flow_ast.Statement.ForOf state_forof) -> proc_for_of state_forof tracker
        | (_, Flow_ast.Statement.FunctionDeclaration func_def) -> 
            let (_, res) = proc_func func_def tracker false in
            res
        | (_, Flow_ast.Statement.If state_if) -> proc_if_statement state_if tracker
          (* Fuzzilli doesn't support imports *)
        | (_, Flow_ast.Statement.ImportDeclaration _) -> []
        | (_, Flow_ast.Statement.Return state_return) -> proc_return state_return tracker
        | (_, Flow_ast.Statement.Throw state_throw) -> proc_throw state_throw tracker
        | (_, Flow_ast.Statement.Try state_try) -> proc_try state_try tracker
        | (_ , VariableDeclaration decl) -> proc_var_decl_statement decl tracker
        | (_, Flow_ast.Statement.While state_while) -> proc_while state_while tracker
        | (_, Flow_ast.Statement.With state_with) -> proc_with state_with tracker
        | _ as s -> raise (Invalid_argument (Printf.sprintf "Unhandled statement type %s" (Util.trim_flow_ast_string (Util.print_statement s))))

and proc_statements (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) (var_tracker: tracker) = 
    match statements with
        [] -> []
        | hd :: tl ->
            let new_statement = proc_single_statement hd var_tracker in
            new_statement @ proc_statements tl var_tracker

let flow_ast_to_inst_list (prog: (Loc.t, Loc.t) Flow_ast.Program.t) emit_builtins include_v8_natives use_placeholder = 
    let init_var_tracker = init_tracker emit_builtins include_v8_natives use_placeholder in
    let (_, prog_t) = prog in
    let hoisted_funcs = handle_varHoist prog_t.statements init_var_tracker in
    let proced_statements = hoisted_funcs @ proc_statements prog_t.statements init_var_tracker in
    let proced_statements_converted = List.map inst_to_prog_inst proced_statements in
    proced_statements_converted
