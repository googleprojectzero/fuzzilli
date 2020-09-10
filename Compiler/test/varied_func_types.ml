open Program_types

let input = 
"const v0 = [1,2,3];
const v1 = (v0) => {
    return v0 + 4;
};
async function v2(v0) {
    return v0 + 5;
}
const v3 = async (v0) => {
    return v0 + 5;
}
function * v4(v0) {
    yield v0 + 6;
}
function * v5(v0) {
    yield *v0;
}"

let correct = [
    {
        inouts = [0l];
        operation = Load_integer {value = 1L};
    };
    {
        inouts = [1l];
        operation = Load_integer {value = 2L};
    };
    {
        inouts = [2l];
        operation = Load_integer {value = 3L};
    };
    {
        inouts = [0l; 1l; 2l; 3l];
        operation = Create_array;
    };
    {
        inouts = [4l; 5l];
        operation = Begin_arrow_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; ];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [6l];
        operation = Load_integer {value = 4L};
    };
    {
        inouts = [5l; 6l; 7l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [7l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_arrow_function_definition;
    };
    {
        inouts = [8l; 9l];
        operation = Begin_async_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; ];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [10l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [9l; 10l; 11l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [11l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_async_function_definition;
    };

    {
        inouts = [12l; 13l];
        operation = Begin_async_arrow_function_definition {
            signature = Some {
                input_types = [Util.default_input_type];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [14l];
        operation = Load_integer {value = 5L};
    };
    {
        inouts = [13l; 14l; 15l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [15l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_async_arrow_function_definition;
    };
    
    {
        inouts = [16l; 17l];
        operation = Begin_generator_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; ];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [18l];
        operation = Load_integer {value = 6L};
    };
    {
        inouts = [17l; 18l; 19l];
        operation = Binary_operation {op = Add};
    };
    {
        inouts = [19l];
        operation = Yield;
    };
    {
        inouts = [];
        operation = End_generator_function_definition;
    };

    {
        inouts = [20l; 21l];
        operation = Begin_generator_function_definition {
            signature = Some {
                input_types = [Util.default_input_type; ];
                output_type = Some Util.default_output_type;
            };
        };
    };
    {
        inouts = [21l];
        operation = Yield_each;
    };
    {
        inouts = [];
        operation = End_generator_function_definition;
    };

]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false in
    Alcotest.(check (list Util.inst_testable)) "varied_func_types" correct prog 