#![allow(unsafe_code)]

use std::ffi::{c_char, c_int, c_long, c_uint, c_ulong, c_void, CStr, CString};
use std::ptr::{null, null_mut};
use std::sync::{Condvar, Mutex, PoisonError};
use std::time::{Duration, Instant};

use crate::audio::{Clip, Format};
use crate::Refusal;

struct Library {
    handle: *mut c_void,
    path: String,
}

impl Library {
    fn open(path: &str) -> Result<Library, Refusal> {
        let c = CString::new(path)
            .map_err(|_| Refusal::Unsupported(format!("{path}: the path holds a NUL byte")))?;
        let handle = unsafe { libc::dlopen(c.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
        if handle.is_null() {
            return Err(Refusal::Unsupported(format!(
                "no audio system: {path} does not load ({})",
                loader_error()
            )));
        }
        Ok(Library {
            handle,
            path: path.to_string(),
        })
    }

    fn symbol<T: Copy>(&self, name: &str) -> Result<T, Refusal> {
        let missing = || Refusal::Unsupported(format!("{} does not export {name}", self.path));
        if std::mem::size_of::<T>() != std::mem::size_of::<*mut c_void>() {
            return Err(missing());
        }
        let c = CString::new(name).map_err(|_| missing())?;
        let found = unsafe { libc::dlsym(self.handle, c.as_ptr()) };
        if found.is_null() {
            return Err(missing());
        }
        Ok(unsafe { std::mem::transmute_copy::<*mut c_void, T>(&found) })
    }
}

fn loader_error() -> String {
    let e = unsafe { libc::dlerror() };
    if e.is_null() {
        "no reason given".into()
    } else {
        unsafe { CStr::from_ptr(e) }.to_string_lossy().into_owned()
    }
}

fn locked<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(PoisonError::into_inner)
}

fn deadline(format: Format, frames: usize) -> Instant {
    Instant::now() + Duration::from_secs_f64(format.seconds(frames)) + Duration::from_secs(2)
}

pub fn play(library: &str, clip: &Clip) -> Result<(), Refusal> {
    let lib = Library::open(library)?;
    if cfg!(target_vendor = "apple") {
        CoreAudio::load(&lib)?.play(clip)
    } else {
        Alsa::load(&lib)?.play(clip)
    }
}

pub fn capture(library: &str, format: Format, frames: usize) -> Result<Clip, Refusal> {
    let lib = Library::open(library)?;
    let samples = if cfg!(target_vendor = "apple") {
        CoreAudio::load(&lib)?.capture(format, frames)?
    } else {
        Alsa::load(&lib)?.capture(format, frames)?
    };
    Clip::new(
        format,
        samples
            .into_iter()
            .map(|s| f64::from(s).clamp(-1.0, 1.0))
            .collect(),
    )
    .map_err(Refusal::Refused)
}

pub fn device_format(library: &str, input: bool) -> Result<Option<Format>, Refusal> {
    let lib = Library::open(library)?;
    if cfg!(target_vendor = "apple") {
        Ok(CoreAudio::load(&lib)?.device_format(input))
    } else {
        Ok(Alsa::load(&lib)?.device_format(input))
    }
}

fn interleaved_f32(clip: &Clip) -> Vec<f32> {
    clip.samples.iter().map(|s| *s as f32).collect()
}

type OsStatus = i32;
type Queue = *mut c_void;

#[repr(C)]
struct StreamDescription {
    rate: f64,
    format_id: u32,
    flags: u32,
    bytes_per_packet: u32,
    frames_per_packet: u32,
    bytes_per_frame: u32,
    channels: u32,
    bits: u32,
    reserved: u32,
}

impl StreamDescription {
    fn float(format: Format) -> StreamDescription {
        let channels = u32::from(format.channels);
        StreamDescription {
            rate: f64::from(format.rate),
            format_id: u32::from_be_bytes(*b"lpcm"),
            flags: 1 | 8,
            bytes_per_packet: 4 * channels,
            frames_per_packet: 1,
            bytes_per_frame: 4 * channels,
            channels,
            bits: 32,
            reserved: 0,
        }
    }
}

#[repr(C)]
struct QueueBuffer {
    capacity: u32,
    data: *mut c_void,
    size: u32,
    user: *mut c_void,
    descriptions_capacity: u32,
    descriptions: *mut c_void,
    descriptions_count: u32,
}

#[repr(C)]
struct PropertyAddress {
    selector: u32,
    scope: u32,
    element: u32,
}

type OutputCallback = extern "C" fn(*mut c_void, Queue, *mut QueueBuffer);
type InputCallback =
    extern "C" fn(*mut c_void, Queue, *mut QueueBuffer, *const c_void, u32, *const c_void);
type Enqueue = unsafe extern "C" fn(Queue, *mut QueueBuffer, u32, *const c_void) -> OsStatus;

const SYSTEM_OBJECT: u32 = 1;
const BUFFER_BYTES: usize = 1 << 15;

fn code(tag: &[u8; 4]) -> u32 {
    u32::from_be_bytes(*tag)
}

struct CoreAudio {
    new_output: unsafe extern "C" fn(
        *const StreamDescription,
        OutputCallback,
        *mut c_void,
        *mut c_void,
        *mut c_void,
        u32,
        *mut Queue,
    ) -> OsStatus,
    new_input: unsafe extern "C" fn(
        *const StreamDescription,
        InputCallback,
        *mut c_void,
        *mut c_void,
        *mut c_void,
        u32,
        *mut Queue,
    ) -> OsStatus,
    allocate: unsafe extern "C" fn(Queue, u32, *mut *mut QueueBuffer) -> OsStatus,
    enqueue: Enqueue,
    start: unsafe extern "C" fn(Queue, *const c_void) -> OsStatus,
    stop: unsafe extern "C" fn(Queue, u8) -> OsStatus,
    dispose: unsafe extern "C" fn(Queue, u8) -> OsStatus,
    queue_property: unsafe extern "C" fn(Queue, u32, *mut c_void, *mut u32) -> OsStatus,
    property_size:
        unsafe extern "C" fn(u32, *const PropertyAddress, u32, *const c_void, *mut u32) -> OsStatus,
    property: unsafe extern "C" fn(
        u32,
        *const PropertyAddress,
        u32,
        *const c_void,
        *mut u32,
        *mut c_void,
    ) -> OsStatus,
}

#[derive(Default)]
struct Drained {
    done: Mutex<usize>,
    wake: Condvar,
}

extern "C" fn on_output(user: *mut c_void, _: Queue, _: *mut QueueBuffer) {
    let drained = unsafe { &*user.cast::<Drained>() };
    *locked(&drained.done) += 1;
    drained.wake.notify_all();
}

struct Heard {
    samples: Mutex<Vec<f32>>,
    wake: Condvar,
    want: usize,
    enqueue: Enqueue,
}

extern "C" fn on_input(
    user: *mut c_void,
    queue: Queue,
    buffer: *mut QueueBuffer,
    _: *const c_void,
    _: u32,
    _: *const c_void,
) {
    let heard = unsafe { &*user.cast::<Heard>() };
    let got = unsafe {
        std::slice::from_raw_parts(
            (*buffer).data.cast::<f32>(),
            (*buffer).size as usize / std::mem::size_of::<f32>(),
        )
    };
    let mut samples = locked(&heard.samples);
    let room = heard.want.saturating_sub(samples.len());
    samples.extend_from_slice(&got[..got.len().min(room)]);
    let full = samples.len() >= heard.want;
    drop(samples);
    if full {
        heard.wake.notify_all();
    } else {
        unsafe { (heard.enqueue)(queue, buffer, 0, null()) };
    }
}

fn status(st: OsStatus, call: &str) -> Result<(), Refusal> {
    if st == 0 {
        Ok(())
    } else {
        Err(Refusal::Refused(format!("{call}: OSStatus {st}")))
    }
}

impl CoreAudio {
    fn load(lib: &Library) -> Result<CoreAudio, Refusal> {
        Ok(CoreAudio {
            new_output: lib.symbol("AudioQueueNewOutput")?,
            new_input: lib.symbol("AudioQueueNewInput")?,
            allocate: lib.symbol("AudioQueueAllocateBuffer")?,
            enqueue: lib.symbol("AudioQueueEnqueueBuffer")?,
            start: lib.symbol("AudioQueueStart")?,
            stop: lib.symbol("AudioQueueStop")?,
            dispose: lib.symbol("AudioQueueDispose")?,
            queue_property: lib.symbol("AudioQueueGetProperty")?,
            property_size: lib.symbol("AudioObjectGetPropertyDataSize")?,
            property: lib.symbol("AudioObjectGetPropertyData")?,
        })
    }

