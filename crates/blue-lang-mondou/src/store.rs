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

/// The default bound on the whole store, every identity together.
pub const DEFAULT_MAX_BYTES: u64 = 256 << 20;

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
    /// of it. Answers the files removed.
    ///
    /// # Errors
    ///
    /// The root cannot be listed.
    pub fn evict(&self) -> std::io::Result<usize> {
        let mut files = Vec::new();
        let mut total = 0u64;
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
                files.push((used, meta.len(), e.path()));
            }
        }
        if total <= self.max_bytes {
            return Ok(0);
        }
        files.sort();
        let target = self.max_bytes / 4 * 3;
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
}
