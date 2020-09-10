open Program_types

let input = 
"function test(v0, ...v101){
    return v0 + v101[0];
}
const v5 = [0,1];
const v17 = test(10,...v5);
"

let correct = [
    {
        inouts = [0l; 1l; 2l];
        operation = Begin_plain_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; Util.spread_input_type];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [2l; 3l];
        operation = Load_element {index = 0L};
    };
    {
        inouts = [1l; 3l; 4l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [4l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [5l];
        operation = Load_integer {value = 0L};
    };
    {
        inouts = [6l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [5l; 6l; 7l];
        operation = Create_array;
    };
    {
        inouts = [8l];
        operation = Load_integer {value = 10L};
    };
    {
        inouts = [0l; 8l; 7l; 9l];
        operation = Call_function_with_spread {spreads = [false; true]}
    }
]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "func_call_with_spread" correct prog 