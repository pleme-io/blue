#[rustfmt::skip]
mod tables;

pub use tables::WORD_SHAPES;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Standing {
    NoWord,
    OwnWord,
    CopyOf {
        word: &'static str,
        foundation: bool,
    },
}

#[must_use]
pub fn standing(hash: &crate::def_hash::DefHash, key: &str) -> Standing {
    let hex = hash.hex();
    let Ok(at) = WORD_SHAPES.binary_search_by(|row| row.0.cmp(&hex[..16])) else {
        return Standing::NoWord;
    };
    let (_, word, foundation) = WORD_SHAPES[at];
    let same_scope = match (word.rsplit_once("::"), key.rsplit_once('/')) {
        (Some((home, _)), Some((own, _))) => {
            blue_lang_syntax::spell_level(own) == blue_lang_syntax::spell_level(home)
        }
        _ => false,
    };
    if same_scope {
        Standing::OwnWord
    } else {
        Standing::CopyOf { word, foundation }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::def_hash::DefHash;

    fn hash_of(hex: &str) -> DefHash {
        let mut bytes = [0u8; 32];
        for (i, b) in bytes.iter_mut().enumerate().take(8) {
            *b = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).expect("hex");
        }
        DefHash(bytes)
    }

    #[test]
    fn the_table_is_sorted_with_one_home_per_shape() {
        assert!(!WORD_SHAPES.is_empty());
        assert!(WORD_SHAPES.windows(2).all(|w| w[0].0 < w[1].0));
        assert!(WORD_SHAPES
            .iter()
            .all(|(hash, word, _)| hash.len() == 16 && word.contains("::")));
    }

    #[test]
    fn a_shape_reads_as_absent_own_or_a_copy() {
        let (hex, word, foundation) = WORD_SHAPES[0];
        let (home, _) = word.split_once("::").expect("a word");
        let hash = hash_of(hex);
        assert_eq!(
            standing(&hash, &format!("{home}/anything")),
            Standing::OwnWord
        );
        assert_eq!(
            standing(&hash, "%root/tally"),
            Standing::CopyOf { word, foundation }
        );
        assert_eq!(
            standing(&DefHash([255; 32]), "%root/tally"),
            Standing::NoWord
        );
    }

    #[test]
    fn a_level_word_is_its_own_level_s() {
        let (hex, word, foundation) = *WORD_SHAPES
            .iter()
            .find(|(_, w, _)| w.split_once("::").is_some_and(|(h, _)| h.contains('/')))
            .expect("a level word in the table");
        let (home, name) = word.rsplit_once("::").expect("a word");
        let hash = hash_of(hex);
        assert_eq!(
            standing(&hash, &format!("{home}/{name}")),
            Standing::OwnWord
        );
        assert_eq!(
            standing(&hash, &format!("{}/{name}", home.replace('/', "-"))),
            Standing::CopyOf { word, foundation }
        );
    }
}
