//! The engine's persistent tier (milestone E5): results
//! keyed by content, kept on disk between runs.
//!
//! **One file per definition.** `$XDG_CACHE_HOME/blue/memo/<identity>/<def_hash>`
//! holds every entry the memo stored for calls of that definition, appended
//! run after run. The layout follows from what invalidates an entry:
//!
//! - an edit changes a definition's `def_hash`, so the entries of the old
//!   tree sit in a file nothing will name again, and eviction removes the
//!   file whole;
//! - a run reads only the files of the definitions it calls, once each, on
//!   the first call that misses in process, so a script that touches three
//!   pure definitions reads three files whatever the store holds;
//! - the file is the unit two machines can share: it is named by content, and
//!   merging two stores is copying files (entries are keyed, so a duplicate
//!   is harmless).
//!
//! A single-file store was the alternative. It reads everything on every run
//! (or keeps a second index file in step), needs one lock for every writer,
//! and must be rewritten to drop an edited definition's entries.
//!
//! **The identity** ([`Identity`]) names the directory: the store format, the
//! blue version and the running executable. An entry is a value the evaluator
//! computed, so it is valid only for that evaluator; a different blue reads
//! a different directory and never sees an incompatible entry.
//!
//! **Damage is ignored, never served.** A file opens with a header naming
//! the format, the identity and the definition; each entry ends with a
//! checksum of itself. A file whose header is wrong is ignored (and replaced
//! on the next write), an entry whose checksum fails is skipped and counted,
//! and a length that runs past the end stops the read there. A miss is always
//! correct, so ignoring is always safe.
//!
//! **Bounded.** Reading a file marks it used; once a run has written, the
//! whole store (every identity) is held under its byte bound by removing the
//! least recently used files first (sticky by default,
//! never unbounded). One definition's file stops growing at a sixteenth of
//! the bound.
//!
//! Writers append whole entries under an exclusive lock on the file; a reader
//! takes no lock and treats a torn entry at the end as damage.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use crate::DefHash;

/// The on-disk format. A change to the header, the entry layout or the value
/// encoding (`crate::canon`) bumps it.
pub const FORMAT: u32 = 1;

const MAGIC: &[u8; 10] = b"blue-memo\0";
const HEADER: usize = MAGIC.len() + 4 + 32 + 32;
const CHECK: usize = 16;
/// An entry's fixed part: its key and its cost.
const FIXED: usize = 32 + 8;

/// The default bound on the whole store, every identity together, and the
/// floor of the bound rule R21 sizes from the load.
pub const DEFAULT_MAX_BYTES: u64 = 256 << 20;

/// How recent a use counts toward the load rule R21 measures.
pub const RECENT: Duration = Duration::from_secs(24 * 60 * 60);

/// Rule R21: the bound a store with the declared bound `max` holds when the
/// files used within [`RECENT`] total `recent` bytes: twice that working set,
/// so eviction never removes what the last day read, at least `max` and at
/// most sixteen times it.
#[must_use]
pub fn sized_bound(max: u64, recent: u64) -> u64 {
    recent.saturating_mul(2).clamp(max, max.saturating_mul(16))
}

/// Which evaluator computed an entry. Entries are read only by the same one.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Identity(pub [u8; 32]);

impl Identity {
    /// The store format, this crate's version (the workspace's), and the
    /// BLAKE3 of the executable running now. Two nodes running the same
    /// bytes share an identity wherever the file sits, so an entry one
    /// computed is served on the other; a rebuild that changes one byte
    /// moves it. The hash is kept beside the cache under a stamp of the
    /// file ([`executable_hash`]); an executable that cannot be read falls
    /// back to its path, size and modification time.
    #[must_use]
    pub fn of_this_build() -> Self {
        let exe = std::env::current_exe().ok();
        let canonical = exe
            .as_deref()
            .map(|p| std::fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf()));
        if let Some(content) = canonical
            .as_deref()
            .and_then(|p| executable_hash(p, cache_root().map(|r| r.join("engine")).as_deref()))
        {
            return Self::of_executable_bytes(&content);
        }
        let meta = canonical.as_deref().and_then(|p| std::fs::metadata(p).ok());
        let mtime = meta
            .as_ref()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_nanos());
        let mut parts: Vec<Vec<u8>> = vec![
            env!("CARGO_PKG_VERSION").as_bytes().to_vec(),
            canonical
                .map(|p| p.to_string_lossy().into_owned().into_bytes())
                .unwrap_or_default(),
            meta.map_or(0, |m| m.len()).to_le_bytes().to_vec(),
            mtime.to_le_bytes().to_vec(),
        ];
        parts.insert(0, FORMAT.to_le_bytes().to_vec());
        Self::from_parts(&parts.iter().map(Vec::as_slice).collect::<Vec<_>>())
    }

    /// The identity of an executable whose bytes hash to `content`
    /// ([`executable_hash`]): the store format, this crate's version and
    /// that hash, and nothing about where the file sits.
    #[must_use]
    pub fn of_executable_bytes(content: &[u8; 32]) -> Self {
        Self::from_parts(&[
            &FORMAT.to_le_bytes(),
            env!("CARGO_PKG_VERSION").as_bytes(),
            b"b3",
            content,
        ])
    }

    /// An identity from explicit parts, each length-prefixed.
    #[must_use]
    pub fn from_parts(parts: &[&[u8]]) -> Self {
        let mut h = blake3::Hasher::new_derive_key("blue memo identity v1");
        for p in parts {
            h.update(&(p.len() as u64).to_le_bytes());
            h.update(p);
        }
        Self(*h.finalize().as_bytes())
    }

    fn dir_name(&self) -> String {
        format!("v{FORMAT}-{}", DefHash(self.0).hex())
    }
}