    fn read<T: Copy + Default>(&self, object: u32, address: &PropertyAddress) -> Option<T> {
        let mut value = T::default();
        let mut size = u32::try_from(std::mem::size_of::<T>()).ok()?;
        let st = unsafe {
            (self.property)(
                object,
                address,
                0,
                null(),
                &mut size,
                std::ptr::from_mut(&mut value).cast(),
            )
        };
        (st == 0).then_some(value)
    }

    fn device_format(&self, input: bool) -> Option<Format> {
        let which = if input { code(b"dIn ") } else { code(b"dOut") };
        let global = code(b"glob");
        let device: u32 = self.read(
            SYSTEM_OBJECT,
            &PropertyAddress {
                selector: which,
                scope: global,
                element: 0,
            },
        )?;
        if device == 0 {
            return None;
        }
        let rate: f64 = self.read(
            device,
            &PropertyAddress {
                selector: code(b"nsrt"),
                scope: global,
                element: 0,
            },
        )?;
        let layout = PropertyAddress {
            selector: code(b"slay"),
            scope: if input { code(b"inpt") } else { code(b"outp") },
            element: 0,
        };
        let mut size = 0u32;
        let st = unsafe { (self.property_size)(device, &layout, 0, null(), &mut size) };
        if st != 0 || size < 8 {
            return None;
        }
        let mut words = vec![0u64; (size as usize).div_ceil(8)];
        let st = unsafe {
            (self.property)(
                device,
                &layout,
                0,
                null(),
                &mut size,
                words.as_mut_ptr().cast(),
            )
        };
        if st != 0 {
            return None;
        }
        let bytes: Vec<u8> = words.iter().flat_map(|w| w.to_ne_bytes()).collect();
        let word = |at: usize| {
            bytes
                .get(at..at + 4)
                .map(|b| u32::from_ne_bytes([b[0], b[1], b[2], b[3]]))
        };
        let buffers = word(0)? as usize;
        let channels: u32 = (0..buffers).map(|i| word(8 + i * 16).unwrap_or(0)).sum();
        let format = Format::new(rate.round() as i64, i64::from(channels)).ok()?;
        Some(format)
    }

