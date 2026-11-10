#[derive(Clone, Copy)]
enum Shape {
    Point { x: i64, y: i64 },
    Circle { r: i64 },
    Rect { w: i64, h: i64 },
}

#[derive(Clone, Copy)]
struct Point {
    x: i64,
    #[allow(dead_code)]
    y: i64,
}

fn area(s: Shape) -> i64 {
    match s {
        Shape::Circle { r } => r * r * 3,
        Shape::Rect { w, h } => w * h,
        Shape::Point { x, y } => x - y,
    }
}

fn pick(n: i64) -> Shape {
    match n % 3 {
        0 => Shape::Circle { r: n % 100 },
        1 => Shape::Rect { w: n % 50, h: n % 7 },
        _ => Shape::Point { x: n % 11, y: n % 13 },
    }
}

fn nudge(p: Point, d: i64) -> Point {
    Point { x: p.x + d, ..p }
}

fn main() {
    let mut acc = 0i64;
    let mut i = std::env::args().nth(1).and_then(|a| a.parse::<i64>().ok()).unwrap_or(0);
    while i != 0 {
        acc += area(pick(i)) + nudge(Point { x: i, y: i }, 1).x;
        i -= 1;
    }
    println!("{acc}");
}
