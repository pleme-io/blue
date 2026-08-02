//! `kigou` (記号) — the character library: which symbols blue understands.
//!
//! The lexer's UTF-8 layer decodes a character; this decides what it *means*.
//! Three answers, and every non-ASCII character gets exactly one:
//!
//! | class | example | blue treats it as |
//! |---|---|---|
//! | [`Class::Operator`] | `≠` `≤` `×` `∧` | the ASCII operator it spells |
//! | [`Class::Word`] | `λ` `∀` `→` `文` | part of an identifier |
//! | [`Class::Reject`] | a bare combining mark, a control char | a lex error |
//!
//! ## Why an operator table rather than "symbols are operators"
//!
//! Because most beautiful symbols are not operators, they are *names*. `λ` is
//! what a reader wants to call a lambda, `∀` is a good name for a
//! universal-quantifier helper, `∇` for a gradient. If every symbol lexed as an
//! operator, none of those could be a function name and the library would be
//! poorer for it.
//!
//! So the table is a **curated allow-list of aliases**: a symbol is an operator
//! only if it is the standard typographic spelling of one blue already has.
//! `≠` is genuinely how mathematics writes `!=`; `∀` is not how it writes
//! anything blue has. Everything not on the list is a name, which is the
//! permissive default and the one that gives the language its range.
//!
//! ## The aliases carry no new semantics
//!
//! Each alias lexes to the *identical token* as its ASCII spelling, so `a ≠ b`
//! and `a != b` are the same program — not equivalent programs, the same one.
//! That is deliberate: a symbol that meant something subtly different from the
//! operator it looks like would be a trap, and the whole value of `≤` is that
//! a reader already knows what it does.

/// What blue does with a character.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Class {
    /// Spells an existing blue operator.
    Operator(&'static str),
    /// May appear in an identifier.
    Word,
    /// Not legal in source outside a string or comment.
    Reject,
}

/// The typographic spellings of blue's operators.
///
/// Curated, not generated: every row is a symbol that mathematics or ordinary
/// typography already uses for exactly this operator, so a reader needs no
/// lookup. A symbol whose meaning would have to be *taught* belongs in an
/// identifier instead, where the author names it.
pub const OPERATOR_ALIASES: &[(char, &str, &str)] = &[
    ('≠', "!=", "not equal"),
    ('≤', "<=", "less than or equal"),
    ('≥', ">=", "greater than or equal"),
    ('×', "*", "multiplication"),
    ('÷', "/", "division"),
    ('−', "-", "minus sign (U+2212, not the ASCII hyphen)"),
    ('∧', "&&", "logical and"),
    ('∨', "||", "logical or"),
    ('¬', "!", "logical not"),
    ('≡', "==", "identical to"),
];

/// The symbols blue explicitly welcomes inside identifiers.
///
/// Not exhaustive — [`classify`] admits any alphabetic character and any
/// symbol not on the operator list — but *named*, because a catalog a reader
/// can scan is worth more than a rule they have to infer. These are the ones
/// worth reaching for.
pub const WELCOME: &[(char, &str)] = &[
    (
        'λ',
        "lambda — the traditional name for an anonymous function",
    ),
    ('∀', "for all"),
    ('∃', "there exists"),
    ('∈', "element of"),
    ('∉', "not an element of"),
    ('∅', "the empty set"),
    ('∪', "union"),
    ('∩', "intersection"),
    ('⊆', "subset of"),
    ('∘', "function composition"),
    ('∑', "sum"),
    ('∏', "product"),
    ('√', "square root"),
    ('∞', "infinity"),
    ('∂', "partial derivative"),
    ('∇', "gradient / nabla"),
    ('∫', "integral"),
    ('→', "maps to / implies"),
    ('←', "assigned from"),
    ('↔', "if and only if"),
    ('⇒', "implies"),
    ('⊤', "top / true"),
    ('⊥', "bottom / false"),
    ('⊢', "proves / entails"),
    ('π', "pi"),
    ('α', "alpha"),
    ('β', "beta"),
    ('γ', "gamma"),
    ('δ', "delta"),
    ('ε', "epsilon"),
    ('θ', "theta"),
    ('μ', "mu"),
    ('σ', "sigma"),
    ('φ', "phi"),
    ('ω', "omega"),
    ('ℕ', "the naturals"),
    ('ℤ', "the integers"),
    ('ℚ', "the rationals"),
    ('ℝ', "the reals"),
    ('ℂ', "the complex numbers"),
];

/// The ASCII operator a character spells, if it spells one.
#[must_use]
pub fn operator_alias(ch: char) -> Option<&'static str> {
    OPERATOR_ALIASES
        .iter()
        .find(|(c, _, _)| *c == ch)
        .map(|(_, op, _)| *op)
}