    fn running(&self, queue: Queue) -> bool {
        let mut on = 0u32;
        let mut size = 4u32;
        let st = unsafe {
            (self.queue_property)(
                queue,
                code(b"aqrn"),
                std::ptr::from_mut(&mut on).cast(),
                &mut size,
            )
        };
        st == 0 && on != 0
    }

    fn play(&self, clip: &Clip) -> Result<(), Refusal> {
        if self.device_format(false).is_none() {
            return Err(Refusal::NotFound("no audio output device".into()));
        }
        let description = StreamDescription::float(clip.format);
        let drained = Box::new(Drained::default());
        let mut queue: Queue = null_mut();
        status(
            unsafe {
                (self.new_output)(
                    &description,
                    on_output,
                    std::ptr::from_ref::<Drained>(&*drained).cast_mut().cast(),
                    null_mut(),
                    null_mut(),
                    0,
                    &mut queue,
                )
            },
            "AudioQueueNewOutput",
        )?;
        let result = self.drive_output(queue, clip, &drained);
        unsafe {
            (self.stop)(queue, 1);
            (self.dispose)(queue, 1);
        }
        result
    }

    fn drive_output(&self, queue: Queue, clip: &Clip, drained: &Drained) -> Result<(), Refusal> {
        let bytes: Vec<u8> = interleaved_f32(clip)
            .into_iter()
            .flat_map(f32::to_ne_bytes)
            .collect();
        let frame = 4 * usize::from(clip.format.channels);
        let chunk = (BUFFER_BYTES / frame).max(1) * frame;
        let mut buffers = 0usize;
        for piece in bytes.chunks(chunk) {
            let mut buffer: *mut QueueBuffer = null_mut();
            let size = u32::try_from(piece.len()).map_err(|e| Refusal::Refused(e.to_string()))?;
            status(
                unsafe { (self.allocate)(queue, size, &mut buffer) },
                "AudioQueueAllocateBuffer",
            )?;
            unsafe {
                std::ptr::copy_nonoverlapping(
                    piece.as_ptr(),
                    (*buffer).data.cast::<u8>(),
                    piece.len(),
                );
                (*buffer).size = size;
            }
            status(
                unsafe { (self.enqueue)(queue, buffer, 0, null()) },
                "AudioQueueEnqueueBuffer",
            )?;
            buffers += 1;
        }
        if buffers == 0 {
            return Ok(());
        }
        status(unsafe { (self.start)(queue, null()) }, "AudioQueueStart")?;
        let until = deadline(clip.format, clip.frames());
        let mut done = locked(&drained.done);
        while *done < buffers {
            let now = Instant::now();
            if now >= until {
                return Err(Refusal::Timeout(format!(
                    "the output device played {done} of {buffers} buffers before the deadline"
                )));
            }
            done = drained
                .wake
                .wait_timeout(done, until - now)
                .unwrap_or_else(PoisonError::into_inner)
                .0;
        }
        drop(done);
        unsafe { (self.stop)(queue, 0) };
        let tail = Instant::now() + Duration::from_secs(1);
        while self.running(queue) && Instant::now() < tail {
            std::thread::sleep(Duration::from_millis(5));
        }
        Ok(())
    }

