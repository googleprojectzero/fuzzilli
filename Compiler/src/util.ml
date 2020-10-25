
let remove_percent input = 
  Str.global_replace (Str.regexp_string "%") "" input 

let encode_newline input =
  Str.global_replace (Str.regexp_string "\n") "\\n" input 

(* Only bother filtering the ones we care about
   TODO: Optimize this list*)
let chrome_builtins = [
  "%PrepareFunctionForOptimization";
  "%OptimizeFunctionOnNextCall";
  "%NeverOptimizeFunction";
  "%DeoptimizeFunction";
  "%DeoptimizeNow";
  "%OptimizeOsr";
  "%RemoveArrayHoles";
  "%CompileLazy";
  "%CompileForOnStackReplacement";
  "%OptimizeObjectForAddingMultipleProperties";
  "%CompileOptimized_Concurrent";
  "%CompileOptimized_NotConcurrent";
]


let modify_chrome_builtins s = 
  let proc whole part = Str.global_replace (Str.regexp_string part) (remove_percent part) whole in
  List.fold_left proc s chrome_builtins  

let string_to_flow_ast str =
  let processed = modify_chrome_builtins str in
  Parser_flow.program processed

let convert_comp_op (op: Flow_ast.Expression.Binary.operator) =
    match op with
        Equal -> Operations_types.{op = Operations_types.Equal}
        | NotEqual -> Operations_types.{op = Operations_types.Not_equal}
        | StrictEqual -> Operations_types.{op = Operations_types.Strict_equal}
        | StrictNotEqual -> Operations_types.{op = Operations_types.Strict_not_equal}
        | LessThan -> Operations_types.{op = Operations_types.Less_than}
        | LessThanEqual -> Operations_types.{op = Operations_types.Less_than_or_equal}
        | GreaterThan -> Operations_types.{op = Operations_types.Greater_than}
        | GreaterThanEqual -> Operations_types.{op = Operations_types.Greater_than_or_equal}
        | _ -> raise (Invalid_argument "Tried to convert invalid comp op")
        
let is_compare_op (op: Flow_ast.Expression.Binary.operator) =
  match op with
    Equal | NotEqual | StrictEqual | StrictNotEqual | LessThan | LessThanEqual | GreaterThan | GreaterThanEqual -> true
    | _ -> false

let paramaterized_type_placeholder a b = ()

let print_unary_expression s = 
  Flow_ast.Expression.Unary.show paramaterized_type_placeholder paramaterized_type_placeholder s ^ "\n"

let print_unary_operator v =
  match v with
    Flow_ast.Expression.Unary.Minus -> "Minus"
    | Flow_ast.Expression.Unary.Plus -> "Plus"
    | Flow_ast.Expression.Unary.Not -> "Not"
    | Flow_ast.Expression.Unary.BitNot -> "BitNot"
    | Flow_ast.Expression.Unary.Typeof -> "Typeof"
    | Flow_ast.Expression.Unary.Void -> "Void"
    | Flow_ast.Expression.Unary.Delete -> "Delete"
    | Flow_ast.Expression.Unary.Await -> "Await"

let print_binary_operator s = 
  Flow_ast.Expression.Binary.show_operator s ^ "\n"

let print_logical_operator s =
  Flow_ast.Expression.Logical.show_operator s ^ "\n"

let print_statement s =
  Flow_ast.Statement.show paramaterized_type_placeholder paramaterized_type_placeholder s ^ "\n"

let print_expression s =
  Flow_ast.Expression.show paramaterized_type_placeholder paramaterized_type_placeholder s ^ "\n"

let print_literal s = 
  Flow_ast.Literal.show paramaterized_type_placeholder s ^ "\n"

(* Gets just the type from a Flow_ast.__TYPE___.show statement. For use in building information on which operations the compiler doesn't handle yet*)
let trim_flow_ast_string s = 
  let split_string = Core.String.split_lines s in
  let res = Core.List.nth split_string 1 in
  match res with
    None -> s
    | Some a -> a

let write_proto_obj_to_file proto_obj file = 
  let encoder = Pbrt.Encoder.create () in 
  Program_pb.encode_program proto_obj encoder;
  let oc = Core.Out_channel.create file in 
  Core.Out_channel.output_bytes oc (Pbrt.Encoder.to_bytes encoder);
  Core.Out_channel.close oc

let rec print_statement_list l = 
  match l with
    | [] -> ""
    | x :: xs -> print_statement x ^ print_statement_list xs

let regex_flag_str_to_int s =
  let open Core in
  if String.contains s 'i' then (Int32.shift_left 1l 0) else 0l
  |> Int32.(lor) (if String.contains s 'g' then (Int32.shift_left 1l 1) else 0l)
  |> Int32.(lor) (if String.contains s 'm' then (Int32.shift_left 1l 2) else 0l)
  |> Int32.(lor) (if String.contains s 's' then (Int32.shift_left 1l 3) else 0l)
  |> Int32.(lor) (if String.contains s 'u' then (Int32.shift_left 1l 4) else 0l)
  |> Int32.(lor) (if String.contains s 'y' then (Int32.shift_left 1l 5) else 0l)

let gen_uuid = 
  let rand_chr _ = Char.chr (Random.int 256) in
  Bytes.init 16 rand_chr

let inst_list_to_prog inst_list = 
  Program_types.{
      uuid = gen_uuid;
      code = inst_list;
      types = [];
      type_collection_status = Program_types.Notattempted;
      comments = [];
      parent = None;
  }

let builtins = ["Reflect";
"Promise";
"Infinity";
"isNaN";
"Int16Array";
"Symbol";
"Object";
"Int32Array";
"Map";
"WeakMap";
"isFinite";
"parseInt";
"Math";
"Int8Array";
"Set";
"Function";
"RegExp";
"Uint32Array";
"JSON";
"String";
"parseFloat";
"WeakSet";
"Uint8Array";
"BigInt";
"undefined";
"NaN";
"Number";
"Proxy";
"ArrayBuffer";
"gc";
"Float32Array";
"eval";
"Float64Array";
"DataView";
"Uint16Array";
"Array";
"this";
"arguments";
"Uint8ClampedArray";
"Boolean";
]

let chrome_natives = [
  "PrepareFunctionForOptimization";
  "OptimizeFunctionOnNextCall";
  "NeverOptimizeFunction";
  "DeoptimizeFunction";
  "DeoptimizeNow";
  "OptimizeOsr";
]

let is_supported_builtin b is_chrome =
  let norm = List.mem b builtins in
  let in_chrome = List.mem b chrome_natives in
  if is_chrome then
    norm || in_chrome
  else 
    norm