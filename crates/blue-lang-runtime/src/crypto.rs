//! Real cryptography — BLAKE3 hashing and Ed25519 signatures — as blue's own
//! surface.
//!
//! ```text
//! blake3_hex(data)                               → 64 hex chars (BLAKE3-256)
//! ed25519_keypair(seed_hex)                      → [secret_hex, public_hex]
//! ed25519_sign(secret_hex, message)              → 128 hex chars
//! ed25519_verify(public_hex, message, sig_hex)   → true / false
//! ```
//!
//! `data` and `message` are a string (its UTF-8 bytes) or a list of byte
//! integers `0..=255`. Keys and signatures are hex, in and out: blue has no
//! byte type, and hex is the one spelling of a key that survives a JSON
//! document, a log line and a terminal unchanged. Output is lowercase; input
//! accepts either case.
//!
//! # Pure layer, not `sys` — and why that is a decision, not a default
//!
//! Every function here is a deterministic function of its arguments. None
//! reads a clock, a file, the environment or an entropy source, so none is a
//! host effect, and the `sys` layer is reserved for exactly those (it is
//! feature-gated because each of its names is a host import). These live
//! beside `json`: installed unconditionally, lowering to **no import**, kept by
//! the `wasm32-unknown-unknown` consumer.
//!
//! The one place that could have forced them into `sys` is key generation,
//! which normally draws from the OS. It does not here: `ed25519_keypair` takes
//! the 32-byte seed from the CALLER. That is what keeps the layer pure, and it
//! is also what makes it testable — RFC 8032's vectors are seeds, so a
//! deterministic keypair is the only kind a test can check against them. Where
//! a caller's seed comes from (a file, a secret store, a future host entropy
//! primitive) is a host question and belongs in `sys` when it is asked.
//!
//! # No C, and the crates chosen for it
//!
//! Ed25519 is `ed25519-dalek` over `curve25519-dalek`; neither compiles C.
//! BLAKE3 is the official `blake3` crate with its **`pure`** feature, which
//! turns off the C and assembly SIMD builds its `build.rs` otherwise performs
//! (on aarch64 it compiled NEON C intrinsics into this very crate before this
//! module existed — `inputs` already hashed with it). Features are pinned
//! explicitly in `Cargo.toml`, so a default that links C cannot arrive on a
//! version bump. The irreducible remainder is stated rather than hidden:
//! `cc` is still in the dependency tree, as an unconditional
//! `[build-dependencies]` entry of `blake3` that Cargo cannot drop, and on
//! x86 `blake3`'s build script still asks the C compiler whether it accepts
//! `-mavx512f` before choosing the Rust implementation. No C object is built
//! or linked on any target.
//!
//! # A typed error on bad input, never a silent `false`
//!
//! `ed25519_verify` answers `false` for exactly one thing: a well-formed
//! signature that does not verify. A key that is not hex, a signature of the
//! wrong length, a public key that is not a curve point, a message that is
//! neither text nor bytes — each RAISES, naming what was wrong. A verifier that
//! folded "you passed me garbage" into "the signature is bad" would let a
//! wiring bug read as a forgery caught, and a forgery caught read as a wiring
//! bug. [`CryptoError`] is the closed set of those refusals, with one
//! `Display`.
//!
//! # Strict verification
//!
//! Verification is `verify_strict`: it rejects non-canonical signatures and
//! small-order public keys, which the permissive `verify` accepts. A signed
//! event log wants one valid signature per (key, message), not several, and a
//! small-order key "verifies" signatures nobody made. A small-order key is
//! refused as bad input ([`CryptoError::WeakPublicKey`]) rather than answered
//! `false`, because no message could ever verify under it.
//!
//! # What this does not protect
//!
//! The secret key arrives and leaves as a blue string. `SigningKey` zeroizes
//! its own copy on drop, but the interpreter's string values are not zeroized,
//! so a secret passed through blue lives in ordinary heap memory until it is
//! reclaimed. This layer computes signatures correctly; it is not a key vault.

use std::sync::Arc;

use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::{Digest, Sha256, Sha512};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

/// Bytes in an Ed25519 secret key (the RFC 8032 seed) and in a public key.
pub const KEY_BYTES: usize = 32;
/// Bytes in an Ed25519 signature.
pub const SIGNATURE_BYTES: usize = 64;

