(** typesystem.proto Binary Encoding *)


(** {2 Protobuf Encoding} *)

val encode_type_ext : Typesystem_types.type_ext -> Pbrt.Encoder.t -> unit
(** [encode_type_ext v encoder] encodes [v] with the given [encoder] *)

val encode_type_ : Typesystem_types.type_ -> Pbrt.Encoder.t -> unit
(** [encode_type_ v encoder] encodes [v] with the given [encoder] *)

val encode_type_extension : Typesystem_types.type_extension -> Pbrt.Encoder.t -> unit
(** [encode_type_extension v encoder] encodes [v] with the given [encoder] *)

val encode_function_signature : Typesystem_types.function_signature -> Pbrt.Encoder.t -> unit
(** [encode_function_signature v encoder] encodes [v] with the given [encoder] *)


(** {2 Protobuf Decoding} *)

val decode_type_ext : Pbrt.Decoder.t -> Typesystem_types.type_ext
(** [decode_type_ext decoder] decodes a [type_ext] value from [decoder] *)

val decode_type_ : Pbrt.Decoder.t -> Typesystem_types.type_
(** [decode_type_ decoder] decodes a [type_] value from [decoder] *)

val decode_type_extension : Pbrt.Decoder.t -> Typesystem_types.type_extension
(** [decode_type_extension decoder] decodes a [type_extension] value from [decoder] *)

val decode_function_signature : Pbrt.Decoder.t -> Typesystem_types.function_signature
(** [decode_function_signature decoder] decodes a [function_signature] value from [decoder] *)
