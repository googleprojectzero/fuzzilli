open Program_types

let input = 
"const v0 = 3072397020;
const v1 = [v0,v0,v0,v0,v0];
for (const v2 of v1){
    placeholder(v2);
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 3072397020L};
    };
    {
        inouts = [0l; 0l; 0l; 0l; 0l; 1l];
        operation = Create_array;
    };
    {
        inouts = [1l; 2l];
        operation = Begin_for_of;
    };
    {
        inouts = [3l];
        operation = Load_builtin {builtin_name = "placeholder"};
    };
    {
        inouts = [3l; 2l; 4l];
        operation = Call_function;
    };
    {
        inouts = [];
        operation = End_for_of;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "for_of" correct prog
    