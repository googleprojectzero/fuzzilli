let build_int_temp tracker i = 
    let op : Operations_types.load_integer = Operations_types.{value = i} in
    let inst_op = Program_types.Load_integer op in
    let temp_reg = Context.get_new_intermed_temp tracker in
    let inst : Program_types.instruction = Program_types.{
        inouts = [temp_reg];
        operation = inst_op;
    } in
    (temp_reg, inst)

let param_to_id (input: ('M, 'T) Flow_ast.Function.Param.t) = 
    let (_, unwrapped_input) = input in
    let pattern = unwrapped_input.argument in
    let (_, act_name) = match pattern with
        (_, (Flow_ast.Pattern.Identifier x)) -> x.name
        | _ -> raise (Invalid_argument "Didn't get an Identifier when expected") in
    act_name.name

let id_to_func_type a tracker = 
    let temp = Context.get_new_intermed_temp tracker in
    let type_ext = Typesystem_types.{
        properties = [];
        methods = [];
        group = "";
        signature = None;
    } in
    let type_mess : Typesystem_types.type_ = Typesystem_types.{
        definite_type = 4095l;
        possible_type = 4095l;
        ext = Extension type_ext;
    } in
    Context.add_new_var_identifier_local tracker a temp false;
    (temp, type_mess)

