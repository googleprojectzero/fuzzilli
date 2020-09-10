open Program_types

(* Note: this produces compiler warnings, but seems to work fine *)
let input = 
"const v0 = /\w+\s/i;
const v1 = /\w+\s/g;
const v2 = /\w+\s/m;
const v3 = /\w+\s/s;
const v4 = /\w+\s/u;
const v5 = /\w+\s/y;"

let correct = [
    {
        inouts = [0l];
        operation = Load_reg_exp {value = "\\w+\\s"; flags = 1l};
    };
    {
        inouts = [1l];
        operation = Load_reg_exp {value = "\\w+\\s"; flags = 2l};
    };
    {
        inouts = [2l];
        operation = Load_reg_exp {value = "\\w+\\s"; flags = 4l};
    };
    {
        inouts = [3l];
        operation = Load_reg_exp {value = "\\w+\\s"; flags = 8l};
    };
    {
        inouts = [4l];
        operation = Load_reg_exp {value = "\\w+\\s"; flags = 16l};
    };
    {
        inouts = [5l];
        operation = Load_reg_exp {value = "\\w+\\s"; flags = 32l};
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "load_regex" correct prog 