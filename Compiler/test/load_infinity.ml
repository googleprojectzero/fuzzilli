open Program_types

let input = 
"const v0 = Infinity;"

let correct = [
    {
        inouts = [0l];
        operation = Load_float {value = infinity};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "load_infinity" correct prog 