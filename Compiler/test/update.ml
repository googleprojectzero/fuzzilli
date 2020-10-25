open Program_types

let input = 
"const v0 = 5;
v0++;
--v0;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [0l; 1l];
        operation = Unary_operation {op = Post_inc};
    };
    {
        inouts = [0l; 2l];
        operation = Unary_operation {op = Pre_dec};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "update" correct prog 