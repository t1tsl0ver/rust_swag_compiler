// Character boundaries and every supported character escape.
'a'
'\0' '\n' '\r' '\t' '\\' '\'' '\"' '\x00' '\x7F'

// Empty strings, escapes, continuations, and suffixes.
"" "\0\n\r\t\\\'\"\x00\x7F"suffix
"left\
    right"

// Quotes and backslashes have no special meaning inside raw strings.
r"" r#"quoted: " and slash: \"#
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
