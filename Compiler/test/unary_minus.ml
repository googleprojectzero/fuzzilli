open Program_types

let input = 
"const v2 = -256;"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 256L};
    };
    {
        inouts = [0l; 1l];
        operation = Unary_operation {op = Minus};
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "unary_minus" correct prog 