//! `waku` (枠) — the frame a blue computation runs inside.
//!
//! Every mode blue has — macro phase, loose code, a typed region, a
//! process, a sealed artifact, the REPL — is *one evaluator running inside
//! a different frame*, and a frame answers exactly one question in three
//! parts: **what may this computation depend on?**
//!
//! | part | governs |
//! |---|---|
//! | [`Reach`] | what definitions may be **named** |
//! | [`When`]  | what has already been **evaluated** when it runs |
//! | [`Where`] | the **heap and the continuation** |
//!
//! The only operation is [`Waku::narrow`], **and narrow cannot widen.**
//! That is not a convention enforced by review — `narrow` takes a bound and
//! returns the meet, so the result is `⊑` both operands by construction and
//! there is no method that returns something above its receiver.
//!
//! ## Why the lattice matters, and what was open about it
//!
//! `theory/BLUE.md` §V.19 recorded "whether this forms a lattice with
//! computable meets" as OPEN and load-bearing. §V.24 closed it: **lattice-hood
//! was never at risk.** A finite product of chains and powersets is a complete
//! lattice under componentwise meet (Davey & Priestley, *Introduction to
//! Lattices and Order*, 2nd ed., ch. 2). The question that actually bites is
//! *which coordinates quantize*, and the answer is **exactly one** — [`When`]'s
//! `Q_link`-shaped bit, whether the evaluator is resident at all.
//!
//! So this module implements the product directly and property-tests the
//! lattice laws rather than assuming them.
//!
//! ## The correction §V.24 forced, and it is encoded here
//!
//! §V.19 said a package declares a **ceiling**. That is Cargo's documented
//! anti-pattern by name, and the only mechanism that *manufactures* an
//! absorbing axis out of a gradient. **Ceilings belong at the root.** So
//! [`Waku`] carries no ceiling: a frame is a *position*, and narrowing is
//! something the root does to it.

use std::collections::BTreeSet;

pub mod capability;
pub mod imports;

pub use capability::{Capability, Import, HOST_MODULE};
pub use imports::imports_of;

/// What definitions a computation may **name**.
///
/// A powerset coordinate, ordered by inclusion. `Unrestricted` is the top;
/// a `Only(set)` is below it, and two `Only`s meet by intersection.
///
/// **This is the capability surface.** A macro-phase frame whose `Reach`
/// omits [`Capability::FileSystem`] cannot *name* `read_file`, and a name that
/// does not resolve is not a policy decision made at call time — it is an
/// absent binding.
///
/// ## The set is CLOSED, and it was not always
///
/// `theory/BLUE-EXECUTION.md` M0. This carried `BTreeSet<String>` until
/// 2026-08-13, and both of that type's failures were real:
/// `Reach::only(["read-flie"])` compiled and granted nothing while reading as a
/// grant, and there was no closed set for an import table to be *total* over —
/// so the lowering could only ever have been a hand-maintained list.
/// [`Capability`] is closed, with no `Other(String)` arm, and
/// [`imports_of`] is exhaustive over it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Reach {
    /// Every name is available. The top of this coordinate.
    Unrestricted,
    /// Exactly these capabilities, and no others.
    Only(BTreeSet<Capability>),
}

impl Reach {
    pub fn only<I>(caps: I) -> Self
    where
        I: IntoIterator<Item = Capability>,
    {
        Reach::Only(caps.into_iter().collect())
    }

    /// The empty frame: nothing may be named. The bottom.
    pub fn nothing() -> Self {
        Reach::Only(BTreeSet::new())
    }

    /// Does some granted capability grant the right to name `name`?
    ///
    /// Still a question about a **name**, because that is what `check_reach`
    /// walks. Closing the type changed where the answer comes from, not what
    /// the question is.
    pub fn permits(&self, name: &str) -> bool {
        match self {
            Reach::Unrestricted => true,
            Reach::Only(caps) => caps.iter().any(|c| c.grants(name)),
        }
    }

    /// Is `self` at or below `other` in the inclusion order?
    pub fn leq(&self, other: &Reach) -> bool {
        match (self, other) {
            (_, Reach::Unrestricted) => true,
            (Reach::Unrestricted, Reach::Only(_)) => false,
            (Reach::Only(a), Reach::Only(b)) => a.is_subset(b),
        }
    }