/// Every way an argument to this layer can be refused.
///
/// Closed, and each arm reads differently, so a reader of the raised message is
/// sent to the one thing that was wrong.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CryptoError {
    /// A key or signature argument that is not a string at all.
    #[error("the {what} must be a hex string; got {got}")]
    NotHexText {
        what: &'static str,
        got: &'static str,
    },
    /// A character outside `0-9a-fA-F`, at a character position.
    #[error("the {what} is not hex: character {position} is `{found}`")]
    NotHex {
        what: &'static str,
        position: usize,
        found: char,
    },
    /// An odd number of hex digits cannot be whole bytes.
    #[error("the {what} has an odd number of hex digits ({digits})")]
    OddHex { what: &'static str, digits: usize },
    /// Well-formed hex of the wrong size.
    #[error("the {what} is {got} bytes; it must be {expected}")]
    WrongLength {
        what: &'static str,
        expected: usize,
        got: usize,
    },
    /// Something that is neither text nor a byte list.
    #[error("a message is a string or a list of bytes; got {got}")]
    NotAMessage { got: &'static str },
    /// A byte-list element that is not an integer.
    #[error("element {index} of the byte list is not an integer; got {got}")]
    NotAByte { index: usize, got: &'static str },
    /// A byte-list element outside `0..=255`.
    #[error("element {index} of the byte list is {value}, outside 0..=255")]
    ByteOutOfRange { index: usize, value: i64 },
    /// 32 bytes that do not decompress to a point on the curve.
    #[error("the public key is not a point on the Ed25519 curve")]
    NotACurvePoint,
    /// A point of small order: every signature under it is meaningless.
    #[error("the public key has small order and cannot vouch for any message")]
    WeakPublicKey,
    #[error("the algorithm must be a string or keyword; got {got}")]
    NotAnAlgorithm { got: &'static str },
    #[error("unknown algorithm `{name}`; the built ones are {known}")]
    UnknownAlgorithm { name: String, known: &'static str },
    #[error("{name} has no keyed form here; a keyed digest is one of {known}")]
    NoMac {
        name: &'static str,
        known: &'static str,
    },
    #[error("the key is not usable as a keyed-digest key")]
    BadMacKey,
    #[error("the peer public key has low order: the shared secret is all zero")]
    LowOrderPoint,
    #[error("the {what} does not verify")]
    Tampered { what: &'static str },
    #[error("the plaintext is too long to seal")]
    TooLong,
    #[error("the outboard does not fit the data")]
    OutboardMismatch,
    #[error("the {what} must be an integer; got {got}")]
    NotACount {
        what: &'static str,
        got: &'static str,
    },
    #[error("the {what} is {value}; it must be 0 or more")]
    NegativeCount { what: &'static str, value: i64 },
}

impl CryptoError {
    pub fn kind(&self) -> Option<&'static str> {
        match self {
            CryptoError::LowOrderPoint => Some("refused"),
            CryptoError::Tampered { .. } => Some("tampered"),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Algorithm {
    Sha1,
    Sha256,
    Sha512,
    Blake3,
}

impl Algorithm {
    pub const DIGESTS: &'static str = "sha1, sha256, sha512, blake3";
    pub const MACS: &'static str = "sha1, sha256, sha512";

    pub fn parse(name: &str) -> Result<Self, CryptoError> {
        match name {
            "sha1" => Ok(Algorithm::Sha1),
            "sha256" => Ok(Algorithm::Sha256),
            "sha512" => Ok(Algorithm::Sha512),
            "blake3" => Ok(Algorithm::Blake3),
            other => Err(CryptoError::UnknownAlgorithm {
                name: other.to_string(),
                known: Self::DIGESTS,
            }),
        }
    }

    pub fn from_value(v: &Value) -> Result<Self, CryptoError> {
        match v {
            Value::Str(s) => Self::parse(s),
            Value::Keyword(k) => Self::parse(k),
            other => Err(CryptoError::NotAnAlgorithm {
                got: other.type_name(),
            }),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Algorithm::Sha1 => "sha1",
            Algorithm::Sha256 => "sha256",
            Algorithm::Sha512 => "sha512",
            Algorithm::Blake3 => "blake3",
        }
    }
}

/// The bytes a message or hash input stands for.
///
/// A string is its UTF-8 bytes, so `"r"` and `[114]` are one message — bytes
/// are bytes, whichever way they were spelled. `nil` is refused rather than
/// read as empty: blue has two empties (`nil != []`), and a message that
/// silently became nil is a bug to surface, not an empty string to sign.
pub fn message_bytes(v: &Value) -> Result<Vec<u8>, CryptoError> {
    match v {
        Value::Str(s) => Ok(s.as_bytes().to_vec()),
        Value::List(items) => items
            .iter()
            .enumerate()
            .map(|(index, item)| match item {
                Value::Int(n) => {
                    u8::try_from(*n).map_err(|_| CryptoError::ByteOutOfRange { index, value: *n })
                }
                other => Err(CryptoError::NotAByte {
                    index,
                    got: other.type_name(),
                }),
            })
            .collect(),
        other => Err(CryptoError::NotAMessage {
            got: other.type_name(),
        }),
    }
}

pub fn hex_vec(v: &Value, what: &'static str) -> Result<Vec<u8>, CryptoError> {
    match v {
        Value::Str(s) => decode_hex(s, what),
        other => Err(CryptoError::NotHexText {
            what,
            got: other.type_name(),
        }),
    }
}

/// Decode a hex argument of exactly `N` bytes.
pub fn hex_array<const N: usize>(v: &Value, what: &'static str) -> Result<[u8; N], CryptoError> {
    let bytes = hex_vec(v, what)?;
    <[u8; N]>::try_from(bytes.as_slice()).map_err(|_| CryptoError::WrongLength {
        what,
        expected: N,
        got: bytes.len(),
    })
}

/// Strict hex: digits only, either case, an even count. No `0x`, no spaces.
fn decode_hex(text: &str, what: &'static str) -> Result<Vec<u8>, CryptoError> {
    let digits: Vec<u8> = text
        .chars()
        .enumerate()
        .map(|(position, found)| {
            found
                .to_digit(16)
                // `to_digit(16)` answers at most 15, so the narrowing is exact.
                .map(|d| d as u8)
                .ok_or(CryptoError::NotHex {
                    what,
                    position,
                    found,
                })
        })
        .collect::<Result<_, _>>()?;
    if !digits.len().is_multiple_of(2) {
        return Err(CryptoError::OddHex {
            what,
            digits: digits.len(),
        });
    }
    Ok(digits
        .as_chunks::<2>()
        .0
        .iter()
        .map(|[hi, lo]| (hi << 4) | lo)
        .collect())
}

/// Lowercase hex, the one output spelling.
pub fn encode_hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(char::from(DIGITS[usize::from(b >> 4)]));
        out.push(char::from(DIGITS[usize::from(b & 0x0f)]));
    }
    out
}

/// BLAKE3-256 of `data`, as lowercase hex.
pub fn blake3_hex(data: &[u8]) -> String {
    blake3::hash(data).to_hex().to_string()
}

/// The public key for an RFC 8032 secret key (the 32-byte seed).
pub fn ed25519_public(secret: &[u8; KEY_BYTES]) -> [u8; KEY_BYTES] {
    SigningKey::from_bytes(secret).verifying_key().to_bytes()
}

/// Sign `message` with an RFC 8032 secret key. Ed25519 signing is
/// deterministic: one (key, message) pair has one signature.
pub fn ed25519_sign(secret: &[u8; KEY_BYTES], message: &[u8]) -> [u8; SIGNATURE_BYTES] {
    SigningKey::from_bytes(secret).sign(message).to_bytes()
}

/// Verify strictly. `Ok(false)` is a well-formed signature that does not
/// verify; `Err` is input that could not have verified anything.
pub fn ed25519_verify(
    public: &[u8; KEY_BYTES],
    message: &[u8],
    signature: &[u8; SIGNATURE_BYTES],
) -> Result<bool, CryptoError> {
    let key = VerifyingKey::from_bytes(public).map_err(|_| CryptoError::NotACurvePoint)?;
    if key.is_weak() {
        return Err(CryptoError::WeakPublicKey);
    }
    let signature = Signature::from_bytes(signature);
    Ok(key.verify_strict(message, &signature).is_ok())
}

pub const AEAD_KEY_BYTES: usize = 32;
pub const AEAD_NONCE_BYTES: usize = 12;
pub const AEAD_TAG_BYTES: usize = 16;

pub fn x25519_public(secret: &[u8; KEY_BYTES]) -> [u8; KEY_BYTES] {
    x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from(*secret)).to_bytes()
}

pub fn x25519_shared(
    secret: &[u8; KEY_BYTES],
    peer: &[u8; KEY_BYTES],
) -> Result<[u8; KEY_BYTES], CryptoError> {
    let shared = x25519_dalek::StaticSecret::from(*secret)
        .diffie_hellman(&x25519_dalek::PublicKey::from(*peer));
    if !shared.was_contributory() {
        return Err(CryptoError::LowOrderPoint);
    }
    Ok(shared.to_bytes())
}

fn aead_cipher(key: &[u8; AEAD_KEY_BYTES]) -> chacha20poly1305::ChaCha20Poly1305 {
    use chacha20poly1305::KeyInit;
    chacha20poly1305::ChaCha20Poly1305::new(chacha20poly1305::Key::from_slice(key))
}

pub fn chacha20poly1305_seal(
    key: &[u8; AEAD_KEY_BYTES],
    nonce: &[u8; AEAD_NONCE_BYTES],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    use chacha20poly1305::aead::{Aead, Payload};
    aead_cipher(key)
        .encrypt(
            chacha20poly1305::Nonce::from_slice(nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CryptoError::TooLong)
}

pub fn chacha20poly1305_open(
    key: &[u8; AEAD_KEY_BYTES],
    nonce: &[u8; AEAD_NONCE_BYTES],
    aad: &[u8],
    sealed: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    use chacha20poly1305::aead::{Aead, Payload};
    aead_cipher(key)
        .decrypt(
            chacha20poly1305::Nonce::from_slice(nonce),
            Payload { msg: sealed, aad },
        )
        .map_err(|_| CryptoError::Tampered {
            what: "sealed message",
        })
}

pub fn bao_outboard(data: &[u8]) -> ([u8; KEY_BYTES], Vec<u8>) {
    let (outboard, root) = bao::encode::outboard(data);
    (*root.as_bytes(), outboard)
}

pub fn bao_slice(
    data: &[u8],
    outboard: &[u8],
    start: u64,
    len: u64,
) -> Result<Vec<u8>, CryptoError> {
    use std::io::{Cursor, Read};
    let mut slice = Vec::new();
    bao::encode::SliceExtractor::new_outboard(Cursor::new(data), Cursor::new(outboard), start, len)
        .read_to_end(&mut slice)
        .map_err(|_| CryptoError::OutboardMismatch)?;
    Ok(slice)
}

pub fn bao_verify_slice(
    root: &[u8; KEY_BYTES],
    slice: &[u8],
    start: u64,
    len: u64,
) -> Result<Vec<u8>, CryptoError> {
    use std::io::Read;
    let mut range = Vec::new();
    bao::decode::SliceDecoder::new(slice, &bao::Hash::from(*root), start, len)
        .read_to_end(&mut range)
        .map_err(|_| CryptoError::Tampered { what: "slice" })?;
    Ok(range)
}

pub fn count(v: &Value, what: &'static str) -> Result<u64, CryptoError> {
    match v {
        Value::Int(n) => {
            u64::try_from(*n).map_err(|_| CryptoError::NegativeCount { what, value: *n })
        }
        other => Err(CryptoError::NotACount {
            what,
            got: other.type_name(),
        }),
    }
}

pub fn digest_hex(algorithm: Algorithm, data: &[u8]) -> String {
    match algorithm {
        Algorithm::Sha1 => encode_hex(&Sha1::digest(data)),
        Algorithm::Sha256 => encode_hex(&Sha256::digest(data)),
        Algorithm::Sha512 => encode_hex(&Sha512::digest(data)),
        Algorithm::Blake3 => blake3_hex(data),
    }
}

fn mac_hex<M: Mac>(
    key: &[u8],
    data: &[u8],
    new: fn(&[u8]) -> Result<M, hmac::digest::InvalidLength>,
) -> Result<String, CryptoError> {
    let mut mac = new(key).map_err(|_| CryptoError::BadMacKey)?;
    mac.update(data);
    Ok(encode_hex(&mac.finalize().into_bytes()))
}

pub fn hmac_hex(algorithm: Algorithm, key: &[u8], data: &[u8]) -> Result<String, CryptoError> {
    match algorithm {
        Algorithm::Sha1 => mac_hex(key, data, Hmac::<Sha1>::new_from_slice),
        Algorithm::Sha256 => mac_hex(key, data, Hmac::<Sha256>::new_from_slice),
        Algorithm::Sha512 => mac_hex(key, data, Hmac::<Sha512>::new_from_slice),
        Algorithm::Blake3 => Err(CryptoError::NoMac {
            name: algorithm.name(),
            known: Algorithm::MACS,
        }),
    }
}

pub fn scan_differences(a: &[u8], b: &[u8]) -> (u8, usize) {
    let width = a.len().max(b.len());
    let mut acc = 0u8;
    let mut visited = 0usize;
    for i in 0..width {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        acc |= x ^ y;
        visited += 1;
    }
    (acc, visited)
}

pub fn bytes_equal(a: &[u8], b: &[u8]) -> bool {
    let (acc, _) = scan_differences(a, b);
    let lengths = (a.len() ^ b.len()) as u64;
    std::hint::black_box(acc) == 0 && std::hint::black_box(lengths) == 0
}

/// Raise a refusal as the named primitive's error.
fn refuse(name: &'static str, span: tatara_lisp::Span) -> impl Fn(CryptoError) -> EvalError {
    move |e| match e.kind() {
        Some(kind) => crate::errors::raise_kind(kind, format!("{name}: {e}"), span),
        None => EvalError::native_fn(name, e.to_string(), span),
    }
}

fn bytes_value(bytes: &[u8]) -> Value {
    Value::list(bytes.iter().map(|b| Value::Int(i64::from(*b))))
}

fn hex_value(bytes: &[u8]) -> Value {
    Value::Str(Arc::from(encode_hex(bytes)))
}

/// Install blue's cryptography surface.
pub fn install_crypto_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "blake3_hex",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| {
            let data = message_bytes(&a[0]).map_err(refuse("blake3_hex", span))?;
            Ok(Value::Str(Arc::from(blake3_hex(&data))))
        },
    );

    interp.register_fn(
        "digest_hex",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, span| {
            let algorithm = Algorithm::from_value(&a[0]).map_err(refuse("digest_hex", span))?;
            let data = message_bytes(&a[1]).map_err(refuse("digest_hex", span))?;
            Ok(Value::Str(Arc::from(digest_hex(algorithm, &data))))
        },
    );

    interp.register_fn(
        "hmac_hex",
        Arity::Exact(3),
        |a: &[Value], _h: &mut H, span| {
            let algorithm = Algorithm::from_value(&a[0]).map_err(refuse("hmac_hex", span))?;
            let key = message_bytes(&a[1]).map_err(refuse("hmac_hex", span))?;
            let data = message_bytes(&a[2]).map_err(refuse("hmac_hex", span))?;
            let tag = hmac_hex(algorithm, &key, &data).map_err(refuse("hmac_hex", span))?;
            Ok(Value::Str(Arc::from(tag)))
        },
    );

    interp.register_fn(
        "bytes_equal?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, span| {
            let left = message_bytes(&a[0]).map_err(refuse("bytes_equal?", span))?;
            let right = message_bytes(&a[1]).map_err(refuse("bytes_equal?", span))?;
            Ok(Value::Bool(bytes_equal(&left, &right)))
        },
    );

    interp.register_fn(
        "ed25519_keypair",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| {
            let seed: [u8; KEY_BYTES] =
                hex_array(&a[0], "seed").map_err(refuse("ed25519_keypair", span))?;
            Ok(Value::list([
                hex_value(&seed),
                hex_value(&ed25519_public(&seed)),
            ]))
        },
    );

    interp.register_fn(
        "ed25519_sign",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, span| {
            let secret: [u8; KEY_BYTES] =
                hex_array(&a[0], "secret key").map_err(refuse("ed25519_sign", span))?;
            let message = message_bytes(&a[1]).map_err(refuse("ed25519_sign", span))?;
            Ok(hex_value(&ed25519_sign(&secret, &message)))
        },
    );

    interp.register_fn(
        "ed25519_verify",
        Arity::Exact(3),
        |a: &[Value], _h: &mut H, span| {
            let public: [u8; KEY_BYTES] =
                hex_array(&a[0], "public key").map_err(refuse("ed25519_verify", span))?;
            let message = message_bytes(&a[1]).map_err(refuse("ed25519_verify", span))?;
            let signature: [u8; SIGNATURE_BYTES] =
                hex_array(&a[2], "signature").map_err(refuse("ed25519_verify", span))?;
            let verdict = ed25519_verify(&public, &message, &signature)
                .map_err(refuse("ed25519_verify", span))?;
            Ok(Value::Bool(verdict))
        },
    );

    interp.register_fn(
        "x25519_keypair",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| {
            let seed: [u8; KEY_BYTES] =
                hex_array(&a[0], "seed").map_err(refuse("x25519_keypair", span))?;
            Ok(Value::list([
                hex_value(&seed),
                hex_value(&x25519_public(&seed)),
            ]))
        },
    );

    interp.register_fn(
        "x25519_shared",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, span| {
            let secret: [u8; KEY_BYTES] =
                hex_array(&a[0], "secret key").map_err(refuse("x25519_shared", span))?;
            let peer: [u8; KEY_BYTES] =
                hex_array(&a[1], "public key").map_err(refuse("x25519_shared", span))?;
            let shared = x25519_shared(&secret, &peer).map_err(refuse("x25519_shared", span))?;
            Ok(hex_value(&shared))
        },
    );

    interp.register_fn(
        "chacha20poly1305_seal",
        Arity::Exact(4),
        |a: &[Value], _h: &mut H, span| {
            let fail = || refuse("chacha20poly1305_seal", span);
            let key: [u8; AEAD_KEY_BYTES] = hex_array(&a[0], "key").map_err(fail())?;
            let nonce: [u8; AEAD_NONCE_BYTES] = hex_array(&a[1], "nonce").map_err(fail())?;
            let aad = message_bytes(&a[2]).map_err(fail())?;
            let plaintext = message_bytes(&a[3]).map_err(fail())?;
            let sealed = chacha20poly1305_seal(&key, &nonce, &aad, &plaintext).map_err(fail())?;
            Ok(hex_value(&sealed))
        },
    );

    interp.register_fn(
        "chacha20poly1305_open",
        Arity::Exact(4),
        |a: &[Value], _h: &mut H, span| {
            let fail = || refuse("chacha20poly1305_open", span);
            let key: [u8; AEAD_KEY_BYTES] = hex_array(&a[0], "key").map_err(fail())?;
            let nonce: [u8; AEAD_NONCE_BYTES] = hex_array(&a[1], "nonce").map_err(fail())?;
            let aad = message_bytes(&a[2]).map_err(fail())?;
            let sealed = hex_vec(&a[3], "sealed message").map_err(fail())?;
            let plaintext = chacha20poly1305_open(&key, &nonce, &aad, &sealed).map_err(fail())?;
            Ok(bytes_value(&plaintext))
        },
    );

    interp.register_fn(
        "bao_outboard",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| {
            let data = message_bytes(&a[0]).map_err(refuse("bao_outboard", span))?;
            let (root, outboard) = bao_outboard(&data);
            Ok(Value::map([
                (
                    tatara_lisp_eval::MapKey::Keyword(Arc::from("root")),
                    hex_value(&root),
                ),
                (
                    tatara_lisp_eval::MapKey::Keyword(Arc::from("outboard")),
                    hex_value(&outboard),
                ),
            ]))
        },
    );

    interp.register_fn(
        "bao_slice",
        Arity::Exact(4),
        |a: &[Value], _h: &mut H, span| {
            let fail = || refuse("bao_slice", span);
            let data = message_bytes(&a[0]).map_err(fail())?;
            let outboard = hex_vec(&a[1], "outboard").map_err(fail())?;
            let start = count(&a[2], "start").map_err(fail())?;
            let len = count(&a[3], "length").map_err(fail())?;
            let slice = bao_slice(&data, &outboard, start, len).map_err(fail())?;
            Ok(hex_value(&slice))
        },
    );

    interp.register_fn(
        "bao_verify_slice",
        Arity::Exact(4),
        |a: &[Value], _h: &mut H, span| {
            let fail = || refuse("bao_verify_slice", span);
            let root: [u8; KEY_BYTES] = hex_array(&a[0], "root").map_err(fail())?;
            let slice = hex_vec(&a[1], "slice").map_err(fail())?;
            let start = count(&a[2], "start").map_err(fail())?;
            let len = count(&a[3], "length").map_err(fail())?;
            let range = bao_verify_slice(&root, &slice, start, len).map_err(fail())?;
            Ok(bytes_value(&range))
        },
    );
}

#[cfg(test)]
mod tests {
    //! The oracle is never this module. Every expected value below is copied
    //! from a document written by someone else: RFC 8032 §7.1 for Ed25519, and
    //! BLAKE3's official `test_vectors/test_vectors.json` for hashing (whose
    //! input for length `n` is the byte sequence `i % 251` for `i` in `0..n`).
    //!
    //! # Red runs, recorded
    //!
    //! Each was performed on 2026-09-24, observed to fail, and reverted.
    //!
    //! 1. **A signer that signs the wrong bytes.** `ed25519_sign` changed to
    //!    sign `message` with one `0x00` byte appended: 4 red —
    //!    `rfc8032_test_1`, `_2`, `_3` on `signature mismatch` (their public
    //!    keys still matched, which is why keys and signatures are asserted
    //!    separately), and `a_signature_round_trips_through_blue`, because the
    //!    verifier was still honest. A round trip alone would NOT catch a
    //!    signer and verifier broken the same way; the vectors would.
    //! 2. **A verifier that always says yes.** `ed25519_verify` changed to
    //!    return `Ok(true)` after the key checks: 3 red —
    //!    `a_tampered_message_does_not_verify`, `a_wrong_key_does_not_verify`,
    //!    `a_tampered_signature_does_not_verify`. Every vector test stayed
    //!    green, which is the case for the controls: vectors only ever ask a
    //!    verifier to say yes.
    //! 3. **A hash of the wrong bytes.** `blake3_hex` changed to
    //!    `blake3::keyed_hash` with an all-zero key: 3 red — every `blake3_*`
    //!    vector test, the empty input included. `text_and_bytes_are_one_message`
    //!    stayed green, as it must: it compares the function with itself, so
    //!    it proves the byte mapping and nothing about the hash.
    use super::*;

    fn eval(src: &str) -> Value {
        crate::run(src)
            .unwrap_or_else(|e| panic!("{src:?}: {e}"))
            .value
    }

    fn s(src: &str) -> String {
        match eval(src) {
            Value::Str(v) => v.to_string(),
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    fn b(src: &str) -> bool {
        match eval(src) {
            Value::Bool(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    fn err(src: &str) -> String {
        crate::run(src)
            .map(|r| r.value)
            .expect_err("must raise")
            .to_string()
    }

    /// One RFC 8032 §7.1 vector, joined from the RFC's wrapped lines.
    struct Vector {
        secret: &'static str,
        public: &'static str,
        /// The message as a blue expression.
        message: &'static str,
        signature: &'static str,
    }

    const TEST_1: Vector = Vector {
        secret: "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
        public: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
        message: "\"\"",
        signature: "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155\
                    5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
    };

    /// MESSAGE `72` — one byte, which is ASCII `r`, so it is written as text.
    const TEST_2: Vector = Vector {
        secret: "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
        public: "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
        message: "\"r\"",
        signature: "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da\
                    085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
    };

    /// MESSAGE `af82` — not valid UTF-8, so it can only be written as bytes.
    /// This is the vector that exercises the byte-list path.
    const TEST_3: Vector = Vector {
        secret: "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
        public: "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
        message: "[175, 130]",
        signature: "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac\
                    18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
    };

    fn check_vector(v: &Vector) {
        let pair = eval(&["ed25519_keypair(\"", v.secret, "\")"].concat());
        let Value::List(pair) = pair else {
            panic!("keypair must be a list, got {pair:?}")
        };
        assert!(matches!(&pair[0], Value::Str(x) if &**x == v.secret));
        assert!(
            matches!(&pair[1], Value::Str(x) if &**x == v.public),
            "public key mismatch: {:?}",
            pair[1]
        );
        let sig = s(&["ed25519_sign(\"", v.secret, "\", ", v.message, ")"].concat());
        assert_eq!(sig, v.signature, "signature mismatch");
        assert!(b(&[
            "ed25519_verify(\"",
            v.public,
            "\", ",
            v.message,
            ", \"",
            v.signature,
            "\")"
        ]
        .concat()));
    }

    #[test]
    fn rfc8032_test_1() {
        check_vector(&TEST_1);
    }

    #[test]
    fn rfc8032_test_2() {
        check_vector(&TEST_2);
    }

    #[test]
    fn rfc8032_test_3() {
        check_vector(&TEST_3);
    }

    /// BLAKE3's official vectors: input of length `n` is `i % 251`.
    fn official_input(n: usize) -> Vec<u8> {
        (0..n).map(|i| (i % 251) as u8).collect()
    }

    #[test]
    fn blake3_the_empty_input() {
        assert_eq!(
            s("blake3_hex(\"\")"),
            "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
        );
        // The same empty input, spelled as bytes.
        assert_eq!(
            s("blake3_hex([])"),
            "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
        );
    }

    #[test]
    fn blake3_one_byte_through_blue() {
        assert_eq!(
            s("blake3_hex([0])"),
            "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"
        );
    }

    /// Across the one-chunk boundary (1024 bytes) and into a multi-chunk tree,
    /// where a SIMD or tree-hashing path would diverge first.
    #[test]
    fn blake3_across_the_chunk_boundary() {
        for (n, want) in [
            (
                3,
                "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f",
            ),
            (
                1023,
                "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11",
            ),
            (
                1024,
                "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
            ),
            (
                1025,
                "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444",
            ),
            (
                8193,
                "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b",
            ),
        ] {
            assert_eq!(blake3_hex(&official_input(n)), want, "input_len {n}");
        }
    }

    /// A string hashes as its UTF-8 bytes, so text and bytes agree.
    #[test]
    fn text_and_bytes_are_one_message() {
        assert_eq!(s("blake3_hex(\"abc\")"), s("blake3_hex([97, 98, 99])"));
        // "é" is two bytes in UTF-8, not one character code.
        assert_eq!(s("blake3_hex(\"é\")"), s("blake3_hex([195, 169])"));
    }

    #[test]
    fn a_signature_round_trips_through_blue() {
        let sig = s(&["ed25519_sign(\"", TEST_2.secret, "\", \"a permit\")"].concat());
        assert!(b(&[
            "ed25519_verify(\"",
            TEST_2.public,
            "\", \"a permit\", \"",
            &sig,
            "\")"
        ]
        .concat()));
    }

    // ── controls: what must NOT verify ─────────────────────────────────

    #[test]
    fn a_tampered_message_does_not_verify() {
        // TEST 2 signs "r"; the same signature over "s" must fail.
        assert!(!b(&[
            "ed25519_verify(\"",
            TEST_2.public,
            "\", \"s\", \"",
            TEST_2.signature,
            "\")"
        ]
        .concat()));
    }

    #[test]
    fn a_wrong_key_does_not_verify() {
        // TEST 2's signature, checked against TEST 1's key.
        assert!(!b(&[
            "ed25519_verify(\"",
            TEST_1.public,
            "\", \"r\", \"",
            TEST_2.signature,
            "\")"
        ]
        .concat()));
    }

    #[test]
    fn a_tampered_signature_does_not_verify() {
        // Flip the last hex digit of TEST 1's signature.
        let mut forged = TEST_1.signature.to_string();
        forged.pop();
        forged.push('a');
        assert_ne!(forged, TEST_1.signature);
        assert!(!b(&[
            "ed25519_verify(\"",
            TEST_1.public,
            "\", \"\", \"",
            &forged,
            "\")"
        ]
        .concat()));
    }

    // ── bad input raises, and names what was wrong ─────────────────────

    #[test]
    fn a_short_key_is_a_named_error_not_false() {
        let e = err("ed25519_verify(\"abcd\", \"m\", \"00\")");
        assert!(e.contains("ed25519_verify"), "{e}");
        assert!(e.contains("public key is 2 bytes"), "{e}");
    }

    #[test]
    fn non_hex_is_a_named_error() {
        let bad = ["\"zz", &TEST_1.secret[2..], "\""].concat();
        let e = err(&["ed25519_sign(", &bad, ", \"m\")"].concat());
        assert!(e.contains("not hex: character 0 is `z`"), "{e}");
    }

    #[test]
    fn odd_hex_is_a_named_error() {
        let e = err("ed25519_keypair(\"abc\")");
        assert!(e.contains("odd number of hex digits (3)"), "{e}");
    }

    #[test]
    fn a_key_that_is_not_a_string_is_a_named_error() {
        let e = err("ed25519_keypair(42)");
        assert!(e.contains("seed must be a hex string; got int"), "{e}");
    }

    #[test]
    fn a_non_message_is_a_named_error() {
        let e = err("blake3_hex(nil)");
        assert!(
            e.contains("a message is a string or a list of bytes"),
            "{e}"
        );
        let e = err("blake3_hex(42)");
        assert!(e.contains("; got int"), "{e}");
    }

    #[test]
    fn a_byte_out_of_range_is_a_named_error() {
        let e = err("blake3_hex([1, 256])");
        assert!(e.contains("element 1 of the byte list is 256"), "{e}");
        let e = err("blake3_hex([1, \"x\"])");
        assert!(
            e.contains("element 1 of the byte list is not an integer; got string"),
            "{e}"
        );
    }

    /// Uppercase hex is accepted; output is always lowercase.
    #[test]
    fn hex_input_is_case_insensitive_and_output_is_lowercase() {
        let upper = TEST_1.secret.to_uppercase();
        let pair = eval(&["ed25519_keypair(\"", &upper, "\")"].concat());
        let Value::List(pair) = pair else { panic!() };
        assert!(matches!(&pair[0], Value::Str(x) if &**x == TEST_1.secret));
        assert!(matches!(&pair[1], Value::Str(x) if &**x == TEST_1.public));
    }

    /// A 32-byte string that is not a compressed curve point is refused, not
    /// answered `false`. `y = 2` has no square root for `x` on Ed25519, which
    /// is a property of the curve and not of this code.
    #[test]
    fn a_public_key_off_the_curve_is_a_named_error() {
        let mut off = [0u8; KEY_BYTES];
        off[0] = 2;
        assert!(
            VerifyingKey::from_bytes(&off).is_err(),
            "control: y=2 is off-curve"
        );
        let e = err(&[
            "ed25519_verify(\"",
            &encode_hex(&off),
            "\", \"m\", \"",
            TEST_1.signature,
            "\")",
        ]
        .concat());
        assert!(e.contains("not a point on the Ed25519 curve"), "{e}");
    }

    /// The identity point (encoded `01 00 … 00`) has order 1 — the weakest key
    /// there is — and must be refused before any signature is considered.
    #[test]
    fn a_small_order_public_key_is_a_named_error() {
        let mut identity = [0u8; KEY_BYTES];
        identity[0] = 1;
        let key = VerifyingKey::from_bytes(&identity).expect("the identity decompresses");
        assert!(key.is_weak(), "control: the identity is small-order");
        let e = err(&[
            "ed25519_verify(\"",
            &encode_hex(&identity),
            "\", \"m\", \"",
            TEST_1.signature,
            "\")",
        ]
        .concat());
        assert!(e.contains("small order"), "{e}");
    }

    #[test]
    fn hex_round_trips() {
        let all: Vec<u8> = (0..=255).collect();
        let text = encode_hex(&all);
        assert_eq!(decode_hex(&text, "t").expect("round trip"), all);
        assert_eq!(decode_hex("", "t").expect("empty"), Vec::<u8>::new());
    }

    const SHA: [(&str, &str, &str, &str); 3] = [
        ("sha1", "da39a3ee5e6b4b0d3255bfef95601890afd80709", "a9993e364706816aba3e25717850c26c9cd0d89d", "6244e66451a1c8695db9731ce2c4fd5de25ccf87"),
        ("sha256", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "4cbc96099a6467ce002461f10549b4898265ebe6188b45efacc44293516e62c4"),
        ("sha512", "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "aee650458ddcbcd4557531b27f1cded4c577f576079b086f57f3c6b9e037a7c0b3cdf7ff58afa09fe279076d1107d5d554f4d34fc6f03d8fd12f93d892802ac3"),
    ];

    fn bytes_literal(byte: u8, count: usize) -> String {
        format!("[{}]", vec![byte.to_string(); count].join(", "))
    }

    #[test]
    fn digests_match_fips_180_for_the_empty_input_and_abc() {
        for (name, empty, abc, _) in SHA {
            assert_eq!(
                s(&format!("digest_hex(\"{name}\", \"\")")),
                empty,
                "{name} empty"
            );
            assert_eq!(
                s(&format!("digest_hex(\"{name}\", \"abc\")")),
                abc,
                "{name} abc"
            );
        }
    }

    #[test]
    fn digests_take_text_and_bytes_and_a_keyword_name() {
        for (name, _, abc, _) in SHA {
            assert_eq!(
                s(&format!("digest_hex(\"{name}\", [97, 98, 99])")),
                abc,
                "{name} bytes"
            );
            assert_eq!(
                s(&format!("digest_hex(:{name}, \"abc\")")),
                abc,
                "{name} keyword"
            );
        }
        assert_eq!(s("digest_hex(\"blake3\", \"\")"), s("blake3_hex(\"\")"));
    }

    #[test]
    fn digests_differ_by_algorithm_and_by_input() {
        let all: std::collections::BTreeSet<String> = ["sha1", "sha256", "sha512", "blake3"]
            .iter()
            .map(|n| s(&format!("digest_hex(\"{n}\", \"abc\")")))
            .collect();
        assert_eq!(all.len(), 4);
        assert_ne!(
            s("digest_hex(\"sha256\", \"abc\")"),
            s("digest_hex(\"sha256\", \"abd\")")
        );
    }

    #[test]
    fn digest_hex_refuses_what_it_cannot_place() {
        assert!(err("digest_hex(\"md5\", \"x\")").contains("unknown algorithm `md5`"));
        assert!(err("digest_hex(\"SHA256\", \"x\")").contains("unknown algorithm"));
        assert!(err("digest_hex(256, \"x\")").contains("string or keyword"));
        assert!(err("digest_hex(nil, \"x\")").contains("string or keyword"));
        assert!(err("digest_hex(\"sha256\", nil)").contains("string or a list of bytes"));
        assert!(err("digest_hex(\"sha256\", [256])").contains("outside 0..=255"));
        assert!(err("digest_hex(\"sha256\")").contains("digest_hex"));
    }

    #[test]
    fn hmac_matches_rfc_4231_and_rfc_2202() {
        let key = bytes_literal(0x0b, 20);
        let long_key = bytes_literal(0xaa, 131);
        let cases: [(&str, &str, &str, &str); 3] = [
            ("sha1", "b617318655057264e28bc0b6fb378c8ef146be00", "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79", "90d0dace1c1bdc957339307803160335bde6df2b"),
            ("sha256", "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"),
            ("sha512", "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854", "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737", "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598"),
        ];
        for (name, one, two, long) in cases {
            assert_eq!(
                s(&format!("hmac_hex(\"{name}\", {key}, \"Hi There\")")),
                one,
                "{name} case 1"
            );
            assert_eq!(
                s(&format!(
                    "hmac_hex(:{name}, \"Jefe\", \"what do ya want for nothing?\")"
                )),
                two,
                "{name} case 2"
            );
            assert_eq!(
                s(&format!("hmac_hex(\"{name}\", {long_key}, \"Test Using Larger Than Block-Size Key - Hash Key First\")")),
                long,
                "{name} long key"
            );
        }
    }

    #[test]
    fn hmac_with_an_empty_key_is_defined_and_differs_from_the_plain_digest() {
        for (name, _, _, empty_key) in SHA {
            assert_eq!(
                s(&format!("hmac_hex(\"{name}\", \"\", \"x\")")),
                empty_key,
                "{name}"
            );
            assert_ne!(
                s(&format!("hmac_hex(\"{name}\", \"\", \"x\")")),
                s(&format!("digest_hex(\"{name}\", \"x\")"))
            );
        }
        assert_eq!(
            s("hmac_hex(\"sha256\", [], \"x\")"),
            s("hmac_hex(\"sha256\", \"\", \"x\")")
        );
    }

    #[test]
    fn hmac_depends_on_the_key_and_the_data() {
        let base = s("hmac_hex(\"sha256\", \"k\", \"m\")");
        assert_ne!(base, s("hmac_hex(\"sha256\", \"k2\", \"m\")"));
        assert_ne!(base, s("hmac_hex(\"sha256\", \"k\", \"m2\")"));
    }

    #[test]
    fn hmac_refuses_blake3_unknown_names_and_bad_arguments() {
        assert!(err("hmac_hex(\"blake3\", \"k\", \"m\")").contains("no keyed form"));
        assert!(err("hmac_hex(\"md5\", \"k\", \"m\")").contains("unknown algorithm"));
        assert!(err("hmac_hex(1, \"k\", \"m\")").contains("string or keyword"));
        assert!(err("hmac_hex(\"sha256\", nil, \"m\")").contains("string or a list of bytes"));
        assert!(err("hmac_hex(\"sha256\", \"k\", nil)").contains("string or a list of bytes"));
        assert!(err("hmac_hex(\"sha256\", \"k\")").contains("hmac_hex"));
    }

    #[test]
    fn bytes_equal_answers_for_text_bytes_and_empties() {
        assert!(b("bytes_equal?(\"abc\", \"abc\")"));
        assert!(b("bytes_equal?(\"abc\", [97, 98, 99])"));
        assert!(b("bytes_equal?(\"\", [])"));
        assert!(!b("bytes_equal?(\"abc\", \"abd\")"));
        assert!(!b("bytes_equal?(\"abc\", \"ab\")"));
        assert!(!b("bytes_equal?(\"ab\", \"abc\")"));
        assert!(!b("bytes_equal?(\"\", \"a\")"));
        assert!(!b("bytes_equal?([1], [1, 0])"));
    }

    #[test]
    fn bytes_equal_refuses_what_is_not_a_message() {
        assert!(err("bytes_equal?(nil, \"a\")").contains("string or a list of bytes"));
        assert!(err("bytes_equal?(\"a\", 1)").contains("string or a list of bytes"));
        assert!(err("bytes_equal?([300], \"a\")").contains("outside 0..=255"));
        assert!(err("bytes_equal?(\"a\")").contains("bytes_equal?"));
    }

    #[test]
    fn the_scan_visits_every_position_whatever_the_first_difference() {
        let reference = vec![7u8; 64];
        for first_difference in 0..64 {
            let mut other = reference.clone();
            other[first_difference] ^= 0xff;
            let (acc, visited) = scan_differences(&reference, &other);
            assert_ne!(acc, 0, "difference at {first_difference} must register");
            assert_eq!(
                visited, 64,
                "stopped early when the first difference was at {first_difference}"
            );
        }
        let (acc, visited) = scan_differences(&reference, &reference);
        assert_eq!((acc, visited), (0, 64));
    }

    #[test]
    fn the_scan_covers_the_longer_side_when_lengths_differ() {
        assert_eq!(scan_differences(b"", b"abcd").1, 4);
        assert_eq!(scan_differences(b"abcd", b"").1, 4);
        assert_eq!(scan_differences(b"x", b"yzzz").1, 4);
        assert_eq!(scan_differences(b"", b"").1, 0);
    }

    #[test]
    fn the_scan_accumulates_every_difference_not_just_the_last() {
        let (acc, _) = scan_differences(&[0b0001, 0b0000, 0b0000], &[0b0000, 0b0000, 0b0000]);
        assert_ne!(acc, 0, "a difference before equal tail bytes must survive");
        let (acc, _) = scan_differences(&[0b0001, 0b0010], &[0b0000, 0b0000]);
        assert_eq!(acc, 0b0011);
    }

    fn rescued(src: &str, kind: &str) -> String {
        s(&format!(
            "begin\n  {src}\n  \"no refusal\"\nrescue :{kind} as e\n  e.message\nend"
        ))
    }

    fn flip_hex_digit(hex: &str, position: usize) -> String {
        let mut chars: Vec<char> = hex.chars().collect();
        chars[position] = if chars[position] == '0' { '1' } else { '0' };
        chars.into_iter().collect()
    }

    fn byte_list(bytes: &[u8]) -> String {
        format!(
            "[{}]",
            bytes
                .iter()
                .map(u8::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        )
    }

    fn list_bytes(v: Value) -> Vec<u8> {
        let Value::List(items) = v else {
            panic!("a byte list, got {v:?}")
        };
        items
            .iter()
            .map(|x| match x {
                Value::Int(n) => u8::try_from(*n).expect("a byte"),
                other => panic!("a byte, got {other:?}"),
            })
            .collect()
    }

    #[test]
    fn rfc7748_section_5_2_vector_1() {
        assert_eq!(
            s("x25519_shared(\"a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4\", \"e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c\")"),
            "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"
        );
    }

    #[test]
    fn rfc7748_section_5_2_vector_2() {
        assert_eq!(
            s("x25519_shared(\"4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d\", \"e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493\")"),
            "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"
        );
    }

    const ALICE_SECRET: &str = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a";
    const ALICE_PUBLIC: &str = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a";
    const BOB_SECRET: &str = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb";
    const BOB_PUBLIC: &str = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f";
    const ALICE_BOB_SHARED: &str =
        "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742";

    #[test]
    fn rfc7748_section_6_1_alice_and_bob() {
        assert_eq!(
            s(&format!("nth(1, x25519_keypair(\"{ALICE_SECRET}\"))")),
            ALICE_PUBLIC
        );
        assert_eq!(
            s(&format!("nth(1, x25519_keypair(\"{BOB_SECRET}\"))")),
            BOB_PUBLIC
        );
        assert_eq!(
            s(&format!(
                "x25519_shared(\"{ALICE_SECRET}\", \"{BOB_PUBLIC}\")"
            )),
            ALICE_BOB_SHARED
        );
        assert_eq!(
            s(&format!(
                "x25519_shared(\"{BOB_SECRET}\", \"{ALICE_PUBLIC}\")"
            )),
            ALICE_BOB_SHARED
        );
    }

    #[test]
    fn x25519_low_order_points_are_refused() {
        for point in [
            "0000000000000000000000000000000000000000000000000000000000000000",
            "0100000000000000000000000000000000000000000000000000000000000000",
            "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800",
            "5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157",
        ] {
            let message = rescued(
                &format!("x25519_shared(\"{ALICE_SECRET}\", \"{point}\")"),
                "refused",
            );
            assert!(message.contains("low order"), "{point}: {message}");
        }
    }

    #[test]
    fn x25519_bad_lengths_are_named_errors() {
        let e = err("x25519_shared(\"abcd\", \"00\")");
        assert!(e.contains("secret key is 2 bytes; it must be 32"), "{e}");
    }

    const RFC8439_KEY: &str = "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f";
    const RFC8439_NONCE: &str = "070000004041424344454647";
    const RFC8439_AAD: &str = "[80, 81, 82, 83, 192, 193, 194, 195, 196, 197, 198, 199]";
    const RFC8439_PLAINTEXT: &str = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
    const RFC8439_SEALED: &str = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691";

    fn open_src(sealed: &str, aad: &str) -> String {
        format!(
            "chacha20poly1305_open(\"{RFC8439_KEY}\", \"{RFC8439_NONCE}\", {aad}, \"{sealed}\")"
        )
    }

    #[test]
    fn rfc8439_section_2_8_2_seal() {
        assert_eq!(
            s(&format!(
                "chacha20poly1305_seal(\"{RFC8439_KEY}\", \"{RFC8439_NONCE}\", {RFC8439_AAD}, \"{RFC8439_PLAINTEXT}\")"
            )),
            RFC8439_SEALED
        );
    }

    #[test]
    fn rfc8439_section_2_8_2_open() {
        assert_eq!(
            list_bytes(eval(&open_src(RFC8439_SEALED, RFC8439_AAD))),
            RFC8439_PLAINTEXT.as_bytes()
        );
        assert_eq!(
            s(&format!(
                "bytes_text({})",
                open_src(RFC8439_SEALED, RFC8439_AAD)
            )),
            RFC8439_PLAINTEXT
        );
    }

    #[test]
    fn a_tampered_tag_is_refused() {
        let last = RFC8439_SEALED.len() - 1;
        let message = rescued(
            &open_src(&flip_hex_digit(RFC8439_SEALED, last), RFC8439_AAD),
            "tampered",
        );
        assert!(
            message.contains("sealed message does not verify"),
            "{message}"
        );
    }

    #[test]
    fn a_tampered_ciphertext_wrong_aad_or_short_message_is_refused() {
        for src in [
            open_src(&flip_hex_digit(RFC8439_SEALED, 0), RFC8439_AAD),
            open_src(RFC8439_SEALED, "[80]"),
            open_src(RFC8439_SEALED, "\"\""),
            open_src(&RFC8439_SEALED[..30], RFC8439_AAD),
            open_src("", RFC8439_AAD),
        ] {
            let message = rescued(&src, "tampered");
            assert!(message.contains("does not verify"), "{src}: {message}");
        }
    }

    #[test]
    fn aead_bad_lengths_are_named_errors() {
        let e = err(&format!(
            "chacha20poly1305_seal(\"{RFC8439_KEY}\", \"0700000040414243\", \"\", \"m\")"
        ));
        assert!(e.contains("nonce is 8 bytes; it must be 12"), "{e}");
        let e = err(&format!(
            "chacha20poly1305_open(\"0001\", \"{RFC8439_NONCE}\", \"\", \"{RFC8439_SEALED}\")"
        ));
        assert!(e.contains("key is 2 bytes; it must be 32"), "{e}");
    }

    #[test]
    fn a_seal_round_trips_and_binds_the_nonce() {
        let sealed = s(&format!(
            "chacha20poly1305_seal(\"{RFC8439_KEY}\", \"{RFC8439_NONCE}\", \"head\", [0, 255, 7])"
        ));
        assert_eq!(sealed.len(), (3 + AEAD_TAG_BYTES) * 2);
        assert_eq!(
            list_bytes(eval(&format!(
                "chacha20poly1305_open(\"{RFC8439_KEY}\", \"{RFC8439_NONCE}\", \"head\", \"{sealed}\")"
            ))),
            [0, 255, 7]
        );
        let message = rescued(
            &format!("chacha20poly1305_open(\"{RFC8439_KEY}\", \"000000000000000000000000\", \"head\", \"{sealed}\")"),
            "tampered",
        );
        assert!(message.contains("does not verify"), "{message}");
    }

    fn bao_input(len: usize) -> Vec<u8> {
        (1u32..).flat_map(u32::to_le_bytes).take(len).collect()
    }

    #[test]
    fn bao_outboard_matches_the_vectors() {
        for (len, root, outboard_len, outboard_blake3) in [
            (
                0,
                "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
                8,
                "71e0a99173564931c0b8acc52d2685a8e39c64dc52e3d02390fdac2a12b155cb",
            ),
            (
                1025,
                "3613596275c4ea790774dedf20835b2daf86cacc892feef6ce720c121572f1f9",
                72,
                "025f630e00fbdcc023b970c9f1f21016c56c0a34e384e712c66428bf1c7999b9",
            ),
            (
                2049,
                "64770fa15a4bbe7770654c4ac68ed4f0e975ad6c85b5edb4d3db3b4b604e084e",
                136,
                "f2afc0716690e8513d8697e3e75f5c3532d51e0c704416e7fb0bbf7c0abfb57e",
            ),
        ] {
            let (got_root, outboard) = bao_outboard(&bao_input(len));
            assert_eq!(encode_hex(&got_root), root, "root, input_len {len}");
            assert_eq!(
                outboard.len(),
                outboard_len,
                "outboard length, input_len {len}"
            );
            assert_eq!(
                blake3_hex(&outboard),
                outboard_blake3,
                "outboard, input_len {len}"
            );
        }
    }

    const SLICE_VECTORS: [(usize, &str, u64, u64, usize, &str, &[usize]); 3] = [
        (
            13312,
            "3e88d1dd20f426640077dcf82d6d4e18ee0062aa72f8ae547a0e65fcd36a0f06",
            2048,
            1024,
            1288,
            "4a41e4b0529f98aaa354fe1cb22880d9cbe850aa8291db1f85e2c73a9954a462",
            &[7, 8, 72, 136, 200, 264],
        ),
        (
            11264,
            "69fa39c8ab837dbb9e419c66a3ab7014ce9f86dba55935936b4c38cfcbc4d5f6",
            1024,
            1024,
            1288,
            "9fa5fc9ac6f34743ab103137310df80cd01bd45fc3afd62ec3dca95054308544",
            &[7, 8, 72, 136, 200, 264],
        ),
        (
            13312,
            "3e88d1dd20f426640077dcf82d6d4e18ee0062aa72f8ae547a0e65fcd36a0f06",
            2047,
            1024,
            2376,
            "04caae4d370ca619a5e16c3e04706abfa350c7c8c4db46cf51d72d687f8b22c9",
            &[7, 8, 72, 136, 200, 264, 1288, 1352],
        ),
    ];

    #[test]
    fn bao_slices_match_the_vectors_and_verify() {
        for (len, root, start, slice_len, out_len, out_blake3, _) in SLICE_VECTORS {
            let input = bao_input(len);
            let (got_root, outboard) = bao_outboard(&input);
            assert_eq!(encode_hex(&got_root), root);
            let slice = bao_slice(&input, &outboard, start, slice_len).expect("extract");
            assert_eq!(slice.len(), out_len, "slice length, {len}@{start}");
            assert_eq!(blake3_hex(&slice), out_blake3, "slice, {len}@{start}");
            let range = bao_verify_slice(&got_root, &slice, start, slice_len).expect("verify");
            let from = usize::try_from(start).expect("start");
            let to = (from + usize::try_from(slice_len).expect("len")).min(len);
            assert_eq!(range, input[from..to], "range, {len}@{start}");
        }
    }

    #[test]
    fn every_bao_vector_corruption_is_refused() {
        for (len, _, start, slice_len, _, _, corruptions) in SLICE_VECTORS {
            let input = bao_input(len);
            let (root, outboard) = bao_outboard(&input);
            let slice = bao_slice(&input, &outboard, start, slice_len).expect("extract");
            for &at in corruptions {
                let mut bad = slice.clone();
                bad[at] ^= 1;
                assert_eq!(
                    bao_verify_slice(&root, &bad, start, slice_len),
                    Err(CryptoError::Tampered { what: "slice" }),
                    "corruption at {at}, {len}@{start}"
                );
            }
        }
    }

    #[test]
    fn a_slice_round_trips_through_blue() {
        let input = bao_input(2049);
        let data = byte_list(&input);
        let range = eval(&format!(
            "d = {data}\nt = bao_outboard(d)\nbao_verify_slice(t.root, bao_slice(d, t.outboard, 1024, 1025), 1024, 1025)"
        ));
        assert_eq!(list_bytes(range), input[1024..]);
        assert!(b(&format!(
            "bao_outboard({data}).root == blake3_hex({data})"
        )));
    }

    #[test]
    fn a_tampered_range_is_refused() {
        let input = bao_input(2049);
        let (root, outboard) = bao_outboard(&input);
        let slice = encode_hex(&bao_slice(&input, &outboard, 1024, 1024).expect("extract"));
        let root = encode_hex(&root);
        let ok = eval(&format!(
            "bao_verify_slice(\"{root}\", \"{slice}\", 1024, 1024)"
        ));
        assert_eq!(list_bytes(ok), input[1024..2048]);
        for position in [slice.len() - 1, slice.len() / 2, 200, 15] {
            let message = rescued(
                &format!(
                    "bao_verify_slice(\"{root}\", \"{}\", 1024, 1024)",
                    flip_hex_digit(&slice, position)
                ),
                "tampered",
            );
            assert!(
                message.contains("slice does not verify"),
                "{position}: {message}"
            );
        }
        let other_root = blake3_hex(b"another value");
        let message = rescued(
            &format!("bao_verify_slice(\"{other_root}\", \"{slice}\", 1024, 1024)"),
            "tampered",
        );
        assert!(message.contains("slice does not verify"), "{message}");
    }

    #[test]
    fn bao_bad_offsets_and_outboards_are_named_errors() {
        let e = err("bao_slice(\"abc\", \"0300000000000000\", -1, 1)");
        assert!(e.contains("start is -1; it must be 0 or more"), "{e}");
        let e = err("bao_verify_slice(\"00\", \"\", 0, nil)");
        assert!(e.contains("root is 1 bytes; it must be 32"), "{e}");
        let e = err("bao_slice(\"abc\", \"\", 0, 1)");
        assert!(e.contains("outboard does not fit the data"), "{e}");
    }
}
