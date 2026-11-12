fn payload(seed: i64, n: i64) -> Vec<u8> {
    (0..n).map(|i| ((seed * 31 + i * 17) % 256) as u8).collect()
}

fn hex_of(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn bytes_of(text: &str) -> Vec<u8> {
    (0..text.len() / 2)
        .map(|i| u8::from_str_radix(&text[2 * i..2 * i + 2], 16).unwrap_or(0))
        .collect()
}

fn frame(seed: i64) -> usize {
    let body = payload(seed, 64);
    let mut framed = vec![1, 0, 64];
    framed.extend_from_slice(&body);
    let wire = hex_of(&framed);
    let back = bytes_of(&wire);
    assert_eq!(back[3], body[0], "round trip lost a byte");
    wire.len()
}

fn main() {
    let frames = std::env::args().nth(1).and_then(|a| a.parse::<i64>().ok()).unwrap_or(400);
    println!("{}", (0..frames).map(frame).sum::<usize>());
}
