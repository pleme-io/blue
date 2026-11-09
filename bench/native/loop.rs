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
    println!("{}", walk(std::hint::black_box(3_000_000), 0));
}
