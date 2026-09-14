#!/usr/bin/env rustx

// This file is intentionally not a valid Rust program.  It is a lexical token
// catalog: reserved words and reserved punctuation are included on purpose.

//! Inner line documentation.
/// Outer line documentation.
// Ordinary line comment.
/* Ordinary /* nested */ block comment. */
/*! Inner block documentation. */
/** Outer block documentation. */

// Strict keywords from the Rust 2024 reference.
_ as async await break const continue crate dyn else enum extern false fn for
if impl in let loop match mod move mut pub ref return self Self static struct
super trait true type unsafe use where while

// Reserved keywords.
abstract become box do final gen macro override priv try typeof unsized virtual yield

// Weak keywords.
macro_rules raw safe union 'static

// Primitive type names plus the commonly used standard-library String type.
bool char str i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 String

// Identifiers, raw identifiers, lifetimes and loop labels.
answer snake_case _unused Москва 東京 r#match 'a 'loop_label 'r#async

// Literals.
0 123 123_u32 0b1111_0000 0o77 0xff_u8
1.0 2. 12E+99_f64 5f32
'R' '\n' '\x52' '\u{00E6}'
"hello" "line\nfeed" "continued\
    text"
b'R' b'\xA0' b"bytes\x20string"
c"C string" c"UTF-8: \u{00E6}"
r"raw" r#"raw "quoted" string"# br##"raw bytes"## cr#"raw C string"#

// Arbitrary suffixes are part of literal tokens; later stages decide whether
// a suffix makes sense for a particular expression.
123custom 1.0custom 'R'custom "text"custom b'R'custom b"bytes"custom

// Every punctuation token from the lexical grammar.
... ..= <<= >>= != %= && &= *= += -= -> .. /= :: <- << <= == => >= >> ^= |= ||
! # $ % & ( ) * + , - . / : ; < = > ? @ [ ] ^ { | } ~
