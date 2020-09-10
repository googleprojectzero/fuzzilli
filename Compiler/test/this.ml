open Program_types

let input = 
"const v0 = this"

let correct = [
    {
        inouts = [0l];
        operation = Load_builtin {builtin_name = "this"};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "this" correct prog 