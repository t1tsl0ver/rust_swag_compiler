fn demo(x: i32) {
    let raw = r##"a\n"##;
    /* outer /* inner */ done */
    let n = 0x2Au8;
    let c = '\n';
    demo(n);
    let binary = 0b101010u8;
    let octal = 0o52u8;
    let decimal = 42u8;
}
