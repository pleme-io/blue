//! **blue compiles only canonical source, judged by the blue that owns it,
//! and no compile door writes a file.**
//!
//! The operator's rule (2026-09-27): *"I want bluelang to not compile anything
//! not formatted correctly"*. Refined 2026-10-23 (`docs/COMPOUNDING.md`): a
//! file's form is judged by its producer's blue, and a test never writes. So
//! a compile door holds the ENTRY to the rule, and a package file a `use(...)`
//! loads through [`LoadPath`] is compiled as written:
//!
//! | the file | what happens |
//! |---|---|
//! | the entry, canonical | compiled as it is |
//! | the entry, not canonical | **refused**: `blue: <path> is not formatted (<rules>); run blue fmt --write <path>`. Nothing is written |
//! | the entry, the formatter refuses it | **refused**, naming the line |
//! | a loaded dependency | compiled as written: its layout is its producer's, held by the producer's own `blue fmt --check` under the blue it pins |
//!
//! Two switches ([`blue_lang_check::evolution`]): `BLUE_FORM=all` judges every
//! dependency's layout too (the importer judges, as before 2026-10-23) and
//! `BLUE_FORM=none` judges no file's; `BLUE_LAYOUT=rewrite` restores
//! formatting a writable file in place before compiling it. A store path is
//! never written under either.
//!
//! **One place.** The loader calls [`admit_dependency`] for every package file
//! and the CLI calls [`read_source`] for the entry of every door that
//! compiles, so no door can forget. The LSP does not come through here: it
//! compiles for analysis, on a buffer that is still being typed.
//!
//! **One surface.** The formatter renders blue's English surface. A program the
//! CLI parses in a `yakugo` surface is not admitted here — formatting it would
//! translate it — so the entry of `blue run` under `BLUE_LANG` is compiled as
//! written.
//!
//! [`LoadPath`]: crate::load_path::LoadPath

use std::io::Write;
use std::path::{Path, PathBuf};

/// Why a file was not compiled. The CLI prints each as `blue: <message>`.
#[derive(Debug, thiserror::Error)]
pub enum Refusal {
    /// Not canonical, and blue may not rewrite it.
    #[error("{path} is not formatted; run blue fmt --write {path}{why}")]
    NotFormatted { path: String, why: String },
    /// The formatter itself refused the file, so there is no canonical form to
    /// compile.
    #[error("{path} cannot be formatted, so it is not compiled: {reason}")]
    Unformattable { path: String, reason: String },
    /// The file could not be read at all.
    #[error("cannot read {path}: {source}")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },
}

/// Is `path` somewhere blue must never write — the nix store?
fn in_store(path: &Path) -> bool {
    path.starts_with("/nix/store")
}

/// The two switches a compile door reads, together.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Policy {
    pub form: blue_lang_check::evolution::FormJudge,
    pub layout: blue_lang_check::evolution::Layout,
}

impl Policy {
    /// `BLUE_FORM`, and `BLUE_LAYOUT` over the door's own `layout`; a value
    /// outside its set is the default here, and refused by the CLI before any
    /// door runs.
    #[must_use]
    pub fn for_door(layout: blue_lang_check::evolution::Layout) -> Self {
        Self {
            form: blue_lang_check::evolution::FormJudge::from_env().unwrap_or_default(),
            layout: blue_lang_check::evolution::Layout::for_door(layout),
        }
    }

    /// The policy of a door that never writes: `blue test`, `blue check`.
    #[must_use]
    pub fn from_env() -> Self {
        Self::for_door(blue_lang_check::evolution::Layout::Judge)
    }

    /// The policy of `blue run`, which formats its entry in place.
    #[must_use]
    pub fn run() -> Self {
        Self::for_door(blue_lang_check::evolution::Layout::Rewrite)
    }
}

