open Program_types

let input = 
"const v0 = true;
const v1 = false;"

let correct = [
    {
        inouts = [0l];
        operation = Load_boolean {value = true};
    };
    {
        inouts = [1l];
        operation = Load_boolean {value = false};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "load_bool" correct prog 