let proc_exp_literal (lit_val: ('T) Flow_ast.Literal.t) (tracker: Context.tracker) =
    let result_var = Context.get_new_intermed_temp tracker in
    let inoutlist = [result_var] in
    match lit_val.value with 
        (Flow_ast.Literal.String s) ->
            let newString = Util.encode_newline s in
            let op : Operations_types.load_string = Operations_types.{value = newString} in
            let inst_op = Program_types.Load_string op in
            let inst : Program_types.instruction = Program_types.{
                inouts = inoutlist;
                operation = inst_op;
            } in
            (result_var, [inst])
        | (Flow_ast.Literal.Boolean b) ->
            let op : Operations_types.load_boolean = Operations_types.{value = b} in
            let inst_op = Program_types.Load_boolean op in
            let inst : Program_types.instruction = Program_types.{
                inouts = inoutlist;
                operation = inst_op;
            } in
            (result_var, [inst])
        | (Flow_ast.Literal.Null) ->
            let inst_op = Program_types.Load_null in
            let inst : Program_types.instruction = Program_types.{
                inouts = inoutlist;
                operation = inst_op;
            } in
            (result_var, [inst])
        | (Flow_ast.Literal.Number num) ->
            if Float.is_integer num && not (String.contains lit_val.raw '.') && Int64.of_float num >= Int64.min_int && Int64.of_float num <= Int64.max_int then
                let op : Operations_types.load_integer = Operations_types.{value = Int64.of_float num} in
                let inst_op = Program_types.Load_integer op in
                let inst : Program_types.instruction = Program_types.{
                    inouts = inoutlist;
                    operation = inst_op;
                } in
                (result_var, [inst])
            else
                let op : Operations_types.load_float = Operations_types.{value = num} in
                let inst_op = Program_types.Load_float op in
                let inst : Program_types.instruction = Program_types.{
                    inouts = inoutlist;
                    operation = inst_op;
                } in
                (result_var, [inst])
        | (Flow_ast.Literal.BigInt b) ->
            if Float.is_integer b && b <= Int64.to_float Int64.max_int && b >= Int64.to_float Int64.min_int then
                let op : Operations_types.load_big_int = Operations_types.{value = Int64.of_float b} in
                let inst_op = Program_types.Load_big_int op in
                let inst : Program_types.instruction = Program_types.{
                    inouts = inoutlist;
                    operation = inst_op;
                } in
                (result_var, [inst])
            else
                raise (Invalid_argument ("Improper Bigint provided"))
        | (Flow_ast.Literal.RegExp r) ->
            let pattern = r.pattern in
            let flags = r.flags in
            let op : Operations_types.load_reg_exp = Operations_types.{value = pattern; flags = Util.regex_flag_str_to_int flags} in
            let inst_op = Program_types.Load_reg_exp op in
            let inst : Program_types.instruction = Program_types.{
                inouts = inoutlist;
                operation = inst_op;
            } in
                (result_var, [inst])

let rec proc_exp_unary (u_val: ('M, 'T) Flow_ast.Expression.Unary.t) (tracker: Context.tracker) =
    match u_val.operator with
        Flow_ast.Expression.Unary.Not ->
            let (arg_result_var, argument) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in
            let op : Operations_types.unary_operation = Operations_types.{op = Operations_types.Logical_not} in
            let inst_op = Program_types.Unary_operation op in
            let inst : Program_types.instruction = Program_types.{
                inouts = [arg_result_var; result_var];
                operation = inst_op;
            } in
            (result_var, argument @ [inst])
        | Flow_ast.Expression.Unary.BitNot ->
            let (arg_result_var, argument) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in
            let op : Operations_types.unary_operation = Operations_types.{op = Operations_types.Bitwise_not} in
            let inst_op = Program_types.Unary_operation op in
            let inst : Program_types.instruction = Program_types.{
                inouts = [arg_result_var; result_var];
                operation = inst_op;
            } in
            (result_var, argument @ [inst])
        | Flow_ast.Expression.Unary.Minus ->
            let (arg_result_var, argument) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in 
            let op : Operations_types.unary_operation = Operations_types.{op = Operations_types.Minus} in
            let inst : Program_types.instruction = Program_types.{
                inouts = [arg_result_var; result_var];
                operation = Program_types.Unary_operation op;
            } in
            (result_var, argument @ [inst])
        | Flow_ast.Expression.Unary.Plus ->
            let (arg_result_var, argument) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in 
            let op : Operations_types.unary_operation = Operations_types.{op = Operations_types.Plus} in
            let inst : Program_types.instruction = Program_types.{
                inouts =  [arg_result_var; result_var];
                operation = Program_types.Unary_operation op;
            } in
            (result_var, argument @ [inst])
        | Flow_ast.Expression.Unary.Typeof ->
            let (arg_result_var, argument) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst_op = Program_types.Type_of in
            let inst : Program_types.instruction = Program_types.{
                inouts = [arg_result_var; result_var];
                operation = inst_op;
            } in
            (result_var, argument @ [inst])
        | Flow_ast.Expression.Unary.Await ->
            let (arg_result_var, argument) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst_op = Program_types.Await in
            let inst : Program_types.instruction = Program_types.{
                inouts = [arg_result_var; result_var];
                operation = inst_op;
            } in
            (result_var, argument @ [inst])
        | Flow_ast.Expression.Unary.Delete ->
            (* Need to determine between computed delete, and named delete*)
            let argument = u_val.argument in
            let (_, unwrapped_arg) = argument in
            let (del_temp, del_inst) = match unwrapped_arg with
                Flow_ast.Expression.Member mem -> 
                    let obj_temp, obj_inst = proc_expression mem._object tracker in
                    let res = match mem.property with
                        Flow_ast.Expression.Member.PropertyIdentifier (_, id) ->
                            let name = id.name in
                            let op : Operations_types.delete_property = Operations_types.{property_name = name} in
                            let inst_op = Program_types.Delete_property op in
                            let inst : Program_types.instruction = Program_types.{
                                inouts = [obj_temp];
                                operation = inst_op;
                            } in
                            (obj_temp, obj_inst @ [inst])
                        | Flow_ast.Expression.Member.PropertyExpression exp ->
                            let sub_temp, sub_inst = proc_expression exp tracker in
                            let inst : Program_types.instruction = Program_types.{
                                inouts =  [obj_temp; sub_temp];
                                operation = Program_types.Delete_computed_property;
                            } in
                            (obj_temp, obj_inst @ sub_inst @ [inst])
                        | _ -> raise (Invalid_argument "Unhandled delete member property") in
                    res
                | Identifier id -> raise (Invalid_argument "Deleting an ID isn't supported in Fuzzilli")
                | _ -> raise (Invalid_argument "Unsupported delete expression ") in
            (del_temp, del_inst)
        | Flow_ast.Expression.Unary.Void ->
            (* Fuzzilli doesn't have a loadVoid operator. Execute the operation inst, and then load undefined*)
            let (arg_result_var, arg_inst) = proc_expression u_val.argument tracker in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst : Program_types.instruction = Program_types.{
                inouts = [result_var];
                operation = Program_types.Load_undefined;
            } in
            (result_var, arg_inst @ [inst])

and proc_exp_id (id_val: ('M, 'T) Flow_ast.Identifier.t) (tracker: Context.tracker) = 
    let (_, unwraped_id_val) = id_val in
    let name = unwraped_id_val.name in
    if String.equal name "Infinity" then (* TODO: What other values go here? *)
        let result_var = Context.get_new_intermed_temp tracker in
        let op : Operations_types.load_float = Operations_types.{value = Float.infinity} in
        let inst : Program_types.instruction = Program_types.{
            inouts = [result_var];
            operation = Program_types.Load_float op;
        } in
        (result_var, [inst])
    else if String.equal name "undefined" then
        let result_var = Context.get_new_intermed_temp tracker in
        let inst : Program_types.instruction = Program_types.{
            inouts = [result_var];
            operation = Program_types.Load_undefined;
        } in
        (result_var, [inst])
    else match Context.lookup_var_name tracker name with
        InScope x -> (x, [])
        | GetFromScope s ->
            let result_var = Context.get_new_intermed_temp tracker in
            let inst_op = Program_types.Load_from_scope Operations_types.{id = s} in
            let inst : Program_types.instruction = Program_types.{
                inouts = [result_var];
                operation = inst_op;
            } in
            (result_var, [inst])
        | NotFound ->
            if Util.is_supported_builtin name (Context.include_v8_natives tracker) then
                let result_var = Context.get_new_intermed_temp tracker in
                let op : Operations_types.load_builtin = Operations_types.{builtin_name = name} in
                let inst_op = Program_types.Load_builtin op in
                let inst : Program_types.instruction = Program_types.{
                    inouts = [result_var];
                    operation = inst_op;
                } in
                (result_var, [inst])
            else
                let result_var = Context.get_new_intermed_temp tracker in
                (* Load now, and check on the second pass to see if declared elsewhere *)
                let inst_op = Program_types.Load_from_scope Operations_types.{id = name} in
                let inst : Program_types.instruction = Program_types.{
                    inouts = [result_var];
                    operation = inst_op;
                } in
                (result_var, [inst])


and proc_exp_bin_op (bin_op: ('M, 'T) Flow_ast.Expression.Binary.t) (tracker: Context.tracker) =
    let op = bin_op.operator in
    let (left_side_var, left_side_insts) = proc_expression bin_op.left tracker in
    let (right_side_var, right_side_insts) = proc_expression bin_op.right tracker in
    let result_var = Context.get_new_intermed_temp tracker in
    let open Flow_ast.Expression.Binary in
    let inst_op = match op with
        Plus | Minus | Mult | Div | Mod | Xor | LShift | RShift | Exp | RShift3 | BitAnd | BitOr -> 
            let built_op : Operations_types.binary_operation = match op with
                Plus -> Operations_types.{op = Operations_types.Add}
                | Minus -> Operations_types.{op = Operations_types.Sub}
                | Mult -> Operations_types.{op = Operations_types.Mul}
                | Div -> Operations_types.{op = Operations_types.Div}
                | Mod -> Operations_types.{op = Operations_types.Mod}
                | Xor -> Operations_types.{op = Operations_types.Xor}
                | LShift -> Operations_types.{op = Operations_types.Lshift}
                | RShift -> Operations_types.{op = Operations_types.Rshift}
                | Exp -> Operations_types.{op = Operations_types.Exp}
                | RShift3 -> Operations_types.{op = Operations_types.Unrshift}
                | BitAnd -> Operations_types.{op = Operations_types.Bit_and}
                | BitOr -> Operations_types.{op = Operations_types.Bit_or}
                | x -> raise (Invalid_argument ("Unhandled binary expression type " ^ (Util.trim_flow_ast_string (Util.print_binary_operator x)))) in
            Program_types.Binary_operation built_op
        | Equal | NotEqual | StrictEqual | StrictNotEqual | LessThan | LessThanEqual | GreaterThan | GreaterThanEqual ->
            let built_op : Operations_types.compare = match op with 
                Equal -> Operations_types.{op = Operations_types.Equal}
                | NotEqual -> Operations_types.{op = Operations_types.Not_equal}
                | StrictEqual -> Operations_types.{op = Operations_types.Strict_equal}
                | StrictNotEqual -> Operations_types.{op = Operations_types.Strict_not_equal}
                | LessThan -> Operations_types.{op = Operations_types.Less_than}
                | LessThanEqual -> Operations_types.{op = Operations_types.Less_than_or_equal}
                | GreaterThan -> Operations_types.{op = Operations_types.Greater_than}
                | GreaterThanEqual -> Operations_types.{op = Operations_types.Greater_than_or_equal}
                | x -> raise (Invalid_argument ("Unhandled compare expression type " ^ (Util.trim_flow_ast_string (Util.print_binary_operator x)))) in
            Program_types.Compare built_op
        | Instanceof -> Program_types.Instance_of
        | In -> Program_types.In in
    let inst : Program_types.instruction = Program_types.{
        inouts = [left_side_var; right_side_var; result_var];
        operation = inst_op;
    } in
    (result_var, left_side_insts @ right_side_insts @ [inst])

and proc_exp_logical (log_op: ('M, 'T) Flow_ast.Expression.Logical.t) (tracker: Context.tracker) = 
    let op = log_op.operator in
    let (left_side_var, left_side_insts) = proc_expression log_op.left tracker in
    let (right_side_var, right_side_insts) = proc_expression log_op.right tracker in
    let result_var = Context.get_new_intermed_temp tracker in
    let built_op : Operations_types.binary_operation = match op with
        Flow_ast.Expression.Logical.And ->
            Operations_types.{op = Operations_types.Logical_and}
        | Flow_ast.Expression.Logical.Or ->
            Operations_types.{op = Operations_types.Logical_or}
        | x -> raise (Invalid_argument ("Unhandled logical expression type" ^ (Util.trim_flow_ast_string (Util.print_logical_operator x))))
    in
    let inst_op = Program_types.Binary_operation built_op in
    let inst : Program_types.instruction = Program_types.{
        inouts = [left_side_var; right_side_var; result_var];
        operation = inst_op;
    } in
    (result_var, left_side_insts @ right_side_insts @ [inst])

and proc_exp_assignment (assign_exp: ('M, 'T) Flow_ast.Expression.Assignment.t) (tracker: Context.tracker) = 
     match assign_exp.left with
        (_, (Flow_ast.Pattern.Identifier id)) -> proc_exp_assignment_norm_id assign_exp tracker id.name
        | (_, (Flow_ast.Pattern.Expression (_, exp))) -> 
            (match exp with
                Flow_ast.Expression.Member mem -> 
                    let obj = mem._object in
                    let prop = mem.property in
                    (match prop with
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
    (tracker: Context.tracker) =
    let obj_temp, obj_inst = proc_expression obj tracker in
    let (_, unwapped_id) = prop_id in
    let name = unwapped_id.name in
    let right_exp_temp, right_exp_inst = proc_expression right_exp tracker in

    let (sugared_assignment_temp, assigment_insts) = match op with
        None -> (right_exp_temp, [])
        | Some x -> 
            let temp_var = Context.get_new_intermed_temp tracker in
            let load_inst : Program_types.instruction = Program_types.{
                inouts =  [obj_temp; temp_var];
                operation = Program_types.Load_property{property_name = name};
            } in
            let built_op : Operations_types.binary_operation = match x with
                PlusAssign -> Operations_types.{op = Operations_types.Add}
                | MinusAssign -> Operations_types.{op = Operations_types.Sub}
                | MultAssign -> Operations_types.{op = Operations_types.Sub}
                | ExpAssign -> Operations_types.{op = Operations_types.Sub}
                | DivAssign -> Operations_types.{op = Operations_types.Sub}
                | ModAssign -> Operations_types.{op = Operations_types.Sub}
                | LShiftAssign -> Operations_types.{op = Operations_types.Sub}
                | RShiftAssign -> Operations_types.{op = Operations_types.Sub}
                | RShift3Assign -> Operations_types.{op = Operations_types.Sub}
                | BitOrAssign -> Operations_types.{op = Operations_types.Sub}
                | BitXorAssign -> Operations_types.{op = Operations_types.Sub}
                | BitAndAssign -> Operations_types.{op = Operations_types.Sub} in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst_op = Program_types.Binary_operation built_op in
            let inst : Program_types.instruction = Program_types.{
                inouts = [temp_var; right_exp_temp; result_var];
                operation = inst_op;
            } in
            (result_var, [load_inst; inst])
            in
    let op = Program_types.Store_property{property_name = name } in
    let inst : Program_types.instruction = Program_types.{
        inouts =  [obj_temp; sugared_assignment_temp];
        operation = op;
    } in
    (sugared_assignment_temp, obj_inst @ right_exp_inst @ assigment_insts @ [inst])

and proc_exp_assignment_prod_exp
    (prop_exp: (Loc.t, Loc.t) Flow_ast.Expression.t) 
    (obj: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (right_exp: (Loc.t, Loc.t) Flow_ast.Expression.t)
    (op: Flow_ast.Expression.Assignment.operator option)
    (tracker: Context.tracker) = 
    let obj_temp, obj_inst = proc_expression obj tracker in
    let index_exp_temp, index_exp_inst = proc_expression prop_exp tracker in
    let right_exp_temp, right_exp_inst = proc_expression right_exp tracker in

    let (sugared_assignment_temp, assigment_insts) = match op with
        None -> (right_exp_temp, [])
        | Some x -> 
            let temp_var = Context.get_new_intermed_temp tracker in
            let load_op = Program_types.Load_computed_property in
            let load_inst : Program_types.instruction = Program_types.{
                inouts =  [obj_temp; index_exp_temp; temp_var];
                operation = load_op;
            } in
            let built_op : Operations_types.binary_operation = match x with
                PlusAssign -> Operations_types.{op = Operations_types.Add}
                | MinusAssign -> Operations_types.{op = Operations_types.Sub}
                | MultAssign -> Operations_types.{op = Operations_types.Sub}
                | ExpAssign -> Operations_types.{op = Operations_types.Sub}
                | DivAssign -> Operations_types.{op = Operations_types.Sub}
                | ModAssign -> Operations_types.{op = Operations_types.Sub}
                | LShiftAssign -> Operations_types.{op = Operations_types.Sub}
                | RShiftAssign -> Operations_types.{op = Operations_types.Sub}
                | RShift3Assign -> Operations_types.{op = Operations_types.Sub}
                | BitOrAssign -> Operations_types.{op = Operations_types.Sub}
                | BitXorAssign -> Operations_types.{op = Operations_types.Sub}
                | BitAndAssign -> Operations_types.{op = Operations_types.Sub} in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst_op = Program_types.Binary_operation built_op in
            let inst : Program_types.instruction = Program_types.{
                inouts = [temp_var; right_exp_temp; result_var];
                operation = inst_op;
            } in
            (result_var, [load_inst; inst])
            in

    let inst : Program_types.instruction = Program_types.{
        inouts =  [obj_temp; index_exp_temp; sugared_assignment_temp];
        operation = Program_types.Store_computed_property;
    } in
    (sugared_assignment_temp, obj_inst @ index_exp_inst @ right_exp_inst @ assigment_insts @ [inst])

and proc_exp_assignment_norm_id (assign_exp: ('M, 'T) Flow_ast.Expression.Assignment.t) (tracker: Context.tracker) (id: (Loc.t, Loc.t) Flow_ast.Identifier.t) = 
    let (_, act_name)  = id in
    let (exp_output_loc, exp_insts) = proc_expression assign_exp.right tracker in

    let (sugared_assignment_temp, sugared_assigment_exp) = match assign_exp.operator with
        None ->
            (exp_output_loc, [])
        | Some x -> 
            let source, source_inst = match Context.lookup_var_name tracker act_name.name with
                InScope x -> (x, [])
                | GetFromScope s -> 
                    let inst_op = Program_types.Load_from_scope Operations_types.{id = s} in
                    let result_var = Context.get_new_intermed_temp tracker in
                    let inst : Program_types.instruction = Program_types.{
                        inouts = [result_var];
                        operation = inst_op;
                    } in
                    (result_var, [inst])
                | NotFound -> 
                    (* Not known currently, but may be declaraed globally later in the program, but earlier in execution order*)
                    let inst_op = Program_types.Load_from_scope Operations_types.{id = act_name.name} in
                    let result_var = Context.get_new_intermed_temp tracker in
                    let inst : Program_types.instruction = Program_types.{
                        inouts = [result_var];
                        operation = inst_op;
                    } in
                    (result_var, [inst]) in

            let built_op : Operations_types.binary_operation = match x with
                PlusAssign -> Operations_types.{op = Operations_types.Add}
                | MinusAssign -> Operations_types.{op = Operations_types.Sub}
                | MultAssign -> Operations_types.{op = Operations_types.Sub}
                | ExpAssign -> Operations_types.{op = Operations_types.Sub}
                | DivAssign -> Operations_types.{op = Operations_types.Sub}
                | ModAssign -> Operations_types.{op = Operations_types.Sub}
                | LShiftAssign -> Operations_types.{op = Operations_types.Sub}
                | RShiftAssign -> Operations_types.{op = Operations_types.Sub}
                | RShift3Assign -> Operations_types.{op = Operations_types.Sub}
                | BitOrAssign -> Operations_types.{op = Operations_types.Sub}
                | BitXorAssign -> Operations_types.{op = Operations_types.Sub}
                | BitAndAssign -> Operations_types.{op = Operations_types.Sub} in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst_op = Program_types.Binary_operation built_op in
            let inst : Program_types.instruction = Program_types.{
                (* A sugared assignment op will always have a valid input variable (e.g can't += a var that doesnt exist!) *)
                inouts = [(source); exp_output_loc; result_var];
                operation = inst_op;
            } in
            (result_var, source_inst @ [inst])
            in
    let var_temp, add_inst = match Context.lookup_var_name tracker act_name.name with
        (* This case is where a variable is being declared, without a let/const/var.*)
        NotFound ->
            let intermed = Context.get_new_intermed_temp tracker in 
            Context.add_new_var_identifier_local tracker act_name.name intermed true;
            let inst : Program_types.instruction = Program_types.{
                inouts = [ sugared_assignment_temp; intermed;];
                operation = Program_types.Dup;
            } in
            (intermed, [inst])
        | InScope existing_temp -> 
            let inst : Program_types.instruction = Program_types.{
                inouts = [existing_temp; sugared_assignment_temp];
                operation = Program_types.Reassign;
            } in 
            (existing_temp, [inst])
        | GetFromScope s -> 
            let inst_op = Program_types.Load_from_scope Operations_types.{id = s} in
            let result_var = Context.get_new_intermed_temp tracker in
            let inst : Program_types.instruction = Program_types.{
                inouts = [result_var];
                operation = inst_op;
            } in
            (result_var, [inst]) in
    (var_temp, exp_insts @ sugared_assigment_exp @ add_inst)

and proc_exp_or_spread (exp_or_spread: ('M, 'T) Flow_ast.Expression.expression_or_spread) (tracker: Context.tracker) = 
    match exp_or_spread with
        Expression exp -> 
            let temp, inst = proc_expression exp tracker in
            (false, (temp, inst))
        | Spread spread -> 
            let (_, unwrapped) = spread in
            let temp, inst = proc_expression unwrapped.argument tracker in
            (true, (temp, inst))
            
    
and proc_arg_list (arg_list: ('M, 'T) Flow_ast.Expression.ArgList.t) (tracker: Context.tracker) =
    let (_, unwrapped) = arg_list in
    let arguments = unwrapped.arguments in
    let temp_func a = proc_exp_or_spread a tracker in
    let (is_spread_list, temp) = List.split (List.map temp_func arguments) in
    let (reg_list, unflattened_inst_list) = List.split temp in
    (is_spread_list, reg_list, List.flatten unflattened_inst_list)

and proc_exp_call (call_exp: ('M, 'T) Flow_ast.Expression.Call.t) (tracker: Context.tracker) = 
    let _ : unit = match call_exp.targs with
        None -> ()
        | Some a -> raise (Invalid_argument "Unhandled targs in call") in
    let (_, callee) = call_exp.callee in
    match callee with
        (* Handle the method call case explicity*)
        Flow_ast.Expression.Member member -> 
            (match member.property with
                (* Handle method calls seperately for all other cases *)
                Flow_ast.Expression.Member.PropertyIdentifier (_, id) -> 
                    let name = id.name in
                    let arguments = call_exp.arguments in  
                    let (sub_exp_temp, sub_exp_inst) = proc_expression member._object tracker in
                    let (is_spread_list, arg_regs, arg_inst) = proc_arg_list arguments tracker in
                    let is_spread = List.fold_left (||) false is_spread_list in
                    if is_spread then raise (Invalid_argument "Unhandled spread in member call") else ();
                    let result_reg = Context.get_new_intermed_temp tracker in
                    let inouts = [sub_exp_temp] @ arg_regs @ [result_reg] in 
                    let op = Program_types.Call_method{method_name = name} in
                    let inst : Program_types.instruction = Program_types.{
                        inouts =  inouts;
                        operation = op;
                    } in
                    (result_reg, sub_exp_inst @ arg_inst @ [inst])
                | _ ->
                    let (callee_reg, callee_inst) = proc_expression call_exp.callee tracker in
                    let arguments = call_exp.arguments in  
                    let (is_spread_list, arg_regs, arg_inst) = proc_arg_list arguments tracker in
                    let is_spread = List.fold_left (||) false is_spread_list in
                    let result_reg = Context.get_new_intermed_temp tracker in
                    let inst : Program_types.instruction = if is_spread
                    then
                        (let op : Operations_types.call_function_with_spread = Operations_types.{spreads = is_spread_list} in
                        let inst_op : Program_types.instruction_operation = Program_types.Call_function_with_spread op in
                        let temp_inout = [callee_reg] @ arg_regs @ [result_reg] in
                        Program_types.{
                            inouts =  temp_inout;
                            operation = inst_op;
                        })
                    else
                        (let op = Program_types.Call_function in
                        let temp_inout = [callee_reg] @ arg_regs @ [result_reg] in
                        Program_types.{
                            inouts =  temp_inout;
                            operation = op;
                        }) in
                    (result_reg, callee_inst @ arg_inst @ [inst]))
        (* Otherwise, run the callee sub expression as normal*)
        | _ ->  let (callee_reg, callee_inst) = proc_expression call_exp.callee tracker in
                let arguments = call_exp.arguments in  
                let (is_spread_list, arg_regs, arg_inst) = proc_arg_list arguments tracker in
                let is_spread = List.fold_left (||) false is_spread_list in
                let result_reg = Context.get_new_intermed_temp tracker in
                let inst : Program_types.instruction = if is_spread
                    then
                        (let op : Operations_types.call_function_with_spread = Operations_types.{spreads = is_spread_list} in
                        let inst_op : Program_types.instruction_operation = Program_types.Call_function_with_spread op in
                        let temp_inout = [callee_reg] @ arg_regs @ [result_reg] in
                        Program_types.{
                            inouts =  temp_inout;
                            operation = inst_op;
                        })
                    else
                        (let op = Program_types.Call_function in
                        let temp_inout = [callee_reg] @ arg_regs @ [result_reg] in
                        Program_types.{
                            inouts =  temp_inout;
                            operation = op;
                        }) in
                (result_reg, callee_inst @ arg_inst @ [inst])

and proc_array_elem (elem: ('M, 'T) Flow_ast.Expression.Array.element) (tracker: Context.tracker) =
    match elem with
        Expression e -> 
            let temp, inst = proc_expression e tracker in
            (false, (temp, inst))
        | Spread spread -> 
            let (_, unwrapped) = spread in
            let temp, inst = proc_expression unwrapped.argument tracker in
            (true, (temp, inst))
        | Hole h ->
            (* Fuzzilli doesn't support array holes, so load undefined instead *)
            let result_var = Context.get_new_intermed_temp tracker in
            let inst : Program_types.instruction = Program_types.{
                inouts = [result_var];
                operation = Program_types.Load_undefined;
            } in
            (false, (result_var, [inst]))    

and proc_create_array (exp: ('M, 'T) Flow_ast.Expression.Array.t) (tracker: Context.tracker) =
    let arr_elements = exp.elements in
    let temp_func a = proc_array_elem a tracker in
    let (is_spread_list,  temp_list) = List.split (List.map temp_func arr_elements) in
    let (arg_regs, arg_inst) = List.split temp_list in
    let flat_inst = List.flatten arg_inst in

    let is_spread = List.fold_left (||) false is_spread_list in

    (* Build create array instruction, including inout and return val, and concat all istructions *)
    let return_temp = Context.get_new_intermed_temp tracker in
    let inouts =  (arg_regs @ [return_temp]) in
    let inst_op : Program_types.instruction_operation = if is_spread then 
        (let op : Operations_types.create_array_with_spread = Operations_types.{spreads = is_spread_list} in
            Program_types.Create_array_with_spread op)
        else Program_types.Create_array in
    let inst : Program_types.instruction = Program_types.{
        inouts = inouts;
        operation = inst_op;
    } in
    (return_temp, flat_inst @ [inst])


and proc_create_object_property (prop_val: ('M, 'T) Flow_ast.Expression.Object.property) (tracker: Context.tracker) =
    match prop_val with
        Property (_, prop) ->
            let temp_reg, prop_name_key, inst = match prop with
                Init init_val ->
                    let temp, exp_inst = proc_expression init_val.value tracker in
                    (temp, init_val.key, exp_inst)
                | Set func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func tracker false in
                    (temp, func.key, inst)
                | Get func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func tracker false in
                    (temp, func.key, inst)
                | Method func -> 
                    let (_, act_func) = func.value in
                    let temp, inst = proc_func act_func tracker false in
                    (temp, func.key, inst) in
            let prop_name : string = match prop_name_key with
                Literal (_, l) -> l.raw
                | Identifier (_, i) -> i.name
                | PrivateName (_, p) -> let (_, i) = p.id in
                    i.name
                | Computed _ -> raise (Invalid_argument "Unhandled Object key type Computed Key in object creation") in
            ((temp_reg, [prop_name]), inst)
        | SpreadProperty (_, spreadProp) -> 
            let temp_reg, exp_inst = proc_expression spreadProp.argument tracker in
            ((temp_reg, []), exp_inst)

and proc_create_object (exp : ('M, 'T) Flow_ast.Expression.Object.t) (tracker: Context.tracker) =
    let props = exp.properties in
    let temp_func a = proc_create_object_property a tracker in
    let (obj_temp_tuple, create_obj_inst) = List.split (List.map temp_func props) in
    let (obj_temp_list, obj_key_list_unflattened) = List.split obj_temp_tuple in
    let obj_key_list_flat = List.flatten obj_key_list_unflattened in
    let flat_inst = List.flatten create_obj_inst in
    let return_temp = Context.get_new_intermed_temp tracker in
    let inouts =  (obj_temp_list @ [return_temp]) in
    let op = if List.length obj_key_list_flat == List.length obj_temp_list then
            Program_types.Create_object{property_names = obj_key_list_flat} 
        else
            Program_types.Create_object_with_spread{property_names = obj_key_list_flat} 
        in
    let inst : Program_types.instruction = Program_types.{
        inouts = inouts;
        operation = op;
    } in
    (return_temp, flat_inst @ [inst])

and proc_exp_member (memb_exp: ('M, 'T) Flow_ast.Expression.Member.t) (tracker: Context.tracker) =
    let sub_exp = memb_exp._object in
    let (sub_exp_temp, sub_exp_inst) = proc_expression sub_exp tracker in
    let return_temp, insts = match memb_exp.property with
        PropertyIdentifier (_, i) ->
            let name = i.name in
            let return_temp = Context.get_new_intermed_temp tracker in
            let inouts =  [sub_exp_temp; return_temp] in
            let op = Program_types.Load_property{property_name = name} in
            let inst : Program_types.instruction = Program_types.{
                inouts = inouts;
                operation = op;
            } in
            (return_temp, [inst])
        | PropertyPrivateName (_, p) -> 
            let (_, i) = p.id in
            let name = i.name in
            let return_temp = Context.get_new_intermed_temp tracker in
            let inouts =  [sub_exp_temp; return_temp] in
            let op = Program_types.Load_property{property_name = name} in
            let inst : Program_types.instruction = Program_types.{
                inouts = inouts;
                operation = op;
            } in
            (return_temp, [inst])
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
                    let return_temp = Context.get_new_intermed_temp tracker in
                    let inouts =  [sub_exp_temp; return_temp] in
                    let op = Program_types.Load_element{index = Int64.of_int n} in
                    let inst : Program_types.instruction = Program_types.{
                        inouts = inouts;
                        operation = op;
                    } in
                    (return_temp, [inst])
                | _ -> (* Do a loadComputed with the expression*)
                    let member_exp_temp, member_exp_inst = proc_expression pe tracker in
                    let return_temp = Context.get_new_intermed_temp tracker in
                    let inouts =  [sub_exp_temp; member_exp_temp; return_temp] in
                    let op = Program_types.Load_computed_property in
                    let inst : Program_types.instruction = Program_types.{
                        inouts = inouts;
                        operation = op;
                    } in
                    (return_temp, member_exp_inst @ [inst]) in

    (return_temp, sub_exp_inst @ insts)

and proc_exp_new (new_exp: ('M, 'T) Flow_ast.Expression.New.t) (tracker: Context.tracker) = 
    let callee = new_exp.callee in
    let (callee_reg, callee_inst) = proc_expression callee tracker in
    let _ : unit = match new_exp.targs with
        None -> ()
        | Some a -> raise (Invalid_argument "Unhandled targs in call") in
    let arguments = new_exp.arguments in  
    let (arg_regs, arg_inst) = match arguments with
        None -> ([], [])
        | Some act_args -> 
            (let (is_spread_list, temp, insts) = proc_arg_list act_args tracker in
            let is_spread = List.fold_left (||) false is_spread_list in
            if is_spread then raise (Invalid_argument "Unhandled spread in new") 
            else (temp, insts))
        in
    let result_reg = Context.get_new_intermed_temp tracker in
    let temp_inout = [callee_reg] @ arg_regs @ [result_reg] in
    let inst : Program_types.instruction = Program_types.{
        inouts =  temp_inout;
        operation = Program_types.Construct;
    } in
    (result_reg, callee_inst @ arg_inst @ [inst])

and proc_exp_this this_exp tracker = 
    let result_reg = Context.get_new_intermed_temp tracker in
    let op : Operations_types.load_builtin = Operations_types.{builtin_name = "this"} in
    let inst_op = Program_types.Load_builtin op in
    let inst : Program_types.instruction = Program_types.{
        inouts = [result_reg];
        operation = inst_op;
    } in
    (result_reg, [inst])

and proc_exp_update (update_exp: (Loc.t, Loc.t) Flow_ast.Expression.Update.t) (tracker: Context.tracker) = 
    let (sub_exp_temp, sub_exp_inst) = proc_expression update_exp.argument tracker in
    let op : Operations_types.unary_operation = match update_exp.operator with
        Increment -> 
            (match update_exp.prefix with
                false -> Operations_types.{op = Operations_types.Post_inc}
                | true -> Operations_types.{op = Operations_types.Pre_inc})
        | Decrement -> 
            (match update_exp.prefix with
                false -> Operations_types.{op = Operations_types.Post_dec}
                | true -> Operations_types.{op = Operations_types.Pre_dec})
        in
    let inst_op = Program_types.Unary_operation op in
    let result_var = Context.get_new_intermed_temp tracker in
    let inst : Program_types.instruction = Program_types.{
        inouts = [sub_exp_temp; result_var];
        operation = inst_op;
    } in
    (result_var, sub_exp_inst @ [inst])


and proc_exp_yield (yield_exp: (Loc.t, Loc.t) Flow_ast.Expression.Yield.t) (tracker: Context.tracker) =
    let (sub_exp_temp, sub_exp_insts) = match yield_exp.argument with
        | Some exp -> proc_expression exp tracker
        | _ -> raise (Invalid_argument "Unhandled yield without argument") in
    let inst : Program_types.instruction = if yield_exp.delegate then
        Program_types.{
            inouts = [sub_exp_temp];
            operation = Program_types.Yield_each;
        }
        else
        Program_types.{
            inouts = [sub_exp_temp];
            operation = Program_types.Yield;
        }
        in
    (sub_exp_temp, sub_exp_insts @ [inst])

(* Template literals aren't handled by Fuzzilli currently, so execute all subexpressions, and then load the first string*)
and proc_exp_temp_lit (temp_exp: (Loc.t, Loc.t) Flow_ast.Expression.TemplateLiteral.t) (tracker: Context.tracker) =
    let proc_sub_exp x = proc_expression x tracker in 
    let (_, sub_exps) = List.map proc_sub_exp temp_exp.expressions |> List.split in
    let flat_subexps = List.flatten sub_exps in

    let result_var = Context.get_new_intermed_temp tracker in
    let inoutlist = [result_var] in
    let load_str_inst = match temp_exp.quasis with
        [(_, x)] | (_, x) :: _ -> 
            let newString = Util.encode_newline x.value.raw in
            let op : Operations_types.load_string = Operations_types.{value = newString} in
            let inst_op = Program_types.Load_string op in
            let inst : Program_types.instruction = Program_types.{
                inouts = inoutlist;
                operation = inst_op;
            } in
            inst
        | _ -> raise (Invalid_argument "Unhandled empty template") in
    (result_var, flat_subexps @ [load_str_inst])

(* Ternary expressions are not handled by Fuzzilli, so convert them to an if-else *)
and proc_exp_conditional (cond_exp: (Loc.t, Loc.t) Flow_ast.Expression.Conditional.t) (tracker: Context.tracker) = 
    let result_temp, zero_temp_inst = build_int_temp tracker 0L in
    let (test_temp, test_inst) = proc_expression cond_exp.test tracker in
    let begin_if_inst : Program_types.instruction = Program_types.{
        inouts = [test_temp];
        operation = Program_types.Begin_if ;
    } in
    let consequent_temp, consequest_inst = proc_expression cond_exp.consequent tracker in
    let consequent_reassing_inst = Program_types.{
        inouts = [result_temp; consequent_temp];
        operation = Program_types.Reassign;
    } in

    let begin_else_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.Begin_else;
    } in
    let alternative_temp, alternative_inst = proc_expression cond_exp.alternate tracker in
    let alternative_reassing_inst : Program_types.instruction = Program_types.{
        inouts = [result_temp; alternative_temp];
        operation = Program_types.Reassign;
    } in
    let end_if_op = Program_types.End_if in 
    let end_if_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = end_if_op;
    } in

    (result_temp, [zero_temp_inst] @ test_inst @ [begin_if_inst] @ consequest_inst @ [consequent_reassing_inst] @ [begin_else_inst] @
        alternative_inst @ [alternative_reassing_inst; end_if_inst])

(* Doesn't do anything with extensions, etc 

class Rectangle {
  constructor(height, width) {
    this.height = height;
    this.width = width;
  }
  calcArea() {
    return this.height * this.width;
  }
}

becomes

function Rectangle(h, w){
  this.height = h;
  this.width = w;
}
var a = Rectangle.prototype;
function getArea(){
  return this.height * this.width;
}
a.getArea = getArea;

then can be used with var foo = new Rectangle(10, 20);
*)

and proc_class_method class_proto_temp tracker (meth: (Loc.t, Loc.t) Flow_ast.Class.Method.t) =
    let (_, unwrapped_meth) = meth in
    let key = unwrapped_meth.key in
    let meth_name = match key with
        Literal (_, l) -> l.raw
        | Identifier (_, i) -> i.name
        | PrivateName (_, p) -> let (_, i) = p.id in
            i.name
        | Computed _ -> raise (Invalid_argument "Unhandled method name in class creation") in
    let (_, func) = unwrapped_meth.value in
    let (meth_temp, meth_inst) = proc_func func tracker false in
    let load_prototype_inst : Program_types.instruction = Program_types.{
        inouts =  [class_proto_temp; meth_temp];
        operation = Program_types.Store_property{property_name = meth_name};
    } in
    (meth_inst @ [load_prototype_inst])

and proc_class (class_decl: (Loc.t, Loc.t) Flow_ast.Class.t) (tracker: Context.tracker) =
    (* Helper methods in collecting the right class methods *)
    (* Filter aid for getting the methods out out of the body. Does not handle properties and private fields currently *)
    let body_elem_is_method (body_elem: (Loc.t, Loc.t) Flow_ast.Class.Body.element) = 
        match body_elem with
            Flow_ast.Class.Body.Method m -> Some m
            | _ -> None in
    (* Filter aid for whether or not a method is a constructor. *)
    let is_constructor (meth: (Loc.t, Loc.t) Flow_ast.Class.Method.t) = 
        let (_, unwrapped_method) = meth in
        match unwrapped_method.kind with
            Flow_ast.Class.Method.Constructor -> true
            | _ -> false in

    (* Find the constructor, and seperate out other methods*)
    let (_, wrapped_body) = class_decl.body in
    let body_elem_list = wrapped_body.body in
    let class_methods = List.filter_map body_elem_is_method body_elem_list in
    let (constructor_list, non_constructor_list) = List.partition is_constructor class_methods in
    if List.length constructor_list != 1 then
        raise (Invalid_argument "Unhandled number of class constructors")
        else ();
    let (_, constructor) = List.hd constructor_list in

    let (_, constructor_func) = constructor.value in 
    let (constructor_temp, constructor_inst) = proc_func constructor_func tracker false  in

    (* Get a reference to the contructors prototype *)
    let prototype_temp = Context.get_new_intermed_temp tracker in
    let load_prototype_inst : Program_types.instruction = Program_types.{
        inouts =  [constructor_temp; prototype_temp];
        operation = Program_types.Load_property{property_name = "prototype"};
    } in

    (* Handle the remaining methods *)
    let other_method_insts = List.map (proc_class_method prototype_temp tracker) non_constructor_list |> List.flatten in

    (match class_decl.id with
        None -> ()
        | Some (_, id) -> 
            Context.add_new_var_identifier_local tracker id.name constructor_temp true);
    (constructor_temp, constructor_inst @ [load_prototype_inst] @ other_method_insts)

and proc_expression (exp: ('M, 'T) Flow_ast.Expression.t) (tracker: Context.tracker) = 
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
        | (Flow_ast.Expression.Class class_exp) ->
            proc_class class_exp tracker
        | (Flow_ast.Expression.Conditional cond_exp) ->
            proc_exp_conditional cond_exp tracker
        | (Flow_ast.Expression.Function func_exp) ->
            proc_func func_exp tracker false
        | (Flow_ast.Expression.Identifier id_val) ->
            proc_exp_id id_val tracker
        | (Flow_ast.Expression.Import _) ->
            (* Fuzzilli doesn't support imports, so effectively nop this out *)
            let result_var = Context.get_new_intermed_temp tracker in
            let inst : Program_types.instruction = Program_types.{
                inouts = [result_var];
                operation = Program_types.Load_undefined;
            } in
            (result_var, [inst])
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
        | (Flow_ast.Expression.TemplateLiteral temp_lit_exp) ->
            proc_exp_temp_lit temp_lit_exp tracker
        | (Flow_ast.Expression.Yield yield_exp) ->
            proc_exp_yield yield_exp tracker
        | x -> raise (Invalid_argument ("Unhandled expression type " ^ (Util.trim_flow_ast_string (Util.print_expression exp))))       

(* Process a single variable declaration *)
and proc_var_dec_declarators (decs : (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.Declarator.t list) (tracker : Context.tracker) (kind: Flow_ast.Statement.VariableDeclaration.kind) =
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
                (* Handle a celaration without a definition *)
                (match kind with
                Flow_ast.Statement.VariableDeclaration.Var | Flow_ast.Statement.VariableDeclaration.Let ->
                    let zero_temp, zero_inst =  build_int_temp tracker 0L in 
                    let intermed = Context.get_new_intermed_temp tracker in 
                    let dup_inst : Program_types.instruction = Program_types.{
                        inouts =  [zero_temp; intermed];
                        operation = Program_types.Dup;
                    } in
                    (intermed, [zero_inst; dup_inst])
                | _ -> raise (Invalid_argument "Empty const declaration"))

            | Some exp -> proc_expression exp tracker in

            (match kind with 
                Flow_ast.Statement.VariableDeclaration.Var ->
                    Context.add_new_var_identifier_local tracker var_name temp_var_num true
                | _ -> Context.add_new_var_identifier_local tracker var_name temp_var_num false);
                    
            new_insts @ (proc_var_dec_declarators tl tracker kind)

(* Processes a variable declaration statement, which can be made up of multiple vars  *)
and proc_var_decl_statement (var_decl: (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.t) (tracker: Context.tracker) =
    let decs = var_decl.declarations in
    let kind = var_decl.kind in
    proc_var_dec_declarators decs tracker kind

and proc_if_statement (if_statement: (Loc.t, Loc.t) Flow_ast.Statement.If.t) (tracker: Context.tracker) =
    let test = if_statement.test in 
    let (test_temp_val, test_inst) = proc_expression test tracker in

    let begin_if_inouts = [test_temp_val] in
    let begin_if_op = Program_types.Begin_if in
    let begin_if_inst : Program_types.instruction = Program_types.{
        inouts = begin_if_inouts;
        operation = begin_if_op;
    } in
    
    Context.push_local_scope tracker;
    let consequent_statements = proc_single_statement if_statement.consequent tracker in
    Context.pop_local_scope tracker;
    (* Fuzzilli requires an else for each if, due to how AbstractInterpreter works*)
    let begin_else_op = Program_types.Begin_else in
    let begin_else_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = begin_else_op;
    } in
    Context.push_local_scope tracker;
    let fin_statement = match if_statement.alternate with
        None -> []
        | Some (_, alt) ->
            let alt_inst = proc_single_statement alt.body tracker in
            alt_inst in
    Context.pop_local_scope tracker;
    let end_if_op = Program_types.End_if in 
    let end_if_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = end_if_op;
    } in
    test_inst @ begin_if_inst :: consequent_statements @ [begin_else_inst] @ fin_statement @ [end_if_inst]    


(* TODO: Improve this. Puts all expressions into a temp, and compares with 0. Could be better*)
and proc_while (while_statement: (Loc.t, Loc.t) Flow_ast.Statement.While.t) (tracker: Context.tracker) = 
    (* Build initial check, put into temp*)
    let test_exp_reg, test_exp_inst = proc_expression while_statement.test tracker in
    let pre_loop_inst = test_exp_inst in

    (* Build begin while *)
    let zero_temp, zero_temp_inst = build_int_temp tracker 0L in
    let begin_while_op = Program_types.Begin_while{comparator = Operations_types.Not_equal} in
    let begin_while_inst : Program_types.instruction = Program_types.{
        inouts =  [test_exp_reg; zero_temp];
        operation = begin_while_op;
    } in
    let begin_loop_inst = zero_temp_inst :: [begin_while_inst] in
    Context.push_local_scope tracker;
    (* Build body *)
    let body_statement = proc_single_statement while_statement.body tracker in
    Context.pop_local_scope tracker;
    (* Reexecute comparison, and load into temp*)
    let test_exp_reg_internal, test_exp_inst_internal = proc_expression while_statement.test tracker in
    let copy_op = Program_types.Reassign in
    let copy_inst : Program_types.instruction = Program_types.{
        inouts = [test_exp_reg; test_exp_reg_internal]; (* In examples, the in var is the one being assigned*)
        operation = copy_op;
    } in
    let re_exec_test_exp = test_exp_inst_internal @ [copy_inst] in

    let end_while_op = Program_types.End_while in
    let end_while_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = end_while_op;
    } in
    pre_loop_inst @ begin_loop_inst @ body_statement @ re_exec_test_exp @ [end_while_inst]

and proc_do_while (do_while_statement: (Loc.t, Loc.t) Flow_ast.Statement.DoWhile.t) (tracker: Context.tracker) =
    (* Build initial check, put into temp*)
    (* let test_exp_reg, test_exp_inst = proc_expression do_while_statement.test tracker in *)
    let zero_temp, zero_temp_inst = build_int_temp tracker 0L in
    let intermed = Context.get_new_intermed_temp tracker in 

    let dup_inst : Program_types.instruction = Program_types.{
        inouts =  [zero_temp; intermed];
        operation = Program_types.Dup;
    } in

    (* Build begin while *)
    let begin_while_op = Program_types.Begin_do_while{comparator = Operations_types.Not_equal} in
    let begin_while_inst : Program_types.instruction = Program_types.{
        inouts =  [intermed; zero_temp];
        operation = begin_while_op;
    } in
    let begin_loop_inst = [begin_while_inst] in
    Context.push_local_scope tracker;
    (* Build body *)
    let body_statement = proc_single_statement do_while_statement.body tracker in
    Context.pop_local_scope tracker;
    (* Execute comparison, and load into temp*)
    let test_exp_reg_internal, test_exp_inst_internal = proc_expression do_while_statement.test tracker in
    let reassign_inst : Program_types.instruction = Program_types.{
        inouts = [intermed; test_exp_reg_internal]; 
        operation = Program_types.Reassign;
    } in
    let re_exec_test_exp = test_exp_inst_internal @ [reassign_inst] in

    let end_while_op = Program_types.End_do_while in
    let end_while_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = end_while_op;
    } in
    [zero_temp_inst; dup_inst] @ begin_loop_inst @ body_statement @ re_exec_test_exp @ [end_while_inst]

    
and proc_try (try_statement: (Loc.t, Loc.t) Flow_ast.Statement.Try.t) (tracker: Context.tracker) = 
    let try_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.Begin_try;
    } in
    Context.push_local_scope tracker;
    let (_, try_block) = try_statement.block in
    let block_inst = proc_statements try_block.body tracker in
    let catch_inst, catch_body_inst = match try_statement.handler with
        None -> raise (Invalid_argument "Empty catch")
        | Some (_, catch_clause) -> 
            let temp = match catch_clause.param with 
                | Some (_, (Flow_ast.Pattern.Identifier var_identifier)) ->
                    let (_, act_name) = var_identifier.name in
                    let intermed_temp = Context.get_new_intermed_temp tracker in
                    Context.add_new_var_identifier_local tracker act_name.name intermed_temp false;
                    intermed_temp
                | _ -> raise (Invalid_argument "Unsupported catch type")
                in
            let (_, catch_cause_block) = catch_clause.body in
            let catch_body_inst = proc_statements catch_cause_block.body tracker in

            let catch_inst : Program_types.instruction = Program_types.{
                inouts = [temp];
                operation = Program_types.Begin_catch;
            } in

            (catch_inst, catch_body_inst)
        in
    let finalizer_inst = match try_statement.finalizer with
        None -> []
        | Some (_, fin_block) -> proc_statements fin_block.body tracker in
    Context.pop_local_scope tracker;
    let end_try_catch_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.End_try_catch;
    } in
    [try_inst] @ block_inst @ [catch_inst] @ catch_body_inst @  [end_try_catch_inst] @ finalizer_inst


and proc_func (func: (Loc.t, Loc.t) Flow_ast.Function.t) (tracker : Context.tracker) (is_arrow: bool)=
    (* Get func name*)
    let func_temp = match func.id with 
        None -> Context.get_new_intermed_temp tracker
        | Some (_, id) ->
            let func_name_string = id.name in
            let temp = Context.get_new_intermed_temp tracker in
            Context.add_new_var_identifier_local tracker func_name_string temp false;
            temp
    in
    Context.push_local_scope tracker;

    (* Process function parameters*)
    let (_, unwrapped_param) = func.params in
    let ids = List.map param_to_id unwrapped_param.params in
    let temp_func x = id_to_func_type x tracker in
    let proced_ids = List.map temp_func ids in
    let temps, types = List.split proced_ids in

    (* Handle optional rest parameters*)
    let rest_temp, rest_type = match unwrapped_param.rest with
        None -> ([],[])
        | Some (_, rest_id) -> 
            let act_id = rest_id.argument in
            let (_, id_string) = match act_id with
                (_, (Flow_ast.Pattern.Identifier x)) -> x.name
                | _ -> raise (Invalid_argument "Unhandled rest temp") in
            let act_id_string = id_string.name in
            let r_temp = Context.get_new_intermed_temp tracker in
            let type_ext = Typesystem_types.{
                properties = [];
                methods = [];
                group = "";
                signature = None;
            } in
            let type_mess : Typesystem_types.type_ = Typesystem_types.{
                definite_type = 2147483648l; (* Ensure this gets updated!!!*)
                possible_type = 2147483648l;
                ext = Extension type_ext;
            } in
            Context.add_new_var_identifier_local tracker act_id_string r_temp false;
            ([r_temp], [type_mess])
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
        definite_type = Int32.shift_left 1l 8;
        possible_type = Int32.shift_left 1l 8;
        ext = Extension type_ext;
    } in

    let func_signature : Typesystem_types.function_signature = Typesystem_types.{
        input_types = all_types;
        output_type = Some output_type;
    } in

    (* Process func body*)
    let func_inst = match func.body with 
        BodyBlock body_block -> 
            let (_, state_block) = body_block in
            proc_statements state_block.body tracker
        | BodyExpression body_exp -> 
            let (_, inst) = proc_expression body_exp tracker in
            inst
    in

    let begin_inst_op, end_inst_op = 
        if is_arrow then
            if func.async then
                let begin_func_op : Operations_types.begin_async_arrow_function_definition
                    = Operations_types.{signature = Some func_signature} in
                let inst_op = Program_types.Begin_async_arrow_function_definition begin_func_op in
                let end_op = Program_types.End_async_arrow_function_definition in
                (inst_op,end_op)
            else
                (* Norm arrow *)
                let begin_func_op : Operations_types.begin_arrow_function_definition
                    = Operations_types.{signature = Some func_signature} in
                let inst_op = Program_types.Begin_arrow_function_definition begin_func_op in
                let end_op = Program_types.End_arrow_function_definition in
                (inst_op,end_op)

        else
            if func.async then
                (* Norm Async*)
                let begin_func_op : Operations_types.begin_async_function_definition
                    = Operations_types.{signature = Some func_signature} in
                let inst_op = Program_types.Begin_async_function_definition begin_func_op in
                let end_op = Program_types.End_async_function_definition in
                (inst_op,end_op)
            else
                if func.generator then
                    (* Generator*)
                    let begin_func_op : Operations_types.begin_generator_function_definition
                        = Operations_types.{signature = Some func_signature} in
                    let inst_op = Program_types.Begin_generator_function_definition begin_func_op in
                    let end_op = Program_types.End_generator_function_definition in
                    (inst_op,end_op)
                else
                    let begin_func_op : Operations_types.begin_plain_function_definition
                        = Operations_types.{signature = Some func_signature} in
                    let inst_op = Program_types.Begin_plain_function_definition begin_func_op in
                    let end_op = Program_types.End_plain_function_definition in
                    (inst_op,end_op)
        in
    let begin_func_inst : Program_types.instruction = Program_types.{
        inouts =  (func_temp :: all_temps);
        operation = begin_inst_op;
    } in

    let end_func_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = end_inst_op;
    } in
    Context.pop_local_scope tracker;

    (func_temp, [begin_func_inst] @ func_inst @ [end_func_inst])

and proc_return (ret_state: (Loc.t, Loc.t) Flow_ast.Statement.Return.t) (tracker: Context.tracker) =
    let inouts, insts = match ret_state.argument with
        None -> 
            let temp, inst = build_int_temp tracker 0L in
            ([temp], [inst])
        | Some exp -> 
            let temp_num, insts = proc_expression exp tracker in
            ([temp_num], insts)
        in
    let return_inst : Program_types.instruction = Program_types.{
        inouts = inouts;
        operation = Program_types.Return;
    } in
    insts @ [return_inst]

and proc_with (with_state: (Loc.t, Loc.t) Flow_ast.Statement.With.t) (tracker: Context.tracker) =
    let with_expression = with_state._object in
    let result_reg, with_insts = proc_expression with_expression tracker in
    let begin_with_inst : Program_types.instruction = Program_types.{
        inouts = [result_reg];
        operation = Program_types.Begin_with;
    } in
    let body_insts = proc_single_statement with_state.body tracker in
    let end_with_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.End_with;
    } in
    with_insts @ [begin_with_inst] @ body_insts @ [end_with_inst]
 
and proc_throw (throw_state: (Loc.t, Loc.t) Flow_ast.Statement.Throw.t) (tracker: Context.tracker) =
    let (temp, inst) = proc_expression throw_state.argument tracker in
    let throw_inst : Program_types.instruction = Program_types.{
        inouts = [temp];
        operation = Program_types.Throw_exception;
    } in
    inst @ [throw_inst]
 
and proc_break = 
    let inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.Break;
        }
    in
    [inst]

and proc_for_in (for_in_state: (Loc.t, Loc.t) Flow_ast.Statement.ForIn.t) (tracker: Context.tracker) =
    
    let (right_temp, right_inst) = proc_expression for_in_state.right tracker in
    Context.push_local_scope tracker;
    let var_id = match for_in_state.left with
        LeftDeclaration (_, d) -> 
            let decs = d.declarations in 
            (match decs with
                [(_, declarator)] -> ( match declarator.id with
                    (_, (Flow_ast.Pattern.Identifier x)) -> x
                    | _ -> raise (Invalid_argument ("Improper declaration in for-in loop")))
                | _ -> raise (Invalid_argument "Improper declaration in for-in loop"))
        | LeftPattern p -> (match p with
            (_, (Flow_ast.Pattern.Identifier id)) -> id
            | _ -> raise (Invalid_argument ("Inproper left pattern in for-in loop"))) in
    let left_temp = Context.get_new_intermed_temp tracker in
    let (_, act_name) = var_id.name in
    Context.add_new_var_identifier_local tracker act_name.name left_temp false;

    let start_for_in : Program_types.instruction = Program_types.{
        inouts =  [right_temp; left_temp];
        operation = Program_types.Begin_for_in;
    } in
    let body_inst = proc_single_statement for_in_state.body tracker in
    let end_for_in : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.End_for_in;
    } in
    Context.pop_local_scope tracker;
    right_inst @ [start_for_in] @ body_inst @ [end_for_in];

