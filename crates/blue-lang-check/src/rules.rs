//! The rule registry: every diagnostic blue's check stage can produce, in one
//! table.
//!
//! **An architecture rule is a pipeline error, and lint is a view over it.**
//! Each row is a rule the check stage enforces. `blue run`, `blue test`,
//! `blue check` and every bidama build pass through that stage, so an
//! error-severity rule is a program that cannot run or build, never an optional
//! report. `blue explain CODE` prints a row; a future `blue lint` lists and
//! fixes over these same rows rather than keeping a second checker.
//!
//! A row carries:
//!
//! | field | what it is |
//! |---|---|
//! | `code` | the stable identifier, `B` + four digits. Never reused, never renumbered |
//! | `slug` | a kebab-case name for the same rule, for prose and `--format json` readers |
//! | `severity` | `Error` blocks the pipeline; `Warning` is reported and does not |
//! | `law` | the rule in one line |
//! | `explanation` | what `blue explain` prints: why the rule exists and how to comply |
//! | `witness` | a blue program that violates the rule, and nothing else |
//! | `imports` | bidamas the witness `use`s, as `(name, source)`, when the rule needs more than one file |
//! | `fix` | whether the rule offers a machine-applicable fix |
//! | `waivable` | whether `# waive CODE:` may silence it. Only a rule whose violating program still has exactly one meaning is waivable: a waiver silences a check and must never change what a program means |
//! | `ratchet` | `None` for a rule that has always held. `Some(n)` for a rule the corpus is being brought to: it is computed on every program, and reported (so enforced) only once `n` is 0; until then the census (`blue census`, `checks.namespace-census`) fails unless the corpus measures exactly `n` |
//!
//! **The ratchet is how a rule becomes an error without a switch.** A rule
//! enters the pipeline in the commit where its measured count reaches zero
//! and its row becomes `Some(0)`; nothing else activates it. Every change to
//! the count is a reviewed edit of the number. That it only goes down is
//! review-caught, not unrepresentable.
//!
//! **The witness is the red run, kept.** `every_rule_fires_on_its_witness`
//! (in `blue-lang-runtime`, where the whole check stage exists) runs each
//! witness through the pipeline and fails unless exactly that code comes out,
//! so a row cannot be added without a program that proves it can fire, and a
//! rule whose implementation stops firing turns its own row red.
//!
//! Adding a rule is one row in [`rules!`]. The macro generates [`Code`], its
//! `ALL` list and [`RULES`] from the same row, so a code without an
//! explanation, a severity or a witness does not compile.

use std::fmt;

/// How much a diagnostic stops.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Severity {
    /// The program is rejected: it does not run, test or build.
    Error,
    /// Reported; the program still runs.
    Warning,
}

impl Severity {
    /// The lowercase word, as `--format json` and the text output spell it.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Severity::Error => "error",
            Severity::Warning => "warning",
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.label())
    }
}

/// Whether a rule can repair what it reports.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FixKind {
    /// No fix is offered.
    None,
    /// Suggestions only (`maybe-incorrect`); `blue check --fix` leaves them.
    Suggested,
    /// A fix that preserves meaning, which `blue check --fix` applies.
    Machine,
}

/// One row of the registry.
#[derive(Clone, Copy, Debug)]
pub struct Rule {
    pub code: Code,
    pub slug: &'static str,
    pub severity: Severity,
    pub law: &'static str,
    pub explanation: &'static str,
    pub witness: &'static str,
    pub imports: &'static [(&'static str, &'static str)],
    pub fix: FixKind,
    pub waivable: bool,
    pub ratchet: Option<u32>,
}

impl Rule {
    /// Is the rule enforced — reported by the check stage, so a violation
    /// cannot run or build? Always, once its census has reached zero.
    #[must_use]
    pub const fn active(&self) -> bool {
        match self.ratchet {
            None | Some(0) => true,
            Some(_) => false,
        }
    }
}

/// A row's `waivable`, `true` when unstated: the pre-namespace rules are.
macro_rules! waivable {
    () => {
        true
    };
    ($w:literal) => {
        $w
    };
}

/// A row's `ratchet`, `None` when unstated.
macro_rules! ratchet {
    () => {
        None
    };
    ($r:expr) => {
        Some($r)
    };
}

