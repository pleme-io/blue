use blue_lang_syntax::{Atom, Sexp, Spanned, SpannedForm};

const MARK: &str = "%line";
const SOURCE: &str = "%source";

fn line_col(src: &str, at: usize) -> Option<(i64, i64)> {
    let before = src.get(..at)?;
    let line = before.matches('\n').count();
    let col = before.rfind('\n').map_or(at, |n| at - n - 1);
    Some((line as i64 + 1, col as i64 + 1))
}

fn atom(at: &Spanned, a: Atom) -> Spanned {
    Spanned::new(at.span, SpannedForm::Atom(a))
}

fn marked(form: Spanned, src: &str) -> Spanned {
    let inner = descended(form, src);
    match line_col(src, inner.span.start) {
        Some((line, col)) => {
            let span = inner.span;
            let items = vec![
                atom(&inner, Atom::Symbol(MARK.to_string())),
                atom(&inner, Atom::Int(line)),
                atom(&inner, Atom::Int(col)),
                inner,
            ];
            Spanned::new(span, SpannedForm::List(items))
        }
        None => inner,
    }
}

fn head_of(items: &[Spanned]) -> Option<&str> {
    items.first().and_then(Spanned::as_symbol)
}

fn statement_positions(items: &[Spanned]) -> std::ops::Range<usize> {
    match head_of(items) {
        Some("begin") => 1..items.len(),
        Some("if") => 2..items.len(),
        Some("define") if matches!(items.get(1).map(|f| &f.form), Some(SpannedForm::List(_))) => {
            2..items.len()
        }
        Some("define-typed") => 3..items.len(),
        _ => 0..0,
    }
}

fn descended(form: Spanned, src: &str) -> Spanned {
    let span = form.span;
    match form.form {
        SpannedForm::List(items) => {
            let statements = statement_positions(&items);
            let walked = items
                .into_iter()
                .enumerate()
                .map(|(i, f)| {
                    if statements.contains(&i) {
                        marked(f, src)
                    } else {
                        descended(f, src)
                    }
                })
                .collect();
            Spanned::new(span, SpannedForm::List(walked))
        }
        other => Spanned::new(span, other),
    }
}

/// A resolved top-level form with each statement of a function body, branch or
/// block wrapped as `(%line LINE COLUMN form)`, so a compiler reading the printed
/// tree knows where its code came from. A top-level form is not itself wrapped,
/// and a node whose span is outside `src` is left bare.
pub fn with_source_lines(form: Spanned, src: &str) -> Spanned {
    descended(form, src)
}

/// The file a marked tree came from, as one form: `(%source PATH LINE ...)`, so a
/// reader of the printed tree holds the text of each line with no file access.
pub fn source_form(path: &str, src: &str) -> Sexp {
    let text = |t: &str| Sexp::Atom(Atom::Str(t.to_string()));
    let mut items = vec![Sexp::Atom(Atom::Symbol(SOURCE.to_string())), text(path)];
    items.extend(src.lines().map(text));
    Sexp::List(items)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn printed(src: &str) -> Vec<String> {
        blue_lang_syntax::parse_program_tree(src)
            .expect("parses")
            .into_iter()
            .map(|f| with_source_lines(f, src).to_sexp().to_string())
            .collect()
    }

    #[test]
    fn each_statement_carries_its_own_line() {
        let got = printed("def f(a)\n  b = a + 1\n  b\nend\n");
        assert_eq!(
            got,
            ["(define (f a) (%line 2 3 (begin (%line 2 3 (define b (+ a 1))) (%line 3 3 b))))"]
        );
    }

    #[test]
    fn a_branch_is_marked_and_its_condition_is_not() {
        let got = printed("def f(a)\n  if a > 1\n    2\n  else\n    3\n  end\nend\n");
        assert_eq!(
            got,
            ["(define (f a) (%line 2 3 (if (> a 1) (%line 3 5 2) (%line 5 5 3))))"]
        );
    }

    #[test]
    fn the_source_form_holds_each_line_and_quotes_what_it_must() {
        let form = source_form("f.b", "a = \"x\"\n\nb\n");
        assert_eq!(form.to_string(), r#"(%source "f.b" "a = \"x\"" "" "b")"#);
    }

    #[test]
    fn a_top_level_constant_is_left_as_it_was() {
        assert_eq!(printed("k = 3\n"), ["(define k 3)"]);
    }

    #[test]
    fn a_span_outside_the_source_is_left_bare() {
        let form = blue_lang_syntax::parse_program_tree("def f()\n  1\nend\n")
            .expect("parses")
            .remove(0);
        let got = with_source_lines(form, "").to_sexp().to_string();
        assert!(!got.contains(MARK), "{got}");
    }
}
