open Program_types

let input = 
"const v0 = 20.15;"

let correct = [
    {
        inouts = [0l];
        operation = Load_float {value = 20.15};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "load_float" correct prog 