/// Build [`Code`], `Code::ALL` and [`RULES`] from one list of rows.
macro_rules! rules {
    ($(
        $code:ident {
            slug: $slug:literal,
            severity: $sev:ident,
            fix: $fix:ident,
            law: $law:literal,
            witness: $witness:literal,
            $(imports: [$(($pkg:literal, $src:literal)),* $(,)?],)?
            $(waivable: $waivable:literal,)?
            $(ratchet: $ratchet:expr,)?
            explanation: $expl:literal $(,)?
        }
    )*) => {
        /// A stable diagnostic code. See [`RULES`] for what each one means.
        #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub enum Code { $($code),* }

        impl Code {
            /// Every code, in registry order.
            pub const ALL: &'static [Code] = &[$(Code::$code),*];

            /// The code as written: `B0001`.
            #[must_use]
            pub const fn as_str(self) -> &'static str {
                match self { $(Code::$code => stringify!($code)),* }
            }
        }

        /// The registry, in code order.
        pub const RULES: &[Rule] = &[$(
            Rule {
                code: Code::$code,
                slug: $slug,
                severity: Severity::$sev,
                law: $law,
                explanation: $expl,
                witness: $witness,
                imports: &[$($(($pkg, $src)),*)?],
                fix: FixKind::$fix,
                waivable: waivable!($($waivable)?),
                ratchet: ratchet!($($ratchet)?),
            }
        ),*];
    };
}