/// The source blue compiles for the ENTRY at `path` whose content is `text`,
/// under `blue run`'s policy.
///
/// # Errors
///
/// A [`Refusal`] when the file is not canonical, or cannot be formatted.
pub fn admit(path: &Path, text: String) -> Result<String, Refusal> {
    admit_with(path, text, Policy::run(), true)
}

/// The source blue compiles for a package file a `use(...)` loads.
///
/// # Errors
///
/// As [`admit`], when `BLUE_FORM=all` judges dependencies.
pub fn admit_dependency(path: &Path, text: String) -> Result<String, Refusal> {
    admit_with(path, text, Policy::from_env(), false)
}

/// [`admit`] under an explicit `policy`, for the entry or a dependency.
///
/// # Errors
///
/// As [`admit`].
pub fn admit_with(
    path: &Path,
    text: String,
    policy: Policy,
    entry: bool,
) -> Result<String, Refusal> {
    use blue_lang_check::evolution::Layout;
    if !policy.form.judges_layout(entry) {
        return Ok(text);
    }
    let shown = path.display().to_string();
    let formatted =
        blue_lang_runtime::timings::stage(blue_lang_runtime::timings::Stage::Format, || {
            blue_lang_fmt::format_source_lossless(&text)
        })
        .map_err(|e| Refusal::Unformattable {
            path: shown.clone(),
            reason: e.to_string(),
        })?;
    if formatted.trim_end() == text.trim_end() {
        return Ok(text);
    }
    let rules = rules_named(&text);
    if in_store(path) {
        return Err(Refusal::NotFormatted {
            path: shown,
            why: format!("{rules} (it is in the nix store, which is read-only)"),
        });
    }
    if policy.layout == Layout::Judge {
        return Err(Refusal::NotFormatted {
            path: shown,
            why: rules,
        });
    }
    match rewrite(path, &formatted) {
        Ok(()) => {
            eprintln!("blue: formatted {shown}{rules}");
            Ok(formatted)
        }
        Err(e) => Err(Refusal::NotFormatted {
            path: shown,
            why: format!("{rules} (it cannot be rewritten here: {e})"),
        }),
    }
}

#[must_use]
pub fn require(label: &str, text: &str) -> Result<(), Refusal> {
    let formatted =
        blue_lang_fmt::format_source_lossless(text).map_err(|e| Refusal::Unformattable {
            path: label.to_owned(),
            reason: e.to_string(),
        })?;
    if formatted.trim_end() == text.trim_end() {
        return Ok(());
    }
    Err(Refusal::NotFormatted {
        path: label.to_owned(),
        why: rules_named(text),
    })
}

pub fn rules_named(text: &str) -> String {
    let diagnostics = blue_lang_runtime::pipeline::form_diagnostics(text);
    if diagnostics.is_empty() {
        return String::new();
    }
    let mut counts: std::collections::BTreeMap<blue_lang_check::Code, usize> =
        std::collections::BTreeMap::new();
    for d in &diagnostics {
        *counts.entry(d.code).or_default() += 1;
    }
    let first = &diagnostics[0];
    let (line, col) = blue_lang_syntax::Span::line_col(text, first.span.start.min(text.len()));
    let named: Vec<String> = counts
        .iter()
        .map(|(c, n)| {
            let slug = c.rule().slug;
            if *n > 1 {
                format!("{c} {slug} ×{n}")
            } else {
                format!("{c} {slug}")
            }
        })
        .collect();
    format!(
        " ({}; first at {line}:{col}: {})",
        named.join(", "),
        first.message
    )
}

/// Read `path` and write its canonical layout back: the door of an explicit
/// write (`blue check --fix`), so it rewrites whatever the switches say.
///
/// # Errors
///
/// As [`admit`], plus [`Refusal::Read`].
pub fn read_layout(path: &Path) -> Result<String, Refusal> {
    let text = std::fs::read_to_string(path).map_err(|source| Refusal::Read {
        path: path.display().to_string(),
        source,
    })?;
    let write = Policy {
        form: blue_lang_check::evolution::FormJudge::Own,
        layout: blue_lang_check::evolution::Layout::Rewrite,
    };
    admit_with(path, text, write, true)
}

