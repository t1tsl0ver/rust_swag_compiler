let i32 = 0x2A;
let f64 = 1_5.5_0;
let text = "A\x42C\n";
let symbol = '\x44';
let byte = b'\x45';
gen safe union macro_rules raw
... <-
## #"guarded"
