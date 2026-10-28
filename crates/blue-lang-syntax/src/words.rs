pub const MIN_WORDS: usize = 2;

const NOT_IN_A_WORD: &[char] = &['[', ']', ',', '"', '\'', '\\', '#'];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flavor {
    Strings,
    Keywords,
}

impl Flavor {
    #[must_use]
    pub const fn sigil(self) -> &'static str {
        match self {
            Flavor::Strings => "%w",
            Flavor::Keywords => "%i",
        }
    }
}

#[must_use]
pub fn is_word_char(c: char) -> bool {
    !c.is_whitespace()
        && !NOT_IN_A_WORD.contains(&c)
        && (c.is_ascii_graphic()
            || (!c.is_ascii() && crate::kigou::classify(c) != crate::kigou::Class::Reject))
}

#[must_use]
pub fn is_word(s: &str) -> bool {
    !s.is_empty() && s.chars().all(is_word_char)
}

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

#[must_use]
pub fn writable<'a>(flavor: Flavor, elements: &[&'a str]) -> Option<Vec<&'a str>> {
    let fits = |w: &str| match flavor {
        Flavor::Strings => is_word(w),
        Flavor::Keywords => is_symbol_name(w),
    };
    (elements.len() >= MIN_WORDS && elements.iter().all(|w| fits(w))).then(|| elements.to_vec())
}

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
