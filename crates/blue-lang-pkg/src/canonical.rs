//! **blue compiles only canonical source. Source it can write, it formats
//! first.**
//!
//! The operator's rule (2026-09-27): *"I want bluelang to not compile anything
//! not formatted correctly"*, kept transparent. So every `.b` file blue is about
//! to compile — the file named to `blue run` / `blue test` / `blue check`, and
//! every package file a `use(...)` loads through [`LoadPath`] — comes through
//! [`admit`]:
//!
//! | the file | what happens |
//! |---|---|
//! | canonical | compiled as it is |
//! | writable, not canonical | rewritten in place, `blue: formatted <path>` on stderr, the canonical text compiled |
//! | read-only (a `/nix/store` path, or no write permission), not canonical | **refused**: `blue: <path> is not formatted; run blue fmt --write <path>` |
//! | the formatter refuses it (a comment with no line) | **refused**, naming the line — a compile error, not a skipped check |
//!
//! Canonical means what `blue fmt --check` means: equal to
//! `format_source_lossless` up to trailing whitespace. There is no flag to turn
//! this off; there is one formatting and blue only compiles it.
//!
//! **One place.** The loader calls [`admit`] for every package file and the CLI
//! calls [`read_source`] for the entry of every door that compiles, so no door
//! can forget. The LSP does not come through here: it compiles for analysis,
//! on a buffer that is still being typed.
//!
//! **Cost, measured instead of cached** (2026-09-27, this machine): the
//! formatter runs on every file on every compile. `blue fmt --check` over all
//! 49 tracked `.b` files in the repository — 34,214 lines — takes 0.08 s of CPU
//! in a release build (0.67 s in a debug one), so a program that loads a
//! handful of packages pays a few milliseconds. A cache keyed on content
//! hashes would be one more piece of state to go stale for no measurable gain.
//!
//! **One surface.** The formatter renders blue's English surface. A program the
//! CLI parses in a `yakugo` surface is not admitted here — formatting it would
//! translate it — so the entry of `blue run` under `BLUE_LANG` is compiled as
//! written. Packages are always English, and always admitted.
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

/// The source blue compiles for the file at `path` whose content is `text`.
///
/// # Errors
///
/// A [`Refusal`] when the file is not canonical and cannot be rewritten, or
/// cannot be formatted at all.
pub fn admit(path: &Path, text: String) -> Result<String, Refusal> {
    let shown = path.display().to_string();
    let formatted =
        blue_lang_fmt::format_source_lossless(&text).map_err(|e| Refusal::Unformattable {
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

/// # Errors
///
/// As [`admit`], plus [`Refusal::Read`].
pub fn read_layout(path: &Path) -> Result<String, Refusal> {
    let text = std::fs::read_to_string(path).map_err(|source| Refusal::Read {
        path: path.display().to_string(),
        source,
    })?;
    admit(path, text)
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
    match tree {
        Some(tree) => blue_lang_fmt::format_tree_lossless(src, &tree),
        None => blue_lang_fmt::format_source_lossless(src),
    }
}

/// Read `path` and [`admit`] it: the entry of every CLI door that compiles.
///
/// # Errors
///
/// As [`admit`], plus [`Refusal::Read`].
pub fn read_source(path: &Path) -> Result<String, Refusal> {
    let text = read_layout(path)?;
    if in_store(path) {
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
        assert_eq!(read_source(&p).expect("admitted"), "x = 1 + 2\n");
    }

    #[test]
    fn a_writable_messy_file_is_rewritten_and_the_canonical_text_compiled() {
        let p = scratch("messy", "x   =   1+2\n");
        assert_eq!(read_source(&p).expect("admitted"), "x = 1 + 2\n");
        assert_eq!(std::fs::read_to_string(&p).expect("read"), "x = 1 + 2\n");
    }

    #[test]
    fn a_one_line_block_is_not_canonical_and_compiles_as_an_inline_lambda() {
        let p = scratch("oneline", "y = map(xs, fn(x) x * 2 end)\n");
        assert_eq!(
            read_source(&p).expect("admitted"),
            "y = map(xs, (x) -> x * 2)\n"
        );
    }

    #[test]
    fn a_read_only_one_line_block_is_refused() {
        let p = scratch("oneline-ro", "f = fn(x) x end\n");
        let mut perm = std::fs::metadata(&p).expect("meta").permissions();
        perm.set_readonly(true);
        std::fs::set_permissions(&p, perm).expect("chmod");
        assert!(read_source(&p).is_err());
    }

    #[test]
    fn a_read_only_messy_file_is_refused_and_left_alone() {
        let p = scratch("readonly", "x   =   1+2\n");
        let mut perm = std::fs::metadata(&p).expect("meta").permissions();
        perm.set_readonly(true);
        std::fs::set_permissions(&p, perm).expect("chmod");
        let err = read_source(&p).expect_err("refused");
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
        let err = read_source(&p).expect_err("refused");
        let msg = err.to_string();
        assert!(msg.contains("cannot be formatted"), "{msg}");
        assert!(msg.contains("line(s) 2"), "{msg}");
    }

    #[test]
    fn a_store_path_is_never_written() {
        let err =
            admit(Path::new("/nix/store/x-pkg/pkg.b"), "x   =   1\n".into()).expect_err("refused");
        assert!(err.to_string().contains("nix store"), "{err}");
    }
}
