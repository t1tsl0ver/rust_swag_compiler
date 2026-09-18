// Character boundaries and every supported character escape.
'a'
'\0' '\n' '\r' '\t' '\\' '\'' '\"' '\x00' '\x7F'
b'\0' b'\n' b'\r' b'\t' b'\\' b'\'' b'\"' b'\x00' b'\xFF'

// Empty strings, escapes, continuations, and suffixes.
"" "\0\n\r\t\\\'\"\x00\x7F"suffix
b"" b"\0\n\r\t\\\'\"\x00\xFF"_suffix
c"" c"ASCII"tag
"left\
    right"

// Quotes and backslashes have no special meaning inside raw strings.
r"" r#"quoted: " and slash: \"#
br"" br##"quote: "# stays inside"##_suffix
cr"" cr###"two hashes "## stay inside"###tag
r#"extra closing hash"##

// Comment classifier boundaries and nesting.
//
///
//// not a doc comment
//!
/**/
/***/
/** outer block doc */
/*! inner block doc */
/* ordinary /* nested */ block */