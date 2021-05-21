[@@@ocaml.warning "-27-30-39"]

type type__mutable = {
  mutable definite_type : int32;
  mutable possible_type : int32;
  mutable ext : Typesystem_types.type_ext;
}

let default_type__mutable () : type__mutable = {
  definite_type = 0l;
  possible_type = 0l;
  ext = Typesystem_types.Extension_idx (0l);
}

type type_extension_mutable = {
  mutable properties : string list;
  mutable methods : string list;
  mutable group : string;
  mutable signature : Typesystem_types.function_signature option;
}

let default_type_extension_mutable () : type_extension_mutable = {
  properties = [];
  methods = [];
  group = "";
  signature = None;
}

type function_signature_mutable = {
  mutable input_types : Typesystem_types.type_ list;
  mutable output_type : Typesystem_types.type_ option;
}

let default_function_signature_mutable () : function_signature_mutable = {
  input_types = [];
  output_type = None;
}


let rec decode_type_ext d = 
  let rec loop () = 
    let ret:Typesystem_types.type_ext = match Pbrt.Decoder.key d with
      | None -> Pbrt.Decoder.malformed_variant "type_ext"
      | Some (3, _) -> (Typesystem_types.Extension_idx (Pbrt.Decoder.int32_as_varint d) : Typesystem_types.type_ext) 
      | Some (4, _) -> (Typesystem_types.Extension (decode_type_extension (Pbrt.Decoder.nested d)) : Typesystem_types.type_ext) 
      | Some (n, payload_kind) -> (
        Pbrt.Decoder.skip d payload_kind; 
        loop () 
      )
    in
    ret
  in
  loop ()

and decode_type_ d =
  let v = default_type__mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
    ); continue__ := false
    | Some (1, Pbrt.Varint) -> begin
      v.definite_type <- Pbrt.Decoder.int32_as_varint d;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_), field(1)" pk
    | Some (2, Pbrt.Varint) -> begin
      v.possible_type <- Pbrt.Decoder.int32_as_varint d;
    end
    | Some (2, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_), field(2)" pk
    | Some (3, Pbrt.Varint) -> begin
      v.ext <- Typesystem_types.Extension_idx (Pbrt.Decoder.int32_as_varint d);
    end
    | Some (3, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_), field(3)" pk
    | Some (4, Pbrt.Bytes) -> begin
      v.ext <- Typesystem_types.Extension (decode_type_extension (Pbrt.Decoder.nested d));
    end
    | Some (4, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_), field(4)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Typesystem_types.definite_type = v.definite_type;
    Typesystem_types.possible_type = v.possible_type;
    Typesystem_types.ext = v.ext;
  } : Typesystem_types.type_)

and decode_type_extension d =
  let v = default_type_extension_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.methods <- List.rev v.methods;
      v.properties <- List.rev v.properties;
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.properties <- (Pbrt.Decoder.string d) :: v.properties;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_extension), field(1)" pk
    | Some (2, Pbrt.Bytes) -> begin
      v.methods <- (Pbrt.Decoder.string d) :: v.methods;
    end
    | Some (2, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_extension), field(2)" pk
    | Some (3, Pbrt.Bytes) -> begin
      v.group <- Pbrt.Decoder.string d;
    end
    | Some (3, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_extension), field(3)" pk
    | Some (4, Pbrt.Bytes) -> begin
      v.signature <- Some (decode_function_signature (Pbrt.Decoder.nested d));
    end
    | Some (4, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(type_extension), field(4)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Typesystem_types.properties = v.properties;
    Typesystem_types.methods = v.methods;
    Typesystem_types.group = v.group;
    Typesystem_types.signature = v.signature;
  } : Typesystem_types.type_extension)

and decode_function_signature d =
  let v = default_function_signature_mutable () in
  let continue__= ref true in
  while !continue__ do
    match Pbrt.Decoder.key d with
    | None -> (
      v.input_types <- List.rev v.input_types;
    ); continue__ := false
    | Some (1, Pbrt.Bytes) -> begin
      v.input_types <- (decode_type_ (Pbrt.Decoder.nested d)) :: v.input_types;
    end
    | Some (1, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(function_signature), field(1)" pk
    | Some (2, Pbrt.Bytes) -> begin
      v.output_type <- Some (decode_type_ (Pbrt.Decoder.nested d));
    end
    | Some (2, pk) -> 
      Pbrt.Decoder.unexpected_payload "Message(function_signature), field(2)" pk
    | Some (_, payload_kind) -> Pbrt.Decoder.skip d payload_kind
  done;
  ({
    Typesystem_types.input_types = v.input_types;
    Typesystem_types.output_type = v.output_type;
  } : Typesystem_types.function_signature)

let rec encode_type_ext (v:Typesystem_types.type_ext) encoder = 
  begin match v with
  | Typesystem_types.Extension_idx x ->
    Pbrt.Encoder.key (3, Pbrt.Varint) encoder; 
    Pbrt.Encoder.int32_as_varint x encoder;
  | Typesystem_types.Extension x ->
    Pbrt.Encoder.key (4, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (encode_type_extension x) encoder;
  end

and encode_type_ (v:Typesystem_types.type_) encoder = 
  Pbrt.Encoder.key (1, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int32_as_varint v.Typesystem_types.definite_type encoder;
  Pbrt.Encoder.key (2, Pbrt.Varint) encoder; 
  Pbrt.Encoder.int32_as_varint v.Typesystem_types.possible_type encoder;
  begin match v.Typesystem_types.ext with
  | Typesystem_types.Extension_idx x ->
    Pbrt.Encoder.key (3, Pbrt.Varint) encoder; 
    Pbrt.Encoder.int32_as_varint x encoder;
  | Typesystem_types.Extension x ->
    Pbrt.Encoder.key (4, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (encode_type_extension x) encoder;
  end;
  ()

and encode_type_extension (v:Typesystem_types.type_extension) encoder = 
  List.iter (fun x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.string x encoder;
  ) v.Typesystem_types.properties;
  List.iter (fun x -> 
    Pbrt.Encoder.key (2, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.string x encoder;
  ) v.Typesystem_types.methods;
  Pbrt.Encoder.key (3, Pbrt.Bytes) encoder; 
  Pbrt.Encoder.string v.Typesystem_types.group encoder;
  begin match v.Typesystem_types.signature with
  | Some x -> 
    Pbrt.Encoder.key (4, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (encode_function_signature x) encoder;
  | None -> ();
  end;
  ()

and encode_function_signature (v:Typesystem_types.function_signature) encoder = 
  List.iter (fun x -> 
    Pbrt.Encoder.key (1, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (encode_type_ x) encoder;
  ) v.Typesystem_types.input_types;
  begin match v.Typesystem_types.output_type with
  | Some x -> 
    Pbrt.Encoder.key (2, Pbrt.Bytes) encoder; 
    Pbrt.Encoder.nested (encode_type_ x) encoder;
  | None -> ();
  end;
  ()
