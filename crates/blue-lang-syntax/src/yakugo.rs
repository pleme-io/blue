//! `yakugo` (訳語) — blue's words, in any human language.
//!
//! A *yakugo* is the equivalent term: the word another language uses for the
//! same thing. A pack is a lexicon of them, and applying one lets a program be
//! written in that language and mean exactly what the English-surfaced one
//! means.
//!
//! ```text
//! définir double(n)          def double(n)
//!   n * 2            ≡        n * 2
//! fin                        end
//! ```
//!
//! Both parse to `(define (double n) (* n 2))`. Not "similar output" — the
//! **same** tree, which is the property the tests below assert and the only
//! thing that makes this a translation rather than a dialect.
//!
//! ## Where the rewrite happens, and why it is not the parser
//!
//! Between the lexer and the parser, on the **token stream**.
//!
//! The parser decides keywords in about twenty places — `at_ident("end")`,
//! `expect_ident("end")`, `body(&["when", "else", "end"])`, and one large
//! `match name.as_str()`. Threading a pack through all of them would mean
//! twenty chances to miss one, and a missed site is not a compile error: it is
//! a keyword that silently stops working in every language but English.
//!
//! Rewriting `Ident` tokens before the parser runs means the parser is
//! **completely unchanged** and every site works by construction. It also gets
//! function names for free, because those are `Ident` tokens too — so a pack
//! can translate `map`/`filter` as readily as `def`/`end`, which a
//! keyword-only design could not.
//!
//! ## The honest cost
//!
//! A pack rewrites *any* identifier it has an entry for. Under the French
//! pack, a variable named `fin` becomes `end` and the program breaks — exactly
//! as naming a variable `end` breaks an English-surfaced program. Localizing
//! the surface localizes what counts as reserved; that is inherent, not a
//! defect of this implementation, and it is why a pack should stay small and
//! deliberate rather than translating every name in sight.
//!
//! ## Why a pack is data
//!
//! Each pack is tatara-lisp — `packs/*.lisp` — not Rust. Adding a language is
//! a data file, not a code change, which is the whole reason blue's surface
//! sits on an AST substrate: the manipulation is expressible in the language
//! the manipulation is *about*.

use std::collections::BTreeMap;

use crate::lex::{lex, Token, TokenKind};

/// One language's lexicon: its word for each of blue's words.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Yakugo {
    /// Short tag, e.g. `"fr"`. Also the pack's filename stem.
    pub tag: String,
    /// Human-readable name of the language, in that language.
    pub name: String,
    /// Locale prefixes this pack answers to, e.g. `["fr", "fr-FR"]`.
    pub locales: Vec<String>,
    /// localized word → canonical blue word.
    words: BTreeMap<String, String>,
}

impl Yakugo {
    /// The canonical blue word for `word`, if this pack translates it.
    #[must_use]
    pub fn canon(&self, word: &str) -> Option<&str> {
        self.words.get(word).map(String::as_str)
    }

    /// How many terms this pack translates.
    #[must_use]
    pub fn len(&self) -> usize {
        self.words.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.words.is_empty()
    }

    /// Does this pack answer to `locale` (e.g. `"fr_FR.UTF-8"`)?
    ///
    /// Prefix-matched after normalising `_`→`-` and dropping any `.charset`
    /// suffix, because the same language arrives spelled differently depending
    /// on where it came from: `fr_FR.UTF-8` from a POSIX environment,
    /// `fr-FR` from macOS's `AppleLanguages`.
    #[must_use]
    pub fn answers_to(&self, locale: &str) -> bool {
        let norm = normalize_locale(locale);
        self.locales
            .iter()
            .any(|l| norm == *l || norm.starts_with(&format!("{l}-")))
    }
}

/// `fr_FR.UTF-8` → `fr-fr`.
fn normalize_locale(locale: &str) -> String {
    locale
        .split('.')
        .next()
        .unwrap_or(locale)
        .replace('_', "-")
        .to_lowercase()
}

