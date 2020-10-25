open Program_types

let input = 
"function foo() {
    var x;
    while (x = 0) {
        x = 1;
    }
}
foo();
"

let correct = [
    {
        inouts = [0l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l; 2l];
        operation = Dup;
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [2l; 3l];
        operation = Reassign;
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [2l; 4l];
        operation = Begin_while {comparator = Not_equal};
    };
    {
        inouts = [5l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [2l; 5l];
        operation = Reassign;
    };
    {
        inouts = [6l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [2l; 6l];
        operation = Reassign;
    };
    {
        inouts = [2l; 2l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = End_while;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [0l; 7l];
        operation = Call_function;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "empty_assignment_scope" correct prog
    