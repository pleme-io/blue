//! blue's canonical formatter.
//!
//! **There is no configuration type in this crate, and that is the
//! feature.** `theory/BLUE.md` §0 makes FORM an axis with exactly one way
//! to write a thing; a single option would forfeit both that and the
//! text↔tree bijection §V.16.1's content-addressed identity rests on. So
//! `format_source` takes source and returns source, and there is nowhere
//! to put a knob. The width is a constant, not a parameter.
//!
//! Two laws hold, and they are property-tested rather than asserted:
//!
//! 1. **Idempotence** — `fmt(fmt(s)) == fmt(s)`.
//! 2. **Round-trip** — `parse(fmt(s)) == parse(s)`. Formatting never
//!    changes what a program means.
//!
//! The second is the one that matters. An idempotence test alone is
//! satisfied by a formatter that deletes the whole file, which is exactly
//! how `caixa-fmt` shipped comment loss its proptest structurally could
//! not see — it compared trees that had already dropped trivia.
//!
//! **The rendering law** (§V.13): *spelling is not semantics*. Where two
//! spellings parse to the same tree, the minimal one is rendered. Where
//! they parse to different trees they are different programs and both
//! survive. So `{a: 1}` is always emitted for a symbol key, and `=>`
//! appears only where it is the sole spelling of that tree.

pub mod doc;

use blue_lang_syntax::{parse_program, ParseError};
use doc::{pretty, Doc};
use tatara_lisp::{Atom, Sexp};

/// The one line width. Not configurable — see the module docs.
pub const WIDTH: usize = 90;

/// Format blue source into its canonical form.
pub fn format_source(src: &str) -> Result<String, ParseError> {
    let forms = parse_program(src)?;
    Ok(format_forms(&forms))
}

/// Render already-parsed forms. Exposed so a caller holding a tree does
/// not have to round-trip through text to print it.
pub fn format_forms(forms: &[Sexp]) -> String {
    let mut out = String::new();
    for form in forms {
        out.push_str(&pretty(&expr(form), WIDTH));
        out.push('\n');
    }
    out
}

/// Is this s-expression a call to `head`?
fn is_call(s: &Sexp, head: &str) -> bool {
    matches!(s, Sexp::List(items)
        if matches!(items.first(), Some(Sexp::Atom(Atom::Symbol(h))) if h == head))
}

fn sym_name(s: &Sexp) -> Option<&str> {
    match s {
        Sexp::Atom(Atom::Symbol(n)) => Some(n),
        _ => None,
    }
}

/// Operators that render infix, with their precedence. Must agree with the
/// parser's table or the round-trip law breaks — which is what
/// `blue_lang_syntax`'s own tests plus this crate's round-trip property
/// jointly enforce.
fn infix_prec(op: &str) -> Option<u8> {
    Some(match op {
        "||" => 1,
        "&&" => 3,
        "==" | "!=" | "<" | "<=" | ">" | ">=" => 5,
        "+" | "-" => 7,
        "*" | "/" | "%" => 9,
        _ => return None,
    })
}

fn expr(s: &Sexp) -> Doc {
    expr_prec(s, 0)
}

/// Render `s`, parenthesizing if its precedence is below `min_prec`.
fn expr_prec(s: &Sexp, min_prec: u8) -> Doc {
    match s {
        Sexp::Nil => Doc::text("nil"),
        Sexp::Atom(a) => atom(a),

        Sexp::List(items) if items.is_empty() => Doc::text("()"),

        Sexp::List(items) => {
            let head = sym_name(&items[0]);

            match head {
                // (if c t [e])
                Some("if") if items.len() == 3 || items.len() == 4 => return if_form(items),
                // (define (name params...) body)
                Some("define") if items.len() == 3 && matches!(&items[1], Sexp::List(_)) => {
                    return def_form(items)
                }
                Some("begin") => return begin_form(&items[1..]),
                Some("list") => return seq("[", "]", &items[1..]),
                Some("map") => return map_form(&items[1..]),
                Some("not") if items.len() == 2 => {
                    return Doc::text("!").concat(expr_prec(&items[1], 11))
                }
                // (- 0 x) is unary minus — the shape the parser emits.
                Some("-") if items.len() == 3 && is_zero(&items[1]) => {
                    return Doc::text("-").concat(expr_prec(&items[2], 11))
                }
                _ => {}
            }

            // Infix operators.
            if let Some(op) = head {
                if let Some(prec) = infix_prec(op) {
                    if items.len() == 3 {
                        let inner = Doc::join(
                            [
                                expr_prec(&items[1], prec),
                                Doc::text(op.to_string()),
                                // Right side binds one tighter, which is
                                // what makes `1 - 2 - 3` re-parse as
                                // `(1 - 2) - 3` rather than regrouping.
                                expr_prec(&items[2], prec + 1),
                            ],
                            Doc::text(" "),
                        );
                        return if prec < min_prec {
                            Doc::text("(").concat(inner).concat(Doc::text(")"))
                        } else {
                            inner.group()
                        };
                    }
                }
            }

            // A send: (name recv args...) where `name` is a plain symbol
            // and there is at least a receiver. Rendered `recv.name(args)`,
            // and `recv.name` with no args — uniform access, per §V.13.
            if let Some(name) = head {
                if items.len() >= 2 && infix_prec(name).is_none() && !is_reserved(name) {
                    return send_form(name, &items[1], &items[2..]);
                }
            }

            // Plain call: (f a b)
            let callee = expr_prec(&items[0], 12);
            callee.concat(seq("(", ")", &items[1..]))
        }

        // Quoting has no blue surface yet; render the tatara-lisp form so
        // output is never silently wrong.
        other => Doc::text(other.to_string()),
    }
}