/// The BLAKE3 of the file at `path`. With `stamps`, the hash is kept there
/// under a stamp of the file (its path, length, inode, device, and its
/// modification and change times, the last of which no caller can set), so
/// the bytes are read once per build, not once per run. A stamp that cannot
/// be read or written costs a re-hash, never a wrong answer.
#[must_use]
pub fn executable_hash(path: &Path, stamps: Option<&Path>) -> Option<[u8; 32]> {
    let meta = std::fs::metadata(path).ok()?;
    let stamp = stamps.map(|dir| dir.join(DefHash(file_stamp(path, &meta)).hex()));
    if let Some(kept) = stamp
        .as_deref()
        .and_then(|s| std::fs::read(s).ok())
        .and_then(|b| <[u8; 32]>::try_from(b.as_slice()).ok())
    {
        return Some(kept);
    }
    let mut h = blake3::Hasher::new();
    h.update_reader(File::open(path).ok()?).ok()?;
    let content = *h.finalize().as_bytes();
    if let Some(stamp) = stamp {
        let _ = keep_stamp(&stamp, &content);
    }
    Some(content)
}

fn file_stamp(path: &Path, meta: &std::fs::Metadata) -> [u8; 32] {
    let nanos = |t: std::io::Result<SystemTime>| {
        t.ok()
            .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_nanos())
    };
    let mut h = blake3::Hasher::new_derive_key("blue engine stamp v1");
    let p = path.to_string_lossy();
    h.update(&(p.len() as u64).to_le_bytes());
    h.update(p.as_bytes());
    h.update(&meta.len().to_le_bytes());
    h.update(&nanos(meta.modified()).to_le_bytes());
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        h.update(&meta.ino().to_le_bytes());
        h.update(&meta.dev().to_le_bytes());
        h.update(&meta.ctime().to_le_bytes());
        h.update(&meta.ctime_nsec().to_le_bytes());
    }
    *h.finalize().as_bytes()
}

fn keep_stamp(stamp: &Path, content: &[u8; 32]) -> std::io::Result<()> {
    let dir = stamp.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(
        ".{}.{}",
        std::process::id(),
        DefHash(*content).hex()
    ));
    std::fs::write(&tmp, content)?;
    std::fs::rename(&tmp, stamp)
}

/// The variable naming read-only cache roots shared with this node: a
/// colon-separated list of directories laid out as [`cache_root`] is
/// (`check/`, `memo/`, `test/`), such as a bidama's analysis from nix.
pub const SHARED_ENV: &str = "BLUE_CACHE_SHARED";

/// The shared roots of one tier: each absolute directory `BLUE_CACHE_SHARED`
/// names, joined with `tier` (`check`, `memo`, `test`).
#[must_use]
pub fn shared_roots(tier: &str) -> Vec<PathBuf> {
    shared_roots_in(std::env::var_os(SHARED_ENV).as_deref(), tier)
}

#[must_use]
pub fn shared_roots_in(value: Option<&std::ffi::OsStr>, tier: &str) -> Vec<PathBuf> {
    value
        .map(|v| {
            std::env::split_paths(v)
                .filter(|p| p.is_absolute())
                .map(|p| p.join(tier))
                .collect()
        })
        .unwrap_or_default()
}

/// The tier holding tier T3's native artifacts (docs/PERFORMANCE.md, 1.7.1):
/// `<root>/native/<NATIVE_LAYOUT>/<def_hash hex>/def`, one directory per
/// definition, built once in the fleet by `nix/native-defs.nix` and named by
/// content, so a definition that changed is never answered by its old code.
pub const NATIVE_TIER: &str = "native";

/// The layout and calling protocol of a native artifact: `def` is an
/// executable taking each Int argument as one decimal argument and printing
/// the Int result on its last line, exiting non-zero on a fault.
pub const NATIVE_LAYOUT: &str = "v1";

/// The native artifact for the definition `hash` names under one of `roots`
/// (each a `native` tier root), the first that holds one.
#[must_use]
pub fn native_artifact_in(roots: &[PathBuf], hash: &DefHash) -> Option<PathBuf> {
    roots
        .iter()
        .map(|r| r.join(NATIVE_LAYOUT).join(hash.hex()).join("def"))
        .find(|p| p.is_file())
}

/// The file beside a native artifact that holds the same definition as a
/// library: it exports `blue_def_entry(args, len, out)`, which answers 0 with
/// the result in `out` and anything else when the interpreter must run the
/// call (`native/seam/def64/lib.rs`).
pub const NATIVE_LIBRARY: &str = "def.so";

/// The library beside the native artifact `artifact`, when its build made one.
#[must_use]
pub fn native_library(artifact: &Path) -> Option<PathBuf> {
    Some(artifact.with_file_name(NATIVE_LIBRARY)).filter(|p| p.is_file())
}

/// Every `native` tier root a run reads, in order: this node's own (under
/// [`cache_root`], where a local build writes), then each root
/// `BLUE_CACHE_SHARED` names.
#[must_use]
pub fn native_roots() -> Vec<PathBuf> {
    cache_root()
        .map(|c| c.join(NATIVE_TIER))
        .into_iter()
        .chain(shared_roots(NATIVE_TIER))
        .collect()
}

/// [`native_artifact_in`] over [`native_roots`].
#[must_use]
pub fn native_artifact(hash: &DefHash) -> Option<PathBuf> {
    native_artifact_in(&native_roots(), hash)
}

/// Where a run asks for a program's definitions to be built:
/// `<native root>/wanted/<key>`, holding the program's path, where `key` is the
/// hex of the program text's content hash. The builder
/// (`native/build/wanted.b`) builds each definition chuuzou compiles that has
/// no artifact yet, then writes `<key>.done`, so the same text is never asked
/// for twice and an edited one is asked for again.
pub const NATIVE_WANTED: &str = "wanted";

