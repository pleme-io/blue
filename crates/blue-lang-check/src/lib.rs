//! The typing ladder — rung 0 and rung 1.
//!
//! §0's central claim, made mechanical:
//!
//! > **Declare nothing and get ZERO analysis. Declare, and get analysis on
//! > that structure only. Correctness never moves.**
//!
//! Two properties make that literal rather than aspirational, and both are
//! property-tested in this crate:
//!
//! 1. **Zero analysis at rung 0.** An unannotated program is not walked
//!    and waved through — it is *not walked*. [`check_program`] returns
//!    immediately on a form with no annotated head, and [`Stats::visited`]
//!    records zero nodes. A checker that must visit every node to discover
//!    there is nothing to check has already paid the cost the ladder
//!    exists to avoid.
//!
//! 2. **Never infer backward across an undeclared boundary.** When typed
//!    code calls something undeclared, the argument is `Dyn` and the
//!    obligation is discharged **at the seam** — a check recorded right
//!    there. The checker does not chase the callee to find out what it
//!    returns. This is the discipline that makes cost a function of
//!    *annotation density* rather than of the transitive call graph, and
//!    §0 states it as the thing that makes the ladder slide *exactly*
//!    rather than approximately.
//!
//! **Honest tier.** These are `checked-at-expansion` diagnostics over a
//! tree. Nothing here is unrepresentability: a type error is a reported
//! `Diagnostic`, not an absent code path. The docs say so because §V.24
//! caught this document rounding exactly this kind of tier up.

use std::collections::BTreeMap;

use tatara_lisp::{Atom, Sexp, Span, Spanned, SpannedForm};

/// A blue type at rung 1.
///
/// `Dyn` is the top and the default. Every rule below is written so that
/// `Dyn` on either side succeeds — the ladder's promise is that
/// unannotated code is *less analyzed*, never *less correct*.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Ty {
    Dyn,
    Int,
    Float,
    Str,
    Bool,
    Sym,
    Nil,
    List(Box<Ty>),
    /// A name the checker does not know. Treated as opaque and nominal.
    Named(String),
}

impl Ty {
    /// Parse a type expression as written in a signature.
    pub fn from_sexp(s: &Sexp) -> Ty {
        match s {
            Sexp::Atom(Atom::Symbol(n)) => match n.as_str() {
                "dyn" => Ty::Dyn,
                "Int" => Ty::Int,
                "Float" => Ty::Float,
                "Str" => Ty::Str,
                "Bool" => Ty::Bool,
                "Sym" => Ty::Sym,
                "Nil" => Ty::Nil,
                other => Ty::Named(other.to_string()),
            },
            Sexp::List(items) if items.len() == 2 => {
                if let Sexp::Atom(Atom::Symbol(h)) = &items[0] {
                    if h == "List" {
                        return Ty::List(Box::new(Ty::from_sexp(&items[1])));
                    }
                }
                Ty::Dyn
            }
            _ => Ty::Dyn,
        }
    }

    /// Is a value of type `self` acceptable where `want` is expected?
    ///
    /// **`Dyn` is compatible in BOTH directions.** That is not laxness —
    /// it is the gradual guarantee's shape: adding an annotation may make
    /// a program *check*, and removing one may make it stop checking, but
    /// neither changes what the program means.
    pub fn accepts(&self, want: &Ty) -> bool {
        match (self, want) {
            (Ty::Dyn, _) | (_, Ty::Dyn) => true,
            (Ty::List(a), Ty::List(b)) => a.accepts(b),
            (a, b) => a == b,
        }
    }

    pub fn name(&self) -> String {
        match self {
            Ty::Dyn => "dyn".into(),
            Ty::Int => "Int".into(),
            Ty::Float => "Float".into(),
            Ty::Str => "Str".into(),
            Ty::Bool => "Bool".into(),
            Ty::Sym => "Sym".into(),
            Ty::Nil => "Nil".into(),
            Ty::List(t) => format!("List({})", t.name()),
            Ty::Named(n) => n.clone(),
        }
    }
}

