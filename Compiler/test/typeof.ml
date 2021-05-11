open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 12;
const v2 = typeof v0;"

let correct = 
    let builder = init_builder false false false in
    let int, load_int = build_load_integer 12L builder in
    let _, typeof_inst = build_typeof_op int builder in
    let res = [load_int; typeof_inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "typeof" correct prog 