/// Ask for the program at `program`, whose text hashes to `key`, to be built
/// into the native root `root`; a text asked for or done already is not asked
/// for again. Answers whether this call asked.
///
/// # Errors
///
/// When the directory or the file cannot be written.
pub fn want_native_in(root: &Path, key: &str, program: &Path) -> std::io::Result<bool> {
    let dir = root.join(NATIVE_WANTED);
    if dir.join(key).exists() || dir.join(format!("{key}.done")).exists() {
        return Ok(false);
    }
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join(key), program.to_string_lossy().as_bytes())?;
    Ok(true)
}

/// [`want_native_in`] under this node's native root, keyed by the content hash
/// of `text`, the program's source: whether it asked. A failure costs the
/// build, never the run.
pub fn want_native(text: &[u8], program: &Path) -> bool {
    let key = blake3::hash(text).to_hex();
    cache_root().is_some_and(|root| {
        want_native_in(&root.join(NATIVE_TIER), key.as_str(), program).unwrap_or(false)
    })
}

/// The tier marking programs whose last run evaluated for long enough that
/// their pure results are worth recording (rule R14): one empty file per
/// program text, named by its content hash.
pub const SLOW_TIER: &str = "slow";

/// Mark the program whose source is `text` as slow, under `root`'s slow
/// tier: whether the mark is there now.
///
/// # Errors
///
/// The directory or the file cannot be written.
pub fn mark_slow_in(root: &Path, text: &[u8]) -> std::io::Result<bool> {
    if root
        .join(SETTLED_TIER)
        .join(blake3::hash(text).to_hex().as_str())
        .is_file()
    {
        return Ok(false);
    }
    let dir = root.join(SLOW_TIER);
    std::fs::create_dir_all(&dir)?;
    let mark = dir.join(blake3::hash(text).to_hex().as_str());
    if !mark.exists() {
        std::fs::write(&mark, b"")?;
    }
    Ok(true)
}

/// [`mark_slow_in`] under this node's cache root. A failure costs the next
/// run its recording, never this run its result.
pub fn mark_slow(text: &[u8]) -> bool {
    cache_root().is_some_and(|root| mark_slow_in(&root, text).unwrap_or(false))
}

/// Whether the program whose source is `text` was marked slow under `root`.
#[must_use]
pub fn marked_slow_in(root: &Path, text: &[u8]) -> bool {
    root.join(SLOW_TIER)
        .join(blake3::hash(text).to_hex().as_str())
        .is_file()
}

/// [`marked_slow_in`] under this node's cache root.
#[must_use]
pub fn marked_slow(text: &[u8]) -> bool {
    cache_root().is_some_and(|root| marked_slow_in(&root, text))
}

/// The tier marking programs a recording run found no costly result in: one
/// empty file per program text, named by its content hash. [`mark_slow_in`]
/// leaves a settled program unmarked, so a program slow only because it makes
/// many cheap calls is not recorded on the walker run after run.
pub const SETTLED_TIER: &str = "settled";

/// Settle the program whose source is `text` under `root`: its slow mark is
/// taken away and it is not marked slow again.
///
/// # Errors
///
/// The directory or the file cannot be written.
pub fn settle_in(root: &Path, text: &[u8]) -> std::io::Result<()> {
    let name = blake3::hash(text).to_hex();
    let dir = root.join(SETTLED_TIER);
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join(name.as_str()), b"")?;
    match std::fs::remove_file(root.join(SLOW_TIER).join(name.as_str())) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
        _ => Ok(()),
    }
}

/// [`settle_in`] under this node's cache root. A failure costs the next run a
/// recording it did not need, never this run its result.
pub fn settle(text: &[u8]) {
    if let Some(root) = cache_root() {
        let _ = settle_in(&root, text);
    }
}

/// Whether any native root holds a native tier (this node's, or a shared
/// one), so a run can skip looking for artifacts without hashing a definition.
#[must_use]
pub fn native_present() -> bool {
    native_roots()
        .iter()
        .any(|r| r.join(NATIVE_LAYOUT).is_dir())
}

/// The tier recording how long a definition's outermost calls ran, keyed by
/// `def_hash`: `<cache_root>/profile/<PROFILE_LAYOUT>/<hex>`, holding the total
/// nanoseconds and the call count. A hash names one body, so a record never
/// goes stale; it only grows.
pub const PROFILE_TIER: &str = "profile";

/// The layout of a profile record: `"<total_ns> <calls>"` on one line.
pub const PROFILE_LAYOUT: &str = "v1";

/// What the profile tier holds for one definition.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Profiled {
    pub total_ns: u64,
    pub calls: u64,
}

impl Profiled {
    /// The mean nanoseconds of one outermost call, or `None` before one.
    #[must_use]
    pub fn mean_ns(self) -> Option<u64> {
        self.total_ns.checked_div(self.calls)
    }

    /// This record with `more` added.
    #[must_use]
    pub fn plus(self, more: Self) -> Self {
        Self {
            total_ns: self.total_ns.saturating_add(more.total_ns),
            calls: self.calls.saturating_add(more.calls),
        }
    }
}

fn profile_path_in(root: &Path, hash: &DefHash) -> PathBuf {
    root.join(PROFILE_TIER)
        .join(PROFILE_LAYOUT)
        .join(hash.hex())
}

/// The profile of `hash` under the cache root `root`.
#[must_use]
pub fn profile_in(root: &Path, hash: &DefHash) -> Option<Profiled> {
    let text = std::fs::read_to_string(profile_path_in(root, hash)).ok()?;
    let mut parts = text.split_whitespace();
    let total_ns = parts.next()?.parse().ok()?;
    let calls = parts.next()?.parse().ok()?;
    Some(Profiled { total_ns, calls })
}

/// Add `more` to the profile of `hash` under `root`, written whole by rename.
///
/// # Errors
///
/// When the directory or the file cannot be written.
pub fn record_profile_in(root: &Path, hash: &DefHash, more: Profiled) -> std::io::Result<()> {
    let path = profile_path_in(root, hash);
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let now = profile_in(root, hash).unwrap_or_default().plus(more);
    let tmp = dir.join(format!(".{}.{}", std::process::id(), hash.hex()));
    std::fs::write(&tmp, format!("{} {}\n", now.total_ns, now.calls))?;
    std::fs::rename(&tmp, path)
}

