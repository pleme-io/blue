use std::collections::{BTreeMap, VecDeque};
use std::io::ErrorKind;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, UdpSocket};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

#[cfg(feature = "sys")]
mod words;

#[cfg(feature = "sys")]
pub use words::{host_clock, host_flash_on, install_wire, provide_loopback, CARRIER};

pub const MTU: usize = 1280;
pub const TIDE_BYTE: u8 = 0x01;
pub const FLASH_BYTE: u8 = 0x02;
pub const STAMP_BYTES: usize = 8;
pub const FLASH_INBOX: usize = 256;
pub const RING_FRAMES: usize = 64;
pub const RING_BYTES: usize = 64 * 1024;
pub const DEFAULT_FLASH_RATE: u64 = 16 * 1024;
pub const RATE_LIMITED: &str = "rate_limited";
pub const LOOPBACK_QUEUE: usize = 1024;
pub const LOOPBACK_FIRST_PORT: u16 = 49152;

static FLASH_RATE: OnceLock<u64> = OnceLock::new();

pub fn set_flash_rate(bytes_per_second: u64) {
    let _ = FLASH_RATE.set(bytes_per_second);
}

#[must_use]
pub fn flash_rate() -> u64 {
    FLASH_RATE.get().copied().unwrap_or(DEFAULT_FLASH_RATE)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Bucket {
    rate: u64,
    burst: u64,
    tokens: u64,
    at_ms: Option<i64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RateRefusal {
    pub bytes: usize,
    pub rate: u64,
    pub burst: u64,
    pub wait_ms: Option<u64>,
}

impl std::fmt::Display for RateRefusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "a Flash frame of {} bytes is past the wire's rate of {} bytes a second (burst {})",
            self.bytes, self.rate, self.burst
        )?;
        match self.wait_ms {
            Some(ms) => write!(f, "; it fits in {ms} ms"),
            None => f.write_str("; no wait makes it fit"),
        }
    }
}

impl Bucket {
    #[must_use]
    pub fn new(rate: u64) -> Self {
        Self {
            rate,
            burst: rate,
            tokens: rate.saturating_mul(1000),
            at_ms: None,
        }
    }

    fn refill(&mut self, now_ms: i64) {
        if let Some(at) = self.at_ms {
            let elapsed = u64::try_from(now_ms.saturating_sub(at)).unwrap_or(0);
            self.tokens = self.burst.saturating_mul(1000).min(
                self.tokens
                    .saturating_add(self.rate.saturating_mul(elapsed)),
            );
        }
        self.at_ms = Some(self.at_ms.map_or(now_ms, |at| at.max(now_ms)));
    }

    pub fn spend(&mut self, bytes: usize, now_ms: i64) -> Result<(), RateRefusal> {
        self.refill(now_ms);
        let cost = u64::try_from(bytes)
            .unwrap_or(u64::MAX)
            .saturating_mul(1000);
        if cost <= self.tokens {
            self.tokens -= cost;
            return Ok(());
        }
        Err(RateRefusal {
            bytes,
            rate: self.rate,
            burst: self.burst,
            wait_ms: (cost <= self.burst.saturating_mul(1000))
                .then(|| (cost - self.tokens).div_ceil(self.rate)),
        })
    }

    #[must_use]
    pub fn tokens(&self) -> u64 {
        self.tokens
    }

    #[must_use]
    pub fn rate(&self) -> u64 {
        self.rate
    }
}

pub type ClockRead = Arc<dyn Fn() -> i64 + Send + Sync>;

type Mailbox = VecDeque<(SocketAddr, Vec<u8>)>;

#[derive(Default)]
pub struct LoopbackNet {
    boxes: Mutex<BTreeMap<SocketAddr, Mailbox>>,
}

fn unspecified(addr: SocketAddr) -> SocketAddr {
    let ip = match addr.ip() {
        IpAddr::V4(_) => IpAddr::V4(Ipv4Addr::UNSPECIFIED),
        IpAddr::V6(_) => IpAddr::V6(Ipv6Addr::UNSPECIFIED),
    };
    SocketAddr::new(ip, addr.port())
}

impl LoopbackNet {
    fn boxes(&self) -> MutexGuard<'_, BTreeMap<SocketAddr, Mailbox>> {
        self.boxes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub fn bind(self: &Arc<Self>, addr: SocketAddr) -> Result<Endpoint, String> {
        let mut boxes = self.boxes();
        let at = if addr.port() == 0 {
            (LOOPBACK_FIRST_PORT..=u16::MAX)
                .map(|port| SocketAddr::new(addr.ip(), port))
                .find(|a| !boxes.contains_key(a))
                .ok_or_else(|| format!("{addr}: no loopback port is free"))?
        } else if boxes.contains_key(&addr) {
            return Err(format!("{addr}: the loopback address is in use"));
        } else {
            addr
        };
        boxes.insert(at, VecDeque::new());
        Ok(Endpoint {
            net: Arc::clone(self),
            at,
        })
    }

