fn contains_pair(rows: [[i32; 4]; 3], target: i32) -> bool {
    for row in rows {
        let mut column = 0;
        while column + 1 < 4 {
            if row[column] == 0 {
                column = column + 1;
                continue;
            }

            // Просматриваем ненулевые элементы подряд, пока не найдём пару или не встретим ноль.
            let found = (loop {
                if column + 1 >= 4 || row[column] == 0 {
                    break false;
                } else if row[column] > 0 {
                    if matches_pair(row[column], normalize(row[column + 1]), target) {
                        break true;
                    }
                }
                column = column + 1;
            });

            if found {
                return true;
            }
        }
    }
    false
}

fn matches_pair(value: i32, next: i32, target: i32) -> bool {
    value == target && next == target
}

fn normalize(value: i32) -> i32 {
    value.saturating_abs()
}

fn main() {
    let rows = [[0, 3, 0, 2], [1, 0, 7, -7], [5, 2, 0, 0]];
    if !contains_pair(rows, 7) || contains_pair(rows, 8) {
        std::process::exit(1);
    }
}
