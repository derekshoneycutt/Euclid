package syntax

SYNTAX_DEFAULT_DOCUMENT_BYTES :: 4 * 1024 * 1024
SYNTAX_DEFAULT_RECORD_BYTES :: 64 * 1024
SYNTAX_DEFAULT_RECORD_COUNT :: 65_536
SYNTAX_DEFAULT_SCOPE_DEPTH :: 3
SYNTAX_DEFAULT_BLOCK_BYTES :: 4 * 1024 * 1024
SYNTAX_SCOPE_ID_BYTES :: 256
SYNTAX_TERMINATOR_BYTES :: 256
SYNTAX_DIAGNOSTIC_SCOPE_BYTES :: 32

Limits :: struct {
    document_bytes: int,
    record_bytes: int,
    record_count: int,
    scope_depth: int,
    block_bytes: int,
}

DEFAULT_LIMITS :: Limits{
    document_bytes = SYNTAX_DEFAULT_DOCUMENT_BYTES,
    record_bytes = SYNTAX_DEFAULT_RECORD_BYTES,
    record_count = SYNTAX_DEFAULT_RECORD_COUNT,
    scope_depth = SYNTAX_DEFAULT_SCOPE_DEPTH,
    block_bytes = SYNTAX_DEFAULT_BLOCK_BYTES,
}

Rule :: enum u8 {
    None,
    Invalid_Utf8,
    Byte_Order_Mark,
    Carriage_Return,
    Missing_Final_Lf,
    Missing_Header,
    Empty_Header,
    Whitespace_Record,
    Invalid_Json,
    Duplicate_Object_Key,
    Record_Not_Object,
    Record_Too_Large,
    Record_Too_Complex,
    Document_Too_Large,
    Too_Many_Records,
    Too_Many_Scopes,
    Scope_Too_Deep,
    Invalid_Scope,
    Mismatched_Scope_End,
    Unclosed_Scope,
    Invalid_Block_Descriptor,
    Invalid_Block_Length,
    Block_Too_Large,
    Block_Destination_Too_Small,
    Block_Action_Missing,
    Invalid_Block_Terminator,
    Block_Terminator_Too_Large,
    Missing_Block_Terminator,
    Invalid_Block_Framing_Lf,
    Block_Too_Large_For_Destination,
    Feed_After_End,
}

Diagnostic :: struct {
    line: int,
    rule: Rule,
    scope_id: [SYNTAX_DIAGNOSTIC_SCOPE_BYTES]u8,
    scope_id_length: u8,
}

Syntax_Limits :: Limits
Syntax_Rule :: Rule
Syntax_Diagnostic :: Diagnostic
