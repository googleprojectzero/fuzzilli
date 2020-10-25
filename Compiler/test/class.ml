open Program_types

let input = 
"class Rectangle {
  constructor(height, width) {
    this.height = height;
    this.width = width;
  }
  calcArea() {
    return this.height * this.width;
  }
}"

let correct = [
    {
        inouts = [0l; 1l; 2l ];
        operation = Begin_plain_function_definition({
            signature = Some({                                                           
                input_types = [{
                        definite_type = 4095l;
                        possible_type = 4095l;
                        ext = Extension({
                            properties = [];
                            methods = [];
                            group = "";
                            signature = None;
                        });
                    };
                    {
                        definite_type = 4095l;
                        possible_type = 4095l;
                        ext = Extension({
                            properties = [];
                            methods = [];
                            group = "";
                        signature = None;
                        });
                    }
                ];
                output_type = Some({
                    definite_type = 256l;
                    possible_type = 256l;
                    ext = Extension({                
                        properties = [];
                        methods = [];
                        group = "";
                        signature = None;
                    });
                });
            });
        });
    };
    {
        inouts = [3l];
        operation = Load_builtin({builtin_name = "this";});
    };
    {
        inouts = [3l; 1l];
        operation = Store_property({property_name = "height";});
    };
    {
        inouts = [4l];
        operation = Load_builtin({builtin_name = "this";});
    };
    {
        inouts = [4l; 2l];
        operation = Store_property({property_name = "width";});
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [0l; 5l];
        operation = Load_property({property_name = "prototype";});
    };
    {
        inouts = [6l];
        operation = Begin_plain_function_definition({
            signature = Some({
                input_types = [];
                output_type = Some({
                    definite_type = 256l;
                    possible_type = 256l;
                    ext = Extension({
                        properties = [];
                        methods = [];
                        group = "";
                        signature = None;
                    });
                });
            });
        });
    };
    {
        inouts = [7l];
        operation = Load_builtin({builtin_name = "this";});
    };
    {
        inouts = [7l; 8l];
        operation = Load_property({property_name = "height";});
    };
    {
        inouts = [9l];
        operation = Load_builtin({builtin_name = "this";});
    };
    {
        inouts = [9l; 10l];
        operation = Load_property({property_name = "width";});
    };
    {
        inouts = [8l; 10l; 11l];
        operation = Binary_operation({op = Mul;});
    };
    {
        inouts = [11l];
        operation = Return;
    };
    {
        inouts = [];
        operation = End_plain_function_definition;
    };
    {
        inouts = [5l; 6l];
        operation = Store_property({property_name = "calcArea";});
    }]

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "class" correct prog