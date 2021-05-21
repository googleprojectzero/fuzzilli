let do_compile infile outfile ~(emit_ast : bool) ~(emit_builtins: bool) ~(v8_natives: bool) ~(use_placeholder: bool)=
    try
      let file_string = Core.In_channel.read_all infile in
      let (prog, err) = Compiler.string_to_flow_ast file_string in
      let (loc_type, a) = prog in
      let prog_string = Compiler.print_ast_statement_list a.statements in
      if emit_ast then    
          print_endline ("Provided AST: \n" ^ prog_string ^ "\n")
          else ();
      let inst_list = Compiler.flow_ast_to_inst_list prog emit_builtins v8_natives use_placeholder in
      let prog = Compiler.inst_list_to_prog inst_list in
        Compiler.write_proto_obj_to_file prog outfile
    with 
    Invalid_argument x -> print_endline ("Invalid arg: " ^ x)
    | Parse_error.Error y -> 
        let _, err_list = List.split y in
        Printf.printf "Compiler Error %s\n" (Parse_error.PP.error (List.hd err_list))
    | y -> print_endline ("Other compiler error" ^ (Core.Exn.to_string y))

let command = 
  let open Core in
  Command.basic
    ~summary:"Compile a JS source file to Fuzzil"
    Command.Let_syntax.(
      let%map_open
        infile = (anon ("infile" %: Filename.arg_type))
        and outfile = (anon ("outfile" %: string))
        and emit_ast = flag "-ast" no_arg ~doc: "Print the Flow_ast"
        and emit_builtins = flag "-builtins" no_arg ~doc: "Print all builtins encountered"
        and v8_natives = flag "-v8-natives" no_arg ~doc: "Include v8 natives, as funtions without the leading %. Requires the builtins be included in the fuzzilli profile for v8. Currently only uses a hardcoded list in util.ml"
        and use_placeholder = flag "-use-placeholder" no_arg ~doc: "Replaces each unknown builtin with 'placeholder'."
    in
    fun () -> do_compile infile outfile ~emit_ast ~emit_builtins ~v8_natives ~use_placeholder)
   
let () = 
  Core.Command.run command