    fn capture(&self, format: Format, frames: usize) -> Result<Vec<f32>, Refusal> {
        if self.device_format(true).is_none() {
            return Err(Refusal::NotFound("no audio input device".into()));
        }
        let want = frames * usize::from(format.channels);
        let description = StreamDescription::float(format);
        let heard = Box::new(Heard {
            samples: Mutex::new(Vec::with_capacity(want)),
            wake: Condvar::new(),
            want,
            enqueue: self.enqueue,
        });
        let mut queue: Queue = null_mut();
        status(
            unsafe {
                (self.new_input)(
                    &description,
                    on_input,
                    std::ptr::from_ref::<Heard>(&*heard).cast_mut().cast(),
                    null_mut(),
                    null_mut(),
                    0,
                    &mut queue,
                )
            },
            "AudioQueueNewInput",
        )?;
        let result = self.drive_input(queue, format, frames, &heard);
        unsafe {
            (self.stop)(queue, 1);
            (self.dispose)(queue, 1);
        }
        result?;
        let samples = std::mem::take(&mut *locked(&heard.samples));
        Ok(samples)
    }

    fn drive_input(
        &self,
        queue: Queue,
        format: Format,
        frames: usize,
        heard: &Heard,
    ) -> Result<(), Refusal> {
        if heard.want == 0 {
            return Ok(());
        }
        let frame = 4 * usize::from(format.channels);
        let chunk = (BUFFER_BYTES / frame).max(1) * frame;
        let size = u32::try_from(chunk).map_err(|e| Refusal::Refused(e.to_string()))?;
        for _ in 0..3 {
            let mut buffer: *mut QueueBuffer = null_mut();
            status(
                unsafe { (self.allocate)(queue, size, &mut buffer) },
                "AudioQueueAllocateBuffer",
            )?;
            status(
                unsafe { (self.enqueue)(queue, buffer, 0, null()) },
                "AudioQueueEnqueueBuffer",
            )?;
        }
        status(unsafe { (self.start)(queue, null()) }, "AudioQueueStart")?;
        let until = deadline(format, frames);
        let mut samples = locked(&heard.samples);
        while samples.len() < heard.want {
            let now = Instant::now();
            if now >= until {
                return Err(Refusal::Timeout(format!(
                    "the input device gave {} of {} samples before the deadline",
                    samples.len(),
                    heard.want
                )));
            }
            samples = heard
                .wake
                .wait_timeout(samples, until - now)
                .unwrap_or_else(PoisonError::into_inner)
                .0;
        }
        Ok(())
    }
}

const PLAYBACK: c_int = 0;
const CAPTURE: c_int = 1;
const NONBLOCK: c_int = 1;
const INTERLEAVED: c_int = 3;
const LATENCY_US: c_uint = 100_000;

fn float_format() -> c_int {
    if cfg!(target_endian = "little") {
        14
    } else {
        15
    }
}

struct Alsa {
    open: unsafe extern "C" fn(*mut *mut c_void, *const c_char, c_int, c_int) -> c_int,
    set_params:
        unsafe extern "C" fn(*mut c_void, c_int, c_int, c_uint, c_uint, c_int, c_uint) -> c_int,
    get_params: unsafe extern "C" fn(*mut c_void, *mut c_ulong, *mut c_ulong) -> c_int,
    writei: unsafe extern "C" fn(*mut c_void, *const c_void, c_ulong) -> c_long,
    readi: unsafe extern "C" fn(*mut c_void, *mut c_void, c_ulong) -> c_long,
    recover: unsafe extern "C" fn(*mut c_void, c_int, c_int) -> c_int,
    drain: unsafe extern "C" fn(*mut c_void) -> c_int,
    nonblock: unsafe extern "C" fn(*mut c_void, c_int) -> c_int,
    close: unsafe extern "C" fn(*mut c_void) -> c_int,
    strerror: unsafe extern "C" fn(c_int) -> *const c_char,
    params_malloc: unsafe extern "C" fn(*mut *mut c_void) -> c_int,
    params_free: unsafe extern "C" fn(*mut c_void),
    params_any: unsafe extern "C" fn(*mut c_void, *mut c_void) -> c_int,
    rate_near: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_uint, *mut c_int) -> c_int,
    channels_near: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_uint) -> c_int,
}