and proc_for_of (for_of_state: (Loc.t, Loc.t) Flow_ast.Statement.ForOf.t) (tracker: Context.tracker) = 
    let (right_temp, right_inst) = proc_expression for_of_state.right tracker in
    Context.push_local_scope tracker;
    let var_id = match for_of_state.left with
        LeftDeclaration (_, d) -> 
            let decs = d.declarations in 
            (match decs with
                [(_, declarator)] -> ( match declarator.id with
                    (_, (Flow_ast.Pattern.Identifier x)) -> x
                    | _ -> raise (Invalid_argument ("Improper declaration in for-of loop")))
                | _ -> raise (Invalid_argument "Improper declaration in for-of loop"))
        | LeftPattern p -> (match p with
            (_, (Flow_ast.Pattern.Identifier id)) -> id
            | _ -> raise (Invalid_argument ("Inproper left pattern in for-of loop"))) in
    let left_temp = Context.get_new_intermed_temp tracker in
    let (_, act_name) = var_id.name in
    Context.add_new_var_identifier_local tracker act_name.name left_temp false;

    let start_for_of : Program_types.instruction = Program_types.{
        inouts =  [right_temp; left_temp];
        operation = Program_types.Begin_for_of;
    } in
    let body_inst = proc_single_statement for_of_state.body tracker in

    let end_for_of : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.End_for_of;
    } in
    Context.pop_local_scope tracker;
    right_inst @ [start_for_of] @ body_inst @ [end_for_of];

