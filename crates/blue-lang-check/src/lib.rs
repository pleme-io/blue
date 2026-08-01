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

use tatara_lisp::{Atom, Sexp};

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
pub fn check_program(forms: &[Sexp]) -> Outcome {
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
            let Sexp::List(items) = form else { continue };
            let sig = sigs.get(&name).expect("just inserted");
            let mut env: BTreeMap<String, Ty> = BTreeMap::new();
            if let Sexp::List(params) = &items[1] {
                for (i, p) in params[1..].iter().enumerate() {
                    if let Sexp::List(pair) = p {
                        if let Sexp::Atom(Atom::Symbol(pn)) = &pair[0] {
                            env.insert(pn.clone(), sig.params[i].clone());
                        }
                    }
                }
            }
            let body_ty = infer(&items[3], &env, &sigs, &mut out);
            if !body_ty.accepts(&sig.ret) {
                out.diagnostics.push(Diagnostic {
                    message: format!(
                        "`{name}` declares it returns {}, but its body produces {}",
                        sig.ret.name(),
                        body_ty.name()
                    ),
                });
            }
        }
    }

    out
}

/// Read `(define-typed (name (p T) ...) R body)`.
fn read_typed_decl(form: &Sexp) -> Option<(String, Sig)> {
    let Sexp::List(items) = form else { return None };
    if items.len() != 4 {
        return None;
    }
    let Sexp::Atom(Atom::Symbol(head)) = &items[0] else {
        return None;
    };
    if head != "define-typed" {
        return None;
    }
    let Sexp::List(sig) = &items[1] else { return None };
    let Sexp::Atom(Atom::Symbol(name)) = &sig[0] else {
        return None;
    };
    let params = sig[1..]
        .iter()
        .map(|p| match p {
            Sexp::List(pair) if pair.len() == 2 => Ty::from_sexp(&pair[1]),
            _ => Ty::Dyn,
        })
        .collect();
    Some((
        name.clone(),
        Sig {
            params,
            ret: Ty::from_sexp(&items[2]),
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
    s: &Sexp,
    env: &BTreeMap<String, Ty>,
    sigs: &BTreeMap<String, Sig>,
    out: &mut Outcome,
) -> Ty {
    out.stats.visited += 1;
    match s {
        Sexp::Nil => Ty::Nil,
        Sexp::Atom(Atom::Int(_)) => Ty::Int,
        Sexp::Atom(Atom::Float(_)) => Ty::Float,
        Sexp::Atom(Atom::Str(_)) => Ty::Str,
        Sexp::Atom(Atom::Bool(_)) => Ty::Bool,
        Sexp::Atom(Atom::Keyword(_)) => Ty::Sym,
        Sexp::Atom(Atom::Symbol(n)) => env.get(n).cloned().unwrap_or(Ty::Dyn),

        Sexp::List(items) if items.is_empty() => Ty::Nil,

        Sexp::List(items) => {
            let head = match &items[0] {
                Sexp::Atom(Atom::Symbol(h)) => h.as_str(),
                _ => {
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
                            message: format!(
                                "`{head}` expects {}, got {}",
                                arg.name(),
                                got.name()
                            ),
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
                        });
                    } else if !got.accepts(want) {
                        out.diagnostics.push(Diagnostic {
                            message: format!(
                                "`{head}` argument {} expects {}, got {}",
                                i + 1,
                                want.name(),
                                got.name()
                            ),
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
    use blue_lang_syntax::parse_program;

    fn check(src: &str) -> Outcome {
        let forms = parse_program(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        check_program(&forms)
    }

    fn msgs(o: &Outcome) -> Vec<String> {
        o.diagnostics.iter().map(|d| d.message.clone()).collect()
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
        assert!(msgs(&o).iter().any(|m| m.contains("expects Int")), "{:?}", msgs(&o));
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
        assert!(o.ok(), "a dyn argument must not be an error: {:?}", msgs(&o));
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
        let o = check(
            "def f(a: Int) -> Int\n  a\nend\ndef g() -> Int\n  f(unknown())\nend",
        );
        assert!(!o.seams.is_empty());
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
