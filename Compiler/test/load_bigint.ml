open Program_types

let input = 
"const v0 = 9007199254740991n;"

let correct = [
    {
        inouts = [0l];
        operation = Load_big_int {value = 9007199254740991L};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "load_bigint" correct prog 