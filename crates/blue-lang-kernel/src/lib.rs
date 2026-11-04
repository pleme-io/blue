#![deny(unsafe_code)]

#[cfg(target_os = "linux")]
mod seam;

use std::fmt;
use std::sync::{Arc, Mutex, PoisonError};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refusal {
    Absent(&'static str),
    Bad(String),
    Errno { word: &'static str, errno: i32 },
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Refusal::Absent(word) => write!(
                f,
                "{word}: this host's kernel has no such call; the kernel surface runs on Linux"
            ),
            Refusal::Bad(why) => f.write_str(why),
            Refusal::Errno { word, errno } => {
                let text = std::io::Error::from_raw_os_error(*errno);
                write!(f, "{word}: {text}")
            }
        }
    }
}

#[derive(Debug)]
pub struct Fd {
    raw: Mutex<Option<i32>>,
}

impl Fd {
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    fn owning(raw: i32) -> Self {
        Self {
            raw: Mutex::new(Some(raw)),
        }
    }

    #[must_use]
    pub fn number(&self) -> Option<i32> {
        *self.raw.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub fn close(&self) {
        let taken = self
            .raw
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take();
        #[cfg(target_os = "linux")]
        if let Some(raw) = taken {
            seam::close(raw);
        }
        #[cfg(not(target_os = "linux"))]
        let _ = taken;
    }

    fn live(&self, word: &str) -> Result<i32, Refusal> {
        self.number()
            .ok_or_else(|| Refusal::Bad(format!("{word}: this file descriptor is closed")))
    }
}

impl Drop for Fd {
    fn drop(&mut self) {
        self.close();
    }
}

#[derive(Clone, Debug)]
pub enum Slot {
    Int { at: usize, width: usize, value: u64 },
    Bytes { at: usize, bytes: Vec<u8> },
    In { at: usize, bytes: Vec<u8> },
    Out { at: usize, capacity: usize },
    InOut { at: usize, bytes: Vec<u8> },
    Strings { at: usize, strings: Vec<String> },
    Descriptor { at: usize, fd: Arc<Fd> },
}

#[derive(Debug)]
pub struct Marshalled {
    pub attr: Vec<u8>,
    in_buffers: Vec<Vec<u8>>,
    out_buffers: Vec<Vec<u8>>,
}

impl Marshalled {
    #[must_use]
    pub fn out_buffers(&self) -> &[Vec<u8>] {
        &self.out_buffers
    }