    pub fn meet(&self, other: &Reach) -> Reach {
        match (self, other) {
            (Reach::Unrestricted, o) | (o, Reach::Unrestricted) => o.clone(),
            (Reach::Only(a), Reach::Only(b)) => Reach::Only(a.intersection(b).cloned().collect()),
        }
    }

    /// The least upper bound: union of what each side may name.
    ///
    /// This is what a set of packages jointly REQUIRE — the dual of
    /// `meet`, and the operation posture resolution runs over floors.
    pub fn join(&self, other: &Reach) -> Reach {
        match (self, other) {
            (Reach::Unrestricted, _) | (_, Reach::Unrestricted) => Reach::Unrestricted,
            (Reach::Only(a), Reach::Only(b)) => Reach::Only(a.union(b).cloned().collect()),
        }
    }
}

/// What has already been **evaluated** when this computation runs.
///
/// A chain, and the one coordinate that **quantizes**: whether an evaluator
/// is resident is a bit, not a gradient (§V.10's `Q_link`, an absorbing
/// bottom — there is no artifact that is 80 % closed).
///
/// Probe P1 in §V.14 is why this is an axis at all and not a consequence of
/// [`Reach`]: blue's two shipped entry points run *different schedules* with
/// an identical registry and environment — interleaved lets a macro call an
/// earlier top-level definition, batched does not. Same names, same
/// reachability, two different languages.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum When {
    /// Nothing may be evaluated at this point. The bottom.
    Sealed = 0,
    /// Only what preceded this form, in order. The macro phase's schedule.
    Preceding = 1,
    /// Anything, including code constructed at run time. `eval` lives here,
    /// and it is what makes the evaluator resident.
    Anytime = 2,
}

impl When {
    pub fn meet(self, other: When) -> When {
        if self <= other {
            self
        } else {
            other
        }
    }

    pub fn join(self, other: When) -> When {
        if self >= other {
            self
        } else {
            other
        }
    }

    /// Does this schedule keep the evaluator in the artifact?
    ///
    /// The quantized bit. `Anytime` requires a resident evaluator; nothing
    /// below it does.
    pub fn needs_resident_evaluator(self) -> bool {
        self == When::Anytime
    }
}

/// Where the heap and the continuation live.
///
/// A chain from most to least constrained. `Arena` is a frame-scoped bump
/// region freed whole; `Process` is a `sumika`; `Shared` may touch a
/// `kura` slab.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Where {
    /// A bump region discarded at scope exit. Nothing may escape it.
    Arena = 0,
    /// One process's own heap.
    Process = 1,
    /// May reach shared frozen data.
    Shared = 2,
}

impl Where {
    pub fn meet(self, other: Where) -> Where {
        if self <= other {
            self
        } else {
            other
        }
    }

    pub fn join(self, other: Where) -> Where {
        if self >= other {
            self
        } else {
            other
        }
    }
}

/// A frame: a point in the product lattice.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Waku {
    pub reach: Reach,
    pub when: When,
    pub place: Where,
}

impl Waku {
    /// The top: everything permitted. What an unannotated blue program
    /// runs in.
    pub fn top() -> Self {
        Self {
            reach: Reach::Unrestricted,
            when: When::Anytime,
            place: Where::Shared,
        }
    }

    /// The bottom: nothing permitted.
    pub fn bottom() -> Self {
        Self {
            reach: Reach::nothing(),
            when: When::Sealed,
            place: Where::Arena,
        }
    }

    /// The macro phase: full compute, no IO, preceding-only schedule.
    ///
    /// This is the frame that closes the measured hole. `theory/BLUE.md`
    /// §0 records that under the *shipped* `tatara-script` configuration a
    /// macro body reads the filesystem at expansion time, because expansion
    /// shares the run phase's registry — tier **ABSENT**. A frame whose
    /// `Reach` omits [`Capability::FileSystem`] makes the call unresolvable
    /// rather than merely discouraged.
    pub fn macro_phase(pure: impl IntoIterator<Item = Capability>) -> Self {
        Self {
            reach: Reach::only(pure),
            when: When::Preceding,
            place: Where::Process,
        }
    }