/// Parse a pack from its tatara-lisp source.
///
/// The format, deliberately flat:
///
/// ```lisp
/// (defyakugo "fr" "français"
///   (locales "fr")
///   (words
///     ("définir" def)
///     ("fin"     end)))
/// ```
///
/// Read with a small hand parser rather than the tatara reader because the
/// shape is fixed and this keeps the crate free of an evaluator dependency —
/// `blue-lang-syntax` is the bottom of the stack and everything above it pays
/// for anything added here.
///
/// # Errors
///
/// Returns a message naming what was expected when the pack is malformed. A
/// pack that half-loads is worse than one that fails: the missing half shows
/// up as a keyword that mysteriously stops working.
pub fn parse_pack(src: &str) -> Result<Yakugo, String> {
    let mut tag = String::new();
    let mut name = String::new();
    let mut locales = Vec::new();
    let mut words = BTreeMap::new();
    let mut in_words = false;

    for (n, raw) in src.lines().enumerate() {
        let line = raw.split(';').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        let at = |what: &str| format!("{what} (line {})", n + 1);

        if let Some(rest) = line.strip_prefix("(defyakugo ") {
            let parts = quoted(rest);
            if parts.len() < 2 {
                return Err(at("defyakugo needs a tag and a name, both quoted"));
            }
            tag = parts[0].clone();
            name = parts[1].clone();
        } else if let Some(rest) = line.strip_prefix("(locales ") {
            locales = quoted(rest);
            if locales.is_empty() {
                return Err(at("locales must list at least one locale tag"));
            }
        } else if line.starts_with("(words") {
            in_words = true;
        } else if in_words && line.starts_with('(') {
            // ("définir" def)
            let localized = quoted(line);
            let canonical: Vec<&str> = line
                .trim_matches(|c| c == '(' || c == ')')
                .split_whitespace()
                .collect();
            let Some(canon) = canonical.last() else {
                return Err(at("a words entry needs a canonical blue word"));
            };
            if localized.len() != 1 {
                return Err(at("a words entry is (\"localized\" canonical)"));
            }
            words.insert(
                localized[0].clone(),
                (*canon).trim_end_matches(')').to_owned(),
            );
        }
    }

    if tag.is_empty() {
        return Err("pack has no (defyakugo …) header".to_owned());
    }
    if words.is_empty() {
        return Err(format!("pack \"{tag}\" translates nothing"));
    }
    if locales.is_empty() {
        locales.push(tag.clone());
    }
    Ok(Yakugo {
        tag,
        name,
        locales,
        words,
    })
}

/// Every double-quoted string in a line, in order.
fn quoted(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut inside = false;
    for c in s.chars() {
        match c {
            '"' if inside => {
                out.push(std::mem::take(&mut cur));
                inside = false;
            }
            '"' => inside = true,
            _ if inside => cur.push(c),
            _ => {}
        }
    }
    out
}

/// The packs compiled into the binary.
///
/// Embedded rather than read from disk so a translated program parses with no
/// filesystem at all — the wasm target has none, and an editor extension
/// should not need a data directory to highlight a French program.
pub const BUILTIN_PACKS: &[(&str, &str)] = &[
    ("ja", include_str!("../packs/ja.lisp")),
    ("fr", include_str!("../packs/fr.lisp")),
    ("es", include_str!("../packs/es.lisp")),
    ("pt", include_str!("../packs/pt.lisp")),
    ("de", include_str!("../packs/de.lisp")),
    ("ru", include_str!("../packs/ru.lisp")),
    ("zh", include_str!("../packs/zh.lisp")),
    ("ar", include_str!("../packs/ar.lisp")),
    ("hi", include_str!("../packs/hi.lisp")),
    ("sw", include_str!("../packs/sw.lisp")),
    // NOT a human language — the generalisation made concrete. A symbolic
    // surface over the SAME structure, so the mechanism cannot be mistaken
    // for translation.
    ("math", include_str!("../packs/math.lisp")),
];

/// Load every builtin pack.
///
/// # Errors
///
/// Returns the first malformed pack's message, naming the pack.
pub fn builtin_packs() -> Result<Vec<Yakugo>, String> {
    BUILTIN_PACKS
        .iter()
        .map(|(tag, src)| parse_pack(src).map_err(|e| format!("pack {tag}: {e}")))
        .collect()
}

/// The pack answering to `locale`, if any.
///
/// # Errors
///
/// Returns a message if a builtin pack is malformed.
pub fn pack_for_locale(locale: &str) -> Result<Option<Yakugo>, String> {
    Ok(builtin_packs()?.into_iter().find(|p| p.answers_to(locale)))
}

/// Rewrite a token stream's identifiers through a pack.
///
/// Only `Ident` tokens are touched, and only those the pack has an entry for —
/// everything else, including every string literal, passes through untouched.
/// A translated program's *strings* are its own data and must not be rewritten.
#[must_use]
pub fn apply(tokens: Vec<Token>, pack: &Yakugo) -> Vec<Token> {
    tokens
        .into_iter()
        .map(|t| match &t.kind {
            TokenKind::Ident(name) => match pack.canon(name) {
                Some(canon) => Token {
                    kind: TokenKind::Ident(canon.to_owned()),
                    span: t.span,
                },
                None => t,
            },
            _ => t,
        })
        .collect()
}