    #[must_use]
    pub fn in_buffers(&self) -> &[Vec<u8>] {
        &self.in_buffers
    }
}

fn put(attr: &mut [u8], at: usize, bytes: &[u8], word: &str) -> Result<(), Refusal> {
    let end = at
        .checked_add(bytes.len())
        .filter(|end| *end <= attr.len())
        .ok_or_else(|| {
            Refusal::Bad(format!(
                "{word}: a field of {} bytes at {at} does not fit a {}-byte struct",
                bytes.len(),
                attr.len()
            ))
        })?;
    attr[at..end].copy_from_slice(bytes);
    Ok(())
}

fn address(buffer: &mut [u8]) -> [u8; 8] {
    let raw = if buffer.is_empty() {
        0
    } else {
        buffer.as_mut_ptr() as usize as u64
    };
    raw.to_ne_bytes()
}

pub fn marshal(word: &str, size: usize, slots: &[Slot]) -> Result<Marshalled, Refusal> {
    let mut attr = vec![0u8; size];
    let mut in_buffers: Vec<Vec<u8>> = Vec::new();
    let mut out_buffers: Vec<Vec<u8>> = Vec::new();
    for slot in slots {
        match slot {
            Slot::Int { at, width, value } => {
                let bytes = value.to_ne_bytes();
                if !matches!(width, 1 | 2 | 4 | 8) {
                    return Err(Refusal::Bad(format!(
                        "{word}: an integer field is 1, 2, 4 or 8 bytes, got {width}"
                    )));
                }
                #[cfg(target_endian = "little")]
                let narrow = &bytes[..*width];
                #[cfg(target_endian = "big")]
                let narrow = &bytes[8 - *width..];
                put(&mut attr, *at, narrow, word)?;
            }
            Slot::Bytes { at, bytes } => put(&mut attr, *at, bytes, word)?,
            Slot::In { at, bytes } => {
                let mut held = bytes.clone();
                put(&mut attr, *at, &address(&mut held), word)?;
                in_buffers.push(held);
            }
            Slot::Out { at, capacity } => {
                let mut held = vec![0u8; *capacity];
                put(&mut attr, *at, &address(&mut held), word)?;
                out_buffers.push(held);
            }
            Slot::InOut { at, bytes } => {
                let mut held = bytes.clone();
                put(&mut attr, *at, &address(&mut held), word)?;
                out_buffers.push(held);
            }
            Slot::Strings { at, strings } => {
                let mut pointers: Vec<u8> = Vec::with_capacity(strings.len() * 8);
                for text in strings {
                    let mut held = text.clone().into_bytes();
                    held.push(0);
                    pointers.extend_from_slice(&address(&mut held));
                    in_buffers.push(held);
                }
                put(&mut attr, *at, &address(&mut pointers), word)?;
                in_buffers.push(pointers);
            }
            Slot::Descriptor { at, fd } => {
                let raw = fd.live(word)?;
                put(&mut attr, *at, &raw.to_ne_bytes(), word)?;
            }
        }
    }
    Ok(Marshalled {
        attr,
        in_buffers,
        out_buffers,
    })
}

#[derive(Debug)]
pub struct Answer {
    pub ret: i64,
    pub errno: Option<i32>,
    pub attr: Vec<u8>,
    pub out: Vec<Vec<u8>>,
    pub fd: Option<Fd>,
}

pub fn bpf(command: u32, size: usize, slots: &[Slot], fd_result: bool) -> Result<Answer, Refusal> {
    const WORD: &str = "bpf_syscall";
    let mut m = marshal(WORD, size, slots)?;
    #[cfg(target_os = "linux")]
    {
        let outcome = seam::bpf(command, &mut m.attr);
        let held = std::mem::take(&mut m.in_buffers);
        drop(held);
        let (ret, errno) = match outcome {
            Ok(n) => (n, None),
            Err(e) => (-1, Some(e)),
        };
        let fd = (fd_result && errno.is_none())
            .then(|| i32::try_from(ret).ok().map(Fd::owning))
            .flatten();
        Ok(Answer {
            ret,
            errno,
            attr: std::mem::take(&mut m.attr),
            out: std::mem::take(&mut m.out_buffers),
            fd,
        })
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (command, fd_result, &mut m);
        Err(Refusal::Absent(WORD))
    }
}

pub fn perf_event_open(
    size: usize,
    slots: &[Slot],
    pid: i32,
    cpu: i32,
    group: Option<&Fd>,
    flags: u64,
) -> Result<Fd, Refusal> {
    const WORD: &str = "perf_event_open";
    let mut m = marshal(WORD, size, slots)?;
    #[cfg(target_os = "linux")]
    {
        let group = group.map_or(Ok(-1), |g| g.live(WORD))?;
        let outcome = seam::perf_event_open(&mut m.attr, pid, cpu, group, flags);
        drop(std::mem::take(&mut m.in_buffers));
        outcome
            .map(Fd::owning)
            .map_err(|errno| Refusal::Errno { word: WORD, errno })
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (&mut m, pid, cpu, group, flags);
        Err(Refusal::Absent(WORD))
    }
}

pub fn open_read(path: &str) -> Result<Fd, Refusal> {
    const WORD: &str = "fd_open";
    #[cfg(target_os = "linux")]
    {
        use std::os::fd::IntoRawFd;
        std::fs::File::open(path)
            .map(|file| Fd::owning(file.into_raw_fd()))
            .map_err(|e| Refusal::Errno {
                word: WORD,
                errno: e.raw_os_error().unwrap_or(libc::EIO),
            })
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = path;
        Err(Refusal::Absent(WORD))
    }
}

pub fn ioctl(fd: &Fd, request: u64, argument: u64) -> Result<i64, Refusal> {
    const WORD: &str = "fd_ioctl";
    #[cfg(target_os = "linux")]
    {
        seam::ioctl(fd.live(WORD)?, request, argument)
            .map_err(|errno| Refusal::Errno { word: WORD, errno })
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (fd, request, argument);
        Err(Refusal::Absent(WORD))
    }
}

#[derive(Debug)]
pub struct Ring {
    #[cfg(target_os = "linux")]
    inner: seam::Ring,
    #[allow(dead_code)]
    map: Arc<Fd>,
}

impl Ring {
    pub fn open(map: Arc<Fd>, size: usize) -> Result<Self, Refusal> {
        const WORD: &str = "ringbuf_open";
        if size == 0 || !size.is_power_of_two() {
            return Err(Refusal::Bad(format!(
                "{WORD}: a ring buffer's size is a power of two, got {size}"
            )));
        }
        #[cfg(target_os = "linux")]
        {
            let raw = map.live(WORD)?;
            let inner = seam::Ring::open(raw, size)
                .map_err(|errno| Refusal::Errno { word: WORD, errno })?;
            Ok(Self { inner, map })
        }
        #[cfg(not(target_os = "linux"))]
        {
            let _ = map;
            Err(Refusal::Absent(WORD))
        }
    }