    /// Is `self` at or below `other` on every coordinate?
    pub fn leq(&self, other: &Waku) -> bool {
        self.reach.leq(&other.reach) && self.when <= other.when && self.place <= other.place
    }

    /// The greatest lower bound. Componentwise, which is what makes the
    /// product a lattice.
    pub fn meet(&self, other: &Waku) -> Waku {
        Waku {
            reach: self.reach.meet(&other.reach),
            when: self.when.meet(other.when),
            place: self.place.meet(other.place),
        }
    }

    /// The least upper bound. Componentwise.
    ///
    /// **This is not an operation on a running computation** — `narrow`
    /// remains the only one of those, and it cannot widen. `join` is a
    /// *resolution-time* operation over the FLOORS a set of packages
    /// declare: the smallest frame that satisfies all of them.
    pub fn join(&self, other: &Waku) -> Waku {
        Waku {
            reach: self.reach.join(&other.reach),
            when: self.when.join(other.when),
            place: self.place.join(other.place),
        }
    }

    /// **The only operation.** Narrow this frame by `bound`.
    ///
    /// Returns the meet, so the result is `⊑` both the receiver and the
    /// bound — *by construction*. There is deliberately no `widen`, and no
    /// method on `Waku` returns a frame above its receiver.
    pub fn narrow(&self, bound: &Waku) -> Waku {
        self.meet(bound)
    }

    /// Does this frame require the evaluator to be resident in the artifact?
    pub fn needs_resident_evaluator(&self) -> bool {
        self.when.needs_resident_evaluator()
    }
}

/// A name a program refers to that its frame does not permit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Escape {
    pub name: String,
}

/// Check every free name in `form` against `waku`'s [`Reach`].
///
/// Returns the names the frame does not permit, in a stable order. An
/// empty result means the program cannot *name* anything outside its
/// frame — which for the macro phase is the capability restriction that
/// name-withholding alone was measured not to provide.
///
/// **Honest tier: this is `checked-at-expansion`, not unrepresentability.**
/// It is a check over a tree, so it is only as strong as the tree it is
/// given — a program that constructs a name at run time and `eval`s it is
/// outside what this can see, which is precisely why `When::Anytime` is
/// tracked as a separate coordinate rather than folded into `Reach`.
pub fn check_reach(waku: &Waku, form: &tatara_lisp::Sexp) -> Vec<Escape> {
    check_reach_program(waku, std::slice::from_ref(form))
}

/// [`check_reach`] over a whole program: several forms sharing one scope.
///
/// **This is the surface a real gate wants, and the single-form one is the
/// special case.** A top-level `define` in form 1 is in scope for form 2, so
/// checking each form independently reports every cross-form reference as an
/// escape. That is why the only non-test caller takes this entry point.
pub fn check_reach_program(waku: &Waku, forms: &[tatara_lisp::Sexp]) -> Vec<Escape> {
    let mut found = BTreeSet::new();
    walk_body(forms, waku, &BTreeSet::new(), &mut found);
    found.into_iter().map(|name| Escape { name }).collect()
}

/// Heads that introduce bindings rather than reference them.
///
/// **A binder is not a name the frame has to permit — it is a name the
/// program itself supplies.** Before this distinction existed, `check_reach`
/// counted *every* symbol, so under any `Reach::Only` a program escaped on
/// its own function names and its own parameters: the frame in
/// `restricted_reach_still_permits_arbitrary_computation` had to name
/// `"fact"` and `"n"` to let `fact` call itself. A gate that can only be
/// pointed at `Reach::Unrestricted` without rejecting correct programs is a
/// gate nothing can use, which is exactly why this function had no caller
/// outside its own tests.
///
/// The shapes are the ones `blue-lang-syntax` emits — `(define (f a) …)`,
/// `(define x v)`, `(defmacro m (a) …)`, `(lambda (a) …)`, `(let ((x v)) …)`
/// and `(begin …)`. A head not listed here is walked as an ordinary call, so
/// an unrecognised binder over-reports rather than under-reports: it can make
/// a correct program look like an escape, never make an escape look correct.
const DEFINE: &str = "define";
const DEFMACRO: &str = "defmacro";
const LAMBDA: &str = "lambda";
const LET: &str = "let";
const BEGIN: &str = "begin";

