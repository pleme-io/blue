const CHUNKS: i64 = 64;
const WORK: i64 = 50_000;

fn chunk(seed: i64) -> i64 {
    (0..WORK).fold(0, |acc, i| (acc * 31 + seed + i) % 1_000_003)
}

fn seed_of(i: i64, edit: i64) -> i64 {
    if i == CHUNKS - 1 {
        i * 7 + 1 + edit
    } else {
        i * 7 + 1
    }
}

fn main() {
    let edit = std::env::args().nth(1).and_then(|a| a.parse::<i64>().ok()).unwrap_or(0);
    println!("{}", (0..CHUNKS).map(|i| chunk(seed_of(i, edit))).sum::<i64>());
}
