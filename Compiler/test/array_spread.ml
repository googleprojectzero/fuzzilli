open Program_types

let input = 
"const v0 = 0;
const v1 = [v0,...v0,];"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [0l; 0l; 1l];
        operation = Create_array_with_spread {spreads = [false; true]};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "array_spread" correct prog 