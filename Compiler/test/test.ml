let () = Alcotest.run "fuzzilli_compiler_tests" [
  "tests", [
    (* Basic Straightline Code *)
    Alcotest.test_case "array_decl" `Quick Array_decl.test;
    Alcotest.test_case "array_hole" `Quick Array_hole.test;
    Alcotest.test_case "basic_compare_test" `Quick Basic_compare_test.test;
    Alcotest.test_case "binary_ops" `Quick Binary_ops.test;
    Alcotest.test_case "bitwise_ops" `Quick Bitwise_ops.test;
    Alcotest.test_case "exp_statement" `Quick Exp_statement.test;
    Alcotest.test_case "in_test" `Quick In_test.test;
    Alcotest.test_case "instance_of" `Quick Instance_of.test;
    Alcotest.test_case "load_array_index" `Quick Load_array_index.test;
    Alcotest.test_case "load_bigint" `Quick Load_bigint.test;
    Alcotest.test_case "load_bool" `Quick Load_bool.test;
    Alcotest.test_case "load_float" `Quick Load_float.test;
    Alcotest.test_case "load_infinity" `Quick Load_infinity.test;
    Alcotest.test_case "load_null" `Quick Load_null.test;
    Alcotest.test_case "load_property" `Quick Load_property.test;
    Alcotest.test_case "load_regex" `Quick Load_regex.test;
    Alcotest.test_case "logical_ops" `Quick Logical_ops.test;
    Alcotest.test_case "new" `Quick New.test;
    Alcotest.test_case "object_creation" `Quick Object_creation.test;
    Alcotest.test_case "prog_10" `Quick Prog_10.test;
    Alcotest.test_case "prog_1007" `Quick Prog_1007.test;
    Alcotest.test_case "prop_name_assignment" `Quick Prop_name_assignment.test;
    Alcotest.test_case "single_constant" `Quick Single_constant.test;
    Alcotest.test_case "single_let" `Quick Single_let.test;
    Alcotest.test_case "single_string_literal" `Quick Single_string_literal.test;
    Alcotest.test_case "spread_object" `Quick Spread_object.test;
    Alcotest.test_case "store_property_sugared" `Quick Store_property_sugared.test;
    Alcotest.test_case "sugared_assignment" `Quick Sugared_assignment.test;
    Alcotest.test_case "ternary" `Quick Ternary.test;
    Alcotest.test_case "this" `Quick This.test;
    Alcotest.test_case "throw" `Quick Throw.test;
    Alcotest.test_case "typeof" `Quick Typeof.test;
    Alcotest.test_case "unary_minus" `Quick Unary_minus.test;
    Alcotest.test_case "unary_ops" `Quick Unary_ops.test;
    Alcotest.test_case "undefined" `Quick Undefined.test;
    Alcotest.test_case "update" `Quick Update.test;
    Alcotest.test_case "void" `Quick Void.test;
  
    (* Control Flow*)
    Alcotest.test_case "basic_break" `Quick Basic_break.test;
    Alcotest.test_case "basic_for" `Quick Basic_for.test;
    Alcotest.test_case "basic_while" `Quick Basic_while.test;
    Alcotest.test_case "basic_continue" `Quick Basic_continue.test;
    Alcotest.test_case "do_while" `Quick Do_while.test;
    Alcotest.test_case "for_in" `Quick For_in.test;
    Alcotest.test_case "for_in_scope2" `Quick For_in_scope2.test;
    Alcotest.test_case "for_in_scoping" `Quick For_in_scoping.test;
    Alcotest.test_case "for_of" `Quick For_of.test;
    Alcotest.test_case "if_else" `Quick If_else.test;
    Alcotest.test_case "lone_if" `Quick Lone_if.test;
    Alcotest.test_case "with" `Quick With.test;
    Alcotest.test_case "with_load_scope" `Quick With_load_scope.test;

    (* Functions*)
    Alcotest.test_case "basic_func_call" `Quick Basic_func_call.test;
    Alcotest.test_case "basic_func_ret" `Quick Basic_func_ret.test;
    Alcotest.test_case "func_dec_order" `Quick Func_dec_order.test;
    Alcotest.test_case "func_call_with_spread" `Quick Func_call_with_spread.test;
    Alcotest.test_case "func_exp_test" `Quick Func_exp_test.test;
    Alcotest.test_case "func_param_scoping" `Quick Func_param_scoping.test;
    Alcotest.test_case "varied_func_types" `Quick Varied_func_types.test;

    (* Array Operations  *)
    Alcotest.test_case "array_assign" `Quick Array_assign.test;
    Alcotest.test_case "array_assign_sugared" `Quick Array_assign_sugared.test;
    Alcotest.test_case "array_spread" `Quick Array_spread.test;
    Alcotest.test_case "create_array" `Quick Create_array.test;
    Alcotest.test_case "del_test" `Quick Del_test.test;

    (* Variable Hoisting *)
    Alcotest.test_case "var_hoisting_1" `Quick Var_hoisting_1.test;
    Alcotest.test_case "var_hoisting_2" `Quick Var_hoisting_2.test;
    Alcotest.test_case "var_hoisting_3" `Quick Var_hoisting_3.test;
    Alcotest.test_case "var_hoisting_shadow" `Quick Var_hoisting_shadow.test;

    (* Other *)
    Alcotest.test_case "empty_assignment_scope" `Quick Empty_assignment_scope.test;
    Alcotest.test_case "v8_natives" `Quick V8_natives.test;

  ];
]