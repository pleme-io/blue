//! The host's board, shared by every seam whose image is a process on the
//! machine blue runs on (kiban's `host64`): its UART is standard output,
//! held to the bytes kiban's model prints (printable ASCII and newline), and
//! its finisher is the end of the run, as in the model.

use kiban_io::Io;
use std::io::Write;

const UART0: u32 = 0x1000_0000;
const FINISHER: u32 = 0x0010_0000;
const STACK: usize = 1 << 30;

pub struct Host {
    pub out: std::io::BufWriter<std::io::Stdout>,
}

impl Io for Host {
    fn write8(&mut self, addr: u32, value: u32) {
        if addr == FINISHER {
            return;
        }
        if addr != UART0 {
            kiban_io::fault()
        }
        let Ok(byte) = u8::try_from(value) else {
            kiban_io::fault()
        };
        if byte != b'\n' && !(32..127).contains(&byte) {
            kiban_io::fault()
        }
        if self.out.write_all(&[byte]).is_err() {
            kiban_io::fault()
        }
    }

    fn write32(&mut self, addr: u32, value: u32) {
        self.write8(addr, value)
    }
}

/// Run `body` on a thread whose stack holds the board's declared recursion
/// depth: its value, or `None` when it faulted (a fault unwinds) or no thread
/// could start.
pub fn on_stack<T: Send + 'static, F: FnOnce() -> T + Send + 'static>(body: F) -> Option<T> {
    std::thread::Builder::new()
        .stack_size(STACK)
        .spawn(body)
        .ok()?
        .join()
        .ok()
}

/// Run `body` against the host [`on_stack`], then flush: whether it returned
/// true and every byte it printed reached standard output. What was printed
/// before a fault is flushed, and the answer is false.
pub fn run<F: FnOnce(&mut Host) -> bool + Send + 'static>(body: F) -> bool {
    on_stack(|| {
        let mut host = Host {
            out: std::io::BufWriter::with_capacity(1 << 16, std::io::stdout()),
        };
        let answered = body(&mut host);
        host.out.flush().is_ok() && answered
    }) == Some(true)
}

/// One value from its token on the seam: `i42`, `b1`, `f<the Float's bits
/// as an Int>`, `s<the string's UTF-8 in hex>`, or a bare decimal Int, as
/// artifacts built before tokens were called.
pub fn decode(token: &str) -> Option<kiban_heap::Value> {
    let (tag, rest) = (token.as_bytes().first()?, token.get(1..)?);
    Some(match tag {
        b'i' => kiban_heap::Value::Int(rest.parse().ok()?),
        b'b' => kiban_heap::Value::Bool(match rest {
            "1" => true,
            "0" => false,
            _ => return None,
        }),
        b'f' => kiban_heap::Value::Float(f64::from_bits(rest.parse::<i64>().ok()?.cast_unsigned())),
        b's' => {
            if rest.len() % 2 != 0 {
                return None;
            }
            let bytes = (0..rest.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(rest.get(i..i + 2)?, 16).ok())
                .collect::<Option<Vec<u8>>>()?;
            kiban_heap::Value::Str(kiban_heap::text(&String::from_utf8(bytes).ok()?))
        }
        _ => kiban_heap::Value::Int(token.parse().ok()?),
    })
}

/// A value's token on the seam, as [`decode`] reads it.
pub fn encode(v: &kiban_heap::Value) -> String {
    match v {
        kiban_heap::Value::Int(n) => format!("i{n}"),
        kiban_heap::Value::Bool(b) => format!("b{}", u8::from(*b)),
        kiban_heap::Value::Float(x) => format!("f{}", x.to_bits().cast_signed()),
        kiban_heap::Value::Str(s) => {
            let mut out = String::with_capacity(1 + 2 * s.len());
            out.push('s');
            for b in s.bytes() {
                out.push_str(&format!("{b:02x}"));
            }
            out
        }
    }
}
