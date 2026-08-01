//! Build inputs — the macro phase's **only** channel to the outside world.
//!
//! Closes `theory/BLUE.md` §VI OPEN #6, which the spec names as gating "blue's
//! whole 'stronger than Ruby's metaprogramming' claim": tenet 2 installs a
//! `NoLoader`, so a macro could read *nothing*, which also meant it could not
//! generate code from a schema — the thing that would make blue's
//! metaprogramming exceed Ruby's rather than merely match it.
//!
//! ```text
//! definput("schema", "b3:1d9e…")     # the DECLARATION: name + content hash
//!
//! defmacro columns()
//!   quote
//!     unquote(input("schema"))       # the macro receives the BYTES
//!   end
//! end
//! ```
//!
//! # Why this is stronger than what Ruby or Elixir can express
//!
//! Both have compile-time/load-time I/O, and in both it is **ambient
//! authority**:
//!
//! - Ruby runs arbitrary code at load time with the whole filesystem open. A
//!   gem's metaprogramming can read anything the process can read.
//! - Elixir's `@external_resource` plus `File.read!/1` is the same authority,
//!   and its recompilation tracking keys on **mtime**, not content — so the
//!   same bytes at a new timestamp force a rebuild, and different bytes at the
//!   same timestamp do not.
//!
//! blue's channel is **capability-restricted and content-addressed**:
//!
//! 1. There is no path anywhere in the API. A macro names an *input*, never a
//!    file, so it cannot reach something the author did not declare — and the
//!    restriction is the absence of a primitive, not a policy consulted at call
//!    time.
//! 2. Bytes are verified against the declared BLAKE3 hash **before** anything
//!    can read them. Wrong bytes are refused, not silently used.
//! 3. Because the declaration *is* the hash, "did the input change" is a
//!    content question. mtime cannot make it lie in either direction.
//!
//! # What is deliberately still impossible
//!
//! A macro cannot enumerate inputs, cannot read a path, cannot fetch a URL, and
//! cannot see an input the program did not declare. Adding any of those would
//! return the ambient authority this exists to remove.

use std::collections::BTreeMap;

use tatara_lisp::{Atom, Sexp};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{Interpreter, Value};

/// The hash prefix a declaration must carry. Explicit so the algorithm is part
/// of the contract rather than an assumption — a bare hex string would silently
/// become un-migratable the day a second algorithm is wanted.
pub const HASH_PREFIX: &str = "b3:";

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum InputError {
    #[error("input `{name}`: expected hash `{expected}`, but the supplied bytes hash to `{actual}`")]
    HashMismatch {
        name: String,
        expected: String,
        actual: String,
    },
    #[error("input `{name}`: hash must start with `{HASH_PREFIX}` (got `{got}`)")]
    UnknownAlgorithm { name: String, got: String },
    #[error("input `{name}` is declared but no bytes were supplied for it")]
    Unsupplied { name: String },
    #[error("`{0}` was supplied but never declared — declare it with definput before use")]
    Undeclared(String),
}

/// One declared input: a name bound to a content hash.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Declaration {
    pub name: String,
    /// `b3:<hex>`.
    pub hash: String,
}

/// The verified inputs a macro phase may read.
///
/// Construction is the verification: an `Inputs` cannot hold bytes that do not
/// match their declared hash, because [`Inputs::bind`] is the only way in and it
/// checks. That is why the reading primitive has no error path for a bad hash —
/// the state is unrepresentable rather than guarded against.
#[derive(Clone, Debug, Default)]
pub struct Inputs {
    verified: BTreeMap<String, Vec<u8>>,
}

impl Inputs {
    pub fn new() -> Self {
        Self::default()
    }

    /// The BLAKE3 content hash of `bytes`, in declaration form.
    #[must_use]
    pub fn hash_of(bytes: &[u8]) -> String {
        let mut out = String::with_capacity(HASH_PREFIX.len() + 64);
        out.push_str(HASH_PREFIX);
        out.push_str(&blake3::hash(bytes).to_hex());
        out
    }