/// A reported problem. Always a diagnostic, never a refusal to run.
#[derive(Clone, Debug, PartialEq)]
pub struct Diagnostic {
    pub message: String,
    /// The byte range in the source that caused it.
    ///
    /// **This field is why the checker walks [`Spanned`] and not `Sexp`.** It
    /// carried only `message` until 2026-08-12, and the consequence was visible
    /// in every editor: `blue-lang-lsp` had nowhere to get a range from, so it
    /// attached every type error to `Range::default()` — line 0, column 0 —
    /// while parse errors, which had a span, pointed at the right byte. A type
    /// error in a 300-line file was reported on its first character.
    ///
    /// Synthetic only for a node with no source origin at all. A checker fed a
    /// tree lifted with `Spanned::from_sexp_synthetic` reports synthetic spans
    /// throughout, which is honest and useless — see [`check_program`] on which
    /// door a consumer should be using.
    pub span: Span,
}

/// A diagnostic renders itself. Per ★★ TYPED EMISSION the only sanctioned
/// ways to produce a string are a `Display`-family `write!`, a typed log or
/// error macro, and a typed AST builder — so a consumer that needed the text
/// was a missing `Display`, not a licence to `format!` at the call site.
impl std::fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

/// A runtime check the compiler must insert because a static one was not
/// available — a **seam**.
///
/// Seams are recorded rather than silently emitted, because §0's rule is
/// that an invisible cost is the one unacceptable outcome. `blue check`
/// can show exactly where the boundary work lands.
#[derive(Clone, Debug, PartialEq)]
pub struct Seam {
    /// The type the typed side requires.
    pub expected: Ty,
    /// Where the check sits, for the report.
    pub at: String,
    /// The byte range of the argument the check guards.
    ///
    /// Spanned for the same reason a diagnostic is: §0's rule is that an
    /// invisible cost is the one unacceptable outcome, and "argument 1 of `add`"
    /// is only half a location — it does not say *which* call. A seam is also
    /// the place a debugger will want to break, since it is exactly where the
    /// compiler inserts work the source does not show.
    pub span: Span,
}

/// What the checker did, so the claim "zero analysis" can be *measured*
/// rather than asserted.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Stats {
    /// Nodes actually visited by the type walk.
    pub visited: usize,
    /// Declarations that carried an annotation.
    pub typed_decls: usize,
}

#[derive(Clone, Debug, Default)]
pub struct Outcome {
    pub diagnostics: Vec<Diagnostic>,
    pub seams: Vec<Seam>,
    pub stats: Stats,
}

impl Outcome {
    pub fn ok(&self) -> bool {
        self.diagnostics.is_empty()
    }
}

/// A function's declared signature.
#[derive(Clone, Debug)]
struct Sig {
    params: Vec<Ty>,
    ret: Ty,
}

/// Check a program.
///
/// **Takes the SPANNED tree, which is the parser's real output.** Reach for
/// `blue_lang_syntax::parse_program_tree`, not `parse_program` — a caller that
/// lifts a spanless tree with `Spanned::from_sexp_synthetic` gets an `Outcome`
/// whose every diagnostic says `<synthetic>` where a position should be, and an
/// editor given that has nothing to underline. That is not a hypothetical: it is
/// exactly the state this function replaced.
pub fn check_program(forms: &[Spanned]) -> Outcome {
    let mut out = Outcome::default();
    let mut sigs: BTreeMap<String, Sig> = BTreeMap::new();

    // Pass 1: collect declared signatures. Only typed heads are read, so
    // an entirely unannotated program leaves this map empty and pass 2
    // has nothing to walk.
    for form in forms {
        if let Some((name, sig)) = read_typed_decl(form) {
            sigs.insert(name, sig);
            out.stats.typed_decls += 1;
        }
    }

    // Pass 2: walk ONLY the typed declarations' bodies.
    //
    // This is the mechanical form of "zero analysis at rung 0": an
    // unannotated program never enters the loop body.
    for form in forms {
        if let Some((name, _)) = read_typed_decl(form) {
            let Some(items) = form.as_list() else {
                continue;
            };
            let sig = sigs.get(&name).expect("just inserted");
            let mut env: BTreeMap<String, Ty> = BTreeMap::new();
            if let Some(params) = items[1].as_list() {
                for (i, p) in params[1..].iter().enumerate() {
                    if let Some(pair) = p.as_list() {
                        if let Some(pn) = pair[0].as_symbol() {
                            env.insert(pn.to_string(), sig.params[i].clone());
                        }
                    }
                }
            }
            let body = &items[3];
            let body_ty = infer(body, &env, &sigs, &mut out);
            if !body_ty.accepts(&sig.ret) {
                out.diagnostics.push(Diagnostic {
                    message: format!(
                        "`{name}` declares it returns {}, but its body produces {}",
                        sig.ret.name(),
                        body_ty.name()
                    ),
                    // The BODY, not the return annotation and not the whole
                    // `def`. The annotation is a statement of intent the author
                    // meant; the body is the thing that disagrees with it, and
                    // rustc points at the tail expression for the same reason.
                    // Pointing at the whole declaration would underline a
                    // twenty-line function to report one wrong line.
                    span: body.span,
                });
            }
        }
    }

    out
}

