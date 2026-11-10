fn fib(n: i64) -> i64 {
    if n < 2 {
        n
    } else {
        fib(n - 1) + fib(n - 2)
    }
}

fn main() {
    println!("{}", fib(std::env::args().nth(1).and_then(|a| a.parse::<i64>().ok()).unwrap_or(0)));
}