and proc_for (for_state: (Loc.t, Loc.t) Flow_ast.Statement.For.t) (tracker: Context.tracker) =

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
    Context.push_local_scope tracker;
    (*start while loop*)
    let zero_temp, zero_temp_inst = build_int_temp tracker 0L in
    let begin_while_op = Program_types.Begin_while{comparator = Operations_types.Not_equal} in
    let begin_while_inst : Program_types.instruction = Program_types.{
        inouts =  [test_exp_reg; zero_temp];
        operation = begin_while_op;
    } in
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
    let copy_op = Program_types.Reassign in
    let copy_inst : Program_types.instruction = Program_types.{
        inouts = [test_exp_reg; test_exp_reg_internal];
        operation = copy_op;
    } in
    let re_exec_test_exp = test_exp_inst_internal @ [copy_inst] in

    (* End while*)
    let end_while_op = Program_types.End_while in
    let end_while_inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = end_while_op;
    } in
    Context.pop_local_scope tracker;
    init_inst @ pre_loop_inst @ begin_loop_inst @ body_insts @ update_insts @ re_exec_test_exp @ [end_while_inst]

and proc_continue = 
    let inst : Program_types.instruction = Program_types.{
        inouts = [];
        operation = Program_types.Continue;
        }
    in
    [inst]



