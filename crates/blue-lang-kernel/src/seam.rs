#![allow(unsafe_code)]

use std::ptr::{null_mut, read_volatile};
use std::sync::atomic::{fence, AtomicU64, Ordering};

fn errno() -> i32 {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

pub fn bpf(command: u32, attr: &mut [u8]) -> Result<i64, i32> {
    let r = unsafe {
        libc::syscall(
            libc::SYS_bpf,
            libc::c_long::from(command),
            attr.as_mut_ptr(),
            attr.len(),
        )
    };
    if r < 0 {
        Err(errno())
    } else {
        Ok(r)
    }
}

pub fn perf_event_open(
    attr: &mut [u8],
    pid: i32,
    cpu: i32,
    group: i32,
    flags: u64,
) -> Result<i32, i32> {
    let r = unsafe {
        libc::syscall(
            libc::SYS_perf_event_open,
            attr.as_mut_ptr(),
            libc::c_long::from(pid),
            libc::c_long::from(cpu),
            libc::c_long::from(group),
            flags as libc::c_ulong,
        )
    };
    if r < 0 {
        Err(errno())
    } else {
        i32::try_from(r).map_err(|_| libc::EBADF)
    }
}

pub fn ioctl(fd: i32, request: u64, argument: u64) -> Result<i64, i32> {
    let r = unsafe { libc::ioctl(fd, request as libc::Ioctl, argument as libc::c_ulong) };
    if r < 0 {
        Err(errno())
    } else {
        Ok(i64::from(r))
    }
}

pub fn close(fd: i32) {
    unsafe {
        libc::close(fd);
    }
}

fn page_size() -> usize {
    let n = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    usize::try_from(n).unwrap_or(4096)
}

const BUSY: u32 = 1 << 31;
const DISCARD: u32 = 1 << 30;
const HEADER: u64 = 8;

#[derive(Debug)]
pub struct Ring {
    consumer: *mut libc::c_void,
    producer: *mut libc::c_void,
    page: usize,
    size: usize,
    fd: i32,
}

unsafe impl Send for Ring {}
unsafe impl Sync for Ring {}

impl Ring {
    pub fn open(fd: i32, size: usize) -> Result<Self, i32> {
        let page = page_size();
        let consumer = unsafe {
            libc::mmap(
                null_mut(),
                page,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd,
                0,
            )
        };
        if consumer == libc::MAP_FAILED {
            return Err(errno());
        }
        let offset = libc::off_t::try_from(page).map_err(|_| libc::EINVAL)?;
        let producer = unsafe {
            libc::mmap(
                null_mut(),
                page + 2 * size,
                libc::PROT_READ,
                libc::MAP_SHARED,
                fd,
                offset,
            )
        };
        if producer == libc::MAP_FAILED {
            let e = errno();
            unsafe {
                libc::munmap(consumer, page);
            }
            return Err(e);
        }
        Ok(Self {
            consumer,
            producer,
            page,
            size,
            fd,
        })
    }

    fn consumer_pos(&self) -> &AtomicU64 {
        unsafe { &*self.consumer.cast::<AtomicU64>() }
    }

    fn producer_pos(&self) -> &AtomicU64 {
        unsafe { &*self.producer.cast::<AtomicU64>() }
    }

    fn data(&self) -> *const u8 {
        unsafe { self.producer.cast::<u8>().cast_const().add(self.page) }
    }

    fn take(&self) -> Option<Vec<u8>> {
        let mask = (self.size as u64) - 1;
        loop {
            let at = self.consumer_pos().load(Ordering::Acquire);
            let end = self.producer_pos().load(Ordering::Acquire);
            if at >= end {
                return None;
            }
            let offset = usize::try_from(at & mask).ok()?;
            let header = unsafe { self.data().add(offset).cast::<u32>() };
            let word = unsafe { read_volatile(header) };
            fence(Ordering::Acquire);
            if word & BUSY != 0 {
                return None;
            }
            let length = u64::from(word & !(BUSY | DISCARD));
            let next = at + ((length + HEADER + 7) & !7);
            let sample = if word & DISCARD == 0 {
                let mut out = vec![0u8; usize::try_from(length).ok()?];
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        self.data().add(offset + 8),
                        out.as_mut_ptr(),
                        out.len(),
                    );
                }
                Some(out)
            } else {
                None
            };
            self.consumer_pos().store(next, Ordering::Release);
            if sample.is_some() {
                return sample;
            }
        }
    }

    pub fn next(&self, timeout_ms: i32) -> Result<Option<Vec<u8>>, i32> {
        if let Some(sample) = self.take() {
            return Ok(Some(sample));
        }
        let mut poller = libc::pollfd {
            fd: self.fd,
            events: libc::POLLIN,
            revents: 0,
        };
        let r = unsafe { libc::poll(&mut poller, 1, timeout_ms) };
        if r < 0 {
            let e = errno();
            return if e == libc::EINTR { Ok(None) } else { Err(e) };
        }
        Ok(self.take())
    }
}

impl Drop for Ring {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.consumer, self.page);
            libc::munmap(self.producer, self.page + 2 * self.size);
        }
    }
}
