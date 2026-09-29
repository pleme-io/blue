//! "Did you mean": the in-scope names nearest to a misspelt one.
//!
//! Distance is optimal string alignment — Levenshtein plus adjacent
//! transposition, so `lenght` is ONE edit from `length`, not two. A
//! transposition is the commonest typo there is, and plain Levenshtein would
//! rank it behind unrelated names one substitution away.

/// The optimal-string-alignment distance between `a` and `b`, over chars.
#[must_use]
pub fn distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let (n, m) = (a.len(), b.len());
    // Three rolling rows: the transposition step reads two rows back.
    let mut prev2 = vec![0usize; m + 1];
    let mut prev: Vec<usize> = (0..=m).collect();
    let mut cur = vec![0usize; m + 1];
    for i in 1..=n {
        cur[0] = i;
        for j in 1..=m {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            let mut d = (prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost);
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                d = d.min(prev2[j - 2] + 1);
            }
            cur[j] = d;
        }
        std::mem::swap(&mut prev2, &mut prev);
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[m]
}

/// The largest distance still worth suggesting for a name of `len` chars.
///
/// A third of the name, at least one: `x` suggests nothing two edits away,
/// and a long name tolerates a longer typo. Two thirds of a short name
/// rewritten is a different name, not a misspelling of it.
#[must_use]
pub fn threshold(len: usize) -> usize {
    (len / 3).max(1)
}

/// Is `candidate` close enough to `wanted` to suggest, and how close?
///
/// A case-only difference is distance 1, never 0: `Length` and `length` are
/// different names in blue, and 0 would mean "the same".
#[must_use]
pub fn closeness(wanted: &str, candidate: &str) -> Option<usize> {
    if wanted == candidate {
        return None;
    }
    let len = wanted.chars().count();
    let d = distance(wanted, candidate).max(1);
    if d > threshold(len) || d >= len {
        return None;
    }
    Some(d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_transposition_is_one_edit() {
        assert_eq!(distance("lenght", "length"), 1);
        assert_eq!(distance("frist", "first"), 1);
    }

    #[test]
    fn distance_is_levenshtein_otherwise() {
        assert_eq!(distance("", "abc"), 3);
        assert_eq!(distance("kitten", "sitting"), 3);
        assert_eq!(distance("same", "same"), 0);
    }

    #[test]
    fn closeness_rejects_distant_and_identical_names() {
        assert_eq!(closeness("lenght", "length"), Some(1));
        assert_eq!(closeness("length", "length"), None);
        assert_eq!(
            closeness("x", "y"),
            None,
            "one char rewritten is a different name"
        );
        assert_eq!(closeness("lenght", "filter"), None);
        assert_eq!(closeness("Length", "length"), Some(1));
    }
}
