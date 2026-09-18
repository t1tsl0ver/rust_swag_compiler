// Identifier and keyword boundaries.
_ __ _0 a a0 a_b for for_each async async_value

// Integer boundaries: separators, every radix, and the largest supported value.
0 0_ 00 0b_0 0b________1 0o_7 0x_FF 18446744073709551615

// Floating-point and punctuation ambiguities.
1e0 1E+_2 1_2.5e-_1 0.0 2.
1..2 2.field 3._field

// Arbitrary literal suffixes are lexically valid.
7suffix 8_suffix 9f32 10.0custom