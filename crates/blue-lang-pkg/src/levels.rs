//! What makes a file its own level: read by the loader, and by `build.rs`,
//! which compiles the same rule into the standard distribution.

/// Does this file open with `namespace()`? It is the first code after the
/// file's `@moduledoc`, so a reader needs no parser.
#[must_use]
pub fn declares_level(text: &str) -> bool {
    let mut in_doc = false;
    for line in text.lines().map(str::trim) {
        if in_doc {
            in_doc = line != "\"\"\"";
        } else if line.starts_with("@moduledoc") {
            in_doc = line.ends_with("\"\"\"");
        } else if !line.is_empty() && !line.starts_with('#') {
            return line == "namespace()";
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::declares_level;

    #[test]
    fn the_first_code_after_the_moduledoc_decides() {
        assert!(declares_level("namespace()\n\ndef f()\n  1\nend\n"));
        assert!(declares_level("# a comment\n\nnamespace()\n"));
        assert!(declares_level(
            "@moduledoc \"\"\"\nnamespace()\ntext\n\"\"\"\n\nnamespace()\n"
        ));
        assert!(!declares_level("def f()\n  namespace()\nend\n"));
        assert!(!declares_level(
            "@moduledoc \"\"\"\nnamespace()\n\"\"\"\n\ndef f()\n  1\nend\n"
        ));
        assert!(!declares_level(""));
    }
}