/// # Errors
///
/// As `blue_lang_fmt::format_source_lossless`.
pub fn format_resolved(path: &Path, src: &str) -> Result<String, blue_lang_fmt::FormatError> {
    format_with(&crate::load_path::LoadPath::for_entry(path), path, src)
}

/// # Errors
///
/// As `blue_lang_fmt::format_source_lossless`.
pub fn format_with(
    loader: &dyn blue_lang_runtime::uses::Loader,
    path: &Path,
    src: &str,
) -> Result<String, blue_lang_fmt::FormatError> {
    use blue_lang_runtime::pipeline::{check_entry, Checking};
    let entry = blue_lang_runtime::uses::Entry {
        path: Some(path),
        text: src,
    };
    let tree = check_entry(entry, loader, None, Checking::WithTests)
        .ok()
        .and_then(|checked| checked.canonical_entry(src));
    blue_lang_runtime::timings::stage(blue_lang_runtime::timings::Stage::Format, || match tree {
        Some(tree) => blue_lang_fmt::format_tree_lossless(src, &tree),
        None => blue_lang_fmt::format_source_lossless(src),
    })
}

/// Read `path` and admit it under `policy`: the entry of every CLI door
/// that compiles.
///
/// # Errors
///
/// As [`admit`], plus [`Refusal::Read`].
pub fn read_source(path: &Path, policy: Policy) -> Result<String, Refusal> {
    read_source_with(path, policy)
}

/// [`read_source`] under an explicit `policy`. Under `BLUE_LAYOUT=rewrite`
/// the spellings only resolution knows (a bare nullary call) are written
/// too; under `judge` the check stage reports them instead.
///
/// # Errors
///
/// As [`read_source`].
pub fn read_source_with(path: &Path, policy: Policy) -> Result<String, Refusal> {
    let text = std::fs::read_to_string(path).map_err(|source| Refusal::Read {
        path: path.display().to_string(),
        source,
    })?;
    let text = admit_with(path, text, policy, true)?;
    if in_store(path) || policy.layout != blue_lang_check::evolution::Layout::Rewrite {
        return Ok(text);
    }
    match format_resolved(path, &text) {
        Ok(spelled) if spelled.trim_end() != text.trim_end() => match rewrite(path, &spelled) {
            Ok(()) => {
                eprintln!("blue: formatted {}", path.display());
                Ok(spelled)
            }
            Err(_) => Ok(text),
        },
        _ => Ok(text),
    }
}

