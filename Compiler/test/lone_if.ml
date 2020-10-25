open Program_types

let input = 
"const v0 = 12;
if(v0){
    let v1 = 12;
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [0l];
        operation = Begin_if;
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [];
        operation = Begin_else;
    };
    {
        inouts = [];
        operation = End_if;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "lone_if" correct prog 