/// Read `(define-typed (name (p T) ...) R body)`.
fn read_typed_decl(form: &Spanned) -> Option<(String, Sig)> {
    let items = form.as_list()?;
    if items.len() != 4 {
        return None;
    }
    if items[0].as_symbol()? != "define-typed" {
        return None;
    }
    let sig = items[1].as_list()?;
    let name = sig[0].as_symbol()?;
    let params = sig[1..]
        .iter()
        .map(|p| match p.as_list() {
            Some(pair) if pair.len() == 2 => Ty::from_sexp(&pair[1].to_sexp()),
            _ => Ty::Dyn,
        })
        .collect();
    Some((
        name.to_string(),
        Sig {
            params,
            ret: Ty::from_sexp(&items[2].to_sexp()),
        },
    ))
}

/// Arithmetic and comparison shapes, so operators can be checked without
/// a full trait system at this rung.
fn op_sig(op: &str) -> Option<(Ty, Ty)> {
    Some(match op {
        "+" | "-" | "*" | "/" | "%" => (Ty::Int, Ty::Int),
        "<" | "<=" | ">" | ">=" => (Ty::Int, Ty::Bool),
        "==" | "!=" => (Ty::Dyn, Ty::Bool),
        "&&" | "||" => (Ty::Bool, Ty::Bool),
        _ => return None,
    })
}

