//! An appliance: one blue program sealed into one executable.
//!
//! `blue bundle` compiles a program (every `use` resolved, checked, erased)
//! into a [`Payload`] that carries the capability record its project's
//! `Bluefile.lock` verified, and [`seal`] closes it with its BLAKE3 digest.
//! The runner (`blue-appliance`) reads the sealed payload from the end of its
//! own file, [`open`]s it, and runs it held to that record. No flag widens the
//! hold, and a payload with no record runs pure: no host capability at all.
//!
//! The executable is the runner's bytes followed by the sealed payload, so
//! sealing is concatenation and one runner serves every program:
//!
//! ```text
//! runner | body (JSON) | digest (32 bytes) | body length (u64 LE) | MAGIC (8)
//! ```

use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use blue_lang_runtime::pipeline::{Compiled, RunError};
use blue_lang_runtime::Hold;
use blue_lang_waku::{Provisions, Waku, When, Where};
use serde::{Deserialize, Serialize};

use crate::capabilities::{reach_of, CapabilityRecord};

/// The payload layout this blue writes and reads.
pub const FORMAT: u32 = 1;

/// The last eight bytes of a sealed payload.
pub const MAGIC: [u8; 8] = *b"blueapp1";

const DIGEST: usize = 32;

/// The seal after the body: digest, body length, [`MAGIC`].
pub const TRAILER: usize = DIGEST + 8 + MAGIC.len();

const DOMAIN: &str = "blue appliance payload v1";

/// The blue a payload is compiled by, and the only blue that runs it.
pub const BLUE_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The hold's name in a breach's message.
pub const WHO: &str = "this appliance's policy";

/// `EX_DATAERR`: a payload is present and refused.
pub const EX_DATAERR: u8 = 65;

/// `EX_NOINPUT`: the executable carries no payload.
pub const EX_NOINPUT: u8 = 66;

/// A compiled program and the policy it runs under.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Payload {
    pub format: u32,
    pub blue: String,
    /// The project's name, or the entry file's stem outside a project.
    pub name: String,
    /// The runtime key of the entry file's `main`, called after the forms.
    pub main: Option<String>,
    /// The verified capability record from `Bluefile.lock`; `None` runs pure.
    pub policy: Option<CapabilityRecord>,
    /// Every top-level form, in evaluation order.
    pub forms: Vec<Form>,
}

/// One top-level form: its erased tree, spanless, and the content identity
/// of the definition it makes.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Form {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub def: Option<Def>,
    /// `blue_lang_proc::trace::form_to_json` of the erased form.
    pub tree: serde_json::Value,
}

/// A definition's runtime key and its `def_hash` (`b3:<hex>`), the hash of
/// its resolved tree before erasure.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Def {
    pub key: String,
    pub hash: String,
}

/// Why a payload is not run.
#[derive(Debug, thiserror::Error)]
pub enum Refusal {
    #[error("this executable carries no payload; `blue bundle --runner` seals one onto a runner")]
    Missing,
    #[error(
        "the seal claims a {len}-byte payload and the executable holds {room} bytes before it"
    )]
    Length { len: u64, room: u64 },
    #[error(
        "the payload does not match its BLAKE3 seal: it changed after `blue bundle` sealed it"
    )]
    Tampered,
    #[error("the payload does not read: {0}")]
    Unreadable(String),
    #[error("the payload has format {found:?}; this runner reads {FORMAT}")]
    Format { found: Option<u64> },
    #[error("the payload was compiled by blue {payload}, and this runner is blue {BLUE_VERSION}")]
    Version { payload: String },
    #[error("the payload's policy {0}")]
    Policy(String),
    #[error("top-level form {top_level} does not decode: {why}")]
    Form { top_level: usize, why: String },
    #[error("reading the executable: {0}")]
    Io(#[from] std::io::Error),
}

impl Refusal {
    /// [`EX_NOINPUT`] when there is no payload, [`EX_DATAERR`] otherwise.
    #[must_use]
    pub fn exit_status(&self) -> u8 {
        match self {
            Refusal::Missing => EX_NOINPUT,
            _ => EX_DATAERR,
        }
    }
}