/// [`profile_in`] under [`cache_root`].
#[must_use]
pub fn profile(hash: &DefHash) -> Option<Profiled> {
    profile_in(&cache_root()?, hash)
}

/// [`record_profile_in`] under [`cache_root`]; a failure costs the next run its
/// profile, never this run its result.
pub fn record_profile(hash: &DefHash, more: Profiled) {
    if let Some(root) = cache_root() {
        let _ = record_profile_in(&root, hash, more);
    }
}

/// blue's cache directory: `$XDG_CACHE_HOME/blue`, else `$HOME/.cache/blue`.
/// Every persistent tier lives under it, one directory each.
#[must_use]
pub fn cache_root() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| {
            std::env::var_os("HOME")
                .filter(|v| !v.is_empty())
                .map(|h| PathBuf::from(h).join(".cache"))
        })?;
    Some(base.join("blue"))
}

/// The store's directory when nothing names one: [`cache_root`]`/memo`.
#[must_use]
pub fn default_root() -> Option<PathBuf> {
    Some(cache_root()?.join("memo"))
}

#[must_use]
pub fn check_root() -> Option<PathBuf> {
    Some(cache_root()?.join("check"))
}

/// One tier of blue's cache (`check`, `memo`, `test`) for this build:
/// [`cache_root`]`/<tier>` under [`Identity::of_this_build`], falling through
/// to the same tier of every root `BLUE_CACHE_SHARED` names. `None` when the
/// directory cannot be created (a read-only home, a build sandbox), and then
/// the executable is never hashed.
#[must_use]
pub fn open_tier(tier: &str) -> Option<Store> {
    let root = cache_root()?.join(tier);
    std::fs::create_dir_all(&root).ok()?;
    Store::open(&root, Identity::of_this_build(), DEFAULT_MAX_BYTES)
        .ok()
        .map(|s| s.sharing(&shared_roots(tier)))
}

impl blue_lang_runtime::check_cache::CheckStore for Store {
    fn load(&self, bucket: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
        Store::load(self, bucket)
            .entries
            .into_iter()
            .map(|(k, s)| (k, s.value))
            .collect()
    }

    fn append(&self, bucket: &DefHash, entries: &[([u8; 32], Vec<u8>)]) {
        let entries: Vec<([u8; 32], Duration, Vec<u8>)> = entries
            .iter()
            .map(|(k, v)| (*k, Duration::ZERO, v.clone()))
            .collect();
        let _ = Store::append(self, bucket, &entries);
    }
}

/// One stored entry.
#[derive(Clone, Debug)]
pub struct Stored {
    /// What computing it cost when it was stored.
    pub cost: Duration,
    /// The canonical encoding of the value (`crate::canon`).
    pub value: Vec<u8>,
}

/// One definition's file, read.
#[derive(Debug, Default)]
pub struct Bucket {
    pub entries: HashMap<[u8; 32], Stored>,
    /// Entries read from a shared root and absent here; [`Store::load`]
    /// copies them into this node's store.
    pub shared: usize,
    /// Entries skipped because their checksum failed or their length ran
    /// past the end, and headers that did not match.
    pub damaged: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Inclusion {
    pub root: [u8; 32],
    pub index: usize,
    pub total: usize,
    pub path: Vec<[u8; 32]>,
}

#[must_use]
pub fn leaf(key: &[u8; 32], value: &[u8]) -> [u8; 32] {
    tameshi::hash::Blake3Hash::digest_fields(&[key, value]).0
}

impl Inclusion {
    #[must_use]
    pub fn verifies(&self, key: &[u8; 32], value: &[u8]) -> bool {
        let path: Vec<tameshi::hash::Blake3Hash> = self
            .path
            .iter()
            .copied()
            .map(tameshi::hash::Blake3Hash)
            .collect();
        tameshi::merkle::verify_leaf_inclusion(
            &path,
            &tameshi::hash::Blake3Hash(self.root),
            &tameshi::hash::Blake3Hash(leaf(key, value)),
            self.index,
            self.total,
        )
    }
}

impl Bucket {
    fn leaves(&self) -> (Vec<[u8; 32]>, Vec<tameshi::hash::Blake3Hash>) {
        let mut keys: Vec<[u8; 32]> = self.entries.keys().copied().collect();
        keys.sort_unstable();
        let leaves = keys
            .iter()
            .map(|k| tameshi::hash::Blake3Hash(leaf(k, &self.entries[k].value)))
            .collect();
        (keys, leaves)
    }

    #[must_use]
    pub fn root(&self) -> [u8; 32] {
        tameshi::merkle::compute_leaf_root(&self.leaves().1).0
    }

    #[must_use]
    pub fn prove(&self, key: &[u8; 32]) -> Option<Inclusion> {
        let (keys, leaves) = self.leaves();
        let index = keys.binary_search(key).ok()?;
        let path = tameshi::merkle::leaf_inclusion_proof(&leaves, index)?;
        Some(Inclusion {
            root: tameshi::merkle::compute_leaf_root(&leaves).0,
            index,
            total: leaves.len(),
            path: path.into_iter().map(|h| h.0).collect(),
        })
    }
}

/// The persistent store of one evaluator identity.
pub struct Store {
    root: PathBuf,
    dir: PathBuf,
    identity: Identity,
    max_bytes: u64,
    shared: Vec<PathBuf>,
}

impl Store {
    /// The store under `root` for `identity`, created if absent.
    ///
    /// # Errors
    ///
    /// The directory cannot be created: a read-only home, a sandbox.
    pub fn open(root: &Path, identity: Identity, max_bytes: u64) -> std::io::Result<Self> {
        let dir = root.join(identity.dir_name());
        std::fs::create_dir_all(&dir)?;
        Ok(Self {
            root: root.to_path_buf(),
            dir,
            identity,
            max_bytes,
            shared: Vec::new(),
        })
    }

