open Program_types

let input = 
"let v0 = 0;
const v1 = 20;
while(v0 <= v1){
    v0 += 1;
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 20L};
    };
    {
        inouts = [0l; 1l; 2l];
        operation = Compare {op = Less_than_or_equal};
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [2l; 3l];
        operation = Begin_while {comparator = Not_equal};
    };
    {
        inouts = [4l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [0l; 4l; 5l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [0l; 5l];
        operation = Reassign;
    };
    {
        inouts = [0l; 1l; 6l];
        operation = Compare {op = Less_than_or_equal};
    };
    {
        inouts = [2l; 6l];
        operation = Reassign;
    };
    {
        inouts = [];
        operation = End_while;
    };
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "basic_while" correct prog 