/// Why `blue bundle` wrote nothing.
#[derive(Debug, thiserror::Error)]
pub enum BundleError {
    #[error(transparent)]
    Source(#[from] crate::canonical::Refusal),
    #[error("{project}: {reason}; run `blue lock {project}`")]
    Stale {
        project: String,
        reason: crate::lock::Staleness,
    },
    #[error(transparent)]
    Lock(#[from] crate::lock::LockError),
    #[error("{project}/Bluefile.lock does not read: {why}")]
    LockText { project: String, why: String },
    #[error(transparent)]
    Compile(#[from] RunError),
    #[error(transparent)]
    Policy(#[from] Refusal),
    #[error("top-level form {top_level} does not survive the payload encoding unchanged")]
    Codec { top_level: usize },
}

/// Why an appliance stopped.
#[derive(Debug, thiserror::Error)]
pub enum Failure {
    #[error(transparent)]
    Refused(#[from] Refusal),
    #[error(transparent)]
    Ran(#[from] RunError),
}

impl Failure {
    /// The refusal's status, or the run's: 77 for a breach, 1 otherwise.
    #[must_use]
    pub fn exit_status(&self) -> u8 {
        match self {
            Failure::Refused(r) => r.exit_status(),
            Failure::Ran(e) => e.exit_status(),
        }
    }
}

impl Payload {
    /// `compiled` as a payload named `name`, held to `policy`. Each
    /// definition carries its `def_hash`; each tree is checked to decode to
    /// itself, so a value the encoding would bend is refused here and never
    /// run changed.
    ///
    /// # Errors
    ///
    /// [`BundleError::Codec`] for a form that does not decode to itself.
    pub fn of(
        name: &str,
        compiled: &Compiled,
        policy: Option<CapabilityRecord>,
    ) -> Result<Self, BundleError> {
        let docs = blue_lang_mondou::program_docs(&compiled.program);
        let hashes = blue_lang_mondou::def_hash::hash_program_documented(&compiled.lowered, &|i| {
            docs.get(&i).cloned()
        });
        let forms = compiled
            .erased
            .iter()
            .enumerate()
            .map(|(top_level, form)| {
                let sexp = form.to_sexp();
                let tree = blue_lang_proc::trace::form_to_json(
                    &tatara_lisp::Spanned::from_sexp_synthetic(&sexp),
                );
                let back = blue_lang_proc::trace::form_from_json(&tree).map(|f| f.to_sexp());
                if back.as_ref() != Ok(&sexp) {
                    return Err(BundleError::Codec { top_level });
                }
                Ok(Form {
                    def: hashes.at(top_level).map(|d| Def {
                        key: d.key.clone(),
                        hash: d.hash.to_string(),
                    }),
                    tree,
                })
            })
            .collect::<Result<_, _>>()?;
        Ok(Self {
            format: FORMAT,
            blue: BLUE_VERSION.to_string(),
            name: name.to_string(),
            main: compiled.main.clone(),
            policy,
            forms,
        })
    }

    /// The hold the payload's policy states ([`hold_of`]).
    ///
    /// # Errors
    ///
    /// As [`hold_of`].
    pub fn hold(&self) -> Result<Hold, Refusal> {
        hold_of(self.policy.as_ref())
    }

    /// The forms the evaluator runs.
    ///
    /// # Errors
    ///
    /// [`Refusal::Form`] naming the first tree that does not decode.
    pub fn trees(&self) -> Result<Vec<tatara_lisp::Spanned>, Refusal> {
        self.forms
            .iter()
            .enumerate()
            .map(|(top_level, f)| {
                blue_lang_proc::trace::form_from_json(&f.tree)
                    .map_err(|why| Refusal::Form { top_level, why })
            })
            .collect()
    }
}

/// The hold a policy states: its ceiling as the frame, its providers bound.
/// `None` is the pure frame: every pure capability and no host effect, never
/// the ambient run `blue run` gives a project that declares nothing.
///
/// # Errors
///
/// [`Refusal::Policy`] for a ceiling label that names no host capability, or
/// a provider filed under another capability's label.
pub fn hold_of(policy: Option<&CapabilityRecord>) -> Result<Hold, Refusal> {
    let Some(record) = policy else {
        return Ok(Hold::from(blue_lang_runtime::session::pure_frame()));
    };
    let reach = reach_of(record.ceiling.as_deref()).map_err(Refusal::Policy)?;
    let mut provisions = Provisions::default();
    for (label, provided) in &record.provided {
        let cap = provided.provision.capability();
        if cap.label() != label {
            return Err(Refusal::Policy(format!(
                "files a {} provider under `{label}`",
                cap.label()
            )));
        }
        let provision = provided;
        provisions
            .add(provision.clone())
            .map_err(|e| Refusal::Policy(format!("provider `{label}`: {e:?}")))?;
    }
    Ok(Hold {
        frame: Waku {
            reach,
            when: When::Anytime,
            place: Where::Process,
        },
        provisions,
    })
}

/// The payload as bytes: its JSON body, then the seal ([`TRAILER`]).
/// Appending these bytes to a runner makes the appliance.
///
/// # Errors
///
/// A payload that does not serialize.
pub fn seal(payload: &Payload) -> Result<Vec<u8>, serde_json::Error> {
    let mut out = serde_json::to_vec(payload)?;
    let digest = digest_of(&out);
    let len = out.len() as u64;
    out.extend_from_slice(&digest);
    out.extend_from_slice(&len.to_le_bytes());
    out.extend_from_slice(&MAGIC);
    Ok(out)
}

/// The appliance: `runner`'s bytes, then `payload` sealed.
///
/// # Errors
///
/// As [`seal`].
pub fn appended(mut runner: Vec<u8>, payload: &Payload) -> Result<Vec<u8>, serde_json::Error> {
    runner.extend(seal(payload)?);
    Ok(runner)
}

fn digest_of(body: &[u8]) -> [u8; DIGEST] {
    let mut h = blake3::Hasher::new_derive_key(DOMAIN);
    h.update(body);
    *h.finalize().as_bytes()
}

/// The sealed payload at the end of `file`, verified against its digest and
/// read as this blue's format.
///
/// # Errors
///
/// A [`Refusal`]: no seal, a length past the file, a digest that does not
/// match, a body that does not read, or another format or blue.
pub fn open<F: Read + Seek>(file: &mut F) -> Result<Payload, Refusal> {
    let size = file.seek(SeekFrom::End(0))?;
    let trailer_len = TRAILER as u64;
    if size < trailer_len {
        return Err(Refusal::Missing);
    }
    let room = size - trailer_len;
    file.seek(SeekFrom::Start(room))?;
    let mut trailer = [0u8; TRAILER];
    file.read_exact(&mut trailer)?;
    let (digest, rest) = trailer.split_at(DIGEST);
    let (len, magic) = rest.split_at(8);
    if magic != MAGIC {
        return Err(Refusal::Missing);
    }
    let len = u64::from_le_bytes(len.try_into().map_err(|_| Refusal::Missing)?);
    if len > room {
        return Err(Refusal::Length { len, room });
    }
    file.seek(SeekFrom::Start(room - len))?;
    let mut body = vec![0u8; usize::try_from(len).map_err(|_| Refusal::Length { len, room })?];
    file.read_exact(&mut body)?;
    if digest_of(&body) != digest {
        return Err(Refusal::Tampered);
    }
    let value: serde_json::Value =
        serde_json::from_slice(&body).map_err(|e| Refusal::Unreadable(e.to_string()))?;
    let format = value.get("format").and_then(serde_json::Value::as_u64);
    if format != Some(u64::from(FORMAT)) {
        return Err(Refusal::Format { found: format });
    }
    match value.get("blue").and_then(serde_json::Value::as_str) {
        Some(BLUE_VERSION) => {}
        other => {
            return Err(Refusal::Version {
                payload: other.unwrap_or("(none)").to_string(),
            })
        }
    }
    serde_json::from_value(value).map_err(|e| Refusal::Unreadable(e.to_string()))
}

/// The payload sealed onto the running executable.
///
/// # Errors
///
/// As [`open`], and an executable that cannot be read.
pub fn open_self() -> Result<Payload, Refusal> {
    let mut file = std::fs::File::open("/proc/self/exe")
        .or_else(|_| std::env::current_exe().and_then(std::fs::File::open))?;
    open(&mut file)
}

/// Run `payload` held to its policy. The program's arguments are the host's
/// to set (`blue_lang_runtime::sys::set_program_args`), and reading them
/// needs the environment capability like any other host name.
///
/// # Errors
///
/// [`Failure::Refused`] for a policy or a form that does not read, and
/// [`Failure::Ran`] for the run's own error.
pub fn run(payload: &Payload) -> Result<tatara_lisp_eval::Value, Failure> {
    let hold = payload.hold()?;
    let trees = payload.trees()?;
    Ok(blue_lang_runtime::pipeline::run_compiled(
        &trees,
        payload.main.as_deref(),
        &hold,
        WHO,
    )?)
}

/// `entry` compiled into a payload. The nearest Bluefile at or above it is
/// its project, whatever its name, as the nix engine reads a project's root:
/// the `Bluefile.lock` beside it must be fresh, its capability record becomes
/// the policy, and a host name the entry writes outside it refuses the
/// bundle. With no Bluefile above it, or no record in the lock, the payload
/// runs pure.
///
/// # Errors
///
/// A [`BundleError`]: the source, a stale or missing lock, the compile, or
/// the encoding.
pub fn bundle(
    entry: &Path,
    surface: Option<&blue_lang_syntax::yakugo::Yakugo>,
) -> Result<Payload, BundleError> {
    let text = crate::canonical::read_source(entry, crate::canonical::Policy::from_env())?;
    let dir = entry
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let dir = dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf());
    let manifest = dir
        .ancestors()
        .find(|at| at.join(crate::MANIFEST_FILE).is_file());
    let (name, policy) = match manifest {
        Some(project) => {
            let shown = project.display().to_string();
            if let crate::lock::Freshness::Stale { reason } = crate::lock::confirm_dir(&project)? {
                return Err(BundleError::Stale {
                    project: shown,
                    reason,
                });
            }
            let lock: crate::lock::Lock =
                std::fs::read_to_string(project.join(crate::lock::LOCK_FILE))
                    .map_err(|e| e.to_string())
                    .and_then(|t| serde_json::from_str(&t).map_err(|e| e.to_string()))
                    .map_err(|why| BundleError::LockText {
                        project: shown,
                        why,
                    })?;
            (lock.manifest.name, lock.capabilities)
        }
        None => (
            entry
                .file_stem()
                .map_or_else(|| "blue".to_string(), |s| s.to_string_lossy().into_owned()),
            None,
        ),
    };
    let hold = hold_of(policy.as_ref())?;
    let loader = crate::load_path::LoadPath::for_entry(entry);
    let compiled = blue_lang_runtime::pipeline::compile(
        blue_lang_runtime::uses::Entry {
            path: Some(entry),
            text: &text,
        },
        &loader,
        surface,
        Some(&hold),
    )?;
    Payload::of(&name, &compiled, policy)
}

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_waku::Capability;
    use std::io::Cursor;

    fn compiled(src: &str) -> Compiled {
        blue_lang_runtime::pipeline::compile(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            None,
        )
        .expect("compiles")
    }

    fn sample() -> Payload {
        Payload::of(
            "sample",
            &compiled("def twice(x)\n  x * 2\nend\n\nwrite_stdout(\"#{twice(21)}\\n\")\n"),
            None,
        )
        .expect("encodes")
    }

    #[test]
    fn a_sealed_payload_opens_to_itself_after_any_prefix() {
        let payload = sample();
        let mut exe = b"\x7fELF any runner bytes".to_vec();
        exe.extend(seal(&payload).unwrap());
        assert_eq!(open(&mut Cursor::new(exe)).unwrap(), payload);
    }

    #[test]
    fn each_definition_carries_its_def_hash() {
        let payload = sample();
        let def = payload.forms[0]
            .def
            .as_ref()
            .expect("twice is a definition");
        assert_eq!(def.key, "%root/twice");
        assert!(
            def.hash.starts_with("b3:") && def.hash.len() == 67,
            "{}",
            def.hash
        );
        assert!(payload.forms[1].def.is_none(), "a call defines nothing");
    }

    #[test]
    fn a_changed_byte_anywhere_in_the_body_is_refused() {
        let sealed = seal(&sample()).unwrap();
        let body = sealed.len() - TRAILER;
        for at in [0, body / 2, body - 1] {
            let mut bent = sealed.clone();
            bent[at] ^= 1;
            assert!(
                matches!(open(&mut Cursor::new(bent)), Err(Refusal::Tampered)),
                "byte {at}"
            );
        }
    }

    #[test]
    fn no_seal_and_a_length_past_the_file_are_refused() {
        assert!(matches!(
            open(&mut Cursor::new(b"a runner and nothing else".to_vec())),
            Err(Refusal::Missing)
        ));
        assert!(matches!(
            open(&mut Cursor::new(Vec::new())),
            Err(Refusal::Missing)
        ));
        let mut sealed = seal(&sample()).unwrap();
        let at = sealed.len() - 16;
        sealed[at..at + 8].copy_from_slice(&u64::MAX.to_le_bytes());
        assert!(matches!(
            open(&mut Cursor::new(sealed)),
            Err(Refusal::Length { .. })
        ));
    }

    #[test]
    fn another_blue_or_format_is_refused_by_name() {
        let mut other = sample();
        other.blue = "0.0.0".into();
        assert!(matches!(
            open(&mut Cursor::new(seal(&other).unwrap())),
            Err(Refusal::Version { .. })
        ));
        other.blue = BLUE_VERSION.into();
        other.format = FORMAT + 1;
        assert!(matches!(
            open(&mut Cursor::new(seal(&other).unwrap())),
            Err(Refusal::Format { found: Some(_) })
        ));
    }

    #[test]
    fn no_policy_holds_to_the_pure_frame_and_withholds_every_host_name() {
        let hold = hold_of(None).unwrap();
        for cap in Capability::host_effects() {
            assert!(!hold.frame.reach.grants(cap), "{cap:?}");
        }
        let withheld: Vec<&str> = hold.withheld_host_names().iter().map(|(n, _)| *n).collect();
        for name in [
            "read_file",
            "now_ms",
            "exec_capture",
            "getenv",
            "http_request",
            "random_bytes",
        ] {
            assert!(withheld.contains(&name), "{name}");
        }
    }

    #[test]
    fn a_record_grants_its_ceiling_and_its_providers_and_nothing_else() {
        let record: CapabilityRecord = serde_json::from_value(serde_json::json!({
            "ceiling": ["filesystem"],
            "provided": {"clock": {"provider": "deterministic-stepped", "at_ms": 5, "step_ms": 1}},
            "floor": ["clock", "filesystem"],
            "packages": {"app": ["clock", "filesystem"]}
        }))
        .unwrap();
        let hold = hold_of(Some(&record)).unwrap();
        let withheld: Vec<&str> = hold.withheld_host_names().iter().map(|(n, _)| *n).collect();
        assert!(!withheld.contains(&"read_file"));
        assert!(
            !withheld.contains(&"now_ms"),
            "the provider stands in for the clock"
        );
        assert!(withheld.contains(&"http_request"));
        assert!(withheld.contains(&"getenv"));

        let mut bad = record.clone();
        bad.ceiling = Some(vec!["telepathy".into()]);
        assert!(matches!(hold_of(Some(&bad)), Err(Refusal::Policy(_))));
    }

    #[test]
    fn a_policy_less_payload_breaches_at_its_first_host_call() {
        let payload = Payload::of(
            "reach",
            &compiled("write_stdout(\"before\\n\")\nread_file(\"/etc/hosts\")\n"),
            None,
        )
        .unwrap();
        let e = run(&payload).expect_err("a pure payload cannot read a file");
        assert_eq!(e.exit_status(), blue_lang_runtime::BREACH_EXIT, "{e}");
        assert!(e.to_string().contains(WHO), "{e}");
    }
}
