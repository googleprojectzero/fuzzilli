open Core

(* Keeps a mapping of ids to temps *)
type temp_map_t = (string, int32, String.comparator_witness) Map.t

(* Keeps a mapping of ids that are still visible in Javascipt, but that Fuzzilli considers out of scope.
Used to determine if var should be loaded from scope, rather than accessed as a temp *)
type var_scope_map_t = (string, string, String.comparator_witness) Map.t

type tracker = 
    { mutable next_index : int32; 
      mutable local_maps : temp_map_t list;
      mutable var_scope_map : var_scope_map_t;
      emit_builtins : bool;
      include_v8_natives : bool;
    }

type lookup_result = InScope of int32
    | GetFromScope of string
    | NotFound

let init_tracker emit_builtins include_v8_natives = {
    next_index = 0l;
    local_maps = [Map.empty (module String)];
    var_scope_map = Map.empty (module String);
    emit_builtins = emit_builtins;
    include_v8_natives = include_v8_natives
    }

let get_new_intermed_temp tracker = 
    let ret_index = tracker.next_index in
    tracker.next_index <- Base.Int32.(+) tracker.next_index 1l;
    ret_index

let add_new_var_identifier_local tracker name num glob_vis =
    let curr_local_map, rest_maps  = match tracker.local_maps with
        [] -> raise (Invalid_argument "Empty local scopes")
        | [x] -> x, []
        | x :: tl -> x, tl 
        in
    let new_map = Map.update curr_local_map name (fun _ -> num) in
    tracker.local_maps <- new_map :: rest_maps;
    if glob_vis then
        let fuzzilli_name_string = "v" ^ (Int32.to_string num) in
        let new_var_map = Map.update tracker.var_scope_map name (fun _ -> fuzzilli_name_string) in
        tracker.var_scope_map <- new_var_map
    else ()


let push_local_scope tracker =
    let new_map = Map.empty (module String) in
    tracker.local_maps <- new_map :: tracker.local_maps
    
let pop_local_scope tracker =
    match (List.tl tracker.local_maps) with
        Some x -> tracker.local_maps <- x
        | None -> raise (Invalid_argument "Tried to pop empty local scope")

let update_map m (i:(int32 * string) option) = 
    match i with
        Some (temp,name ) -> Map.update m name (fun _ -> temp)
        | None -> m

let should_emit_builtins tracker =
    tracker.emit_builtins

let rec check_local_maps map_list name =
    match map_list with
    (hd :: tl) -> (match Map.find hd name with
        Some x -> Some x
        | None -> check_local_maps tl name)
    | [] -> None

(* Fist looks through the local maps in appropriate order, then checks globals,
and then items declared as 'var' but out of fuzzilli scope *)
let lookup_var_name tracker name = 
    let local_map_res = check_local_maps tracker.local_maps name in
    match local_map_res with 
    Some x -> InScope x
    | None -> match Map.find tracker.var_scope_map name with
        Some s -> GetFromScope s
        | None -> NotFound

let include_v8_natives tracker = 
    tracker.include_v8_natives