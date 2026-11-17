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