    pub fn next(&self, timeout_ms: i32) -> Result<Option<Vec<u8>>, Refusal> {
        const WORD: &str = "ringbuf_next";
        #[cfg(target_os = "linux")]
        {
            self.inner
                .next(timeout_ms)
                .map_err(|errno| Refusal::Errno { word: WORD, errno })
        }
        #[cfg(not(target_os = "linux"))]
        {
            let _ = timeout_ms;
            Err(Refusal::Absent(WORD))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integers_land_at_their_offsets_and_the_rest_stays_zero() {
        let m = marshal(
            "t",
            12,
            &[
                Slot::Int {
                    at: 0,
                    width: 4,
                    value: 0x0102_0304,
                },
                Slot::Int {
                    at: 8,
                    width: 2,
                    value: 0xABCD,
                },
            ],
        )
        .unwrap();
        let mut want = vec![0u8; 12];
        want[..4].copy_from_slice(&0x0102_0304u32.to_ne_bytes());
        want[8..10].copy_from_slice(&0xABCDu16.to_ne_bytes());
        assert_eq!(m.attr, want);
    }

    #[test]
    fn an_empty_size_with_no_slots_is_an_empty_struct_and_a_field_past_the_end_is_refused() {
        assert!(marshal("t", 0, &[]).unwrap().attr.is_empty());
        let e = marshal(
            "t",
            4,
            &[Slot::Int {
                at: 2,
                width: 4,
                value: 1,
            }],
        )
        .unwrap_err();
        assert!(e.to_string().contains("does not fit"), "{e}");
    }

    #[test]
    fn a_buffer_field_holds_the_address_of_a_buffer_kept_for_the_call() {
        let m = marshal(
            "t",
            16,
            &[
                Slot::In {
                    at: 0,
                    bytes: vec![7, 8, 9],
                },
                Slot::Out { at: 8, capacity: 5 },
            ],
        )
        .unwrap();
        let held = m.in_buffers[0].as_ptr() as usize as u64;
        let out = m.out_buffers[0].as_ptr() as usize as u64;
        assert_eq!(u64::from_ne_bytes(m.attr[0..8].try_into().unwrap()), held);
        assert_eq!(u64::from_ne_bytes(m.attr[8..16].try_into().unwrap()), out);
        assert_eq!(m.in_buffers[0], [7, 8, 9]);
        assert_eq!(m.out_buffers()[0], [0, 0, 0, 0, 0]);
    }

    #[test]
    fn a_strings_field_is_an_array_of_addresses_of_nul_terminated_names() {
        let m = marshal(
            "t",
            8,
            &[Slot::Strings {
                at: 0,
                strings: vec!["ab".into(), "c".into()],
            }],
        )
        .unwrap();
        assert_eq!(m.in_buffers()[0], [b'a', b'b', 0]);
        assert_eq!(m.in_buffers()[1], [b'c', 0]);
        let table = &m.in_buffers()[2];
        assert_eq!(table.len(), 16);
        let first = u64::from_ne_bytes(table[..8].try_into().unwrap());
        assert_eq!(first, m.in_buffers()[0].as_ptr() as usize as u64);
        let addr = u64::from_ne_bytes(m.attr[..8].try_into().unwrap());
        assert_eq!(addr, table.as_ptr() as usize as u64);
    }

    #[test]
    fn an_empty_buffer_is_a_null_address() {
        let m = marshal(
            "t",
            8,
            &[Slot::In {
                at: 0,
                bytes: vec![],
            }],
        )
        .unwrap();
        assert_eq!(m.attr, [0u8; 8]);
    }

    #[test]
    fn a_descriptor_slot_writes_the_number_and_a_closed_one_is_refused() {
        let fd = Arc::new(Fd {
            raw: Mutex::new(Some(41)),
        });
        let m = marshal(
            "t",
            4,
            &[Slot::Descriptor {
                at: 0,
                fd: fd.clone(),
            }],
        )
        .unwrap();
        assert_eq!(m.attr, 41i32.to_ne_bytes());
        *fd.raw.lock().unwrap() = None;
        let e = marshal("t", 4, &[Slot::Descriptor { at: 0, fd }]).unwrap_err();
        assert!(e.to_string().contains("closed"), "{e}");
    }

    #[test]
    fn a_width_that_is_no_integer_width_is_refused() {
        let e = marshal(
            "t",
            8,
            &[Slot::Int {
                at: 0,
                width: 3,
                value: 1,
            }],
        )
        .unwrap_err();
        assert!(e.to_string().contains("1, 2, 4 or 8"), "{e}");
    }

    #[test]
    fn a_ring_size_that_is_not_a_power_of_two_is_refused_before_any_call() {
        let map = Arc::new(Fd {
            raw: Mutex::new(None),
        });
        let e = Ring::open(map, 3).unwrap_err();
        assert!(e.to_string().contains("power of two"), "{e}");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn on_linux_a_directory_opens_and_a_missing_path_answers_its_errno() {
        let dir = open_read("/").expect("the root directory opens");
        assert!(dir.number().is_some());
        assert_eq!(
            open_read("/no/such/path").map(|_| ()),
            Err(Refusal::Errno {
                word: "fd_open",
                errno: libc::ENOENT
            })
        );
    }

    #[cfg(not(target_os = "linux"))]
    #[test]
    fn off_linux_every_call_is_a_named_absence() {
        assert_eq!(
            bpf(0, 0, &[], false).unwrap_err(),
            Refusal::Absent("bpf_syscall")
        );
        assert_eq!(
            perf_event_open(8, &[], 0, 0, None, 0).unwrap_err(),
            Refusal::Absent("perf_event_open")
        );
        assert_eq!(open_read("/").map(|_| ()), Err(Refusal::Absent("fd_open")));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn on_linux_a_bad_command_is_an_errno_never_a_crash() {
        let a = bpf(9_999, 8, &[], false).unwrap();
        assert!(a.errno.is_some());
        assert_eq!(a.ret, -1);
    }
}
