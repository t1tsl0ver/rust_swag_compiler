struct Point {
    x: i32,
    y: i32,
}

enum Command {
    Shift,
    Reset,
}

impl Point {
    fn apply(&mut self, command: Command, delta: i32) {
        if (command as i32) == (Command::Shift as i32) {
            self.x = self.x + delta;
            self.y = self.y - delta;
        } else {
            self.x = 0;
            self.y = 0;
        }
    }
}

fn main() {
    let mut point = Point { x: 2, y: 5 };

    point.apply(Command::Shift, 3);
    if point.x != 5 || point.y != 2 {
        std::process::exit(1);
    }

    point.apply(Command::Reset, 0);
    if point.x != 0 || point.y != 0 {
        std::process::exit(1);
    }
}