    /// Bind bytes to a declaration, verifying the hash.
    ///
    /// **Refuses on mismatch.** Accepting the bytes and warning would defeat the
    /// point: the declaration is a claim about *which* bytes, and honouring a
    /// different set makes the build irreproducible in exactly the way content
    /// addressing exists to prevent.
    pub fn bind(&mut self, decl: &Declaration, bytes: Vec<u8>) -> Result<(), InputError> {
        if !decl.hash.starts_with(HASH_PREFIX) {
            return Err(InputError::UnknownAlgorithm {
                name: decl.name.clone(),
                got: decl.hash.clone(),
            });
        }
        let actual = Self::hash_of(&bytes);
        if actual != decl.hash {
            return Err(InputError::HashMismatch {
                name: decl.name.clone(),
                expected: decl.hash.clone(),
                actual,
            });
        }
        self.verified.insert(decl.name.clone(), bytes);
        Ok(())
    }

    pub fn get(&self, name: &str) -> Option<&[u8]> {
        self.verified.get(name).map(Vec::as_slice)
    }

    pub fn len(&self) -> usize {
        self.verified.len()
    }

    pub fn is_empty(&self) -> bool {
        self.verified.is_empty()
    }
}

/// Collect `definput("name", "b3:…")` declarations from a program.
///
/// Scanned rather than evaluated in order, so a `definput` may appear anywhere
/// in the file. Evaluating them in sequence would make a macro's access depend
/// on whether its declaration happened to be written above it — a positional
/// rule nobody would remember and the compiler would not enforce.
#[must_use]
pub fn declarations(forms: &[Sexp]) -> Vec<Declaration> {
    forms.iter().filter_map(as_declaration).collect()
}

fn as_declaration(form: &Sexp) -> Option<Declaration> {
    let Sexp::List(items) = form else { return None };
    if items.len() != 3 {
        return None;
    }
    match (&items[0], &items[1], &items[2]) {
        (
            Sexp::Atom(Atom::Symbol(head)),
            Sexp::Atom(Atom::Str(name)),
            Sexp::Atom(Atom::Str(hash)),
        ) if &**head == "definput" => Some(Declaration {
            name: name.to_string(),
            hash: hash.to_string(),
        }),
        _ => None,
    }
}

