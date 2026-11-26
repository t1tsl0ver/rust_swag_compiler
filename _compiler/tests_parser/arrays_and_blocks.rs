fn edge_score(values: &[i32; 4], start: usize) -> i64 {
    let first = values[start];
    let last = values[values.len() - 1];
    {
        let first = first + 1;
        (first * 2 + last) as i64
    }
}

fn main() {
    let values: [i32; 4] = [0x02, 0b11, 5, 8];
    if edge_score(&values, 1) != 16_i64 {
        std::process::exit(1);
    }
}