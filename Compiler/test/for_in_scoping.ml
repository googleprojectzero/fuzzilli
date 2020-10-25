open Program_types

let input = 
"i = \"ABC\"
for (i in [0, 0]) {
}
b = i + \"D\";"

let correct = [
    {
        inouts = [0l];
        operation = Load_string {value = "ABC"};
    };
    {
        inouts = [0l; 1l];
        operation = Dup;
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 0L}
    };
    {
        inouts = [3l];
        operation = Load_integer {value = 0L}
    };
    {
        inouts = [2l; 3l; 4l];
        operation = Create_array;
    };
    {
        inouts = [4l; 5l];
        operation = Begin_for_in;
    };
    {
        inouts = [];
        operation = End_for_in;
    };
    {
        inouts = [6l];
        operation = Load_string {value = "D"};
    };
    {
        inouts = [1l; 6l; 7l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [7l; 8l];
        operation = Dup;
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false in
    Alcotest.(check (list Util.inst_testable)) "for_in_scoping" correct prog
    