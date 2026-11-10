fn fill(n: i64) -> Vec<i64> {
    let mut xs = Vec::new();
    let mut n = n;
    while n != 0 {
        xs.push(n % 1000);
        n -= 1;
    }
    xs
}

fn add(xs: &[i64]) -> i64 {
    xs.iter().sum()
}

fn main() {
    let n = std::env::args().nth(1).and_then(|a| a.parse::<i64>().ok()).unwrap_or(0);
    let a = add(&fill(n));
    let b = add(&fill(n));
    println!("{a} {b}");
}