struct Pcm<'a> {
    alsa: &'a Alsa,
    handle: *mut c_void,
}

impl Drop for Pcm<'_> {
    fn drop(&mut self) {
        unsafe { (self.alsa.close)(self.handle) };
    }
}

impl Alsa {
    fn load(lib: &Library) -> Result<Alsa, Refusal> {
        Ok(Alsa {
            open: lib.symbol("snd_pcm_open")?,
            set_params: lib.symbol("snd_pcm_set_params")?,
            get_params: lib.symbol("snd_pcm_get_params")?,
            writei: lib.symbol("snd_pcm_writei")?,
            readi: lib.symbol("snd_pcm_readi")?,
            recover: lib.symbol("snd_pcm_recover")?,
            drain: lib.symbol("snd_pcm_drain")?,
            nonblock: lib.symbol("snd_pcm_nonblock")?,
            close: lib.symbol("snd_pcm_close")?,
            strerror: lib.symbol("snd_strerror")?,
            params_malloc: lib.symbol("snd_pcm_hw_params_malloc")?,
            params_free: lib.symbol("snd_pcm_hw_params_free")?,
            params_any: lib.symbol("snd_pcm_hw_params_any")?,
            rate_near: lib.symbol("snd_pcm_hw_params_set_rate_near")?,
            channels_near: lib.symbol("snd_pcm_hw_params_set_channels_near")?,
        })
    }

    fn reason(&self, err: c_int) -> String {
        let text = unsafe { (self.strerror)(err) };
        if text.is_null() {
            format!("error {err}")
        } else {
            unsafe { CStr::from_ptr(text) }
                .to_string_lossy()
                .into_owned()
        }
    }

    fn refusal(&self, call: &str, err: c_int) -> Refusal {
        let why = format!("{call}: {}", self.reason(err));
        match -err {
            libc::ENOENT | libc::ENODEV | libc::ENXIO => Refusal::NotFound(why),
            libc::EACCES | libc::EPERM => Refusal::Denied(why),
            _ => Refusal::Refused(why),
        }
    }

