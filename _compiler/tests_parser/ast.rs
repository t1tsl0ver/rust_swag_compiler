pub mod sample {
    // В этой грамматике объявление кортежной структуры заканчивается закрывающей скобкой.
    pub struct Pair(pub i32, pub i32)
    pub struct Named { pub value: i32 }
    pub enum Choice {
        Off,
        On = 1,
        Record { value: i32 },
    }

    pub trait Read {
        const DEFAULT: i32;
        fn get(&self) -> i32;
    }

    impl Read for Pair {
        const DEFAULT: i32 = 0;
        fn get(&self) -> i32 { self.0 }
    }

    pub fn run(mut input: i32, obj: &mut Pair) -> i32 {
        let mut local: i32;
        let r#type = (if input > 0 { 1 } else { 2 });
        if input > 0 { input = 2; }
        if input == 0 { 0 } else { 1 };;
        pkg::call(1, 2, (if true { 3 } else { 4 }),);
        obj.method(5, 6);
        obj.callback;
        f(8);
        obj[0];
        let value = input + r#type * 3;
        Named { value: value };
        if true { value } else { 0 }
    }

    fn literal_sample() {
        1.5;
        "text";
        r#"raw"#;
        'x';
    }
}