/// Install the reading primitives against `inputs`.
///
/// Two, and no more:
///
/// - `input(name)` — the declared bytes as a string.
/// - `definput(name, hash)` — a no-op at run time. The declaration is consumed
///   by [`declarations`] *before* evaluation; this exists so the form is not an
///   unbound symbol, and returns the name so it reads as a value.
///
/// There is deliberately no `inputs()`, no `input_path()`, and no
/// `read_file()`. Each would hand back the ambient authority this removes.
pub fn install_input_primitives<H: 'static>(interp: &mut Interpreter<H>, inputs: Inputs) {
    let table = std::sync::Arc::new(inputs);

    let read = table.clone();
    interp.register_fn(
        "input",
        Arity::Exact(1),
        move |args: &[Value], _h: &mut H, span| {
            let name = match &args[0] {
                Value::Str(s) => s.to_string(),
                other => {
                    return Err(tatara_lisp_eval::EvalError::type_mismatch(
                        "an input name (string)",
                        other.type_name(),
                        span,
                    )
                    .into())
                }
            };
            match read.get(&name) {
                // Lossy is correct here: an input is bytes, and a macro that
                // wants to *read* it wants text. A schema with invalid UTF-8 is
                // a schema the macro could not have parsed anyway.
                Some(bytes) => Ok(Value::Str(String::from_utf8_lossy(bytes).into())),
                // NOT a file read, and not nil. An undeclared name is a program
                // error: silently returning nil is how a macro generates an
                // empty table and nobody notices until runtime.
                None => Err(tatara_lisp_eval::EvalError::native_fn(
                    "input",
                    "no input named `".to_string()
                        + &name
                        + "` is declared. A macro may only read inputs the program \
                           declared with definput — there is no path-based read.",
                    span,
                )
                .into()),
            }
        },
    );

    interp.register_fn(
        "definput",
        Arity::Exact(2),
        move |args: &[Value], _h: &mut H, _span| Ok(args[0].clone()),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    const BYTES: &[u8] = b"id,name,email\n";

    fn decl(name: &str, hash: &str) -> Declaration {
        Declaration {
            name: name.to_string(),
            hash: hash.to_string(),
        }
    }

    #[test]
    fn correct_bytes_bind() {
        let mut i = Inputs::new();
        i.bind(&decl("schema", &Inputs::hash_of(BYTES)), BYTES.to_vec())
            .expect("hash matches");
        assert_eq!(i.get("schema"), Some(BYTES));
    }

    /// **Wrong bytes are refused, not warned about.** The declaration is a claim
    /// about *which* bytes; honouring a different set makes the build
    /// irreproducible in exactly the way content addressing prevents.
    #[test]
    fn bytes_that_do_not_match_the_declared_hash_are_refused() {
        let mut i = Inputs::new();
        let err = i
            .bind(&decl("schema", &Inputs::hash_of(BYTES)), b"tampered".to_vec())
            .expect_err("must refuse");
        assert!(matches!(err, InputError::HashMismatch { .. }), "{err}");
        assert_eq!(i.get("schema"), None, "and nothing may be bound");
    }

    /// The error names both hashes, so the author can tell "I edited the file"
    /// from "I pasted the wrong hash".
    #[test]
    fn a_mismatch_names_both_hashes() {
        let mut i = Inputs::new();
        let expected = Inputs::hash_of(BYTES);
        let err = i
            .bind(&decl("schema", &expected), b"other".to_vec())
            .expect_err("refuse");
        let msg = err.to_string();
        assert!(msg.contains(&expected), "must name the expected: {msg}");
        assert!(
            msg.contains(&Inputs::hash_of(b"other")),
            "and the actual: {msg}"
        );
    }

    /// The algorithm is part of the contract. A bare hex string is refused
    /// rather than assumed to be BLAKE3.
    #[test]
    fn a_hash_without_the_algorithm_prefix_is_refused() {
        let mut i = Inputs::new();
        let bare = blake3::hash(BYTES).to_hex().to_string();
        let err = i.bind(&decl("schema", &bare), BYTES.to_vec()).expect_err("refuse");
        assert!(matches!(err, InputError::UnknownAlgorithm { .. }), "{err}");
    }

    /// Hashing is content-only — the same bytes always hash the same, and one
    /// changed byte changes it. This is what mtime cannot do.
    #[test]
    fn the_hash_is_a_function_of_content_alone() {
        assert_eq!(Inputs::hash_of(BYTES), Inputs::hash_of(&BYTES.to_vec()));
        assert_ne!(Inputs::hash_of(BYTES), Inputs::hash_of(b"id,name,emaiL\n"));
        assert!(Inputs::hash_of(BYTES).starts_with(HASH_PREFIX));
    }

    // ---- declarations ---------------------------------------------------

    #[test]
    fn declarations_are_scanned_from_anywhere_in_the_program() {
        let src = format!(
            "1 + 1\ndefinput(\"schema\", \"{}\")\n2 + 2",
            Inputs::hash_of(BYTES)
        );
        let forms = blue_lang_syntax::parse_program(&src).expect("parse");
        let decls = declarations(&forms);
        assert_eq!(decls.len(), 1);
        assert_eq!(decls[0].name, "schema");
    }

    /// Position must not matter. Evaluating declarations in order would make a
    /// macro's access depend on whether its `definput` was written above it.
    #[test]
    fn a_declaration_below_its_use_is_still_found() {
        let src = format!(
            "defmacro m()\n  quote\n    input(\"late\")\n  end\nend\ndefinput(\"late\", \"{}\")",
            Inputs::hash_of(BYTES)
        );
        let forms = blue_lang_syntax::parse_program(&src).expect("parse");
        assert_eq!(declarations(&forms).len(), 1);
    }

    #[test]
    fn a_program_with_no_declarations_yields_none() {
        let forms = blue_lang_syntax::parse_program("1 + 1").expect("parse");
        assert!(declarations(&forms).is_empty());
    }
}
