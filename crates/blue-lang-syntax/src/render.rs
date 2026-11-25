//! The one string and float renderer. Every surface that turns a string or
//! a float value back into blue source — the formatter, the runtime's `to_s`,
//! error messages — writes this exact spelling, so a value rendered anywhere
//! lexes back to itself. Before this module the formatter and the runtime carried two
//! private tables that had already drifted: `to_s` printed a carriage return
//! or a NUL raw, so a value holding one rendered differently from the source
//! that produced it (found by the conformance rows for the control escapes,
//! 2026-11-16).

/// Render `s` as a blue string literal, quotes and escapes included.
pub fn render_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    let mut after_hash = false;
    for c in s.chars() {
        match c {
            // A string whose VALUE holds `#{` (written `"#\u{7b}"`) printed
            // as `"#{"`, which the lexer reads as an interpolation opener
            // (2026-09-29, the tree generator). blue has no `\{` escape, so
            // the brace after a `#` is written by codepoint.
            '{' if after_hash => out.push_str("\\u{7b}"),
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if invisible(c) => out.push_str(&format!("\\u{{{:x}}}", c as u32)),
            c => out.push(c),
        }
        after_hash = c == '#';
    }
    out.push('"');
    out
}

/// A float must render so it lexes back as a float — `1.0`, never `1`. A
/// magnitude at or past 1e21, or under 1e-7, keeps its exponent (`1.5e307`),
/// where ECMAScript's `Number::toString` keeps it: its decimal form pads
/// zeros past the 17 digits an f64 holds, which no reader can count.
pub fn render_float(f: f64) -> String {
    let a = f.abs();
    if f.is_finite() && a != 0.0 && !(1e-7..1e21).contains(&a) {
        let e = format!("{f:e}");
        return match e.split_once('e') {
            Some((m, x)) if !m.contains('.') => format!("{m}.0e{x}"),
            _ => e,
        };
    }
    let s = format!("{f}");
    if s.contains('.') || s.contains('e') || s.contains("inf") || s.contains("NaN") {
        s
    } else {
        format!("{s}.0")
    }
}

/// The characters that never print as themselves: control characters besides
/// the three with short escapes, and the Unicode characters that hide in
/// rendered text (zero-width, bidi, non-breaking space).
fn invisible(c: char) -> bool {
    (c.is_control() && c != '\n' && c != '\t' && c != '\r')
        || matches!(c, '\u{200b}'..='\u{200f}' | '\u{2028}' | '\u{2029}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}' | '\u{feff}' | '\u{00a0}')
}

#[cfg(test)]
mod tests {
    use super::render_string;

    #[test]
    fn renders_the_short_escapes() {
        assert_eq!(render_string("a\tb\nc\rd"), "\"a\\tb\\nc\\rd\"");
    }

    #[test]
    fn renders_invisible_characters_by_codepoint() {
        assert_eq!(render_string("a\0b"), "\"a\\u{0}b\"");
        assert_eq!(render_string("a\u{200b}b"), "\"a\\u{200b}b\"");
    }

    #[test]
    fn renders_an_interpolation_opener_by_codepoint() {
        assert_eq!(render_string("#{x}"), "\"#\\u{7b}x}\"");
    }

    #[test]
    fn every_rendered_string_lexes_back_to_itself() {
        for s in [
            "plain",
            "a\tb\nc\rd",
            "a\0b\u{b}c",
            "#\u{7b}interpolation",
            "quote\" back\\slash",
            "zero\u{200b}width \u{feff}bom \u{00a0}nbsp",
            "héllo → 🌍",
        ] {
            let rendered = render_string(s);
            let lexed = crate::lex::lex(&rendered)
                .expect("rendered source lexes")
                .into_iter()
                .find_map(|t| match t.kind {
                    crate::lex::TokenKind::Str(v) => Some(v),
                    _ => None,
                })
                .expect("one string token");
            assert_eq!(lexed, s, "round trip through {rendered}");
        }
    }
}
