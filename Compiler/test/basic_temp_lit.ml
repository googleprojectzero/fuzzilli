open Program_types

let input = 
"source = `#_\\u200C`;"

let correct = [
    {
        inouts = [0l];
        operation = Load_string({value = "#_\\u200C"});
    };
    {
        inouts = [0l; 1l];
        operation = Dup;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_temp_lit" correct prog 