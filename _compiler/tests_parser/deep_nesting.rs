fn main() {
    let mut hits = 0;
    for row in 0..3 {
        if row < 2 {
            let mut col = 0;
            while col < 2 {
                col = col + 1;
                if (row + col) % 2 == 0 {
                    for layer in 0..2 {
                        if layer == 1 {
                            loop {
                                if col > 0 {
                                    for step in 0..2 {
                                        if step == row {
                                            hits = hits + 1;
                                        }
                                    }
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
    if hits != 2 {
        std::process::exit(1);
    }
}