and proc_single_statement (statement: (Loc.t, Loc.t) Flow_ast.Statement.t) (tracker: Context.tracker) = 
    match statement with 
        (_, Flow_ast.Statement.Block state_block) -> proc_statements state_block.body tracker
        | (_, Flow_ast.Statement.Break _) -> proc_break
        | (_, Flow_ast.Statement.ClassDeclaration class_decl) -> 
            let (_, insts) = proc_class class_decl tracker in
            insts
        | (_, Flow_ast.Statement.Continue state_continue) -> proc_continue
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
          (* Fuzzilli doesn't support imports. This should effectively replace all imports with placeholder *)
        | (_, Flow_ast.Statement.ImportDeclaration _) -> []
        | (_, Flow_ast.Statement.Return state_return) -> proc_return state_return tracker
        | (_, Flow_ast.Statement.Throw state_throw) -> proc_throw state_throw tracker
        | (_, Flow_ast.Statement.Try state_try) -> proc_try state_try tracker
        | (_ , VariableDeclaration decl) -> proc_var_decl_statement decl tracker
        | (_, Flow_ast.Statement.While state_while) -> proc_while state_while tracker
        | (_, Flow_ast.Statement.With state_with) -> proc_with state_with tracker
        | _ as s -> raise (Invalid_argument (Printf.sprintf "Unhandled statement type %s" (Util.trim_flow_ast_string (Util.print_statement s))))

and proc_statements (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) (var_tracker: Context.tracker) = 
    match statements with
        [] -> []
        | hd :: tl ->
            let new_statement = proc_single_statement hd var_tracker in
            new_statement @ proc_statements tl var_tracker

(* Updates load_from_scope for any items declared later in the program, due to JS having wonky scoping*)
and patch_inst (inst: Program_types.instruction) (tracker: Context.tracker) = 
    let op = inst.operation in
    match op with
        Program_types.Load_from_scope load_scope ->
            (let name = load_scope.id in
            match Context.lookup_var_name tracker name with
                GetFromScope name ->
                    let op : Operations_types.load_from_scope = Operations_types.{id = name} in
                    let inst_op = Program_types.Load_from_scope op in
                    let new_inst : Program_types.instruction = Program_types.{
                        inouts = inst.inouts;
                        operation = inst_op;
                    } in
                    new_inst
                | InScope x -> 
                    let act_name = "v" ^ (Int32.to_string x) in
                    let op : Operations_types.load_from_scope = Operations_types.{id = act_name} in
                    let inst_op = Program_types.Load_from_scope op in
                    let new_inst : Program_types.instruction = Program_types.{
                        inouts = inst.inouts;
                        operation = inst_op;
                    } in
                    new_inst
                | NotFound -> 
                    (*Handle Fuzzilli temps loaded from scope. TODO: Make better/less sketch*)
                    if not (Str.string_match (Str.regexp "v[0-9]+") name 0) && Context.use_placeholder tracker then 
                        (* Load a placeholder so everything runs anyways*)
                        let op : Operations_types.load_builtin = Operations_types.{builtin_name = "placeholder"} in
                        let inst_op = Program_types.Load_builtin op in
                        let new_inst : Program_types.instruction = Program_types.{
                            inouts = inst.inouts;
                            operation = inst_op;
                        } in
                        if Context.should_emit_builtins tracker then
                            print_endline ("Builtin:" ^ name) else ();
                        new_inst
                    else 
                        inst)
        | _ -> inst

let flow_ast_to_inst_list (prog: (Loc.t, Loc.t) Flow_ast.Program.t) emit_builtins include_v8_natives use_placeholder = 
    let init_var_tracker = Context.init_tracker emit_builtins include_v8_natives use_placeholder in
    let (loc_type, prog_t) = prog in
    let statements = prog_t.statements in 
    let proced_statements = proc_statements statements init_var_tracker in
    let fix_scope_func i = patch_inst i init_var_tracker in
    let fixed_load_scope = List.map fix_scope_func proced_statements in
    fixed_load_scope
