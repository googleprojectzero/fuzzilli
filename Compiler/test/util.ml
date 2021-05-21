let inst_testable = Alcotest.testable Compiler.pp_instruction (=)

let type_ext = Typesystem_types.{
    properties = [];
    methods = [];
    group = "";
    signature = None;
}


let default_input_type = Typesystem_types.{
    definite_type = 4095l;
    possible_type = 4095l;
    ext = Extension type_ext
}

let spread_input_type = Typesystem_types.{
    definite_type = 2147483648l;
    possible_type = 2147483648l;
    ext = Extension type_ext
}

let default_output_type = Typesystem_types.{
    definite_type = Int32.shift_left 1l 8;
    possible_type = Int32.shift_left 1l 8;
    ext = Extension type_ext
}