rules! {
    B0001 {
        slug: "unbound-name",
        severity: Error,
        fix: Suggested,
        law: "every name a program uses is bound: a local, a parameter, a definition, an imported bidama's definition, or a builtin",
        witness: "def f(xs)\n  lenght(xs)\nend\n",
        explanation: "\
A name is resolved against the scopes in front of it, innermost first: the
enclosing function's locals and parameters, then the file's own definitions,
then every imported bidama's definitions, then blue's builtins, macros and
special forms. A name found in none of them is unbound.

The check runs on every path through the program, including functions that
never run, so a typo in an error branch is reported before the branch is
taken. The suggestions are the in-scope names nearest by edit distance; each
names the scope it comes from. They are suggestions, not fixes: the nearest
name is not always the one you meant.

To comply, correct the spelling, bind the name, or `use` the bidama that
defines it.",
    }
    B0002 {
        slug: "unused-binding",
        severity: Warning,
        fix: Machine,
        law: "a local binding is read at least once, or its name starts with `_`",
        witness: "def f(x)\n  y = x + 1\n  x\nend\n",
        explanation: "\
A parameter, an assignment inside a function, or a binding introduced by a
`case`, which nothing reads. It is a warning, not an error: an unused binding
does not change what a program computes.

The fix renames the binding to `_name`, which says the value is deliberately
ignored and silences the warning. The fix is machine-applicable because no
reference reads the old name, so renaming the binder changes nothing else.
Deleting the binding instead is not offered, because its value may have side
effects.",
    }
    B0003 {
        slug: "return-type-mismatch",
        severity: Error,
        fix: None,
        law: "a typed definition's body produces the type its signature declares",
        witness: "def f(a: Int) -> Str\n  a + 1\nend\n",
        explanation: "\
A `def` with a return annotation (`-> Str`) promises a value of that type. The
body's type is inferred from literals, operators, annotated parameters and
calls to other typed definitions; `dyn` is compatible with everything. The
diagnostic points at the body, which is the part that disagrees.

To comply, change the body or the annotation. Removing the annotation removes
the check: untyped code is not analysed at all.",
    }
    B0004 {
        slug: "operand-type-mismatch",
        severity: Error,
        fix: None,
        law: "an operator inside a typed definition receives operands of the type it takes",
        witness: "def f(s: Str) -> Int\n  s + 1\nend\n",
        explanation: "\
Arithmetic operators take `Int`, comparisons `<` `<=` `>` `>=` take `Int`, and
`&&` `||` take `Bool`. Inside a typed definition an operand whose type is
known and different is reported at the operand itself.",
    }
    B0005 {
        slug: "argument-type-mismatch",
        severity: Error,
        fix: None,
        law: "a call to a typed definition passes arguments of the declared parameter types",
        witness: "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\ndef g() -> Int\n  add(1, \"two\")\nend\n",
        explanation: "\
A call to a definition whose parameters are annotated has each argument
checked against its parameter. An argument whose type is unknown (`dyn`) is
not an error: it becomes a seam, a runtime check at that point, which
`blue check` lists.",
    }
    B0006 {
        slug: "syntax-error",
        severity: Error,
        fix: None,
        law: "a file parses",
        witness: "def f(\n",
        explanation: "\
The parser could not read the file. The position is where it stopped, which is
at or after the mistake. Blue has no postfix index (`xs[0]`; use `nth(0, xs)`),
no command calls (`f x`; write `f(x)`), no blocks (`do |x|`; use `fn(x) … end`)
and no keyword arguments.",
    }
    B0007 {
        slug: "malformed-waiver",
        severity: Error,
        fix: None,
        law: "a waiver names a known code and gives a reason: `# waive B0001: <reason>`",
        witness: "# waive B0001\ndef f()\n  1\nend\n",
        explanation: "\
A waiver is a comment on its own line directly above a top-level definition:

    # waive B0002: the parameter is part of a callback's fixed shape
    def on_event(event, ctx)
      ...

It suppresses that one code inside that one definition, and nothing else.
There is no file-wide or global waiver. A waiver must name a code from the
registry (`blue explain --list`) and give a reason after the colon; one that
does not is itself an error, because a waiver nobody can read is a silent
exception.",
    }
    B0008 {
        slug: "unused-waiver",
        severity: Warning,
        fix: None,
        law: "a waiver suppresses at least one diagnostic",
        witness: "# waive B0001: nothing here is unbound\ndef f()\n  1\nend\n",
        explanation: "\
A waiver whose definition no longer produces the waived code. Delete it: a
stale waiver would silently cover the next real violation of that rule.",
    }
    B0009 {
        slug: "ambiguous-name",
        severity: Error,
        fix: None,
        law: "a name resolves to one definition: no two namespaces in the same resolution tier define it",
        witness: "use(\"kagi_a\", [:kagi])\nuse(\"kagi_b\", [:kagi])\n\nkagi()\n",
        imports: [
            ("kagi_a", "def kagi()\n  1\nend\n"),
            ("kagi_b", "def kagi()\n  2\nend\n"),
        ],
        explanation: "\
Names resolve by tier: locals, then the referencing file's (or bidama's) own
definitions, then every other imported definition, then builtins. The first
tier holding the name wins. When two namespaces in that tier both define it —
two imported bidamas that each define `kagi` — nothing in the program says
which is meant, and today the one loaded last would silently win.

To comply, rename one of the definitions. (The bidama distribution's
collision gate already forbids this among its own packages.)",
    }
    B0010 {
        slug: "qualifier-not-imported",
        severity: Error,
        fix: None,
        law: "a qualified name's package is one the file `use`s: `retsu::first` needs `use(\"retsu\")`",
        witness: "def f(xs)\n  retsu::first(xs)\nend\n",
        explanation: "\
`retsu::first` names the definition `first` of the bidama `retsu`, exactly.
The qualifier must be a bidama the file declares with `use(\"retsu\")`
(and, inside a bidama, `needs(\"retsu\", …)` in its Bluefile): a file
reaches only what it says it depends on, so no reference can work by the
accident of some other file having loaded the package.

To comply, add the `use` — or, if a builtin was meant, write `blue::first`.",
    }
    B0011 {
        slug: "no-such-definition",
        severity: Error,
        fix: Suggested,
        law: "a qualified name, or a name a `use` lists, is a definition of that package",
        witness: "use(\"kagi_a\")\n\nkagi_a::kagj()\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        explanation: "\
`kazu::first(xs)` says the definition is kazu's. When kazu defines no
`first`, that is a mistake in the program, not something to fall back from:
the qualifier is exact, and nothing else is consulted. The same holds for
`use(\"kazu\", [:first])`, which lists `first` as kazu's.

The help names the bidama that does define it, if one is loaded, and the
nearest names the qualified bidama has. `blue::name` names a builtin, and
is checked against the interpreter's own names.",
    }
    B0012 {
        slug: "implicit-reference",
        severity: Error,
        fix: Machine,
        law: "a bare name that is another bidama's definition is one the file lists: `use(\"retsu\", [:first])`, or written `retsu::first`",
        witness: "use(\"kagi_a\")\n\nkagi()\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
Today every definition of every loaded bidama lands in one global
environment, so a bare `first` reaches retsu's `first` from any file that
something loaded retsu into, including through a dependency's dependency.
Per-bidama namespaces bind a bare name to the file's own definitions, then
the names its `use` forms list, then builtins, so that same `first` would
quietly become the builtin. This rule finds every such reference before
that can happen.

The fix writes `retsu::first` when the file already `use`s retsu. Otherwise
add `use(\"retsu\", [:first])` (and, inside a bidama, `needs(\"retsu\", …)`
to its Bluefile). `blue migrate` makes every reference in a file explicit at
once, and proves the program's meaning unchanged.",
    }
    B0013 {
        slug: "prefixed-definition",
        severity: Error,
        fix: None,
        law: "a bidama's definition does not spell its bidama: `def parse` in `moji`, never `def moji_parse`",
        witness: "use(\"kagi\")\n\nkagi::kagi_x()\n",
        imports: [("kagi", "def kagi_x()\n  1\nend\n")],
        ratchet: 2,
        explanation: "\
The bidama is the namespace: callers write `moji::parse`, so `moji_parse`
says the package twice. The prefix was how blue's single namespace kept two
packages from colliding; with per-bidama namespaces it only makes names
longer.

To comply, strip the prefix and rewrite every caller (`blue migrate`). A
name that cannot lose its prefix (the stripped name is a reserved word or a
builtin the package itself uses) keeps it under a waiver saying so.",
    }
    B0014 {
        slug: "mangled-namespace",
        severity: Error,
        fix: None,
        law: "a bidama does not prefix nine in ten of its definitions with one short `x_`",
        witness: "use(\"mangled\")\n\nmangled::mg_a()\n",
        imports: [(
            "mangled",
            "def mg_a()\n  1\nend\n\ndef mg_b()\n  1\nend\n\ndef mg_c()\n  1\nend\n\ndef mg_d()\n  1\nend\n\ndef mg_e()\n  1\nend\n\ndef mg_f()\n  1\nend\n\ndef mg_g()\n  1\nend\n\ndef mg_h()\n  1\nend\n"
        )],
        ratchet: 13,
        explanation: "\
A bidama whose definitions are nearly all `q_…`, `lc_…` or `kj_…` has
built a namespace by hand, which per-bidama namespaces make unnecessary:
`kueri::join` rather than `q_join`. The threshold (eight or more
definitions, 90% sharing one prefix of one to four letters) is calibrated on
blue's own distribution, where it finds exactly the 13 hand-prefixed
bidamas; the next highest share is 60%.

To comply, strip the prefix with `blue migrate` and declare the old
spelling with `legacy_names`, so callers keep working while they move.",
    }
    B0015 {
        slug: "non-canonical-import",
        severity: Error,
        fix: Machine,
        law: "a file's `use` forms come first, one per package, sorted by package, each list sorted",
        witness: "use(\"kagi_b\")\nuse(\"kagi_a\")\n\nkagi_a::kagi()\nkagi_b::kagi()\n",
        imports: [
            ("kagi_a", "def kagi()\n  1\nend\n"),
            ("kagi_b", "def kagi()\n  2\nend\n"),
        ],
        ratchet: 0,
        explanation: "\
Once names are qualified or listed, where a `use` sits in a file no longer
changes what the file means, so there is one way to write the imports: every
`use` before the first other form, at most one per package, sorted by
package, and each list of names sorted without repeats. `use(\"x\", [])`
lists nothing and is written `use(\"x\")`.

Sorting a list is a machine-applicable fix. Moving a `use` is left to the
author: while one global environment holds every definition, the order in
which packages load can decide which of two same-named definitions wins.",
    }
    B0016 {
        slug: "unused-import",
        severity: Error,
        fix: None,
        law: "every `use` is reached by something in the file, and every name it lists is read",
        witness: "use(\"kagi_a\")\n\n1\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        ratchet: 8,
        explanation: "\
A `use` nothing in the file reaches, or a listed name the file never reads,
is a dependency the program does not have. Remove it. Inside a bidama,
remove the matching `needs` from its Bluefile too (B0019 says so).

A facade that exists to depend on other packages says so with a waiver.",
    }
    B0017 {
        slug: "duplicate-definition",
        severity: Error,
        fix: None,
        law: "a namespace defines a function or macro once",
        witness: "def f()\n  1\nend\n\ndef f()\n  2\nend\n",
        waivable: false,
        ratchet: 0,
        explanation: "\
Two `def f` in one namespace: the one evaluated last silently replaces the
other, so the program means whichever the author did not look at. Rename
one. A value may be rebound at the top level (`total = total + 1` in a
script); a function is defined once.",
    }
    B0018 {
        slug: "redundant-qualifier",
        severity: Error,
        fix: Machine,
        law: "a qualifier changes what its name means: not a bidama's own definition, not a listed name, not a builtin already reached bare",
        witness: "blue::length([1])\n",
        waivable: false,
        ratchet: 0,
        explanation: "\
`moji::split` inside moji, `retsu::first` in a file that lists `first` from
retsu, and `blue::length` where nothing else defines `length` all mean
exactly their bare name. One way to write a thing: the fix strips the
qualifier.",
    }
    B0019 {
        slug: "needs-mismatch",
        severity: Error,
        fix: None,
        law: "the bidamas a bidama `use`s are exactly the ones its Bluefile `needs`",
        witness: "use(\"kagi_b\")\n\nkagi_b::kagi()\n",
        imports: [
            ("kagi_a", "def kagi()\n  1\nend\n"),
            ("kagi_b", "use(\"kagi_a\")\n\ndef kagi()\n  kagi_a::kagi()\nend\n"),
        ],
        waivable: false,
        ratchet: 0,
        explanation: "\
`needs` is what nix builds a bidama against; `use` is what its code reaches.
A `use` with no `needs` compiles here and fails in the sandbox, where the
package is absent; a `needs` with no `use` is a dependency nothing uses.
Edit the Bluefile, then run `blue lock <dir>`.",
    }
    B0020 {
        slug: "package-as-value",
        severity: Error,
        fix: None,
        law: "a bidama's name is written as a qualifier, `retsu::first(xs)`, never as a value",
        witness: "use(\"kagi_a\")\n\nkagi_a::kagi() + kagi_a / 2\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
`retsu.first(xs)` is a send to a value named `retsu`, and `retsu/first` is a
division; neither names retsu's `first`. blue qualifies with `::`:
`retsu::first(xs)`.",
    }
}

