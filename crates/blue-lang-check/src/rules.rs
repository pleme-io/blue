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
        witness: "use(\"kagi_a\")\nuse(\"kagi_b\")\n\nkagi()\n",
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
