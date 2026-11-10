fn walk(mut i: i64, mut acc: i64) -> i64 {
    loop {
        if i == 0 {
            return acc;
        } else if i % 3 == 0 {
            acc += i * 2;
        } else if i % 5 == 1 {
            acc -= i;
        } else {
            acc += 1;
        }
        i -= 1;
    }
}

fn main() {
    println!("{}", walk(std::env::args().nth(1).and_then(|a| a.parse::<i64>().ok()).unwrap_or(0), 0));
}