    fn deliver(&self, from: SocketAddr, to: SocketAddr, datagram: &[u8]) -> usize {
        let mut boxes = self.boxes();
        let target = if boxes.contains_key(&to) {
            Some(to)
        } else {
            Some(unspecified(to)).filter(|any| boxes.contains_key(any))
        };
        if let Some(queue) = target.and_then(|t| boxes.get_mut(&t)) {
            if queue.len() < LOOPBACK_QUEUE {
                queue.push_back((from, datagram.to_vec()));
            }
        }
        datagram.len()
    }

    fn take(&self, at: SocketAddr) -> Vec<(SocketAddr, Vec<u8>)> {
        self.boxes()
            .get_mut(&at)
            .map(|queue| queue.drain(..).collect())
            .unwrap_or_default()
    }

    #[must_use]
    pub fn bound(&self) -> usize {
        self.boxes().len()
    }
}

pub struct Endpoint {
    net: Arc<LoopbackNet>,
    at: SocketAddr,
}

impl Drop for Endpoint {
    fn drop(&mut self) {
        self.net.boxes().remove(&self.at);
    }
}

enum Link {
    Udp(UdpSocket),
    Loopback(Endpoint),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SendError {
    Frame(String),
    Rate(RateRefusal),
}

impl From<String> for SendError {
    fn from(e: String) -> Self {
        SendError::Frame(e)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Channel {
    Tide,
    Flash,
}

impl Channel {
    #[must_use]
    pub fn byte(self) -> u8 {
        match self {
            Channel::Tide => TIDE_BYTE,
            Channel::Flash => FLASH_BYTE,
        }
    }

    #[must_use]
    pub fn of(byte: u8) -> Option<Channel> {
        match byte {
            TIDE_BYTE => Some(Channel::Tide),
            FLASH_BYTE => Some(Channel::Flash),
            _ => None,
        }
    }

    #[must_use]
    pub const fn header(self) -> usize {
        match self {
            Channel::Tide => 1 + STAMP_BYTES,
            Channel::Flash => 1,
        }
    }

    #[must_use]
    pub const fn room(self) -> usize {
        MTU - self.header()
    }

    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Channel::Tide => "Tide",
            Channel::Flash => "Flash",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Frame {
    pub channel: Channel,
    pub stamp_ms: Option<i64>,
    pub payload: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum WireError {
    #[error("a {channel} frame is at most {MTU} bytes with its header; this payload of {payload} bytes makes {len}")]
    PastMtu {
        channel: &'static str,
        payload: usize,
        len: usize,
    },
    #[error("an empty datagram is no frame")]
    Empty,
    #[error("the framing byte {0:#04x} names no channel; 0x01 is Tide, 0x02 is Flash")]
    UnknownChannel(u8),
    #[error("a Tide frame carries an {STAMP_BYTES}-byte stamp after its framing byte; this datagram has {0} bytes")]
    ShortStamp(usize),
    #[error("a datagram of {0} bytes is past the {MTU}-byte MTU")]
    PastMtuReceived(usize),
}

pub fn encode(channel: Channel, stamp_ms: i64, payload: &[u8]) -> Result<Vec<u8>, WireError> {
    let len = channel.header() + payload.len();
    if len > MTU {
        return Err(WireError::PastMtu {
            channel: channel.name(),
            payload: payload.len(),
            len,
        });
    }
    let mut out = Vec::with_capacity(len);
    out.push(channel.byte());
    if channel == Channel::Tide {
        out.extend_from_slice(&stamp_ms.to_be_bytes());
    }
    out.extend_from_slice(payload);
    Ok(out)
}

pub fn decode(datagram: &[u8]) -> Result<Frame, WireError> {
    if datagram.len() > MTU {
        return Err(WireError::PastMtuReceived(datagram.len()));
    }
    let (&first, rest) = datagram.split_first().ok_or(WireError::Empty)?;
    let channel = Channel::of(first).ok_or(WireError::UnknownChannel(first))?;
    match channel {
        Channel::Flash => Ok(Frame {
            channel,
            stamp_ms: None,
            payload: rest.to_vec(),
        }),
        Channel::Tide => {
            if rest.len() < STAMP_BYTES {
                return Err(WireError::ShortStamp(datagram.len()));
            }
            let (stamp, payload) = rest.split_at(STAMP_BYTES);
            let mut be = [0u8; STAMP_BYTES];
            be.copy_from_slice(stamp);
            Ok(Frame {
                channel,
                stamp_ms: Some(i64::from_be_bytes(be)),
                payload: payload.to_vec(),
            })
        }
    }
}

#[derive(Clone, Debug)]
pub struct Ring<T> {
    items: VecDeque<(T, usize)>,
    bytes: usize,
    max_frames: usize,
    max_bytes: usize,
    evicted: u64,
}

impl<T> Ring<T> {
    #[must_use]
    pub fn new(max_frames: usize, max_bytes: usize) -> Self {
        Self {
            items: VecDeque::new(),
            bytes: 0,
            max_frames: max_frames.max(1),
            max_bytes: max_bytes.max(MTU),
            evicted: 0,
        }
    }

    pub fn push(&mut self, item: T, len: usize) -> usize {
        let mut evicted = 0;
        while !self.items.is_empty()
            && (self.items.len() >= self.max_frames || self.bytes + len > self.max_bytes)
        {
            self.pop();
            evicted += 1;
        }
        self.items.push_back((item, len));
        self.bytes += len;
        self.evicted += evicted as u64;
        evicted
    }

    pub fn pop(&mut self) -> Option<T> {
        self.items.pop_front().map(|(item, len)| {
            self.bytes -= len;
            item
        })
    }

    #[must_use]
    pub fn front_len(&self) -> Option<usize> {
        self.items.front().map(|(_, len)| *len)
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.items.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    #[must_use]
    pub fn bytes(&self) -> usize {
        self.bytes
    }

    #[must_use]
    pub fn evicted(&self) -> u64 {
        self.evicted
    }

    #[must_use]
    pub fn bounds(&self) -> (usize, usize) {
        (self.max_frames, self.max_bytes)
    }

    #[must_use]
    pub fn room(&self) -> (usize, usize) {
        (
            self.max_frames.saturating_sub(self.items.len()),
            self.max_bytes.saturating_sub(self.bytes),
        )
    }

    pub fn take_where(&mut self, mut wanted: impl FnMut(&T) -> bool) -> Vec<T> {
        let mut taken = Vec::new();
        let mut kept = VecDeque::with_capacity(self.items.len());
        for (item, len) in std::mem::take(&mut self.items) {
            if wanted(&item) {
                self.bytes -= len;
                taken.push(item);
            } else {
                kept.push_back((item, len));
            }
        }
        self.items = kept;
        taken
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Received {
    pub from: SocketAddr,
    pub stamp_ms: Option<i64>,
    pub payload: String,
    pub bytes: usize,
}

#[derive(Clone, Debug)]
struct Outgoing {
    peer: SocketAddr,
    payload: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub sent: u64,
    pub received: u64,
    pub dropped: u64,
    pub refused: u64,
}

pub struct Wire {
    link: Link,
    flash_bucket: Bucket,
    flash: bool,
    tide: bool,
    flash_in: VecDeque<Received>,
    tide_in: Ring<Received>,
    tide_out: Ring<Outgoing>,
    flash_counts: Counts,
    tide_counts: Counts,
    malformed: u64,
}

impl Wire {
    pub fn bind(addr: &str) -> std::io::Result<Self> {
        Ok(Self::over(Link::Udp(UdpSocket::bind(addr)?)))
    }

    #[must_use]
    pub fn on(endpoint: Endpoint) -> Self {
        Self::over(Link::Loopback(endpoint))
    }

    fn over(link: Link) -> Self {
        Self {
            link,
            flash_bucket: Bucket::new(flash_rate()),
            flash: false,
            tide: false,
            flash_in: VecDeque::new(),
            tide_in: Ring::new(RING_FRAMES, RING_BYTES),
            tide_out: Ring::new(RING_FRAMES, RING_BYTES),
            flash_counts: Counts::default(),
            tide_counts: Counts::default(),
            malformed: 0,
        }
    }

    #[must_use]
    pub fn is_loopback(&self) -> bool {
        matches!(self.link, Link::Loopback(_))
    }

    #[must_use]
    pub fn flash_bucket(&self) -> Bucket {
        self.flash_bucket
    }

    pub fn open(&mut self, channel: Channel, ring: (usize, usize)) {
        match channel {
            Channel::Flash => self.flash = true,
            Channel::Tide => {
                self.tide = true;
                self.tide_in = Ring::new(ring.0, ring.1);
                self.tide_out = Ring::new(ring.0, ring.1);
            }
        }
    }

    #[must_use]
    pub fn is_open(&self, channel: Channel) -> bool {
        match channel {
            Channel::Flash => self.flash,
            Channel::Tide => self.tide,
        }
    }

    pub fn close(&mut self, channel: Channel) -> bool {
        match channel {
            Channel::Flash => {
                self.flash = false;
                self.flash_in.clear();
            }
            Channel::Tide => {
                self.tide = false;
                self.tide_in = Ring::new(RING_FRAMES, RING_BYTES);
                self.tide_out = Ring::new(RING_FRAMES, RING_BYTES);
            }
        }
        self.flash || self.tide
    }

    pub fn address(&self) -> std::io::Result<SocketAddr> {
        match &self.link {
            Link::Udp(socket) => socket.local_addr(),
            Link::Loopback(endpoint) => Ok(endpoint.at),
        }
    }

    pub fn flash_put(
        &mut self,
        peer: SocketAddr,
        payload: &[u8],
        now_ms: i64,
    ) -> Result<usize, SendError> {
        let datagram = encode(Channel::Flash, 0, payload).map_err(|e| e.to_string())?;
        let mut bucket = self.flash_bucket;
        if let Err(refusal) = bucket.spend(datagram.len(), now_ms) {
            self.flash_bucket = bucket;
            self.flash_counts.refused += 1;
            return Err(SendError::Rate(refusal));
        }
        let sent = self.transmit(Channel::Flash, peer, &datagram)?;
        self.flash_bucket = bucket;
        Ok(sent)
    }

    pub fn tide_put(&mut self, peer: SocketAddr, payload: &[u8]) -> Result<usize, String> {
        let len = encode(Channel::Tide, 0, payload)
            .map_err(|e| e.to_string())?
            .len();
        Ok(self.tide_out.push(
            Outgoing {
                peer,
                payload: payload.to_vec(),
            },
            len,
        ))
    }

    pub fn tide_queue_all(
        &mut self,
        peer: SocketAddr,
        payloads: &[String],
    ) -> Result<usize, String> {
        let lens = payloads
            .iter()
            .map(|p| encode(Channel::Tide, 0, p.as_bytes()).map(|d| d.len()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        let bytes: usize = lens.iter().sum();
        let (frames_free, bytes_free) = self.tide_out.room();
        if lens.len() > frames_free || bytes > bytes_free {
            return Err(format!(
                "{} Tide frames of {bytes} bytes do not fit the send ring, which has room for {frames_free} frames and {bytes_free} bytes; release what is queued, or open the wire with a larger ring_frames: and ring_bytes:",
                lens.len()
            ));
        }
        for (payload, len) in payloads.iter().zip(lens) {
            self.tide_out.push(
                Outgoing {
                    peer,
                    payload: payload.as_bytes().to_vec(),
                },
                len,
            );
        }
        Ok(bytes)
    }

    pub fn tide_take(&mut self, prefix: &str, timeout: Duration) -> std::io::Result<Vec<Received>> {
        self.wait_for(timeout, |w| {
            Some(w.tide_in.take_where(|r| r.payload.starts_with(prefix))).filter(|t| !t.is_empty())
        })
        .map(Option::unwrap_or_default)
    }

    pub fn tide_release(&mut self, max_bytes: usize, stamp_ms: i64) -> Result<usize, String> {
        let mut sent = 0;
        while let Some(len) = self.tide_out.front_len() {
            if sent + len > max_bytes {
                break;
            }
            let Some(out) = self.tide_out.pop() else {
                break;
            };
            let datagram =
                encode(Channel::Tide, stamp_ms, &out.payload).map_err(|e| e.to_string())?;
            sent += self.transmit(Channel::Tide, out.peer, &datagram)?;
        }
        Ok(sent)
    }

    pub fn tide_send(
        &mut self,
        peer: SocketAddr,
        payload: &[u8],
        stamp_ms: i64,
    ) -> Result<usize, String> {
        let datagram = encode(Channel::Tide, stamp_ms, payload).map_err(|e| e.to_string())?;
        self.transmit(Channel::Tide, peer, &datagram)
    }

    fn transmit(
        &mut self,
        channel: Channel,
        peer: SocketAddr,
        datagram: &[u8],
    ) -> Result<usize, String> {
        let n = match &self.link {
            Link::Udp(socket) => socket
                .send_to(datagram, peer)
                .map_err(|e| format!("{peer}: {e}"))?,
            Link::Loopback(endpoint) => endpoint.net.deliver(endpoint.at, peer, datagram),
        };
        match channel {
            Channel::Flash => self.flash_counts.sent += 1,
            Channel::Tide => self.tide_counts.sent += 1,
        }
        Ok(n)
    }

    fn file(&mut self, datagram: &[u8], from: SocketAddr) {
        let Ok(frame) = decode(datagram) else {
            self.malformed += 1;
            return;
        };
        let Ok(payload) = String::from_utf8(frame.payload) else {
            self.malformed += 1;
            return;
        };
        let received = Received {
            from,
            stamp_ms: frame.stamp_ms,
            payload,
            bytes: datagram.len(),
        };
        match frame.channel {
            Channel::Flash if self.flash && self.flash_in.len() < FLASH_INBOX => {
                self.flash_counts.received += 1;
                self.flash_in.push_back(received);
            }
            Channel::Flash => self.flash_counts.dropped += 1,
            Channel::Tide if self.tide => {
                self.tide_counts.received += 1;
                self.tide_in.push(received, datagram.len());
            }
            Channel::Tide => self.tide_counts.dropped += 1,
        }
    }

    fn waiting(&mut self, channel: Channel) -> Option<Received> {
        match channel {
            Channel::Flash => self.flash_in.pop_front(),
            Channel::Tide => self.tide_in.pop(),
        }
    }

    fn pending(&self) -> std::io::Result<Vec<(SocketAddr, Vec<u8>)>> {
        let socket = match &self.link {
            Link::Loopback(endpoint) => return Ok(endpoint.net.take(endpoint.at)),
            Link::Udp(socket) => socket,
        };
        let mut buf = [0u8; MTU + 1];
        let mut got = Vec::new();
        socket.set_nonblocking(true)?;
        let outcome = loop {
            match socket.recv_from(&mut buf) {
                Ok((n, from)) => got.push((from, buf[..n].to_vec())),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break Ok(()),
                Err(e) if e.kind() == ErrorKind::ConnectionRefused => {}
                Err(e) => break Err(e),
            }
        };
        socket.set_nonblocking(false)?;
        outcome.map(|()| got)
    }

    fn drain(&mut self) -> std::io::Result<()> {
        for (from, datagram) in self.pending()? {
            self.file(&datagram, from);
        }
        Ok(())
    }

    pub fn next(
        &mut self,
        channel: Channel,
        timeout: Duration,
    ) -> std::io::Result<Option<Received>> {
        self.wait_for(timeout, |w| w.waiting(channel))
    }

    fn wait_for<T>(
        &mut self,
        timeout: Duration,
        mut found: impl FnMut(&mut Self) -> Option<T>,
    ) -> std::io::Result<Option<T>> {
        let deadline = Instant::now() + timeout;
        let mut buf = [0u8; MTU + 1];
        loop {
            self.drain()?;
            if let Some(r) = found(self) {
                return Ok(Some(r));
            }
            let left = deadline.saturating_duration_since(Instant::now());
            let Link::Udp(socket) = &self.link else {
                return Ok(None);
            };
            if left.is_zero() {
                return Ok(None);
            }
            socket.set_read_timeout(Some(left))?;
            match socket.recv_from(&mut buf) {
                Ok((n, from)) => self.file(&buf[..n], from),
                Err(e)
                    if matches!(
                        e.kind(),
                        ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::ConnectionRefused
                    ) => {}
                Err(e) => return Err(e),
            }
        }
    }

    #[must_use]
    pub fn counts(&self, channel: Channel) -> Counts {
        match channel {
            Channel::Flash => self.flash_counts,
            Channel::Tide => self.tide_counts,
        }
    }

    #[must_use]
    pub fn queued(&self) -> (usize, usize) {
        (self.tide_out.len(), self.tide_out.bytes())
    }

    #[must_use]
    pub fn evicted(&self) -> (u64, u64) {
        (self.tide_out.evicted(), self.tide_in.evicted())
    }

    #[must_use]
    pub fn malformed(&self) -> u64 {
        self.malformed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pair() -> (Wire, Wire, SocketAddr, SocketAddr) {
        let mut a = Wire::bind("127.0.0.1:0").expect("bind a");
        let mut b = Wire::bind("127.0.0.1:0").expect("bind b");
        for w in [&mut a, &mut b] {
            w.open(Channel::Flash, (RING_FRAMES, RING_BYTES));
            w.open(Channel::Tide, (RING_FRAMES, RING_BYTES));
        }
        let (aa, ba) = (a.address().unwrap(), b.address().unwrap());
        (a, b, aa, ba)
    }

    #[test]
    fn a_flash_frame_is_its_framing_byte_and_its_payload_up_to_the_mtu() {
        let full = vec![b'x'; Channel::Flash.room()];
        let datagram = encode(Channel::Flash, 99, &full).expect("a full Flash frame");
        assert_eq!(datagram.len(), MTU);
        assert_eq!(datagram[0], 0x02);
        assert_eq!(
            decode(&datagram).unwrap(),
            Frame {
                channel: Channel::Flash,
                stamp_ms: None,
                payload: full.clone()
            }
        );
        let over = vec![b'x'; Channel::Flash.room() + 1];
        assert_eq!(
            encode(Channel::Flash, 0, &over),
            Err(WireError::PastMtu {
                channel: "Flash",
                payload: 1280,
                len: 1281
            })
        );
    }

    #[test]
    fn a_tide_frame_carries_its_send_stamp_after_its_framing_byte() {
        let datagram = encode(Channel::Tide, -5, b"bulk").unwrap();
        assert_eq!(datagram[0], 0x01);
        assert_eq!(datagram.len(), 1 + 8 + 4);
        let frame = decode(&datagram).unwrap();
        assert_eq!(frame.stamp_ms, Some(-5));
        assert_eq!(frame.payload, b"bulk");
        assert_eq!(Channel::Tide.room(), 1271);
        assert!(encode(Channel::Tide, 0, &vec![0u8; 1272]).is_err());
        assert!(encode(Channel::Tide, 0, &vec![0u8; 1271]).is_ok());
    }

    #[test]
    fn a_datagram_that_is_no_frame_is_refused_by_name() {
        assert_eq!(decode(&[]), Err(WireError::Empty));
        assert_eq!(decode(&[0x03, 1]), Err(WireError::UnknownChannel(0x03)));
        assert_eq!(decode(&[0x01, 0, 0]), Err(WireError::ShortStamp(3)));
        assert_eq!(
            decode(&vec![0x02; MTU + 1]),
            Err(WireError::PastMtuReceived(1281))
        );
    }

    #[test]
    fn the_ring_evicts_its_oldest_frame_and_never_holds_past_its_bounds() {
        let mut r: Ring<u32> = Ring::new(3, 3000);
        assert_eq!(r.push(1, 1000), 0);
        assert_eq!(r.push(2, 1000), 0);
        assert_eq!(r.push(3, 1000), 0);
        assert_eq!(r.push(4, 1000), 1);
        assert_eq!((r.len(), r.bytes(), r.evicted()), (3, 3000, 1));
        assert_eq!(r.push(5, 1280), 2);
        assert_eq!((r.len(), r.bytes()), (2, 2280));
        assert_eq!(r.push(6, 1280), 1);
        assert!(r.len() <= 3 && r.bytes() <= 3000);
        assert_eq!(r.pop(), Some(5));
        assert_eq!(r.pop(), Some(6));
        assert_eq!(r.pop(), None);
        assert_eq!(r.evicted(), 4);
        let mut held: Ring<usize> = Ring::new(64, 64 * 1024);
        for i in 0..500 {
            held.push(i, 1 + (i * 7919) % MTU);
            assert!(held.len() <= 64 && held.bytes() <= 64 * 1024);
        }
        assert_eq!(Ring::<u8>::new(0, 0).bounds(), (1, MTU));
    }

    #[test]
    fn a_flash_frame_crosses_loopback_whole_and_lands_only_in_the_flash_inbox() {
        let (mut a, mut b, aa, ba) = pair();
        assert_eq!(a.flash_put(ba, b"alert", 0).unwrap(), 6);
        let got = b
            .next(Channel::Flash, Duration::from_secs(2))
            .unwrap()
            .expect("the frame arrives");
        assert_eq!(got.payload, "alert");
        assert_eq!(got.from, aa);
        assert_eq!(got.bytes, 6);
        assert_eq!(got.stamp_ms, None);
        assert_eq!(b.next(Channel::Tide, Duration::ZERO).unwrap(), None);
        assert_eq!(a.counts(Channel::Flash).sent, 1);
        assert_eq!(b.counts(Channel::Flash).received, 1);
        assert!(a.flash_put(ba, &vec![0u8; 1280], 0).is_err());
        assert_eq!(a.counts(Channel::Flash).sent, 1);
    }

    #[test]
    fn tide_frames_wait_in_the_ring_until_released_and_flash_preempts_them() {
        let (mut a, _, _, _) = pair();
        let raw = UdpSocket::bind("127.0.0.1:0").unwrap();
        let ra = raw.local_addr().unwrap();
        for i in 0..3 {
            assert_eq!(a.tide_put(ra, format!("bulk {i}").as_bytes()).unwrap(), 0);
        }
        assert_eq!(a.queued(), (3, 3 * (9 + 6)));
        a.flash_put(ra, b"urgent", 0).unwrap();
        assert_eq!(a.tide_release(29, 7).unwrap(), 15);
        assert_eq!(a.queued(), (2, 30));
        assert_eq!(a.tide_release(1_000_000, 8).unwrap(), 30);
        raw.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let mut buf = [0u8; 2048];
        let order: Vec<Frame> = (0..4)
            .map(|_| {
                let (n, _) = raw.recv_from(&mut buf).unwrap();
                decode(&buf[..n]).unwrap()
            })
            .collect();
        assert_eq!(order[0].channel, Channel::Flash);
        assert_eq!(order[0].payload, b"urgent");
        assert_eq!(
            order[1..].iter().map(|f| f.stamp_ms).collect::<Vec<_>>(),
            vec![Some(7), Some(8), Some(8)]
        );
        assert_eq!(order[3].payload, b"bulk 2");
    }

    #[test]
    fn a_tide_inbox_past_its_bound_evicts_its_oldest_frame() {
        let mut a = Wire::bind("127.0.0.1:0").unwrap();
        let mut b = Wire::bind("127.0.0.1:0").unwrap();
        a.open(Channel::Tide, (RING_FRAMES, RING_BYTES));
        b.open(Channel::Tide, (2, MTU * 2));
        let ba = b.address().unwrap();
        for i in 0..5 {
            a.tide_send(ba, format!("t{i}").as_bytes(), i).unwrap();
        }
        std::thread::sleep(Duration::from_millis(50));
        let first = b
            .next(Channel::Tide, Duration::from_secs(2))
            .unwrap()
            .unwrap();
        let second = b.next(Channel::Tide, Duration::ZERO).unwrap().unwrap();
        assert_eq!(
            (first.payload.as_str(), second.payload.as_str()),
            ("t3", "t4")
        );
        assert_eq!(b.evicted().1, 3);
        assert_eq!(b.counts(Channel::Tide).received, 5);
    }

    #[test]
    fn a_frame_for_a_closed_channel_is_dropped_not_kept() {
        let (mut a, mut b, _, ba) = pair();
        b.close(Channel::Flash);
        a.flash_put(ba, b"nobody listens", 0).unwrap();
        a.tide_send(ba, b"heard", 1).unwrap();
        let got = b
            .next(Channel::Tide, Duration::from_secs(2))
            .unwrap()
            .unwrap();
        assert_eq!(got.payload, "heard");
        b.drain().unwrap();
        assert_eq!(b.counts(Channel::Flash).dropped, 1);
        assert_eq!(b.counts(Channel::Flash).received, 0);
        assert!(!b.close(Channel::Tide));
    }

    #[test]
    fn a_full_bucket_sends_twelve_full_frames_at_once_and_names_the_wait_to_the_millisecond() {
        let mut b = Bucket::new(DEFAULT_FLASH_RATE);
        for _ in 0..12 {
            assert_eq!(b.spend(MTU, 0), Ok(()));
        }
        assert_eq!(
            b.spend(MTU, 0),
            Err(RateRefusal {
                bytes: MTU,
                rate: 16_384,
                burst: 16_384,
                wait_ms: Some(16)
            })
        );
        assert!(b.spend(MTU, 15).is_err());
        assert_eq!(b.spend(MTU, 16), Ok(()));
        let left = b.tokens();
        assert!(b.spend(MTU, 3).is_err());
        assert_eq!(b.tokens(), left, "a clock that steps back adds nothing");
    }

    #[test]
    fn no_wait_fits_a_frame_past_the_burst_and_a_zero_rate_sends_nothing() {
        let mut slow = Bucket::new(1_000);
        assert_eq!(slow.spend(MTU, 0).unwrap_err().wait_ms, None);
        assert_eq!(slow.spend(1_000, 0), Ok(()));
        let mut off = Bucket::new(0);
        let refused = off.spend(1, 1_000_000).unwrap_err();
        assert_eq!(refused.wait_ms, None);
        assert!(refused.to_string().contains("no wait makes it fit"));
    }

    #[test]
    fn over_seeded_runs_no_window_spends_more_than_the_burst_and_the_rate_allow() {
        let mut seed: u64 = 0x5eed;
        let mut draw = |n: u64| {
            seed = seed
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            (seed >> 33) % n
        };
        for _ in 0..50 {
            let mut b = Bucket::new(DEFAULT_FLASH_RATE);
            let mut now: i64 = 0;
            let mut sent: Vec<(i64, u64)> = Vec::new();
            for _ in 0..80 {
                now += i64::try_from(draw(40)).unwrap();
                let bytes = 1 + draw(MTU as u64);
                if b.spend(usize::try_from(bytes).unwrap(), now).is_ok() {
                    sent.push((now, bytes));
                }
            }
            for i in 0..sent.len() {
                for k in i..sent.len() {
                    let bytes: u64 = sent[i..=k].iter().map(|s| s.1).sum();
                    let elapsed = u64::try_from(sent[k].0 - sent[i].0).unwrap();
                    assert!(bytes * 1000 <= 16_384_000 + 16_384 * elapsed);
                }
            }
        }
    }

    #[test]
    fn a_wire_refuses_a_flash_burst_past_its_rate_and_sends_nothing_it_refused() {
        let mut a = Wire::bind("127.0.0.1:0").unwrap();
        a.open(Channel::Flash, (RING_FRAMES, RING_BYTES));
        let raw = UdpSocket::bind("127.0.0.1:0").unwrap();
        let ra = raw.local_addr().unwrap();
        let full = vec![b'x'; Channel::Flash.room()];
        for _ in 0..12 {
            assert_eq!(a.flash_put(ra, &full, 0), Ok(MTU));
        }
        match a.flash_put(ra, &full, 0) {
            Err(SendError::Rate(r)) => assert_eq!(r.wait_ms, Some(16)),
            other => panic!("{other:?}"),
        }
        assert!(matches!(
            a.flash_put(ra, &vec![0u8; MTU], 99),
            Err(SendError::Frame(_))
        ));
        let c = a.counts(Channel::Flash);
        assert_eq!((c.sent, c.refused), (12, 1));
        raw.set_read_timeout(Some(Duration::from_millis(300)))
            .unwrap();
        let mut buf = [0u8; 2048];
        let mut heard = 0;
        while raw.recv_from(&mut buf).is_ok() {
            heard += 1;
        }
        assert_eq!(heard, 12);
    }

    #[test]
    fn a_loopback_net_delivers_to_bound_addresses_only_and_frees_them_on_close() {
        let net = Arc::new(LoopbackNet::default());
        let mut a = Wire::on(net.bind("127.0.0.1:0".parse().unwrap()).unwrap());
        let mut b = Wire::on(net.bind("127.0.0.1:0".parse().unwrap()).unwrap());
        let (aa, ba) = (a.address().unwrap(), b.address().unwrap());
        assert_eq!((aa.port(), ba.port()), (49152, 49153));
        for w in [&mut a, &mut b] {
            w.open(Channel::Flash, (RING_FRAMES, RING_BYTES));
            w.open(Channel::Tide, (RING_FRAMES, RING_BYTES));
        }
        a.tide_put(ba, b"bulk").unwrap();
        a.flash_put(ba, b"alert", 0).unwrap();
        assert_eq!(a.tide_release(1_000, 5).unwrap(), 13);
        let flash = b.next(Channel::Flash, Duration::ZERO).unwrap().unwrap();
        assert_eq!((flash.payload.as_str(), flash.from), ("alert", aa));
        let tide = b.next(Channel::Tide, Duration::ZERO).unwrap().unwrap();
        assert_eq!((tide.payload.as_str(), tide.stamp_ms), ("bulk", Some(5)));
        assert_eq!(
            a.flash_put("127.0.0.1:1".parse().unwrap(), b"void", 0),
            Ok(5)
        );
        let started = Instant::now();
        assert_eq!(
            b.next(Channel::Flash, Duration::from_secs(30)).unwrap(),
            None
        );
        assert!(started.elapsed() < Duration::from_secs(5));
        assert!(net.bind(ba).is_err(), "the address is in use");
        assert_eq!(net.bound(), 2);
        drop(b);
        assert_eq!(net.bound(), 1);
        assert!(net.bind(ba).is_ok(), "closing frees the address");
        let any = net.bind("0.0.0.0:7000".parse().unwrap()).unwrap();
        let mut c = Wire::on(any);
        c.open(Channel::Flash, (RING_FRAMES, RING_BYTES));
        a.flash_put("127.0.0.1:7000".parse().unwrap(), b"to any", 0)
            .unwrap();
        assert_eq!(
            c.next(Channel::Flash, Duration::ZERO)
                .unwrap()
                .map(|r| r.payload),
            Some("to any".to_string())
        );
    }

    #[test]
    fn a_loopback_wire_holds_the_flash_rate_as_a_socket_does() {
        let net = Arc::new(LoopbackNet::default());
        let mut a = Wire::on(net.bind("127.0.0.1:0".parse().unwrap()).unwrap());
        a.open(Channel::Flash, (RING_FRAMES, RING_BYTES));
        let to: SocketAddr = "127.0.0.1:9".parse().unwrap();
        let full = vec![b'x'; Channel::Flash.room()];
        let sent = (0..13)
            .filter(|_| a.flash_put(to, &full, 0).is_ok())
            .count();
        assert_eq!(sent, 12);
        assert_eq!(a.counts(Channel::Flash).refused, 1);
    }

    #[test]
    fn a_loopback_inbox_past_its_bound_drops_what_does_not_fit() {
        let net = Arc::new(LoopbackNet::default());
        let a = net.bind("127.0.0.1:0".parse().unwrap()).unwrap();
        let b = net.bind("127.0.0.1:0".parse().unwrap()).unwrap();
        for _ in 0..LOOPBACK_QUEUE + 10 {
            net.deliver(a.at, b.at, b"x");
        }
        assert_eq!(net.take(b.at).len(), LOOPBACK_QUEUE);
        assert!(net.take(b.at).is_empty());
    }
}
