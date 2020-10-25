open Program_types

let input = 
"const v1 = new Uint8Array();
const v5 = new Float32Array(12);"

let correct = [
    {
        inouts = [0l];
        operation = Load_builtin {builtin_name = "Uint8Array"};
    };
    {
        inouts = [0l; 1l];
        operation = Construct;
    };
    {
        inouts = [2l];
        operation = Load_builtin {builtin_name = "Float32Array"};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 12L};
    };
    {
        inouts = [2l; 3l; 4l];
        operation = Construct;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "new_test" correct prog 