/// Walk a sequence of forms that share one scope.
///
/// Definitions are collected across the whole sequence *before* any form is
/// walked, so mutual recursion and forward references resolve. A `define`
/// binds for the rest of its level, and the level is what this function is.
fn walk_body(
    forms: &[tatara_lisp::Sexp],
    waku: &Waku,
    outer: &BTreeSet<String>,
    out: &mut BTreeSet<String>,
) {
    let mut scope = outer.clone();
    for f in forms {
        if let Some(name) = defined_name(f) {
            scope.insert(name);
        }
    }
    for f in forms {
        walk(f, waku, &scope, out);
    }
}

/// The name `form` defines at its own level, if it defines one.
fn defined_name(form: &tatara_lisp::Sexp) -> Option<String> {
    use tatara_lisp::{Atom, Sexp};
    let Sexp::List(items) = form else {
        return None;
    };
    let Some(Sexp::Atom(Atom::Symbol(head))) = items.first() else {
        return None;
    };
    match head.as_str() {
        // `(define (f a b) …)` and `(define x v)`.
        DEFINE => match items.get(1)? {
            Sexp::List(sig) => symbol_of(sig.first()?),
            other => symbol_of(other),
        },
        // `(defmacro m (a) …)`.
        DEFMACRO => symbol_of(items.get(1)?),
        _ => None,
    }
}

fn symbol_of(s: &tatara_lisp::Sexp) -> Option<String> {
    use tatara_lisp::{Atom, Sexp};
    match s {
        Sexp::Atom(Atom::Symbol(n)) => Some(n.clone()),
        _ => None,
    }
}

/// Every symbol appearing in a parameter list, added to the callee's scope.
///
/// `&rest` is swept up along with the name it introduces. Binding the marker
/// itself is harmless — nothing references it — and the alternative is a
/// second place that has to know tatara's parameter grammar.
fn params_of(s: &tatara_lisp::Sexp, into: &mut BTreeSet<String>) {
    use tatara_lisp::Sexp;
    if let Sexp::List(items) = s {
        for i in items {
            if let Some(n) = symbol_of(i) {
                into.insert(n);
            }
        }
    }
}

fn walk(s: &tatara_lisp::Sexp, waku: &Waku, scope: &BTreeSet<String>, out: &mut BTreeSet<String>) {
    use tatara_lisp::{Atom, Sexp};
    match s {
        Sexp::Atom(Atom::Symbol(name)) => {
            if !scope.contains(name) && !waku.reach.permits(name) {
                out.insert(name.clone());
            }
        }
        Sexp::List(items) => {
            if walk_binder(items, waku, scope, out) {
                return;
            }
            for i in items {
                walk(i, waku, scope, out);
            }
        }
        Sexp::Quote(_) => {
            // Quoted data is not a reference to a binding.
        }
        Sexp::Quasiquote(inner) | Sexp::Unquote(inner) | Sexp::UnquoteSplice(inner) => {
            walk(inner, waku, scope, out)
        }
        _ => {}
    }
}