/// Lex `src`, apply `pack`, and hand the canonical token stream back.
///
/// # Errors
///
/// Propagates a lex error unchanged — a pack cannot fix source that does not
/// tokenize, and pretending otherwise would report the wrong problem.
pub fn canonical_tokens(src: &str, pack: &Yakugo) -> Result<Vec<Token>, crate::lex::LexError> {
    Ok(apply(lex(src)?, pack))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pack(tag: &str) -> Yakugo {
        let (_, src) = BUILTIN_PACKS
            .iter()
            .find(|(t, _)| *t == tag)
            .unwrap_or_else(|| panic!("no builtin pack {tag}"));
        parse_pack(src).unwrap_or_else(|e| panic!("pack {tag}: {e}"))
    }

    #[test]
    fn every_builtin_pack_loads() {
        let packs = builtin_packs().expect("all builtin packs must parse");
        assert_eq!(
            packs.len(),
            BUILTIN_PACKS.len(),
            "a pack was dropped during loading"
        );
        for p in &packs {
            assert!(
                p.len() >= 15,
                "pack {} translates only {} terms — a pack that omits a \
                 structural keyword leaves that keyword English-only, which is \
                 a half-translated surface rather than a language",
                p.tag,
                p.len()
            );
        }
    }

    /// The property that makes this a translation and not a dialect.
    #[test]
    fn every_language_produces_the_identical_ast() {
        // The same function, written in each language, must parse to one tree.
        let english = crate::parse_program("def double(n)\n  n * 2\nend\ndouble(21)")
            .expect("english must parse");

        for (tag, _) in BUILTIN_PACKS {
            let p = pack(tag);
            let src = translate("def double(n)\n  n * 2\nend\ndouble(21)", &p);
            let got = crate::parse_program_in(&src, &p)
                .unwrap_or_else(|e| panic!("{tag}: {src:?} failed to parse: {e}"));
            assert_eq!(
                format!("{got:?}"),
                format!("{english:?}"),
                "{tag} produced a DIFFERENT tree — the translation changed the \
                 program's meaning, which is the one thing it must never do.\n\
                 source was:\n{src}"
            );
        }
    }

    /// Render canonical blue into a pack's language, for the test above.
    fn translate(src: &str, pack: &Yakugo) -> String {
        let mut out = src.to_owned();
        // Longest canonical word first, so `unquote_splice` is not eaten by
        // `unquote`.
        let mut pairs: Vec<(&String, &String)> = pack.words.iter().map(|(l, c)| (c, l)).collect();
        pairs.sort_by_key(|(c, _)| std::cmp::Reverse(c.len()));
        for (canon, localized) in pairs {
            out = replace_word(&out, canon, localized);
        }
        out
    }

    /// Whole-word replacement — `end` must not match inside `append`.
    fn replace_word(hay: &str, needle: &str, with: &str) -> String {
        let mut out = String::new();
        let mut rest = hay;
        while let Some(i) = rest.find(needle) {
            let before_ok = i == 0
                || !rest[..i]
                    .chars()
                    .next_back()
                    .is_some_and(|c| c.is_alphanumeric() || c == '_');
            let after = &rest[i + needle.len()..];
            let after_ok = !after
                .chars()
                .next()
                .is_some_and(|c| c.is_alphanumeric() || c == '_');
            out.push_str(&rest[..i]);
            if before_ok && after_ok {
                out.push_str(with);
            } else {
                out.push_str(needle);
            }
            rest = after;
        }
        out.push_str(rest);
        out
    }

    #[test]
    fn a_pack_does_not_rewrite_string_literals() {
        // A French program's strings are its data. If `apply` touched them, a
        // string containing a keyword would silently change.
        let p = pack("fr");
        let fin = p
            .words
            .iter()
            .find(|(_, c)| c.as_str() == "end")
            .map(|(l, _)| l.clone())
            .expect("fr must translate end");
        let src = format!("def f()\n  \"{fin}\"\nend");
        let canonical = crate::parse_program(&src.replace("def", "def")).is_ok();
        assert!(canonical, "setup: the program must parse");
        let toks = canonical_tokens(&src, &p).expect("lex");
        let strings: Vec<_> = toks
            .iter()
            .filter_map(|t| match &t.kind {
                TokenKind::Str(s) => Some(s.clone()),
                _ => None,
            })
            .collect();
        assert!(
            strings.contains(&fin),
            "the string literal {fin:?} was rewritten by the pack; only Ident \
             tokens may be translated: {strings:?}"
        );
    }

    #[test]
    fn locales_match_across_spelling_conventions() {
        let p = pack("fr");
        // POSIX, macOS and bare forms all arrive in practice.
        assert!(p.answers_to("fr_FR.UTF-8"), "POSIX form must match");
        assert!(p.answers_to("fr-CA"), "macOS regional form must match");
        assert!(p.answers_to("fr"), "bare tag must match");
        assert!(
            !p.answers_to("de_DE.UTF-8"),
            "another language must NOT match"
        );
        // The prefix must be a real language boundary, not a substring.
        assert!(!p.answers_to("frisian"), "a mere prefix must not match");
    }

    #[test]
    fn a_malformed_pack_is_a_typed_error_naming_the_problem() {
        assert!(parse_pack("").is_err(), "an empty pack must not load");
        let e = parse_pack("(defyakugo \"xx\" \"x\")\n(locales \"xx\")\n(words\n)")
            .expect_err("a pack translating nothing must not load");
        assert!(e.contains("xx"), "the error must name the pack: {e}");
    }

    #[test]
    fn pack_for_locale_finds_and_misses_honestly() {
        assert!(
            pack_for_locale("ja_JP.UTF-8")
                .expect("packs load")
                .is_some_and(|p| p.tag == "ja"),
            "a Japanese locale must resolve to the ja pack"
        );
        assert!(
            pack_for_locale("xx_YY").expect("packs load").is_none(),
            "an unknown locale must resolve to NOTHING rather than a default — \
             silently falling back would run a program in a language the \
             author did not write it in"
        );
    }
}