    /// This store, falling through to `roots` on a miss: read-only roots laid
    /// out as this one's, each read under this store's identity only. A
    /// shared entry is copied here when read, so the next run finds it
    /// locally. A root that is this store's own is skipped.
    #[must_use]
    pub fn sharing(mut self, roots: &[PathBuf]) -> Self {
        let own = std::fs::canonicalize(&self.root).unwrap_or_else(|_| self.root.clone());
        self.shared = roots
            .iter()
            .filter(|r| std::fs::canonicalize(r).map_or(true, |c| c != own))
            .map(|r| r.join(self.identity.dir_name()))
            .collect();
        self
    }

    #[must_use]
    pub fn dir(&self) -> &Path {
        &self.dir
    }

    #[must_use]
    pub fn identity(&self) -> Identity {
        self.identity
    }

    fn path(&self, bucket: &DefHash) -> PathBuf {
        self.dir.join(bucket.hex())
    }

    fn header(&self, bucket: &DefHash) -> [u8; HEADER] {
        let mut h = [0u8; HEADER];
        h[..MAGIC.len()].copy_from_slice(MAGIC);
        h[MAGIC.len()..MAGIC.len() + 4].copy_from_slice(&FORMAT.to_le_bytes());
        h[MAGIC.len() + 4..MAGIC.len() + 36].copy_from_slice(&self.identity.0);
        h[MAGIC.len() + 36..].copy_from_slice(bucket.bytes());
        h
    }

    /// Every entry stored for `bucket`. A missing or unreadable file is an
    /// empty bucket; reading one marks it used.
    #[must_use]
    pub fn load(&self, bucket: &DefHash) -> Bucket {
        let path = self.path(bucket);
        let mut out = match std::fs::read(&path) {
            Ok(bytes) => {
                if let Ok(f) = OpenOptions::new().write(true).open(&path) {
                    let _ = f.set_modified(SystemTime::now());
                }
                self.parse(bucket, &bytes)
            }
            Err(_) => Bucket::default(),
        };
        let mut promote = Vec::new();
        for dir in &self.shared {
            let Ok(bytes) = std::fs::read(dir.join(bucket.hex())) else {
                continue;
            };
            let read = self.parse(bucket, &bytes);
            out.damaged += read.damaged;
            for (key, stored) in read.entries {
                if !out.entries.contains_key(&key) {
                    promote.push((key, stored.cost, stored.value.clone()));
                    out.entries.insert(key, stored);
                }
            }
        }
        out.shared = promote.len();
        if !promote.is_empty() {
            let _ = self.append(bucket, &promote);
        }
        out
    }

    fn parse(&self, bucket: &DefHash, bytes: &[u8]) -> Bucket {
        let mut out = Bucket::default();
        if bytes.len() < HEADER || bytes[..HEADER] != self.header(bucket) {
            out.damaged = 1;
            return out;
        }
        let mut at = HEADER;
        while at < bytes.len() {
            let Some(len) = bytes
                .get(at..at + 4)
                .and_then(|b| b.try_into().ok())
                .map(u32::from_le_bytes)
                .map(|n| n as usize)
            else {
                out.damaged += 1;
                break;
            };
            let end = at + 4 + len + CHECK;
            if len < FIXED || end > bytes.len() {
                out.damaged += 1;
                break;
            }
            let body = &bytes[at + 4..at + 4 + len];
            if checksum(&bytes[at..at + 4], body) != bytes[at + 4 + len..end] {
                out.damaged += 1;
                at = end;
                continue;
            }
            let mut key = [0u8; 32];
            key.copy_from_slice(&body[..32]);
            let nanos = u64::from_le_bytes(body[32..40].try_into().expect("8 bytes"));
            out.entries.insert(
                key,
                Stored {
                    cost: Duration::from_nanos(nanos),
                    value: body[FIXED..].to_vec(),
                },
            );
            at = end;
        }
        out
    }

    /// Append `entries` to `bucket`'s file, under an exclusive lock. A file
    /// whose header is wrong is replaced; a file at its share of the bound
    /// takes nothing more. Answers how many entries were written.
    ///
    /// # Errors
    ///
    /// The file cannot be opened, locked or written.
    pub fn append(
        &self,
        bucket: &DefHash,
        entries: &[([u8; 32], Duration, Vec<u8>)],
    ) -> std::io::Result<usize> {
        let mut f = OpenOptions::new()
            .read(true)
            .append(true)
            .create(true)
            .open(self.path(bucket))?;
        f.lock()?;
        let len = f.metadata()?.len();
        let header = self.header(bucket);
        let mut buf = Vec::new();
        let mut size = len;
        if len < HEADER as u64 || !starts_with(&mut f, &header)? {
            f.set_len(0)?;
            buf.extend_from_slice(&header);
            size = HEADER as u64;
        }
        let share = self.max_bytes / 16;
        let mut written = 0;
        for (key, cost, value) in entries {
            let len = FIXED + value.len();
            let Ok(len32) = u32::try_from(len) else {
                continue;
            };
            if size + (4 + len + CHECK) as u64 > share {
                break;
            }
            let start = buf.len();
            buf.extend_from_slice(&len32.to_le_bytes());
            buf.extend_from_slice(key);
            buf.extend_from_slice(
                &u64::try_from(cost.as_nanos())
                    .unwrap_or(u64::MAX)
                    .to_le_bytes(),
            );
            buf.extend_from_slice(value);
            let check = checksum(&buf[start..start + 4], &buf[start + 4..]);
            buf.extend_from_slice(&check);
            size += (4 + len + CHECK) as u64;
            written += 1;
        }
        f.write_all(&buf)?;
        f.unlock()?;
        Ok(written)
    }

