(** program.proto Binary Encoding *)


(** {2 Protobuf Encoding} *)

val encode_instruction_operation : Program_types.instruction_operation -> Pbrt.Encoder.t -> unit
(** [encode_instruction_operation v encoder] encodes [v] with the given [encoder] *)

val encode_instruction : Program_types.instruction -> Pbrt.Encoder.t -> unit
(** [encode_instruction v encoder] encodes [v] with the given [encoder] *)

val encode_type_collection_status : Program_types.type_collection_status -> Pbrt.Encoder.t -> unit
(** [encode_type_collection_status v encoder] encodes [v] with the given [encoder] *)

val encode_type_quality : Program_types.type_quality -> Pbrt.Encoder.t -> unit
(** [encode_type_quality v encoder] encodes [v] with the given [encoder] *)

val encode_type_info : Program_types.type_info -> Pbrt.Encoder.t -> unit
(** [encode_type_info v encoder] encodes [v] with the given [encoder] *)

val encode_program : Program_types.program -> Pbrt.Encoder.t -> unit
(** [encode_program v encoder] encodes [v] with the given [encoder] *)


(** {2 Protobuf Decoding} *)

val decode_instruction_operation : Pbrt.Decoder.t -> Program_types.instruction_operation
(** [decode_instruction_operation decoder] decodes a [instruction_operation] value from [decoder] *)

val decode_instruction : Pbrt.Decoder.t -> Program_types.instruction
(** [decode_instruction decoder] decodes a [instruction] value from [decoder] *)

val decode_type_collection_status : Pbrt.Decoder.t -> Program_types.type_collection_status
(** [decode_type_collection_status decoder] decodes a [type_collection_status] value from [decoder] *)

val decode_type_quality : Pbrt.Decoder.t -> Program_types.type_quality
(** [decode_type_quality decoder] decodes a [type_quality] value from [decoder] *)

val decode_type_info : Pbrt.Decoder.t -> Program_types.type_info
(** [decode_type_info decoder] decodes a [type_info] value from [decoder] *)

val decode_program : Pbrt.Decoder.t -> Program_types.program
(** [decode_program decoder] decodes a [program] value from [decoder] *)
