#!/usr/bin/env rust-script

//! A large valid Rust 2024 source used to exercise the educational lexer.
/*! It intentionally favors lexical variety over useful application logic. */

#![allow(
    dead_code,
    unused_assignments,
    unused_mut,
    unused_variables,
    unused_unsafe
)]

use std::ffi::CStr;
use std::fmt::Debug;

// An ordinary line comment.
/* An ordinary block comment with /* a nested comment */ inside it. */
const ANSWER: i32 = 42;
const HEX_MASK: u32 = 0xFF_00_FF_00;
static APPLICATION_NAME: &str = "lexer-test";

type SharedText<'a> = &'a str;
type Callback = extern "C" fn(i32) -> i32;

/// A generic point documented with an outer line doc comment.
/** The outer block doc-comment form is tested here as well. */
#[derive(Clone, Copy, Debug, PartialEq)]
struct Point<T>
where
    T: Copy,
{
    x: T,
    y: T,
}

impl<T> Point<T>
where
    T: Copy,
{
    const DIMENSIONS: usize = 2;

    fn new(x: T, y: T) -> Self {
        Self { x, y }
    }

    fn coordinates(&self) -> (T, T) {
        (self.x, self.y)
    }
}

struct TupleStruct(i32, bool, char);
struct UnitStruct;

#[derive(Debug)]
enum Message<'a> {
    Quit,
    Move { x: i32, y: i32 },
    Write(&'a str),
    ChangeColor(u8, u8, u8),
}

union NumberBits {
    integer: u32,
    float: f32,
}

trait Describe {
    type Output;

    fn describe(&self) -> Self::Output;
}

impl Describe for Point<i32> {
    type Output = String;

    fn describe(&self) -> Self::Output {
        format!("Point({}, {})", self.x, self.y)
    }
}

fn describe_dynamic(value: &dyn Describe<Output = String>) -> String {
    value.describe()
}

struct FixedBuffer<T, const N: usize> {
    values: [T; N],
}

impl<T: Copy, const N: usize> FixedBuffer<T, N> {
    fn filled(value: T) -> Self {
        Self { values: [value; N] }
    }
}

mod nested_module {
    pub(crate) const MODULE_VALUE: i32 = super::ANSWER;

    pub fn value_from_parent() -> i32 {
        self::MODULE_VALUE
    }
}

macro_rules! arithmetic {
    ($left:expr, +, $right:expr) => {
        $left + $right
    };
    ($left:expr, *, $right:expr) => {
        $left * $right
    };
}

unsafe extern "C" {
    safe fn abs(value: i32) -> i32;
}

extern "C" fn callback(value: i32) -> i32 {
    value + 1
}

fn select<'a, T>(left: &'a T, right: &'a T, choose_left: bool) -> &'a T
where
    T: Debug,
{
    if choose_left {
        left
    } else {
        right
    }
}

fn raw_lifetime<'r#async>(value: &'r#async str) -> &'r#async str {
    value
}

fn checked_division(left: i32, right: i32) -> Result<i32, &'static str> {
    if right == 0 {
        return Err("division by zero");
    }
    Ok(left / right)
}

fn question_mark_operator() -> Result<i32, &'static str> {
    let result = checked_division(84, 2)?;
    Ok(result)
}

unsafe fn union_integer(bits: NumberBits) -> u32 {
    unsafe { bits.integer }
}

async fn asynchronous_example() -> i32 {
    let future = async move { 40 + 2 };
    future.await
}

