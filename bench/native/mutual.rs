fn is_even(n: i64) -> i64 {
    if n == 0 { 1 } else { is_odd(n - 1) }
}

fn is_odd(n: i64) -> i64 {
    if n == 0 { 0 } else { is_even(n - 1) }
}

fn main() {
    let n = std::hint::black_box(9_999);
    println!("{}{}{}", is_even(10), is_even(7), is_odd(n));
}
