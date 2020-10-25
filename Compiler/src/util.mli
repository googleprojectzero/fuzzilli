val string_to_flow_ast : string -> (Loc.t, Loc.t) Flow_ast.Program.t * (Loc.t * Parse_error.t) list

val encode_newline : string -> string

val convert_comp_op : Flow_ast.Expression.Binary.operator -> Operations_types.compare

val is_compare_op : Flow_ast.Expression.Binary.operator -> bool

val print_statement : ('M, 'T) Flow_ast.Statement.t -> string

val print_unary_expression : ('M, 'T) Flow_ast.Expression.Unary.t -> string

val print_unary_operator : Flow_ast.Expression.Unary.operator -> string

val print_binary_operator : Flow_ast.Expression.Binary.operator -> string

val print_logical_operator : Flow_ast.Expression.Logical.operator -> string

val print_expression : ('M, 'T) Flow_ast.Expression.t -> string

val print_statement_list: (('M, 'T) Flow_ast.Statement.t) list -> string

val print_literal: ('T) Flow_ast.Literal.t -> string

val trim_flow_ast_string : string -> string

val write_proto_obj_to_file : Program_types.program -> string -> unit

val inst_list_to_prog : Program_types.instruction list -> Program_types.program

val regex_flag_str_to_int : string -> int32

val is_supported_builtin : string -> bool -> bool