fn literal_examples() {
    // Every named primitive type appears explicitly.
    let signed_8: i8 = 1i8;
    let signed_16: i16 = 2i16;
    let signed_32: i32 = 3i32;
    let signed_64: i64 = 4i64;
    let signed_128: i128 = 5i128;
    let signed_size: isize = 6isize;

    let unsigned_8: u8 = 7u8;
    let unsigned_16: u16 = 8u16;
    let unsigned_32: u32 = 9u32;
    let unsigned_64: u64 = 10u64;
    let unsigned_128: u128 = 11u128;
    let unsigned_size: usize = 12usize;

    let float_32: f32 = 5f32;
    let float_64: f64 = 123.0f64;
    let exponent: f64 = 12E+3_f64;
    let trailing_dot: f64 = 2.;

    let binary = 0b1111_0000u8;
    let octal = 0o77u8;
    let hexadecimal = 0xff_u16;
    let decimal = 98_222u32;

    let boolean: bool = true;
    let character: char = 'R';
    let escaped_quote: char = '\'';
    let escaped_ascii: char = '\x52';
    let escaped_unicode: char = '\u{00E6}';

    let string_slice: &str = "ordinary string\nwith escape";
    let owned_string: String = String::from("owned");
    let multiline = "first line
second line";
    let continued = "left\
                     right";
    let raw = r#"raw string contains "quotes" and \\slashes"#;

    let byte: u8 = b'R';
    let escaped_byte: u8 = b'\xA0';
    let bytes: &[u8] = b"byte\x20string";
    let raw_bytes: &[u8] = br##"raw byte "string""##;

    let c_string: &CStr = c"C string";
    let raw_c_string: &CStr = cr#"raw C "string""#;

    let unit: () = ();
    let tuple: (i32, bool, char) = (1, false, 'x');
    let array: [i32; 3] = [1, 2, 3];
    let slice: &[i32] = &array[..];
    let reference: &i32 = &array[0];
    let mutable_reference: &mut i32 = &mut 10;
    let const_pointer: *const i32 = reference as *const i32;
    let raw_pointer: *const i32 = &raw const array[1];
    let function_pointer: fn(i32, i32) -> i32 = |a, b| a + b;
    let c_function_pointer: Callback = callback;
    let r#match = "raw identifier";
}

fn operator_examples() -> i32 {
    let mut arithmetic_value = (10 + 2) * 3 - 4 / 2 % 2;
    arithmetic_value += 1;
    arithmetic_value -= 1;
    arithmetic_value *= 2;
    arithmetic_value /= 2;
    arithmetic_value %= 7;

    let mut bits: u32 = 0b1010;
    bits &= 0b1111;
    bits |= 0b0001;
    bits ^= 0b0010;
    bits <<= 2;
    bits >>= 1;

    let bit_expression = (bits & 0xff) | (bits ^ 0x0f);
    let shifts = (1u32 << 4) >> 1;
    let comparisons = arithmetic_value == 3
        || arithmetic_value != 4
        || arithmetic_value < 10
        || arithmetic_value <= 10
        || arithmetic_value > 0
        || arithmetic_value >= 0;
    let logical = comparisons && true || !false;

    let reference = &arithmetic_value;
    let dereferenced = *reference;
    let negative = -dereferenced;

    arithmetic!(negative, +, arithmetic!(2, *, 3))
}

fn control_flow_examples(message: Message<'_>) -> i32 {
    let mut total = 0;

    for number in 0..=5 {
        if number == 2 {
            continue;
        } else if number > 4 {
            break;
        } else {
            total += number;
        }
    }

    let mut index = 0;
    while index < 3 {
        index += 1;
    }

    'outer: loop {
        loop {
            total += 1;
            break 'outer;
        }
    }

    let matched = match message {
        Message::Quit => 0,
        Message::Move { x, y } if x > 0 => x + y,
        Message::Move { x: _, y } => y,
        Message::Write(text) => text.len() as i32,
        Message::ChangeColor(red @ 1..=255, green, blue) => {
            i32::from(red) + i32::from(green) + i32::from(blue)
        }
        Message::ChangeColor(_, _, _) => 0,
    };

    let Some(nonzero) = Some(matched) else {
        return total;
    };

    let pair = (nonzero, total);
    let (ref first, mut second) = pair;
    second += *first;

    let closure = move |value: i32| -> i32 { value + second };
    closure(total)
}

fn main() {
    literal_examples();

    let point = Point::new(3, 4);
    let description = describe_dynamic(&point);
    let other = String::from("other");
    let selected = select(&description, &other, true);
    let module_value = nested_module::value_from_parent();
    let operation = operator_examples();
    let control = control_flow_examples(Message::Move { x: 1, y: 2 });
    let result = question_mark_operator().unwrap_or_default();
    let compile_time_value = const { ANSWER + 1 };

    println!(
        "{}: {selected}; module={module_value}; operation={operation}; control={control}; result={result}; const={compile_time_value}",
        APPLICATION_NAME,
    );
}