/// Walk `items` as a binding form. `false` if it is not one.
///
/// The head symbol is still walked in every arm: a special form is a `match`
/// arm in no environment, so whether `define` is a name the frame must permit
/// is a question this crate deliberately does not answer — it reports the head
/// like any other symbol and lets the frame say. Changing that is a change to
/// what `Reach` *means*, not a bug fix, and belongs with the capability
/// universe that would give it somewhere to be decided.
fn walk_binder(
    items: &[tatara_lisp::Sexp],
    waku: &Waku,
    scope: &BTreeSet<String>,
    out: &mut BTreeSet<String>,
) -> bool {
    use tatara_lisp::{Atom, Sexp};
    let Some(Sexp::Atom(Atom::Symbol(head))) = items.first() else {
        return false;
    };
    match head.as_str() {
        DEFINE if items.len() >= 3 => {
            walk(&items[0], waku, scope, out);
            let mut inner = scope.clone();
            match &items[1] {
                // `(define (f a b) body…)` — the name and the parameters.
                sig @ Sexp::List(_) => params_of(sig, &mut inner),
                // `(define x v)` — the name, so a recursive lambda sees it.
                other => {
                    if let Some(n) = symbol_of(other) {
                        inner.insert(n);
                    }
                }
            }
            walk_body(&items[2..], waku, &inner, out);
            true
        }
        DEFMACRO if items.len() >= 4 => {
            walk(&items[0], waku, scope, out);
            let mut inner = scope.clone();
            if let Some(n) = symbol_of(&items[1]) {
                inner.insert(n);
            }
            params_of(&items[2], &mut inner);
            walk_body(&items[3..], waku, &inner, out);
            true
        }
        LAMBDA if items.len() >= 3 => {
            walk(&items[0], waku, scope, out);
            let mut inner = scope.clone();
            params_of(&items[1], &mut inner);
            walk_body(&items[2..], waku, &inner, out);
            true
        }
        LET if items.len() >= 3 => {
            walk(&items[0], waku, scope, out);
            let mut inner = scope.clone();
            if let Sexp::List(bindings) = &items[1] {
                for b in bindings {
                    if let Sexp::List(pair) = b {
                        // The value is evaluated in the OUTER scope.
                        for v in pair.iter().skip(1) {
                            walk(v, waku, scope, out);
                        }
                        if let Some(n) = pair.first().and_then(symbol_of) {
                            inner.insert(n);
                        }
                    }
                }
            }
            walk_body(&items[2..], waku, &inner, out);
            true
        }
        // A sequence is one scope, so a `define` inside it binds for the rest.
        BEGIN if items.len() >= 2 => {
            walk(&items[0], waku, scope, out);
            walk_body(&items[1..], waku, scope, out);
            true
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frames() -> Vec<Waku> {
        vec![
            Waku::top(),
            Waku::bottom(),
            Waku::macro_phase([Capability::Operators, Capability::Collections]),
            // Two overlapping-but-distinct sets, so the powerset coordinate's
            // meet and join are exercised on something other than ⊤ and ⊥.
            Waku {
                reach: Reach::only([Capability::CoreForms, Capability::Operators]),
                when: When::Preceding,
                place: Where::Process,
            },
            Waku {
                reach: Reach::only([Capability::Operators, Capability::Clock]),
                when: When::Anytime,
                place: Where::Arena,
            },
            Waku {
                reach: Reach::Unrestricted,
                when: When::Sealed,
                place: Where::Shared,
            },
        ]
    }

    // ---- the lattice laws, tested rather than assumed -----------------

    #[test]
    fn meet_is_commutative() {
        for a in frames() {
            for b in frames() {
                assert_eq!(a.meet(&b), b.meet(&a), "{a:?} vs {b:?}");
            }
        }
    }

    #[test]
    fn meet_is_associative() {
        for a in frames() {
            for b in frames() {
                for c in frames() {
                    assert_eq!(
                        a.meet(&b).meet(&c),
                        a.meet(&b.meet(&c)),
                        "{a:?} {b:?} {c:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn meet_is_idempotent() {
        for a in frames() {
            assert_eq!(a.meet(&a), a);
        }
    }

    /// The meet is a genuine greatest lower bound: below both, and above
    /// anything else that is below both.
    #[test]
    fn meet_is_the_greatest_lower_bound() {
        for a in frames() {
            for b in frames() {
                let m = a.meet(&b);
                assert!(m.leq(&a), "meet not below a: {m:?} vs {a:?}");
                assert!(m.leq(&b), "meet not below b: {m:?} vs {b:?}");
                for c in frames() {
                    if c.leq(&a) && c.leq(&b) {
                        assert!(
                            c.leq(&m),
                            "{c:?} is below both but not below the meet {m:?}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn join_is_the_least_upper_bound() {
        for a in frames() {
            for b in frames() {
                let j = a.join(&b);
                assert!(a.leq(&j), "join not above a: {a:?} vs {j:?}");
                assert!(b.leq(&j), "join not above b: {b:?} vs {j:?}");
                for c in frames() {
                    if a.leq(&c) && b.leq(&c) {
                        assert!(
                            j.leq(&c),
                            "{c:?} is above both but not above the join {j:?}"
                        );
                    }
                }
            }
        }
    }

    /// Absorption ties meet and join together. If these fail, the two
    /// operations are not duals and the structure is not a lattice.
    #[test]
    fn absorption_laws_hold() {
        for a in frames() {
            for b in frames() {
                assert_eq!(a.meet(&a.join(&b)), a, "meet-absorption: {a:?} {b:?}");
                assert_eq!(a.join(&a.meet(&b)), a, "join-absorption: {a:?} {b:?}");
            }
        }
    }

    #[test]
    fn top_and_bottom_are_the_bounds() {
        for a in frames() {
            assert!(a.leq(&Waku::top()), "{a:?} not below top");
            assert!(Waku::bottom().leq(&a), "bottom not below {a:?}");
        }
    }

    // ---- narrow cannot widen ------------------------------------------

    /// **The load-bearing invariant.** Exhaustive over the frame set: no
    /// narrowing ever produces something above its receiver.
    #[test]
    fn narrow_never_widens() {
        for a in frames() {
            for b in frames() {
                let n = a.narrow(&b);
                assert!(
                    n.leq(&a),
                    "narrow widened: {a:?}.narrow({b:?}) = {n:?}, which is not below the receiver"
                );
            }
        }
    }

    #[test]
    fn narrowing_is_monotone_in_the_bound() {
        // If b ⊑ c then a.narrow(b) ⊑ a.narrow(c).
        for a in frames() {
            for b in frames() {
                for c in frames() {
                    if b.leq(&c) {
                        assert!(a.narrow(&b).leq(&a.narrow(&c)));
                    }
                }
            }
        }
    }

    #[test]
    fn narrowing_twice_is_narrowing_once_by_the_meet() {
        for a in frames() {
            for b in frames() {
                for c in frames() {
                    assert_eq!(a.narrow(&b).narrow(&c), a.narrow(&b.meet(&c)));
                }
            }
        }
    }

    /// Anti-vacuity: narrowing must actually be able to CHANGE a frame.
    /// If `narrow` were the identity every law above would hold trivially.
    #[test]
    fn narrowing_actually_narrows_something() {
        let a = Waku::top();
        let b = Waku::macro_phase([Capability::Operators]);
        assert_ne!(a.narrow(&b), a, "narrow was a no-op on the top frame");
        assert!(
            !a.leq(&a.narrow(&b)),
            "the narrowed frame should be strictly below top"
        );
    }

    // ---- the quantized coordinate --------------------------------------

    /// `When` is the one coordinate that quantizes: the evaluator is
    /// resident or it is not. There is no artifact that is 80 % closed.
    #[test]
    fn only_anytime_needs_a_resident_evaluator() {
        assert!(Waku::top().needs_resident_evaluator());
        assert!(!Waku::macro_phase([Capability::Operators]).needs_resident_evaluator());
        assert!(!Waku::bottom().needs_resident_evaluator());
    }

    /// And narrowing can only ever REMOVE the requirement, never add it —
    /// which is what makes sealing an artifact a one-way door.
    #[test]
    fn narrowing_never_adds_the_evaluator_requirement() {
        for a in frames() {
            for b in frames() {
                let n = a.narrow(&b);
                if n.needs_resident_evaluator() {
                    assert!(
                        a.needs_resident_evaluator(),
                        "narrowing ADDED an evaluator requirement: {a:?} -> {n:?}"
                    );
                }
            }
        }
    }

    // ---- the capability check -------------------------------------------

    fn parse(src: &str) -> tatara_lisp::Sexp {
        blue_lang_syntax::parse_expr(src).expect("parse")
    }

    /// The measured hole, closed at blue's level: a macro-phase frame that
    /// does not name `read-file` makes the call unresolvable.
    #[test]
    fn a_macro_frame_refuses_an_io_name() {
        let w = Waku::macro_phase([Capability::Operators, Capability::Collections]);
        let escapes = check_reach(&w, &parse("read_file(1)"));
        assert_eq!(
            escapes,
            vec![Escape {
                name: "read_file".into()
            }],
            "the IO name should have escaped the frame"
        );
    }

    #[test]
    fn a_macro_frame_permits_what_it_names() {
        let w = Waku::macro_phase([Capability::Operators, Capability::Collections]);
        assert!(check_reach(&w, &parse("1 + 2")).is_empty());
        assert!(check_reach(&w, &parse("list(1, 2)")).is_empty());
    }

    /// Full compute survives the restriction — this is the property that
    /// makes a capability-restricted macro phase usable rather than inert.
    ///
    /// **The frame names the OPERATORS and nothing else.** It used to have to
    /// name `"fact"` and `"n"` as well, because the walk counted a program's
    /// own function name and its own parameter as references it had to be
    /// permitted to make. That is what kept this function unusable outside its
    /// own tests: any real frame would have had to enumerate the program's
    /// identifiers, which the frame cannot know.
    #[test]
    fn restricted_reach_still_permits_arbitrary_computation() {
        let w = Waku::macro_phase([Capability::Operators, Capability::CoreForms]);
        let src = "def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend";
        let forms = blue_lang_syntax::parse_program(src).expect("parse");
        let escapes = check_reach_program(&w, &forms);
        assert!(
            escapes.is_empty(),
            "a pure recursive function escaped a restricted frame: {escapes:?}"
        );
    }

    /// A local binding is in scope for the rest of its sequence.
    ///
    /// `c = a + b` lowers to a `define` inside the function's `begin`, so a
    /// walk that does not treat a sequence as one scope reports `c` as an
    /// escape at its own use site.
    #[test]
    fn a_local_binding_is_not_an_escape() {
        let w = Waku::macro_phase([Capability::Operators, Capability::CoreForms]);
        let src = "def f(a, b)\n  c = a + b\n  c * 2\nend";
        let forms = blue_lang_syntax::parse_program(src).expect("parse");
        let escapes = check_reach_program(&w, &forms);
        assert!(escapes.is_empty(), "got {escapes:?}");
    }

    /// A top-level definition is in scope for a LATER top-level form — which
    /// is only visible to a program-level walk, and is why the gate uses one.
    #[test]
    fn a_definition_reaches_a_later_form() {
        let w = Waku::macro_phase([Capability::CoreForms]);
        let forms = blue_lang_syntax::parse_program("def g()\n  1\nend\ng()").expect("parse");
        assert!(
            check_reach_program(&w, &forms).is_empty(),
            "got {:?}",
            check_reach_program(&w, &forms)
        );
        // …and checking the forms one at a time cannot see it. Recorded so the
        // program-level entry point is not "tidier", it is load-bearing.
        let alone = check_reach(&w, &forms[1]);
        assert_eq!(alone.len(), 1, "got {alone:?}");
        assert_eq!(alone[0].name, "g");
    }

    /// Anti-vacuity for the binder work: scoping must not swallow a name the
    /// program never bound. `read_file` is free in exactly the same position
    /// `fact` is bound in, and only one of them escapes.
    #[test]
    fn a_free_name_inside_a_binder_still_escapes() {
        let w = Waku::macro_phase([Capability::Operators, Capability::CoreForms]);
        let src = "def f(n)\n  read_file(n)\nend";
        let forms = blue_lang_syntax::parse_program(src).expect("parse");
        let names: Vec<String> = check_reach_program(&w, &forms)
            .into_iter()
            .map(|e| e.name)
            .collect();
        assert_eq!(names, vec!["read_file".to_string()], "got {names:?}");
    }

    #[test]
    fn the_top_frame_permits_everything() {
        assert!(check_reach(&Waku::top(), &parse("read_file(x)")).is_empty());
    }

    /// Anti-vacuity: the check must be able to FIND something. A checker
    /// that always returned empty would pass every test above.
    #[test]
    fn the_bottom_frame_refuses_every_name() {
        let escapes = check_reach(&Waku::bottom(), &parse("a + b"));
        let names: Vec<&str> = escapes.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"a"), "got {names:?}");
        assert!(names.contains(&"b"), "got {names:?}");
        assert!(names.contains(&"+"), "got {names:?}");
    }

    #[test]
    fn quoted_data_is_not_a_reference() {
        // A quoted symbol is data, not a binding it must be able to name.
        let w = Waku::macro_phase(Vec::<Capability>::new());
        let quoted = tatara_lisp::Sexp::Quote(Box::new(parse("anything")));
        assert!(check_reach(&w, &quoted).is_empty());
    }
}
