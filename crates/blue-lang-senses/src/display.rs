use std::path::PathBuf;

#[cfg(not(unix))]
use crate::canvas::Canvas;
#[cfg(not(unix))]
use crate::Refusal;

pub const SOCKET_VARIABLE: &str = "BLUE_CANVAS_SOCKET";
pub const PROTOCOL: &str = "garasu-canvas/1";

#[must_use]
pub fn socket() -> PathBuf {
    if let Some(p) = std::env::var_os(SOCKET_VARIABLE) {
        return PathBuf::from(p);
    }
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("garasu")
        .join("canvas.sock")
}

#[cfg(unix)]
mod unix {
    use std::io::{BufRead, BufReader, Write};
    use std::os::unix::net::UnixStream;
    use std::path::Path;
    use std::time::Duration;

    use serde_json::{json, Value};

    use super::{socket, PROTOCOL};
    use crate::canvas::Canvas;
    use crate::Refusal;

    const WAIT: Duration = Duration::from_secs(5);

    pub struct Screen {
        stream: UnixStream,
        replies: BufReader<UnixStream>,
    }

    fn io_refusal(path: &Path, e: &std::io::Error) -> Refusal {
        let why = format!("the canvas server at {}: {e}", path.display());
        match e.kind() {
            std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused => {
                Refusal::NotFound(format!("no canvas server at {}: {e}", path.display()))
            }
            std::io::ErrorKind::PermissionDenied => Refusal::Denied(why),
            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut => Refusal::Timeout(why),
            _ => Refusal::Refused(why),
        }
    }

    impl Screen {
        pub fn open(canvas: &Canvas, title: &str) -> Result<Screen, Refusal> {
            let path = socket();
            let stream = UnixStream::connect(&path).map_err(|e| io_refusal(&path, &e))?;
            stream
                .set_read_timeout(Some(WAIT))
                .and_then(|()| stream.set_write_timeout(Some(WAIT)))
                .map_err(|e| io_refusal(&path, &e))?;
            let replies = BufReader::new(stream.try_clone().map_err(|e| io_refusal(&path, &e))?);
            let mut screen = Screen { stream, replies };
            screen.send(
                &json!({
                    "op": "open",
                    "protocol": PROTOCOL,
                    "width": canvas.width(),
                    "height": canvas.height(),
                    "title": title,
                }),
                &[],
            )?;
            Ok(screen)
        }

        fn send(&mut self, header: &Value, payload: &[u8]) -> Result<(), Refusal> {
            let path = socket();
            let mut line = header.to_string();
            line.push('\n');
            self.stream
                .write_all(line.as_bytes())
                .and_then(|()| self.stream.write_all(payload))
                .and_then(|()| self.stream.flush())
                .map_err(|e| io_refusal(&path, &e))?;
            let mut reply = String::new();
            let read = self
                .replies
                .read_line(&mut reply)
                .map_err(|e| io_refusal(&path, &e))?;
            if read == 0 {
                return Err(Refusal::Refused(format!(
                    "the canvas server at {} closed the connection",
                    path.display()
                )));
            }
            let answer: Value = serde_json::from_str(reply.trim_end()).map_err(|e| {
                Refusal::Refused(format!("the canvas server answered {reply:?}: {e}"))
            })?;
            if answer["ok"] == json!(true) {
                Ok(())
            } else {
                Err(Refusal::Refused(format!(
                    "the canvas server refused {}: {}",
                    header["op"],
                    answer["error"].as_str().unwrap_or("no reason given")
                )))
            }
        }

        pub fn present(&mut self, canvas: &Canvas) -> Result<(), Refusal> {
            let pixels = canvas.front_rgb8();
            self.send(
                &json!({
                    "op": "present",
                    "format": "rgb8",
                    "width": canvas.width(),
                    "height": canvas.height(),
                    "bytes": pixels.len(),
                }),
                &pixels,
            )
        }

        pub fn close(mut self) -> Result<(), Refusal> {
            self.send(&json!({"op": "close"}), &[])
        }
    }
}

#[cfg(unix)]
pub use unix::Screen;

#[cfg(not(unix))]
pub struct Screen;

#[cfg(not(unix))]
impl Screen {
    pub fn open(_: &Canvas, _: &str) -> Result<Screen, Refusal> {
        Err(Refusal::Unsupported(format!(
            "this platform reaches no canvas server ({})",
            socket().display()
        )))
    }

    pub fn present(&mut self, _: &Canvas) -> Result<(), Refusal> {
        Err(Refusal::Unsupported(
            "this platform reaches no canvas server".into(),
        ))
    }

    pub fn close(self) -> Result<(), Refusal> {
        Ok(())
    }
}