/// Replace `path`'s content with `text`, atomically: a sibling temporary file,
/// then a rename, so a reader never sees half a file. The file's permissions
/// carry over. A file without write permission is refused BEFORE the rename,
/// which would otherwise succeed in a writable directory and quietly replace a
/// file its owner had made read-only.
fn rewrite(path: &Path, text: &str) -> std::io::Result<()> {
    let meta = std::fs::metadata(path)?;
    if meta.permissions().readonly() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "the file is read-only",
        ));
    }
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let tmp: PathBuf = dir.join(format!(".{name}.blue-fmt.{}", std::process::id()));
    let result = (|| {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(text.as_bytes())?;
        f.sync_all()?;
        std::fs::set_permissions(&tmp, meta.permissions())?;
        std::fs::rename(&tmp, path)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str, text: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("blue-canonical-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("mkdir");
        let p = dir.join(format!("{name}.b"));
        std::fs::write(&p, text).expect("write");
        p
    }

    #[test]
    fn a_canonical_file_is_compiled_as_written() {
        let p = scratch("clean", "x = 1 + 2\n");
        assert_eq!(read_source(&p, REWRITE).expect("admitted"), "x = 1 + 2\n");
    }

    const REWRITE: Policy = Policy {
        form: blue_lang_check::evolution::FormJudge::Own,
        layout: blue_lang_check::evolution::Layout::Rewrite,
    };

    #[test]
    fn a_writable_messy_entry_is_refused_and_never_written() {
        let p = scratch("messy-judged", "x   =   1+2\n");
        let err = read_source_with(&p, Policy::default()).expect_err("refused");
        assert!(err.to_string().contains("run blue fmt --write"), "{err}");
        assert_eq!(std::fs::read_to_string(&p).expect("read"), "x   =   1+2\n");
    }

    #[test]
    fn a_dependency_compiles_as_written_and_is_never_written() {
        let p = scratch("dep-as-written", "x   =   1+2\n");
        let text = std::fs::read_to_string(&p).expect("read");
        assert_eq!(
            admit_with(&p, text.clone(), Policy::default(), false).expect("admitted"),
            text
        );
        assert_eq!(
            admit_with(&p, text.clone(), REWRITE, false).expect("admitted"),
            text
        );
        assert_eq!(std::fs::read_to_string(&p).expect("read"), text);
        let all = Policy {
            form: blue_lang_check::evolution::FormJudge::All,
            ..Policy::default()
        };
        assert!(admit_with(&p, text.clone(), all, false).is_err());
        assert_eq!(std::fs::read_to_string(&p).expect("read"), text);
    }

    #[test]
    fn a_writable_messy_file_is_rewritten_when_rewrite_is_asked_for() {
        let p = scratch("messy", "x   =   1+2\n");
        assert_eq!(
            read_source_with(&p, REWRITE).expect("admitted"),
            "x = 1 + 2\n"
        );
        assert_eq!(std::fs::read_to_string(&p).expect("read"), "x = 1 + 2\n");
    }

    #[test]
    fn a_one_line_block_is_not_canonical_and_compiles_as_an_inline_lambda() {
        let p = scratch("oneline", "y = map(xs, fn(x) x * 2 end)\n");
        assert_eq!(
            read_source_with(&p, REWRITE).expect("admitted"),
            "y = map(xs, (x) -> x * 2)\n"
        );
    }

    #[test]
    fn a_read_only_one_line_block_is_refused() {
        let p = scratch("oneline-ro", "f = fn(x) x end\n");
        let mut perm = std::fs::metadata(&p).expect("meta").permissions();
        perm.set_readonly(true);
        std::fs::set_permissions(&p, perm).expect("chmod");
        assert!(read_source(&p, REWRITE).is_err());
    }

    #[test]
    fn a_read_only_messy_file_is_refused_and_left_alone() {
        let p = scratch("readonly", "x   =   1+2\n");
        let mut perm = std::fs::metadata(&p).expect("meta").permissions();
        perm.set_readonly(true);
        std::fs::set_permissions(&p, perm).expect("chmod");
        let err = read_source(&p, REWRITE).expect_err("refused");
        assert!(
            err.to_string()
                .contains("is not formatted; run blue fmt --write"),
            "{err}"
        );
        assert_eq!(std::fs::read_to_string(&p).expect("read"), "x   =   1+2\n");
    }

    #[test]
    fn a_file_the_formatter_refuses_is_a_compile_error_naming_the_line() {
        let p = scratch("unplaceable", "y = 1\nx = # no line\n  5\n");
        let err = read_source(&p, REWRITE).expect_err("refused");
        let msg = err.to_string();
        assert!(msg.contains("cannot be formatted"), "{msg}");
        assert!(msg.contains("line(s) 2"), "{msg}");
    }

    #[test]
    fn a_store_path_is_never_written() {
        let err = admit_with(
            Path::new("/nix/store/x-pkg/pkg.b"),
            "x   =   1\n".into(),
            REWRITE,
            true,
        )
        .expect_err("refused");
        assert!(err.to_string().contains("nix store"), "{err}");
    }
}
