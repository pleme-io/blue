//! The base protocol both of blue's stdio servers speak: the language server
//! (LSP) and the debugger (`blue debug`, the Debug Adapter Protocol). Each
//! message is a `Content-Length` header, a blank line, then that many bytes
//! of JSON. One reader and one writer, so the two servers cannot frame a
//! message two ways.

use std::io::{BufRead, Write};

use serde_json::Value;

/// Read one message. `None` at the end of the input, and for a message with
/// no `Content-Length`: it cannot be framed, and guessing a length would
/// desynchronise the stream for every message after it.
///
/// # Errors
///
/// A read that fails.
pub fn read_message<R: BufRead>(input: &mut R) -> std::io::Result<Option<Value>> {
    let mut length: Option<usize> = None;
    loop {
        let mut line = String::new();
        if input.read_line(&mut line)? == 0 {
            return Ok(None);
        }
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            break;
        }
        if let Some(rest) = trimmed
            .strip_prefix("Content-Length:")
            .or_else(|| trimmed.strip_prefix("content-length:"))
        {
            length = rest.trim().parse().ok();
        }
    }
    let Some(length) = length else {
        return Ok(None);
    };
    let mut buf = vec![0u8; length];
    input.read_exact(&mut buf)?;
    Ok(serde_json::from_slice(&buf).ok())
}

/// Write one message and flush it.
///
/// # Errors
///
/// A write that fails.
pub fn write_message<W: Write>(output: &mut W, value: &Value) -> std::io::Result<()> {
    let body = serde_json::to_vec(value)?;
    write!(output, "Content-Length: {}\r\n\r\n", body.len())?;
    output.write_all(&body)?;
    output.flush()
}