    fn pcm(&self, stream: c_int, mode: c_int) -> Result<Pcm<'_>, Refusal> {
        let mut handle: *mut c_void = null_mut();
        let st = unsafe { (self.open)(&mut handle, c"default".as_ptr(), stream, mode) };
        if st < 0 {
            return Err(self.refusal("snd_pcm_open", st));
        }
        Ok(Pcm { alsa: self, handle })
    }

    fn configure(&self, pcm: &Pcm<'_>, format: Format) -> Result<c_ulong, Refusal> {
        let st = unsafe {
            (self.set_params)(
                pcm.handle,
                float_format(),
                INTERLEAVED,
                c_uint::from(format.channels),
                format.rate,
                1,
                LATENCY_US,
            )
        };
        if st < 0 {
            return Err(self.refusal("snd_pcm_set_params", st));
        }
        let mut buffer: c_ulong = 0;
        let mut period: c_ulong = 0;
        let st = unsafe { (self.get_params)(pcm.handle, &mut buffer, &mut period) };
        if st < 0 {
            return Err(self.refusal("snd_pcm_get_params", st));
        }
        Ok(period.max(1))
    }

    fn device_format(&self, input: bool) -> Option<Format> {
        let pcm = self
            .pcm(if input { CAPTURE } else { PLAYBACK }, NONBLOCK)
            .ok()?;
        let mut params: *mut c_void = null_mut();
        if unsafe { (self.params_malloc)(&mut params) } < 0 || params.is_null() {
            return None;
        }
        let mut rate: c_uint = 48_000;
        let mut dir: c_int = 0;
        let mut channels: c_uint = 2;
        let ok = unsafe {
            (self.params_any)(pcm.handle, params) >= 0
                && (self.rate_near)(pcm.handle, params, &mut rate, &mut dir) >= 0
                && (self.channels_near)(pcm.handle, params, &mut channels) >= 0
        };
        unsafe { (self.params_free)(params) };
        if !ok {
            return None;
        }
        Format::new(i64::from(rate), i64::from(channels)).ok()
    }

    fn transfer(
        &self,
        pcm: &Pcm<'_>,
        call: &str,
        format: Format,
        period: c_ulong,
        samples: usize,
        mut io: impl FnMut(usize, c_ulong) -> c_long,
    ) -> Result<(), Refusal> {
        let channels = usize::from(format.channels);
        let until = deadline(format, samples / channels);
        let mut at = 0usize;
        while at < samples {
            if Instant::now() >= until {
                return Err(Refusal::Timeout(format!(
                    "{call} moved {at} of {samples} samples before the deadline"
                )));
            }
            let left = c_ulong::try_from((samples - at) / channels)
                .unwrap_or(c_ulong::MAX)
                .min(period);
            let n = io(at, left);
            if n == -c_long::from(libc::EAGAIN) {
                std::thread::sleep(Duration::from_millis(2));
                continue;
            }
            if n < 0 {
                let err = c_int::try_from(n).unwrap_or(c_int::MIN);
                if unsafe { (self.recover)(pcm.handle, err, 1) } < 0 {
                    return Err(self.refusal(call, err));
                }
                continue;
            }
            at += usize::try_from(n).unwrap_or(0) * channels;
        }
        Ok(())
    }

    fn play(&self, clip: &Clip) -> Result<(), Refusal> {
        let pcm = self.pcm(PLAYBACK, NONBLOCK)?;
        let period = self.configure(&pcm, clip.format)?;
        let samples = interleaved_f32(clip);
        self.transfer(
            &pcm,
            "snd_pcm_writei",
            clip.format,
            period,
            samples.len(),
            |at, left| unsafe { (self.writei)(pcm.handle, samples[at..].as_ptr().cast(), left) },
        )?;
        let st = unsafe { (self.nonblock)(pcm.handle, 0) };
        if st < 0 {
            return Err(self.refusal("snd_pcm_nonblock", st));
        }
        let st = unsafe { (self.drain)(pcm.handle) };
        if st < 0 {
            return Err(self.refusal("snd_pcm_drain", st));
        }
        Ok(())
    }

    fn capture(&self, format: Format, frames: usize) -> Result<Vec<f32>, Refusal> {
        let pcm = self.pcm(CAPTURE, NONBLOCK)?;
        let period = self.configure(&pcm, format)?;
        let mut samples = vec![0f32; frames * usize::from(format.channels)];
        let total = samples.len();
        self.transfer(
            &pcm,
            "snd_pcm_readi",
            format,
            period,
            total,
            |at, left| unsafe { (self.readi)(pcm.handle, samples[at..].as_mut_ptr().cast(), left) },
        )?;
        Ok(samples)
    }
}
