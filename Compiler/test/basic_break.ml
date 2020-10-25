open Program_types

let input = 
"const v0 = 1;
while(v0){
    break;
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [0l; 1l];
        operation = Begin_while {comparator = Not_equal};
    };
    {
        inouts = [];
        operation = Break;
    };
    {
        inouts = [0l; 0l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = End_while;
    };


]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "basic_break" correct prog 