    /// Hold the whole store (every identity under the root) under its bound,
    /// removing the least recently used files first, down to three quarters
    /// of it. The bound is sized from the measured load (rule R21,
    /// [`sized_bound`]); `BLUE_CACHE=fixed` holds it to the one the store was
    /// opened with. Answers the files removed.
    ///
    /// # Errors
    ///
    /// The root cannot be listed.
    pub fn evict(&self) -> std::io::Result<usize> {
        self.evict_sized(!blue_lang_runtime::kitei::switched_off("R21"))
    }

    fn evict_sized(&self, sized: bool) -> std::io::Result<usize> {
        let now = SystemTime::now();
        let mut files = Vec::new();
        let mut total = 0u64;
        let mut recent = 0u64;
        for identity in std::fs::read_dir(&self.root)?.flatten() {
            let Ok(entries) = std::fs::read_dir(identity.path()) else {
                continue;
            };
            for e in entries.flatten() {
                let Ok(meta) = e.metadata() else { continue };
                if !meta.is_file() {
                    continue;
                }
                total += meta.len();
                let used = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
                if now.duration_since(used).is_ok_and(|age| age < RECENT) {
                    recent += meta.len();
                }
                files.push((used, meta.len(), e.path()));
            }
        }
        let bound = if sized {
            sized_bound(self.max_bytes, recent)
        } else {
            self.max_bytes
        };
        if total <= bound {
            return Ok(0);
        }
        files.sort();
        let target = bound / 4 * 3;
        let mut removed = 0;
        for (_, len, path) in files {
            if total <= target {
                break;
            }
            if std::fs::remove_file(&path).is_ok() {
                total = total.saturating_sub(len);
                removed += 1;
            }
        }
        for identity in std::fs::read_dir(&self.root)?.flatten() {
            if identity.path() != self.dir {
                let _ = std::fs::remove_dir(identity.path());
            }
        }
        Ok(removed)
    }
}

fn starts_with(f: &mut File, header: &[u8]) -> std::io::Result<bool> {
    let mut got = vec![0u8; header.len()];
    f.seek(SeekFrom::Start(0))?;
    let ok = f.read_exact(&mut got).is_ok() && got == header;
    f.seek(SeekFrom::End(0))?;
    Ok(ok)
}

fn checksum(len: &[u8], body: &[u8]) -> [u8; CHECK] {
    let mut h = blake3::Hasher::new_derive_key("blue memo entry v1");
    h.update(len);
    h.update(body);
    let mut out = [0u8; CHECK];
    out.copy_from_slice(&h.finalize().as_bytes()[..CHECK]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("blue-store-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        p
    }

    #[test]
    fn a_program_text_is_asked_for_once_and_never_once_done() {
        let root = temp("wanted");
        let wanted = root.join(NATIVE_WANTED).join("ab12");
        assert!(want_native_in(&root, "ab12", Path::new("/p/a.b")).expect("asked"));
        assert_eq!(
            std::fs::read_to_string(&wanted).expect("the request"),
            "/p/a.b"
        );
        assert!(!want_native_in(&root, "ab12", Path::new("/p/b.b")).expect("asked again"));
        assert_eq!(
            std::fs::read_to_string(&wanted).expect("the request"),
            "/p/a.b"
        );
        std::fs::remove_file(&wanted).expect("taken");
        std::fs::write(root.join(NATIVE_WANTED).join("ab12.done"), "").expect("done");
        assert!(!want_native_in(&root, "ab12", Path::new("/p/a.b")).expect("not asked"));
        assert!(!wanted.exists());
        assert!(want_native_in(&root, "cd34", Path::new("/p/a.b")).expect("an edited text"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_settled_program_loses_its_slow_mark_and_is_not_marked_again() {
        let root = temp("settled");
        let text = b"def main()\n  1\nend\n";
        assert!(mark_slow_in(&root, text).expect("marks"));
        assert!(marked_slow_in(&root, text));
        settle_in(&root, text).expect("settles");
        assert!(!marked_slow_in(&root, text));
        assert!(!mark_slow_in(&root, text).expect("reads"));
        assert!(!marked_slow_in(&root, text));
        assert!(mark_slow_in(&root, b"other").expect("marks"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_profile_only_grows_and_its_mean_is_per_call() {
        let root = temp("profile");
        let h = DefHash([7; 32]);
        assert_eq!(profile_in(&root, &h), None);
        record_profile_in(
            &root,
            &h,
            Profiled {
                total_ns: 300,
                calls: 1,
            },
        )
        .expect("writes");
        record_profile_in(
            &root,
            &h,
            Profiled {
                total_ns: 100,
                calls: 1,
            },
        )
        .expect("writes");
        let p = profile_in(&root, &h).expect("reads");
        assert_eq!(
            p,
            Profiled {
                total_ns: 400,
                calls: 2
            }
        );
        assert_eq!(p.mean_ns(), Some(200));
        assert_eq!(Profiled::default().mean_ns(), None);
        let other = DefHash([8; 32]);
        assert_eq!(profile_in(&root, &other), None);
        let _ = std::fs::remove_dir_all(&root);
    }

    fn entry(n: u8, value: &[u8]) -> ([u8; 32], Duration, Vec<u8>) {
        ([n; 32], Duration::from_micros(u64::from(n)), value.to_vec())
    }

    #[test]
    fn entries_written_by_one_run_are_read_by_the_next() {
        let root = temp("round");
        let id = Identity::from_parts(&[b"a"]);
        let bucket = DefHash([7; 32]);
        let store = Store::open(&root, id, DEFAULT_MAX_BYTES).expect("opens");
        assert_eq!(
            store
                .append(&bucket, &[entry(1, b"one"), entry(2, b"two")])
                .expect("writes"),
            2
        );
        assert_eq!(
            store
                .append(&bucket, &[entry(3, b"three")])
                .expect("writes"),
            1
        );
        let again = Store::open(&root, id, DEFAULT_MAX_BYTES).expect("opens");
        let b = again.load(&bucket);
        assert_eq!(b.damaged, 0);
        assert_eq!(b.entries.len(), 3);
        assert_eq!(b.entries[&[2; 32]].value, b"two");
        assert_eq!(b.entries[&[3; 32]].cost, Duration::from_micros(3));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn every_entry_of_a_bucket_proves_against_its_root_and_a_changed_value_does_not() {
        let root = temp("proof");
        let store =
            Store::open(&root, Identity::from_parts(&[b"p"]), DEFAULT_MAX_BYTES).expect("opens");
        let bucket = DefHash([9; 32]);
        let written: Vec<_> = (1..=5).map(|n| entry(n, &[n, n])).collect();
        store.append(&bucket, &written).expect("writes");
        let b = store.load(&bucket);
        for n in 1..=5u8 {
            let proof = b.prove(&[n; 32]).expect("stored");
            assert_eq!(proof.root, b.root());
            assert_eq!(proof.total, 5);
            assert!(proof.verifies(&[n; 32], &[n, n]));
            assert!(!proof.verifies(&[n; 32], &[n]));
        }
        assert!(b.prove(&[6; 32]).is_none());
        let before = b.root();
        store.append(&bucket, &[entry(6, b"six")]).expect("writes");
        assert_ne!(store.load(&bucket).root(), before);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn another_identity_never_reads_an_entry() {
        let root = temp("identity");
        let bucket = DefHash([7; 32]);
        let a =
            Store::open(&root, Identity::from_parts(&[b"a"]), DEFAULT_MAX_BYTES).expect("opens");
        a.append(&bucket, &[entry(1, b"one")]).expect("writes");
        let b =
            Store::open(&root, Identity::from_parts(&[b"b"]), DEFAULT_MAX_BYTES).expect("opens");
        assert!(b.load(&bucket).entries.is_empty());
        std::fs::copy(a.path(&bucket), b.path(&bucket)).expect("copies");
        let read = b.load(&bucket);
        assert!(read.entries.is_empty());
        assert_eq!(read.damaged, 1);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_damaged_entry_is_skipped_and_its_neighbours_survive() {
        let root = temp("damage");
        let id = Identity::from_parts(&[b"a"]);
        let bucket = DefHash([9; 32]);
        let store = Store::open(&root, id, DEFAULT_MAX_BYTES).expect("opens");
        store
            .append(
                &bucket,
                &[entry(1, b"first"), entry(2, b"second"), entry(3, b"third")],
            )
            .expect("writes");
        let path = store.path(&bucket);
        let mut bytes = std::fs::read(&path).expect("reads");
        let second = bytes
            .windows(6)
            .position(|w| w == b"second")
            .expect("present");
        bytes[second] ^= 0x20;
        std::fs::write(&path, &bytes).expect("writes");
        let b = store.load(&bucket);
        assert_eq!(b.damaged, 1);
        assert_eq!(b.entries.len(), 2);
        assert!(!b.entries.contains_key(&[2; 32]));
        bytes[second] ^= 0x20;
        bytes.truncate(bytes.len() - 5);
        std::fs::write(&path, &bytes).expect("writes");
        let b = store.load(&bucket);
        assert_eq!((b.entries.len(), b.damaged), (2, 1));
        bytes[0] = b'X';
        std::fs::write(&path, &bytes).expect("writes");
        assert_eq!(store.load(&bucket).damaged, 1);
        store
            .append(&bucket, &[entry(4, b"fourth")])
            .expect("writes");
        let b = store.load(&bucket);
        assert_eq!((b.entries.len(), b.damaged), (1, 0));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn eviction_holds_the_bound_and_removes_the_least_recently_used_first() {
        let root = temp("evict");
        let id = Identity::from_parts(&[b"a"]);
        let store = Store::open(&root, id, 16 << 10).expect("opens");
        let value = vec![0u8; 800];
        for n in 0..40u8 {
            store
                .append(&DefHash([n; 32]), &[entry(n, &value)])
                .expect("writes");
            let p = store.path(&DefHash([n; 32]));
            let f = OpenOptions::new().write(true).open(&p).expect("opens");
            f.set_modified(SystemTime::UNIX_EPOCH + Duration::from_secs(1_000 + u64::from(n)))
                .expect("dates");
        }
        assert_eq!(store.load(&DefHash([0; 32])).entries.len(), 1);
        let removed = store.evict().expect("evicts");
        assert!(removed > 0);
        let total: u64 = std::fs::read_dir(store.dir())
            .expect("lists")
            .flatten()
            .map(|e| e.metadata().map_or(0, |m| m.len()))
            .sum();
        assert!(total <= 16 << 10, "{total}");
        assert!(
            store.path(&DefHash([0; 32])).exists(),
            "the file just read survives"
        );
        assert!(
            !store.path(&DefHash([1; 32])).exists(),
            "the oldest unread file goes"
        );
        assert!(store.path(&DefHash([39; 32])).exists(), "the newest stays");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_bound_is_twice_the_day_s_working_set_between_the_declared_bound_and_sixteen_times_it() {
        assert_eq!(sized_bound(100, 0), 100);
        assert_eq!(sized_bound(100, 50), 100);
        assert_eq!(sized_bound(100, 70), 140);
        assert_eq!(sized_bound(100, 800), 1600);
        assert_eq!(sized_bound(100, 801), 1600);
        assert_eq!(sized_bound(u64::MAX, u64::MAX), u64::MAX);
    }

    #[test]
    fn rule_r21_keeps_a_working_set_used_today_that_a_fixed_bound_evicts() {
        let root = temp("evict-load");
        let id = Identity::from_parts(&[b"a"]);
        let store = Store::open(&root, id, 16 << 10).expect("opens");
        let value = vec![0u8; 800];
        for n in 0..40u8 {
            store
                .append(&DefHash([n; 32]), &[entry(n, &value)])
                .expect("writes");
        }
        let on_disk = |s: &Store| -> u64 {
            std::fs::read_dir(s.dir())
                .expect("lists")
                .flatten()
                .map(|e| e.metadata().map_or(0, |m| m.len()))
                .sum()
        };
        let held = on_disk(&store);
        assert!(held > 16 << 10, "{held}");
        assert_eq!(store.evict_sized(true).expect("evicts"), 0);
        assert_eq!(on_disk(&store), held, "the day's working set is kept");
        assert!(store.evict_sized(false).expect("evicts") > 0);
        assert!(
            on_disk(&store) <= 16 << 10,
            "BLUE_CACHE=fixed holds the declared bound"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_shared_root_answers_a_miss_and_the_entry_is_copied_here() {
        let root = temp("shared-local");
        let other = temp("shared-other");
        let id = Identity::from_parts(&[b"a"]);
        let bucket = DefHash([9; 32]);
        Store::open(&other, id, DEFAULT_MAX_BYTES)
            .expect("opens")
            .append(&bucket, &[entry(1, b"one"), entry(2, b"two")])
            .expect("writes");
        let local = Store::open(&root, id, DEFAULT_MAX_BYTES).expect("opens");
        local.append(&bucket, &[entry(2, b"mine")]).expect("writes");
        let sharing = Store::open(&root, id, DEFAULT_MAX_BYTES)
            .expect("opens")
            .sharing(&[other.clone()]);
        let b = sharing.load(&bucket);
        assert_eq!((b.entries.len(), b.shared), (2, 1));
        assert_eq!(b.entries[&[2; 32]].value, b"mine");
        assert_eq!(b.entries[&[1; 32]].value, b"one");
        let _ = std::fs::remove_dir_all(&other);
        let alone = Store::open(&root, id, DEFAULT_MAX_BYTES).expect("opens");
        let b = alone.load(&bucket);
        assert_eq!((b.entries.len(), b.shared), (2, 0));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_shared_root_under_another_identity_answers_nothing() {
        let root = temp("shared-id-local");
        let other = temp("shared-id-other");
        let bucket = DefHash([9; 32]);
        let theirs =
            Store::open(&other, Identity::from_parts(&[b"b"]), DEFAULT_MAX_BYTES).expect("opens");
        theirs.append(&bucket, &[entry(1, b"one")]).expect("writes");
        let id = Identity::from_parts(&[b"a"]);
        let planted = other.join(id.dir_name());
        std::fs::create_dir_all(&planted).expect("dir");
        std::fs::copy(theirs.path(&bucket), planted.join(bucket.hex())).expect("copies");
        let mine = Store::open(&root, id, DEFAULT_MAX_BYTES)
            .expect("opens")
            .sharing(&[other.clone()]);
        let b = mine.load(&bucket);
        assert!(b.entries.is_empty());
        assert_eq!(b.damaged, 1);
        let _ = std::fs::remove_dir_all(&root);
        let _ = std::fs::remove_dir_all(&other);
    }

    #[test]
    fn one_executable_is_one_identity_wherever_it_sits_and_one_byte_moves_it() {
        let dir = temp("exe");
        let stamps = dir.join("stamps");
        std::fs::create_dir_all(&dir).expect("dir");
        let a = dir.join("a");
        let b = dir.join("b");
        std::fs::write(&a, b"the same engine").expect("writes");
        std::fs::write(&b, b"the same engine").expect("writes");
        let ha = executable_hash(&a, Some(&stamps)).expect("hashes");
        assert_eq!(ha, *blake3::hash(b"the same engine").as_bytes());
        assert_eq!(executable_hash(&b, Some(&stamps)), Some(ha));
        assert_eq!(executable_hash(&a, Some(&stamps)), Some(ha));
        assert_eq!(std::fs::read_dir(&stamps).expect("stamps").count(), 2);
        std::fs::write(&b, b"the same enginf").expect("rewrites");
        let hb = executable_hash(&b, Some(&stamps)).expect("hashes");
        assert_ne!(hb, ha);
        assert!(Identity::of_executable_bytes(&hb) != Identity::of_executable_bytes(&ha));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_shared_roots_are_the_absolute_directories_named() {
        let v = std::ffi::OsString::from("/a/blue:relative:/b");
        assert_eq!(
            shared_roots_in(Some(&v), "check"),
            vec![PathBuf::from("/a/blue/check"), PathBuf::from("/b/check")]
        );
        assert!(shared_roots_in(None, "memo").is_empty());
    }

    #[test]
    fn one_definition_stops_growing_at_its_share() {
        let root = temp("share");
        let store = Store::open(&root, Identity::from_parts(&[b"a"]), 16 << 10).expect("opens");
        let bucket = DefHash([5; 32]);
        let many: Vec<_> = (0..100u8).map(|n| entry(n, &[0u8; 100])).collect();
        let written = store.append(&bucket, &many).expect("writes");
        assert!(written < 100 && written > 0, "{written}");
        assert!(
            std::fs::metadata(store.path(&bucket))
                .expect("exists")
                .len()
                <= 1 << 10
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_native_artifact_is_found_by_its_def_hash_and_only_by_it() {
        let root = temp("native");
        let hash = DefHash([7; 32]);
        let other = DefHash([8; 32]);
        let dir = root.join(NATIVE_TIER).join(NATIVE_LAYOUT).join(hash.hex());
        std::fs::create_dir_all(&dir).expect("creates");
        std::fs::write(dir.join("def"), b"").expect("writes");
        let roots = shared_roots_in(Some(root.as_os_str()), NATIVE_TIER);
        assert_eq!(native_artifact_in(&roots, &hash), Some(dir.join("def")));
        assert_eq!(native_artifact_in(&roots, &other), None);
        assert_eq!(native_artifact_in(&[], &hash), None);
        let _ = std::fs::remove_dir_all(&root);
    }
}