fn is_zero(s: &Sexp) -> bool {
    matches!(s, Sexp::Atom(Atom::Int(0)))
}

fn is_reserved(name: &str) -> bool {
    matches!(
        name,
        "if" | "define" | "begin" | "list" | "map" | "not" | "quote" | "lambda" | "let"
    )
}

fn atom(a: &Atom) -> Doc {
    match a {
        Atom::Symbol(s) => Doc::text(s.clone()),
        Atom::Keyword(k) => Doc::text(format!(":{k}")),
        Atom::Str(s) => Doc::text(render_string(s)),
        Atom::Int(i) => Doc::text(i.to_string()),
        Atom::Float(f) => Doc::text(render_float(*f)),
        Atom::Bool(b) => Doc::text(if *b { "true" } else { "false" }),
        other => Doc::text(format!("{other:?}")),
    }
}

fn render_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A float must render so it lexes back as a float — `1.0`, never `1`.
fn render_float(f: f64) -> String {
    let s = format!("{f}");
    if s.contains('.') || s.contains('e') || s.contains("inf") || s.contains("NaN") {
        s
    } else {
        format!("{s}.0")
    }
}

/// `open a, b, c close`, breaking one-per-line when it does not fit.
fn seq(open: &str, close: &str, items: &[Sexp]) -> Doc {
    if items.is_empty() {
        return Doc::text(format!("{open}{close}"));
    }
    let inner = Doc::join(
        items.iter().map(|i| expr(i)),
        Doc::text(",").concat(Doc::line()),
    );
    Doc::text(open.to_string())
        .concat(Doc::softline().concat(inner).nest(2))
        .concat(Doc::softline())
        .concat(Doc::text(close.to_string()))
        .group()
}

/// `{a: 1, "k" => v}` — **the minimal-spelling law in one function.**
///
/// A keyword key has a shorthand, so the shorthand is always emitted. Any
/// other key has no shorthand, so the rocket appears — because it is the
/// only spelling of that tree, never as a style choice.
fn map_form(kvs: &[Sexp]) -> Doc {
    if kvs.is_empty() {
        return Doc::text("{}");
    }
    let mut pairs = Vec::new();
    for pair in kvs.chunks(2) {
        let d = match pair {
            [Sexp::Atom(Atom::Keyword(k)), v] => Doc::text(format!("{k}: "))
                .concat(expr(v)),
            [k, v] => expr(k)
                .concat(Doc::text(" => "))
                .concat(expr(v)),
            // Odd trailing key — render it rather than silently dropping.
            [k] => expr(k),
            _ => Doc::nil(),
        };
        pairs.push(d);
    }
    let inner = Doc::join(pairs, Doc::text(",").concat(Doc::line()));
    Doc::text("{")
        .concat(Doc::softline().concat(inner).nest(2))
        .concat(Doc::softline())
        .concat(Doc::text("}"))
        .group()
}

fn send_form(name: &str, recv: &Sexp, args: &[Sexp]) -> Doc {
    let base = expr_prec(recv, 12).concat(Doc::text(format!(".{name}")));
    if args.is_empty() {
        base
    } else {
        base.concat(seq("(", ")", args))
    }
}