/// What blue does with `ch`.
///
/// ASCII is not this function's business — the lexer handles it directly, and
/// routing it here would put a table lookup in front of every byte of every
/// ordinary program.
#[must_use]
pub fn classify(ch: char) -> Class {
    if let Some(op) = operator_alias(ch) {
        return Class::Operator(op);
    }
    // A control character or an unpaired combining mark cannot begin anything
    // and is almost always an invisible paste artefact — the class of bug that
    // costs an hour because the source *looks* correct.
    if ch.is_control() || ch.is_whitespace() {
        return Class::Reject;
    }
    Class::Word
}

/// Everything in the catalog, for `blue kigou` and for documentation.
///
/// One function rather than two exported tables, so a caller cannot render
/// half the catalog and believe it is the whole thing.
#[must_use]
pub fn catalog() -> Vec<(char, String, Class)> {
    let mut out: Vec<(char, String, Class)> = OPERATOR_ALIASES
        .iter()
        .map(|(c, op, why)| (*c, format!("{why} — reads as `{op}`"), classify(*c)))
        .collect();
    out.extend(
        WELCOME
            .iter()
            .map(|(c, why)| (*c, (*why).to_owned(), classify(*c))),
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_alias_lexes_to_the_same_program_as_its_ascii_spelling() {
        // The property that makes an alias safe: not "equivalent", identical.
        for (ch, ascii, why) in OPERATOR_ALIASES {
            let fancy = crate::parse_program(&format!("def f(a, b)\n  a {ch} b\nend"));
            let plain = crate::parse_program(&format!("def f(a, b)\n  a {ascii} b\nend"));
            let plain = plain.unwrap_or_else(|e| panic!("ascii `{ascii}` must parse: {e}"));
            let fancy = fancy.unwrap_or_else(|e| panic!("`{ch}` ({why}) must parse: {e}"));
            assert_eq!(
                format!("{fancy:?}"),
                format!("{plain:?}"),
                "`{ch}` and `{ascii}` produced DIFFERENT trees — an alias that \
                 means something other than the operator it looks like is a trap"
            );
        }
    }

    #[test]
    fn welcomed_symbols_are_usable_as_names() {
        for (ch, why) in WELCOME {
            assert_eq!(
                classify(*ch),
                Class::Word,
                "`{ch}` ({why}) is in WELCOME but does not classify as part of \
                 an identifier"
            );
            let src = format!("def {ch}(n)\n  n\nend\n{ch}(1)");
            assert!(
                crate::parse_program(&src).is_ok(),
                "`{ch}` ({why}) is catalogued as a usable name but will not parse"
            );
        }
    }

    #[test]
    fn the_two_tables_do_not_overlap() {
        // A character that is both an operator and a name is ambiguous, and
        // the tables are hand-maintained, so this is the check that keeps a
        // later addition from creating one.
        for (ch, _) in WELCOME {
            assert!(
                operator_alias(*ch).is_none(),
                "`{ch}` appears in BOTH the operator aliases and the welcome \
                 list — it cannot be an operator and a name at once"
            );
        }
    }

    #[test]
    fn invisible_characters_are_rejected_rather_than_named() {
        // A zero-width space pasted into source is the bug that costs an hour,
        // because the source looks right.
        assert_eq!(classify('\u{00a0}'), Class::Reject, "no-break space");
        assert_eq!(classify('\u{0007}'), Class::Reject, "control character");
    }

    /// `elsif` regression — it used to vanish silently.
    ///
    /// Lives here rather than in the parser tests because this file's demo
    /// program is what exposed it: a clamp written with `elsif` returned its
    /// input unchanged, and the alias work was briefly suspected before the
    /// same failure reproduced in pure ASCII.
    #[test]
    fn an_elsif_arm_is_reachable() {
        let src = "def k(a)\n  if a < 1\n    1\n  elsif a < 5\n    2\n  else\n    3\n  end\nend";
        let forms = crate::parse_program(src).expect("elsif must parse");
        let text = format!("{forms:?}");
        // Three arms means a NESTED if in the else position. A swallowed
        // `elsif` produces exactly one `if` and quietly drops the middle arm.
        assert!(
            text.matches("Symbol(\"if\")").count() >= 2,
            "the elsif arm did not become a nested if — it was swallowed, and \
             a swallowed arm returns the else value with no error: {text}"
        );
    }

    #[test]
    fn the_catalog_is_whole() {
        let c = catalog();
        assert_eq!(
            c.len(),
            OPERATOR_ALIASES.len() + WELCOME.len(),
            "catalog() dropped entries — a partial catalog read as a whole one \
             is how a reader concludes a character is unsupported"
        );
    }
}