fn infer(
    s: &Spanned,
    env: &BTreeMap<String, Ty>,
    sigs: &BTreeMap<String, Sig>,
    out: &mut Outcome,
) -> Ty {
    out.stats.visited += 1;
    match &s.form {
        SpannedForm::Nil => Ty::Nil,
        SpannedForm::Atom(Atom::Int(_)) => Ty::Int,
        SpannedForm::Atom(Atom::Float(_)) => Ty::Float,
        SpannedForm::Atom(Atom::Str(_)) => Ty::Str,
        SpannedForm::Atom(Atom::Bool(_)) => Ty::Bool,
        SpannedForm::Atom(Atom::Keyword(_)) => Ty::Sym,
        SpannedForm::Atom(Atom::Symbol(n)) => env.get(n).cloned().unwrap_or(Ty::Dyn),

        SpannedForm::List(items) if items.is_empty() => Ty::Nil,

        SpannedForm::List(items) => {
            let head = match items[0].as_symbol() {
                Some(h) => h,
                None => {
                    for i in items {
                        infer(i, env, sigs, out);
                    }
                    return Ty::Dyn;
                }
            };

            // `if`
            if head == "if" && items.len() >= 3 {
                infer(&items[1], env, sigs, out);
                let t = infer(&items[2], env, sigs, out);
                if let Some(e) = items.get(3) {
                    let f = infer(e, env, sigs, out);
                    return if t.accepts(&f) { t } else { Ty::Dyn };
                }
                return Ty::Dyn;
            }

            if head == "begin" {
                let mut last = Ty::Nil;
                for i in &items[1..] {
                    last = infer(i, env, sigs, out);
                }
                return last;
            }

            // Operators
            if let Some((arg, ret)) = op_sig(head) {
                for a in &items[1..] {
                    let got = infer(a, env, sigs, out);
                    if !got.accepts(&arg) {
                        out.diagnostics.push(Diagnostic {
                            message: format!("`{head}` expects {}, got {}", arg.name(), got.name()),
                            // The OFFENDING OPERAND, not the whole operator
                            // expression. `s + 1` where `s: Str` is a complaint
                            // about `s`; underlining `s + 1` would leave the
                            // reader to work out which half is wrong, and in
                            // `a + b + c` it would underline all of it.
                            span: a.span,
                        });
                    }
                }
                return ret;
            }

            // A call to a DECLARED function: check the arguments.
            if let Some(sig) = sigs.get(head) {
                for (i, a) in items[1..].iter().enumerate() {
                    let got = infer(a, env, sigs, out);
                    let Some(want) = sig.params.get(i) else {
                        continue;
                    };
                    if got == Ty::Dyn && *want != Ty::Dyn {
                        // THE SEAM. The argument is undeclared and the
                        // callee is not. The obligation is discharged HERE
                        // with a runtime check — the checker does NOT walk
                        // into the caller to find out what it produces.
                        out.seams.push(Seam {
                            expected: want.clone(),
                            at: format!("argument {} of `{head}`", i + 1),
                            span: a.span,
                        });
                    } else if !got.accepts(want) {
                        out.diagnostics.push(Diagnostic {
                            message: format!(
                                "`{head}` argument {} expects {}, got {}",
                                i + 1,
                                want.name(),
                                got.name()
                            ),
                            span: a.span,
                        });
                    }
                }
                return sig.ret.clone();
            }

            // A call to something UNDECLARED. Walk the arguments (they may
            // contain typed sub-expressions) and yield Dyn. **We do not go
            // looking for the callee's definition** — that is the backward
            // inference the ladder forbids.
            for a in &items[1..] {
                infer(a, env, sigs, out);
            }
            Ty::Dyn
        }

        _ => Ty::Dyn,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_syntax::parse_program_tree;

    fn check(src: &str) -> Outcome {
        let forms = parse_program_tree(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        check_program(&forms)
    }

    fn msgs(o: &Outcome) -> Vec<String> {
        o.diagnostics.iter().map(|d| d.message.clone()).collect()
    }

    /// The `(line, column)` a span's start resolves to in `src`, ZERO-based —
    /// what an editor would show, and what a fixture can state by hand.
    fn line_col(src: &str, span: Span) -> (usize, usize) {
        let (l, c) = Span::line_col(src, span.start);
        (l - 1, c - 1)
    }

    /// The exact source text a span covers. Independent evidence: it is a slice
    /// of the input, computed by nothing the checker owns.
    fn text(src: &str, span: Span) -> &str {
        &src[span.start..span.end]
    }

    // ---- rung 0: ZERO analysis, measured ------------------------------

    /// §0's claim taken literally. An unannotated program is not walked
    /// and waved through — it is not walked.
    #[test]
    fn unannotated_code_is_not_analyzed_at_all() {
        let o = check("def add(a, b)\n  a + b\nend\nadd(1, \"nope\")");
        assert!(o.ok(), "rung 0 produced diagnostics: {:?}", msgs(&o));
        assert_eq!(
            o.stats.visited, 0,
            "rung 0 visited {} nodes — zero analysis means zero",
            o.stats.visited
        );
        assert_eq!(o.stats.typed_decls, 0);
    }

    #[test]
    fn a_big_unannotated_program_still_visits_nothing() {
        let src = (0..50)
            .map(|i| format!("def f{i}(a, b)\n  a + b * {i}\nend"))
            .collect::<Vec<_>>()
            .join("\n");
        let o = check(&src);
        assert_eq!(o.stats.visited, 0);
    }

    // ---- rung 1: checked, and only where declared ---------------------

    #[test]
    fn an_annotated_function_is_checked() {
        let o = check("def add(a: Int, b: Int) -> Int\n  a + b\nend");
        assert!(o.ok(), "{:?}", msgs(&o));
        assert_eq!(o.stats.typed_decls, 1);
        assert!(o.stats.visited > 0, "a typed decl must actually be walked");
    }

    #[test]
    fn a_wrong_return_type_is_reported() {
        let o = check("def f(a: Int) -> Str\n  a + 1\nend");
        assert!(!o.ok());
        assert!(msgs(&o)[0].contains("returns Str"), "{:?}", msgs(&o));
    }

    #[test]
    fn a_wrong_argument_type_is_reported() {
        let o = check(
            "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\
             def g() -> Int\n  add(1, \"two\")\nend",
        );
        assert!(!o.ok());
        assert!(
            msgs(&o).iter().any(|m| m.contains("argument 2")),
            "{:?}",
            msgs(&o)
        );
    }

    #[test]
    fn an_operator_misuse_inside_a_typed_body_is_reported() {
        let o = check("def f(s: Str) -> Int\n  s + 1\nend");
        assert!(!o.ok());
        assert!(
            msgs(&o).iter().any(|m| m.contains("expects Int")),
            "{:?}",
            msgs(&o)
        );
    }

    // ---- the seam discipline ------------------------------------------

    /// The load-bearing rule: when typed code receives something
    /// undeclared, the obligation is discharged AT THE SEAM. The checker
    /// does not chase the callee.
    #[test]
    fn an_undeclared_argument_produces_a_seam_not_an_error() {
        let o = check(
            "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\
             def g() -> Int\n  add(mystery(), 2)\nend",
        );
        assert!(
            o.ok(),
            "a dyn argument must not be an error: {:?}",
            msgs(&o)
        );
        assert_eq!(o.seams.len(), 1, "expected exactly one seam: {:?}", o.seams);
        assert_eq!(o.seams[0].expected, Ty::Int);
        assert!(o.seams[0].at.contains("argument 1"));
    }

    /// **Cost is a function of annotation density, not of the call graph.**
    /// Adding fifty unannotated functions around a typed one must not
    /// increase the work done — if it did, the ladder would not slide.
    #[test]
    fn cost_does_not_grow_with_untyped_code_around_it() {
        let typed = "def add(a: Int, b: Int) -> Int\n  a + b\nend";
        let small = check(typed);

        let noise = (0..50)
            .map(|i| format!("def n{i}(x, y)\n  x * y + {i}\nend"))
            .collect::<Vec<_>>()
            .join("\n");
        let big = check(&format!("{noise}\n{typed}\n{noise}"));

        assert_eq!(
            small.stats.visited, big.stats.visited,
            "analysis cost grew with surrounding untyped code: {} -> {}",
            small.stats.visited, big.stats.visited
        );
    }

    /// Dyn is compatible in both directions, so annotating never makes a
    /// working program stop working — the gradual guarantee's shape.
    #[test]
    fn dyn_is_compatible_in_both_directions() {
        assert!(Ty::Dyn.accepts(&Ty::Int));
        assert!(Ty::Int.accepts(&Ty::Dyn));
        let o = check("def f(a) -> Int\n  a\nend");
        assert!(o.ok(), "{:?}", msgs(&o));
    }

    /// Partial annotation is the ladder at its finest grain: one parameter
    /// checked, another left dyn, in the same signature.
    #[test]
    fn a_signature_can_be_partially_annotated() {
        let o = check(
            "def f(a: Int, b) -> Int\n  a\nend\n\
             def g() -> Int\n  f(\"bad\", 1)\nend",
        );
        assert!(
            msgs(&o).iter().any(|m| m.contains("argument 1")),
            "the annotated parameter should be checked: {:?}",
            msgs(&o)
        );
        assert!(
            !msgs(&o).iter().any(|m| m.contains("argument 2")),
            "the unannotated parameter must NOT be checked: {:?}",
            msgs(&o)
        );
    }

    // ---- anti-vacuity --------------------------------------------------

    /// The checker must be able to FAIL. If it never reported anything,
    /// every "ok" assertion above would be worthless.
    #[test]
    fn the_checker_actually_reports_errors() {
        assert!(!check("def f() -> Int\n  \"s\"\nend").ok());
        assert!(!check("def f(a: Str) -> Str\n  a + 1\nend").ok());
    }

    /// And it must be able to record a seam. A checker that produced none
    /// would pass the seam test by doing nothing.
    #[test]
    fn seams_are_actually_recorded() {
        let o = check("def f(a: Int) -> Int\n  a\nend\ndef g() -> Int\n  f(unknown())\nend");
        assert!(!o.seams.is_empty());
    }

    // ---- spans ----------------------------------------------------------
    //
    // Every assertion below states a position as a LITERAL line and column,
    // hand-counted from the fixture above it, and separately asserts the exact
    // source text the span slices out. Neither number comes from the checker, so
    // neither can agree with a wrong answer: a span off by one byte fails the
    // text assertion, and a span pointing at the wrong node fails both.
    //
    // Every fixture deliberately puts its error somewhere OTHER than line 0,
    // column 0. That was the value the LSP reported for every type error before
    // this field existed, so a gate whose fixture happens to have its error on
    // the first byte would pass against the exact bug being fixed.

    /// A return-type mismatch points at the BODY that disagrees.
    ///
    /// RED RUN (2026-08-12): `span: body.span` in `check_program` changed to
    /// `span: form.span` — the whole declaration, which is the plausible wrong
    /// answer rather than a nonsense one:
    ///
    ///   assertion `left == right` failed: the diagnostic must point at the body
    ///     left: (4, 0)
    ///    right: (5, 2)
    ///
    /// It reported the `def` keyword on line 4 instead of the body on line 5.
    #[test]
    fn a_return_type_mismatch_points_at_the_body() {
        // line 0: def ok(a: Int) -> Int
        // line 1:   a
        // line 2: end
        // line 3:
        // line 4: def bad(a: Int) -> Str
        // line 5:   a + 1        <- the body that produces Int
        // line 6: end
        let src = "def ok(a: Int) -> Int\n  a\nend\n\ndef bad(a: Int) -> Str\n  a + 1\nend\n";
        let o = check(src);
        assert_eq!(o.diagnostics.len(), 1, "{:?}", msgs(&o));

        let d = &o.diagnostics[0];
        assert_eq!(
            line_col(src, d.span),
            (5, 2),
            "the diagnostic must point at the body, got {:?} for {}",
            d.span,
            d.message
        );
        assert_eq!(
            text(src, d.span),
            "a + 1",
            "the span must cover exactly the body expression"
        );
    }

    /// An operator misuse points at the OFFENDING OPERAND, not the expression.
    ///
    /// RED RUN (2026-08-12): `span: a.span` in the `op_sig` arm changed to
    /// `span: s.span` — the enclosing operator expression, which is what a
    /// coarser implementation would report:
    ///
    ///   assertion `left == right` failed: the span must cover exactly the bad
    ///   operand
    ///     left: "s + 1"
    ///    right: "s"
    ///
    /// The line and column happened to still match, because `s` starts the
    /// expression — which is why the text assertion is here and not optional.
    #[test]
    fn an_operator_misuse_points_at_the_offending_operand() {
        // line 0: # a comment, so nothing lands on line 0 by accident
        // line 1: def wrong(s: Str) -> Int
        // line 2:   s + 1     <- `s` at column 2 is the Str where Int was wanted
        // line 3: end
        let src = "# a comment, so nothing lands on line 0 by accident\n\
                   def wrong(s: Str) -> Int\n\
                   \x20 s + 1\n\
                   end\n";
        let o = check(src);
        assert_eq!(o.diagnostics.len(), 1, "{:?}", msgs(&o));

        let d = &o.diagnostics[0];
        assert!(d.message.contains("expects Int"), "{}", d.message);
        assert_eq!(line_col(src, d.span), (2, 2), "span {:?}", d.span);
        assert_eq!(
            text(src, d.span),
            "s",
            "the span must cover exactly the bad operand"
        );
    }

    /// A wrong call argument points at THAT argument.
    #[test]
    fn a_wrong_argument_points_at_the_argument() {
        // line 0: def add(a: Int, b: Int) -> Int
        // line 1:   a + b
        // line 2: end
        // line 3:
        // line 4: def g() -> Int
        // line 5:   add(1, "two")   <- `"two"` starts at column 9
        // line 6: end
        let src = "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\n\
                   def g() -> Int\n  add(1, \"two\")\nend\n";
        let o = check(src);
        let d = o
            .diagnostics
            .iter()
            .find(|d| d.message.contains("argument 2"))
            .unwrap_or_else(|| panic!("expected an argument-2 diagnostic: {:?}", msgs(&o)));

        assert_eq!(line_col(src, d.span), (5, 9), "span {:?}", d.span);
        assert_eq!(text(src, d.span), "\"two\"");
    }

    /// A seam records WHERE the inserted check sits, not just which argument
    /// slot it guards. "argument 1 of `add`" does not say which call.
    #[test]
    fn a_seam_carries_the_span_of_the_argument_it_guards() {
        // line 0: def add(a: Int, b: Int) -> Int
        // line 1:   a + b
        // line 2: end
        // line 3:
        // line 4: def g() -> Int
        // line 5:   add(mystery(), 2)   <- `mystery()` starts at column 6
        // line 6: end
        let src = "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\n\
                   def g() -> Int\n  add(mystery(), 2)\nend\n";
        let o = check(src);
        assert!(
            o.ok(),
            "a dyn argument is a seam, not an error: {:?}",
            msgs(&o)
        );
        assert_eq!(o.seams.len(), 1, "{:?}", o.seams);

        let seam = &o.seams[0];
        assert_eq!(line_col(src, seam.span), (5, 6), "span {:?}", seam.span);
        assert_eq!(text(src, seam.span), "mystery()");
    }

    /// **No reported position is synthetic.** A synthetic span is the sentinel
    /// for "this node has no source origin", and a checker that emitted them for
    /// ordinary user code would be reporting positions no editor can use — which
    /// is the whole failure mode `Diagnostic::span` exists to close, wearing a
    /// different mask.
    ///
    /// The corpus is every diagnostic shape the checker can produce, so a new
    /// construction site that forgets its span is caught here rather than in an
    /// editor.
    ///
    /// RED RUN (2026-08-12): the corpus fed through
    /// `Spanned::from_sexp_synthetic(&parse_program(src))` instead of
    /// `parse_program_tree` — the lift a caller reaching for the spanless parse
    /// would perform:
    ///
    ///   thread 'tests::no_reported_position_is_synthetic' panicked:
    ///   `def f(a: Int) -> Str\n  a\nend` reported a synthetic span for
    ///   ``f` declares it returns Str, but its body produces Int`
    ///
    /// It trips on the first corpus entry and panics there, so the run proves
    /// the gate fires — not that every entry independently would. This is also
    /// the gate that proves the spans survive the PARSER, not merely that the
    /// field exists to be filled in.
    #[test]
    fn no_reported_position_is_synthetic() {
        let corpus = [
            "def f(a: Int) -> Str\n  a\nend",
            "def f(s: Str) -> Int\n  s + 1\nend",
            "def add(a: Int, b: Int) -> Int\n  a + b\nend\ndef g() -> Int\n  add(1, \"x\")\nend",
            "def f(a: Int) -> Int\n  a\nend\ndef g() -> Int\n  f(unknown())\nend",
            "def f(a: Int, b) -> Int\n  a\nend\ndef g() -> Int\n  f(\"bad\", 1)\nend",
        ];
        let mut diagnostics = 0;
        let mut seams = 0;
        for src in corpus {
            let o = check(src);
            for d in &o.diagnostics {
                assert!(
                    !d.span.is_synthetic(),
                    "{src:?} reported a synthetic span for `{}`",
                    d.message
                );
                assert!(
                    d.span.end <= src.len(),
                    "{src:?}: span {:?} runs past the source ({} bytes)",
                    d.span,
                    src.len()
                );
                diagnostics += 1;
            }
            for s in &o.seams {
                assert!(
                    !s.span.is_synthetic(),
                    "{src:?} seam at {} is synthetic",
                    s.at
                );
                seams += 1;
            }
        }
        // Anti-vacuity: the loop above proves nothing if the corpus reported
        // nothing. Counted, not asserted non-empty, so a corpus that silently
        // stopped producing three of four findings still fails. The count is 4
        // and not 5 because the fourth entry's `unknown()` argument is a SEAM
        // rather than an error — the count caught that when it was first written
        // as 5, which is the kind of mistake `assert!(!is_empty())` hides.
        assert_eq!(diagnostics, 4, "the corpus stopped reporting diagnostics");
        assert_eq!(seams, 1, "the corpus stopped reporting seams");
    }

    /// Correctness never moves: a program that runs must still run whether
    /// or not it is annotated. Same tree, both spellings.
    #[test]
    fn annotation_does_not_change_the_body() {
        use blue_lang_syntax::parse_program;
        let untyped = parse_program("def add(a, b)\n  a + b\nend").expect("parse");
        let typed = parse_program("def add(a: Int, b: Int) -> Int\n  a + b\nend").expect("parse");
        let body_of = |f: &Sexp| match f {
            Sexp::List(items) => items.last().cloned(),
            _ => None,
        };
        assert_eq!(
            body_of(&untyped[0]),
            body_of(&typed[0]),
            "annotating changed the body"
        );
    }
}