impl Code {
    /// This code's registry row.
    #[must_use]
    pub fn rule(self) -> &'static Rule {
        RULES
            .iter()
            .find(|r| r.code == self)
            .expect("rules! builds one row per code")
    }

    /// The severity a diagnostic with this code carries.
    #[must_use]
    pub fn severity(self) -> Severity {
        self.rule().severity
    }

    /// Parse `B0001`. `None` for anything not in the registry.
    #[must_use]
    pub fn parse(s: &str) -> Option<Code> {
        Code::ALL.iter().copied().find(|c| c.as_str() == s)
    }
}

impl fmt::Display for Code {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// A rule rendered as `blue explain` prints it.
pub struct Explain<'a>(pub &'a Rule);

impl fmt::Display for Explain<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let r = self.0;
        writeln!(f, "{} {} ({})", r.code, r.slug, r.severity)?;
        writeln!(f)?;
        writeln!(f, "Law: {}", r.law)?;
        writeln!(f)?;
        writeln!(f, "{}", r.explanation)?;
        writeln!(f)?;
        writeln!(f, "Example that violates it:")?;
        writeln!(f)?;
        for line in r.witness.lines() {
            writeln!(f, "    {line}")?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// **Every code has an explanation, a law, a slug and a witness.** The
    /// macro makes each field syntactically required; this makes each one
    /// non-empty, which the macro cannot.
    ///
    /// Red run (2026-09-29): B0008's `explanation` set to `"   "`:
    /// `B0008 has an empty explanation`.
    #[test]
    fn every_code_has_an_explanation() {
        for r in RULES {
            assert!(
                !r.explanation.trim().is_empty(),
                "{} has an empty explanation",
                r.code
            );
            assert!(!r.law.trim().is_empty(), "{} has an empty law", r.code);
            assert!(!r.witness.trim().is_empty(), "{} has no witness", r.code);
            assert!(
                r.slug.chars().all(|c| c.is_ascii_lowercase() || c == '-'),
                "{} slug `{}` is not kebab-case",
                r.code,
                r.slug
            );
        }
    }

    /// Codes are unique, ordered, and spelled `B` + four digits, so a reader
    /// can sort them and a new one has an obvious next number.
    #[test]
    fn codes_are_unique_ordered_and_well_formed() {
        let names: Vec<&str> = Code::ALL.iter().map(|c| c.as_str()).collect();
        let mut sorted = names.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(names, sorted, "codes must be unique and in order");
        for n in names {
            assert!(
                n.len() == 5 && n.starts_with('B') && n[1..].chars().all(|c| c.is_ascii_digit()),
                "`{n}` is not B + four digits"
            );
            assert_eq!(Code::parse(n).map(Code::as_str), Some(n));
        }
        assert_eq!(RULES.len(), Code::ALL.len());
    }

    #[test]
    fn an_unknown_code_does_not_parse() {
        assert_eq!(Code::parse("B9999"), None);
        assert_eq!(Code::parse("b0001"), None);
    }
}
