open Program_types

let input = 
"for (var x in x) {
  function x() {
    ;
  }
  let a = x();
}
"

let correct = [
    {
        inouts = [0l];
        operation = Load_builtin {builtin_name = "placeholder"};
    };
    {
        inouts = [0l; 1l];
        operation = Begin_for_in;
    };
    {
        inouts = [2l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [2l; 3l];
        operation = Call_function;
    };
    {
        inouts = [];
        operation = End_for_in;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_in_scope2" correct prog
    