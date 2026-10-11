//! Word lists: Ruby's `%w[a b]` (a list of strings) and `%i[a b]` (a list of
//! keywords), the same trees as `["a", "b"]` and `[:a, :b]`.
//!
//! One module owns what a word is, so the lexer that reads a word list and the
//! formatter that chooses to write one cannot disagree: a list the formatter
//! prints as `%w[…]` re-lexes to exactly the strings it held.
//!
//! **One delimiter, `[ ]`.** Ruby also takes `( )`, `{ }`, `< >` and more. In
//! blue each of those already means something after `%`: `a %w(b)` is
//! `a % w(b)`, a valid program today, and taking it would change its meaning.
//! `%w[` cannot be: `w[b]` is indexing, which blue does not have. `[ ]` is also
//! RuboCop's default for both literals. The transposed `w%[…]` is not accepted:
//! one spelling.
//!
//! **What a word may hold.** A `%w` word is a run of characters that is not
//! white space, a control or invisible character, or one of `[ ] , " ' \ #`.
//! The comma and the quotes are refused rather than kept because
//! `%w[a, b]` and `%w["a" "b"]` are the classic mistakes (Ruby keeps `"a,"`
//! and `"\"a\""`, and RuboCop has a cop for each); `#` because a reader takes
//! it for a comment or an interpolation; a bracket and `\` because the literal
//! has no escapes. A `%i` word is a name as `:name` spells it.

/// The fewest elements the formatter writes as a word list. One is written
/// `["a"]`: `%w[a]` saves nothing and reads as a typo. RuboCop's `MinSize` for
/// `WordArray` and `SymbolArray` is 2 as well.
pub const MIN_WORDS: usize = 2;

/// Characters a `%w` word may not contain, besides white space and the
/// characters [`crate::kigou`] rejects.
const NOT_IN_A_WORD: &[char] = &['[', ']', ',', '"', '\'', '\\', '#'];

/// Which literal: `%w` holds strings, `%i` keywords.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flavor {
    Strings,
    Keywords,
}

impl Flavor {
    /// The two characters that open the literal before its `[`.
    #[must_use]
    pub const fn sigil(self) -> &'static str {
        match self {
            Flavor::Strings => "%w",
            Flavor::Keywords => "%i",
        }
    }
}

/// May `c` sit inside a `%w` word?
#[must_use]
pub fn is_word_char(c: char) -> bool {
    !c.is_whitespace()
        && !NOT_IN_A_WORD.contains(&c)
        && (c.is_ascii_graphic()
            || (!c.is_ascii() && crate::kigou::classify(c) != crate::kigou::Class::Reject))
}

/// Can the string `s` be written as one `%w` word?
#[must_use]
pub fn is_word(s: &str) -> bool {
    !s.is_empty() && s.chars().all(is_word_char)
}

/// Is `s` a name `:s` spells — so `%i[s]` holds the keyword `:s`?
///
/// The lexer's `:name` rule: an ASCII letter or `_`, then letters, digits, `_`
/// or any non-ASCII character, then at most one `?` or `!`.
#[must_use]
pub fn is_symbol_name(s: &str) -> bool {
    let b = s.as_bytes();
    let Some(&first) = b.first() else {
        return false;
    };
    if !(first.is_ascii_alphabetic() || first == b'_') {
        return false;
    }
    let body = match b.last() {
        Some(b'?' | b'!') if b.len() > 1 => &s[..s.len() - 1],
        _ => s,
    };
    body.chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || (!c.is_ascii() && is_word_char(c)))
}

/// Why `word` cannot sit in a word list of `flavor`, or `None` when it can.
#[must_use]
pub fn refusal(flavor: Flavor, word: &str) -> Option<String> {
    match flavor {
        Flavor::Strings => {
            let bad = word.chars().find(|c| !is_word_char(*c))?;
            Some(match bad {
                ',' => "words in `%w[…]` are separated by spaces, not commas: `%w[a b]`".into(),
                '"' | '\'' => "a word in `%w[…]` is written without quotes: `%w[a b]`".into(),
                c => format!(
                    "`{c}` cannot be part of a word in `%w[…]`; write the list as `[\"…\", …]`"
                ),
            })
        }
        Flavor::Keywords if is_symbol_name(word) => None,
        Flavor::Keywords if word.starts_with(':') => {
            Some("a name in `%i[…]` is written without its colon: `%i[a b]`".into())
        }
        Flavor::Keywords if word.contains(',') => {
            Some("names in `%i[…]` are separated by spaces, not commas: `%i[a b]`".into())
        }
        Flavor::Keywords => Some(format!(
            "`{word}` is not a name `:{word}` could spell, so it cannot be in `%i[…]`"
        )),
    }
}

/// The words of a list the formatter writes as a word list: `elements` when
/// there are at least [`MIN_WORDS`] and each can be one word.
#[must_use]
pub fn writable<'a>(flavor: Flavor, elements: &[&'a str]) -> Option<Vec<&'a str>> {
    let fits = |w: &str| match flavor {
        Flavor::Strings => is_word(w),
        Flavor::Keywords => is_symbol_name(w),
    };
    (elements.len() >= MIN_WORDS && elements.iter().all(|w| fits(w))).then(|| elements.to_vec())
}

/// A list of keywords as blue writes it: `%i[a b]` from two names on, `[:a]`
/// for one, `[]` for none. For a caller that writes an import list as text
/// (a check's fix, an editor's edit) and must write what the formatter would.
#[must_use]
pub fn render_keywords(names: &[&str]) -> String {
    match writable(Flavor::Keywords, names) {
        Some(words) => format!("%i[{}]", words.join(" ")),
        None => {
            let items: Vec<String> = names.iter().map(|n| format!(":{n}")).collect();
            format!("[{}]", items.join(", "))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_word_is_any_visible_run_but_the_refused_characters() {
        for w in ["a", "--force", "a.b", "x/y", "http://h:1", "λ", "a=b", "é"] {
            assert!(is_word(w), "{w}");
        }
        for w in [
            "", "a b", "a,", "\"a\"", "'a'", "a]", "[a", "a\\b", "#a", "a\u{85}", "a\u{7}",
        ] {
            assert!(!is_word(w), "{w:?}");
        }
    }

    #[test]
    fn a_symbol_name_is_what_colon_spells() {
        for n in ["a", "_x", "pair?", "save!", "a1", "nome_ção"] {
            assert!(is_symbol_name(n), "{n}");
        }
        for n in ["", "1a", "a-b", "a?b", "?", "a??", ":a", "a.b", "éa"] {
            assert!(!is_symbol_name(n), "{n:?}");
        }
    }

    #[test]
    fn the_threshold_is_two() {
        assert_eq!(writable(Flavor::Strings, &["a"]), None);
        assert_eq!(writable(Flavor::Strings, &["a", "b"]), Some(vec!["a", "b"]));
        assert_eq!(writable(Flavor::Strings, &["a", "b c"]), None);
        assert_eq!(render_keywords(&["a"]), "[:a]");
        assert_eq!(render_keywords(&["a", "b"]), "%i[a b]");
        assert_eq!(render_keywords(&[]), "[]");
    }
}
