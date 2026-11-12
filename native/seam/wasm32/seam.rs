use kiban_io::Io;
use std::io::Write;

const UART0: u32 = 0x1000_0000;
const FINISHER: u32 = 0x0010_0000;

struct Host {
    out: std::io::BufWriter<std::io::Stdout>,
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
        if byte == b'\n' && self.out.flush().is_err() {
            kiban_io::fault()
        }
    }

    fn write32(&mut self, addr: u32, value: u32) {
        self.write8(addr, value)
    }
}

fn main() {
    let mut host = Host {
        out: std::io::BufWriter::with_capacity(1 << 16, std::io::stdout()),
    };
    program::main(&mut host);
    if host.out.flush().is_err() {
        std::process::exit(1)
    }
}
