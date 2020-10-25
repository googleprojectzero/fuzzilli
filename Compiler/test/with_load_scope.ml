open Program_types

let input = 
"const v9 = {__proto__:0,length:0};
with (v9) {
    const v11 = length;
}
"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Create_object {property_names = ["__proto__"; "length"]};
    };
    {
        inouts = [2l];
        operation = Begin_with;
    };
    {
        inouts = [3l];
        operation = Load_builtin {builtin_name = "placeholder"};
    };
    {
        inouts = [];
        operation = End_with;
    }

]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "with" correct prog 