fn if_form(items: &[Sexp]) -> Doc {
    let mut d = Doc::text("if ")
        .concat(expr(&items[1]))
        .concat(Doc::text("\n"))
        .concat(indent_block(&items[2]));
    if let Some(els) = items.get(3) {
        d = d
            .concat(Doc::text("\nelse\n"))
            .concat(indent_block(els));
    }
    d.concat(Doc::text("\nend"))
}

fn def_form(items: &[Sexp]) -> Doc {
    let Sexp::List(sig) = &items[1] else {
        return Doc::text(items[1].to_string());
    };
    let name = sym_name(&sig[0]).unwrap_or("_");
    let params: Vec<String> = sig[1..]
        .iter()
        .map(|p| sym_name(p).unwrap_or("_").to_string())
        .collect();
    Doc::text(format!("def {name}({})", params.join(", ")))
        .concat(Doc::text("\n"))
        .concat(indent_block(&items[2]))
        .concat(Doc::text("\nend"))
}

fn begin_form(forms: &[Sexp]) -> Doc {
    Doc::join(forms.iter().map(|f| expr(f)), Doc::text("\n"))
}

/// Render a block body indented two spaces. Block layout is line-based
/// rather than group-based: a `def` body always breaks, because collapsing
/// one onto a single line would be a second rendering of the same tree.
fn indent_block(body: &Sexp) -> Doc {
    let rendered = pretty(&expr(body), WIDTH.saturating_sub(2));
    let indented = rendered
        .lines()
        .map(|l| if l.is_empty() { String::new() } else { format!("  {l}") })
        .collect::<Vec<_>>()
        .join("\n");
    Doc::text(indented)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn f(src: &str) -> String {
        format_source(src).unwrap_or_else(|e| panic!("{src:?}: {e}"))
    }

    // ---- the minimal-spelling law (§V.13) ---------------------------

    /// Both spellings parse to one tree, so both format to the SHORTER
    /// one. That is the law: spelling is not semantics.
    #[test]
    fn a_symbol_key_always_renders_as_the_shorthand() {
        assert_eq!(f("{a: 1}").trim(), "{a: 1}");
        assert_eq!(f("{:a => 1}").trim(), "{a: 1}");
    }

    /// And the rocket survives exactly where it is the only spelling of
    /// that tree — never as a style choice.
    #[test]
    fn a_non_symbol_key_keeps_the_rocket_because_it_must() {
        assert_eq!(f(r#"{"k" => 1}"#).trim(), r#"{"k" => 1}"#);
    }

    #[test]
    fn unary_forms_render_back_to_their_surface() {
        assert_eq!(f("-x").trim(), "-x");
        assert_eq!(f("!x").trim(), "!x");
    }

    // ---- structure ---------------------------------------------------

    #[test]
    fn precedence_is_preserved_without_redundant_parens() {
        assert_eq!(f("1 + 2 * 3").trim(), "1 + 2 * 3");
    }

    #[test]
    fn parens_are_emitted_only_where_precedence_requires_them() {
        assert_eq!(f("(1 + 2) * 3").trim(), "(1 + 2) * 3");
    }

    #[test]
    fn left_associativity_survives_the_round_trip() {
        assert_eq!(f("1 - 2 - 3").trim(), "1 - 2 - 3");
    }

    #[test]
    fn a_bare_send_stays_bare() {
        assert_eq!(f("user.name").trim(), "user.name");
        assert_eq!(f("a.b.c").trim(), "a.b.c");
    }

    #[test]
    fn a_send_with_args_keeps_its_parens() {
        assert_eq!(f("user.greet(1, 2)").trim(), "user.greet(1, 2)");
    }

    #[test]
    fn def_and_if_render_as_blocks() {
        let out = f("def add(a,b)\n a+b\nend");
        assert_eq!(out.trim(), "def add(a, b)\n  a + b\nend");
    }

    #[test]
    fn if_else_renders_as_a_block() {
        let out = f("if a\n1\nelse\n2\nend");
        assert_eq!(out.trim(), "if a\n  1\nelse\n  2\nend");
    }

    #[test]
    fn nested_blocks_indent_cumulatively() {
        let out = f("def f(n)\nif n\n1\nend\nend");
        assert_eq!(out.trim(), "def f(n)\n  if n\n    1\n  end\nend");
    }

    #[test]
    fn floats_render_so_they_lex_back_as_floats() {
        assert_eq!(f("1.0").trim(), "1.0");
    }

    #[test]
    fn strings_are_re_escaped() {
        assert_eq!(f(r#""a\nb""#).trim(), r#""a\nb""#);
    }
}
