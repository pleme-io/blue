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
    pub frontend: Option<&'static str>,
    /// The bidama the witness is the source of, when the rule judges a
    /// bidama's own file (the documentation rules): the witness is checked as
    /// `<package>.b` of that bidama.
    pub package: Option<&'static str>,
    /// A program the machine-applicable fix a `Suggested` rule carries for
    /// part of its class repairs: `blue check --fix` applies it, and the
    /// rule no longer fires on the result.
    pub fixes: Option<&'static str>,
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

macro_rules! frontend {
    () => {
        None
    };
    ($t:literal) => {
        Some($t)
    };
}

macro_rules! package {
    () => {
        None
    };
    ($t:literal) => {
        Some($t)
    };
}

macro_rules! fixes {
    () => {
        None
    };
    ($t:literal) => {
        Some($t)
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
            $(frontend: $frontend:literal,)?
            $(package: $package:literal,)?
            $(fixes: $fixes:literal,)?
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
                frontend: frontend!($($frontend)?),
                package: package!($($package)?),
                fixes: fixes!($($fixes)?),
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
        waivable: false,
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
        law: "a waiver names a known, waivable code and gives a reason: `# waive B0002: <reason>`",
        witness: "# waive B0001\ndef f()\n  1\nend\n",
        waivable: false,
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
        severity: Error,
        fix: None,
        law: "a waiver suppresses at least one diagnostic",
        witness: "# waive B0001: nothing here is unbound\ndef f()\n  1\nend\n",
        explanation: "\
A waiver whose definition no longer produces the waived code. Delete it: a
stale waiver would silently cover the next real violation of that rule, so
it is an error, not a note.",
    }
    B0009 {
        slug: "ambiguous-name",
        severity: Error,
        fix: None,
        law: "a name resolves to one definition: no two namespaces in the same resolution tier define it",
        witness: "use(\"kagi_a\", [:kagi])\nuse(\"kagi_b\", [:kagi])\n\nkagi\n",
        imports: [
            ("kagi_a", "def kagi()\n  1\nend\n"),
            ("kagi_b", "def kagi()\n  2\nend\n"),
        ],
        waivable: false,
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
        fix: Machine,
        law: "a qualified name's package is one the file `use`s: `retsu::first` needs `use(\"retsu\")`",
        witness: "def f(xs)\n  retsu::first(xs)\nend\n",
        waivable: false,
        explanation: "\
`retsu::first` names the definition `first` of the bidama `retsu`, exactly.
The qualifier must be a bidama the file declares with `use(\"retsu\")`
(and, inside a bidama, `needs(\"retsu\", …)` in its Bluefile): a file
reaches only what it says it depends on, so no reference can work by the
accident of some other file having loaded the package.

To comply, add the `use` — or, if a builtin was meant, write `blue::first`.
In a script whose program has loaded the bidama, `blue check --fix` adds
`use(\"retsu\")` for you; inside a bidama the Bluefile's `needs` is yours to
write.",
    }
    B0011 {
        slug: "no-such-definition",
        severity: Error,
        fix: Suggested,
        law: "a qualified name, or a name a `use` lists, is a definition of that package",
        witness: "use(\"kagi_a\")\n\nkagi_a::kagj()\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        waivable: false,
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
        witness: "use(\"kagi_a\")\n\nkagi\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
Each bidama is a namespace: a bare name binds to the file's own
definitions, then the names its `use` forms list, then builtins. Under the
flat runtime before 2026-09-29, a bare `first` reached retsu's `first` from
any file that something loaded retsu into. This rule finds the references
whose meaning that change moves:

- a bare name another bidama defines that binds to nothing here (it was
  reached only through a load), always;
- a bare name that binds to a builtin, only when the defining bidama lists
  it as flat-era, `legacy_names(\"0.1.0\", [:first])`, and its version is
  inside that window. A definition not listed never changes an importer's
  bare call: the builtin answers, and nothing is refused.

The fix writes `retsu::first` when the file already `use`s retsu. When it does
not, and the file is a script, `blue check --fix` adds one `use(\"retsu\",
[:first, :last])` listing every name the file reaches that way. Otherwise
add `use(\"retsu\", [:first])` (and, inside a bidama, `needs(\"retsu\", …)`
to its Bluefile). `blue migrate` makes every reference in a file explicit at
once, and proves the program's meaning unchanged.",
    }
    B0013 {
        slug: "prefixed-definition",
        severity: Error,
        fix: None,
        law: "a bidama's definition does not spell its bidama: `def parse` in `moji`, never `def moji_parse`",
        witness: "use(\"kagi\")\n\nkagi::kagi_x\n",
        imports: [("kagi", "def kagi_x()\n  1\nend\n")],
        ratchet: 0,
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
        witness: "use(\"mangled\")\n\nmangled::mg_a\n",
        imports: [(
            "mangled",
            "def mg_a()\n  1\nend\n\ndef mg_b()\n  1\nend\n\ndef mg_c()\n  1\nend\n\ndef mg_d()\n  1\nend\n\ndef mg_e()\n  1\nend\n\ndef mg_f()\n  1\nend\n\ndef mg_g()\n  1\nend\n\ndef mg_h()\n  1\nend\n"
        )],
        ratchet: 0,
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
        witness: "use(\"kagi_b\")\nuse(\"kagi_a\")\n\nkagi_a::kagi\nkagi_b::kagi\n",
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

Sorting a list is a machine-applicable fix, and so is sorting the `use` forms
by package when they all sit before the file's other forms and name each
package once: the forms swap places and nothing else moves. Merging two `use`
forms of one package, and moving a `use` up past a definition, are left to the
author.",
    }
    B0016 {
        slug: "unused-import",
        severity: Error,
        fix: None,
        law: "every `use` is reached by something in the file, and every name it lists is read",
        witness: "use(\"kagi_a\")\n\n1\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        ratchet: 0,
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
        fix: Machine,
        law: "the bidamas a bidama `use`s are exactly the `needs` its Bluefile.lock records",
        witness: "use(\"kagi_b\")\n\nkagi_b::kagi\n",
        imports: [
            ("kagi_a", "def kagi()\n  1\nend\n"),
            ("kagi_b", "use(\"kagi_a\")\n\ndef kagi()\n  kagi_a::kagi\nend\n"),
        ],
        waivable: false,
        ratchet: 0,
        explanation: "\
The lock's `needs` is what nix builds a bidama against; `use` is what its
code reaches. `blue lock DIR` derives the lock's `needs` from the bidama's
`use` forms: a Bluefile `needs` row only narrows a used package's range, and
a used package with no row takes the caret of the version the load path
resolves. So
this fires when a `use` changed after the last lock (or, with no lock, when
the Bluefile's rows disagree with the `use` forms). A `use` with no locked
`needs` compiles here and fails in the sandbox, where the package is absent.
`blue check --fix FILE` deletes any row naming an unused package and
relocks.",
    }
    B0020 {
        slug: "package-as-value",
        severity: Error,
        fix: None,
        law: "a bidama's name is written as a qualifier, `retsu::first(xs)`, never as a value",
        witness: "use(\"kagi_a\")\n\nkagi_a::kagi + kagi_a / 2\n",
        imports: [("kagi_a", "def kagi()\n  1\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
`retsu.first(xs)` is a send to a value named `retsu`, and `retsu/first` is a
division; neither names retsu's `first`. blue qualifies with `::`:
`retsu::first(xs)`.",
    }
    B0021 {
        slug: "legacy-name",
        severity: Error,
        fix: Machine,
        law: "a renamed or moved definition is called by its new name; the old name is a bridge that closes at the next minor version",
        witness: "use(\"lg\")\n\nlg::lg_hours\n",
        imports: [("lg", "legacy_names(\"0.1.1\", \"lg\")\n\ndef hours()\n  1\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
A bidama that stripped its hand-made prefix (`lc_hours` became `hours`)
declares the old spelling with `legacy_names(\"0.1.1\", \"lc\")`, so a caller
written against the old name still resolves — to the same definition, the
one `raifusaikuru::hours` names — while the bridge is open: from `since` to
the next minor version.

A reference through the bridge is this rule. Its severity is derived, never
configured: an ERROR inside the distribution the bidama ships in (the
bidama's own repository can never depend on its bridge), a WARNING for any
other caller while the window is open. Once the window closes the old name
resolves to nothing, and the unbound-name diagnostic carries the same
machine-applicable fix, read from the ledger the declaration keeps.

A definition MOVED to another bidama — a twin given one home rather than
copied — is declared the same way, by the bidama it left:
`legacy_names(\"0.1.2\", [[\"opt\", \"deeta::get_or\"]])`. `kinji::opt`
then resolves to `deeta::get_or` over the same window and under the same
severity, and the fix writes the new home qualified, adding the `use` the
file lacks.",
    }
    B0022 {
        slug: "legacy-misuse",
        severity: Error,
        fix: None,
        law: "a `legacy_names` declaration is one of each form per bidama, dates from a version the bidama has reached, names no name twice, and moves a name only to a definition a loaded bidama holds",
        witness: "use(\"lg\")\n\nlg::hours\n",
        imports: [("lg", "legacy_names(\"9.0.0\", \"lg\")\n\ndef hours()\n  1\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
`legacy_names` is the rename ledger: from version `since` every definition
`x` is also `prefix_x`, and a definition that kept its prefix is also its
stripped name. It must sit in a bidama, once; `since` must be a version the
bidama's Bluefile has reached (dating a rename in the future would open no
window, and re-dating it to reopen one is a one-line change a reviewer
sees); and an old or stripped name must not also be defined, which would
give two definitions one name. A moves declaration names each old name
once, the old name is no longer defined, and each new home is a bidama the
declaring one needs and a name that home defines.",
    }
    B0023 {
        slug: "bare-nullary-call",
        severity: Error,
        fix: Machine,
        law: "a call to a function that takes no parameters is written bare: `now_ms`, never `now_ms()`",
        witness: "def f()\n  1\nend\n\nf()\n",
        waivable: false,
        explanation: "\
A name that resolves to a definition or builtin with exactly zero parameters
(`def f()`, `now_ms`, `argv`) is CALLED where it is written bare, so `f` and
`f()` are one tree once resolved, and blue writes the one spelling: `f`. The
fix drops the parentheses, and `blue fmt --write` applies it to every call in
a file, interpolations included.

The rule follows resolution, never spelling. A local, a parameter or a
pattern binding named `f` is a value; a function with one or more parameters,
optional ones or a rest parameter is a value when bare and keeps `f(x)`; a
name inside a macro call's arguments or a quoted template is syntax and is
left as written. To pass a zero-parameter function itself, write
`fn() f end`.

Reported for the file being compiled only: an imported package spelled the
older way means the same program, and its own build is where it is held to
the one spelling.",
    }
    B0024 {
        slug: "layout",
        severity: Error,
        fix: Machine,
        law: "a file is laid out as `blue fmt` writes it: indentation, line breaks at 80 columns, blank lines and parentheses",
        witness: "x   =   1\n",
        waivable: false,
        explanation: "\
blue has one layout, chosen for a person reading the file cold: two-space
indentation, a line broken at 80 columns after an operator or between
arguments, one blank line around a form that spans lines, parentheses only
where precedence needs them, and a call whose one argument is a literal kept
on its line. There is no option, so a file that differs from it is not yet
blue source.

`blue run`, `blue test` and `blue check` rewrite a writable file to the
layout before compiling it and say so; a read-only file is refused, naming
the rule. `blue fmt --write` applies it. The more specific spelling rules
(B0025 to B0035, B0042, B0046, B0047) are reported instead when one of them explains the
difference.",
    }
    B0025 {
        slug: "logical-words",
        severity: Error,
        fix: Machine,
        law: "logic is written in words: `a and b`, `a or b`, `not x`, never `&&`, `||`, `!`",
        witness: "ready = true\nready && ready\n",
        waivable: false,
        explanation: "\
A reader who has never seen blue reads `if ready and not failed` aloud
without a lookup; `if ready && !failed` needs one, and `!` disappears beside
a name. Both spellings build the same tree, `(and ready (not failed))`, so
blue reads `&&`, `||`, `!` (and `∧`, `∨`, `¬`) and writes the words.

`and` and `or` bind as `&&` and `||` did; `not` binds tightly, as `!` did, so
`not ready and done` is `(not ready) and done`. A negation that is an
operand of a comparison or arithmetic is written in parentheses,
`(not a) == b`, so it can never be read the other way.",
    }
    B0026 {
        slug: "unless",
        severity: Error,
        fix: Machine,
        law: "a negated condition is written `if not c`, never `unless c`",
        witness: "done = false\nunless done\n  1\nend\n",
        waivable: false,
        explanation: "\
`unless c` is read as `if not c`: the same tree. `if not c` keeps one
conditional keyword, reads naturally with `else` and `elsif` where `unless …
else` reads backwards, and needs no second word to learn.",
    }
    B0027 {
        slug: "elsif",
        severity: Error,
        fix: Machine,
        law: "an `else` whose whole body is an `if` is written `elsif`",
        witness: "a = 1\nif a == 1\n  1\nelse\n  if a == 2\n    2\n  end\nend\n",
        waivable: false,
        explanation: "\
`else` holding only an `if … end` and `elsif` are one tree. `elsif` keeps
the chain flat, one `end` for the whole chain and every branch at the same
indentation. A comment beside the inner `if` keeps the nested spelling,
since `elsif` would leave the comment no line.",
    }
    B0028 {
        slug: "call-form",
        severity: Error,
        fix: Machine,
        law: "a call is written `f(x, y)`: never `x.f(y)` or `x |> f(y)`",
        witness: "xs = [1]\nxs |> count\n",
        waivable: false,
        explanation: "\
`x.f(y)`, `x |> f(y)` and `f(x, y)` are one tree, `(f x y)`. blue writes the
call form: the function is named first, as a reader looks for it, and a
recursive call reads forwards. `x.name` without parentheses is not a call:
it reads the field `name` of a record.",
    }
    B0029 {
        slug: "keyword-key",
        severity: Error,
        fix: Machine,
        law: "a map key that is a keyword is written `name: value`, never `:name => value`",
        witness: "{:a => 1}\n",
        waivable: false,
        explanation: "\
`{a: 1}` and `{:a => 1}` are one tree. The label form is shorter and reads
as a record's field; `=>` stays where it is the only spelling of the key: a
string, a number, or an expression.",
    }
    B0030 {
        slug: "parameter-list",
        severity: Error,
        fix: Machine,
        law: "a definition and a lambda write their parameter list, even an empty one: `def f()`, `fn() … end`",
        witness: "def f\n  1\nend\n\nf\n",
        waivable: false,
        explanation: "\
`def f` and `def f()` are one tree. The parentheses say, where the function
is defined, that it takes nothing; the call is then written bare (B0023).",
    }
    B0031 {
        slug: "operator-spelling",
        severity: Error,
        fix: Machine,
        law: "an operator or literal is written as itself, never as the call it lowers to or a typographic alias",
        witness: "not(true)\n",
        waivable: false,
        explanation: "\
`not(x)`, `and(a, b)`, `mod(a, b)`, `equal?(a, b)`, `list(1, 2)`,
`define(x, 1)` and `0 - x` build the trees `not x`, `a and b`, `a % b`,
`a == b`, `[1, 2]`, `x = 1` and `-x` build; `≠ ≤ ≥ × ÷ − ≡` are read as
`!= <= >= * / - ==`. blue writes the operator, the literal, and the ASCII
spelling a reader can type.",
    }
    B0032 {
        slug: "trailing-comma",
        severity: Error,
        fix: Machine,
        law: "no comma before a closing bracket",
        witness: "[1, 2,]\n",
        waivable: false,
        explanation: "\
A trailing comma is read and dropped: a broken list already puts each
element on its own line, so the comma adds nothing a reader needs.",
    }
    B0033 {
        slug: "literal-spelling",
        severity: Error,
        fix: Machine,
        law: "a literal is written as `blue fmt` writes its value: digits of six or more grouped `1_000_000`, an invisible character escaped `\\u{1b}`",
        witness: "1000000\n",
        waivable: false,
        explanation: "\
A number is one value however it is spelled, so it has one spelling: an
integer of six or more digits is grouped in threes (`1_000_000`), a shorter
one is not (`65535`), and a float is written as its shortest exact decimal.
A string is written with its characters, except that a quote, a backslash,
a control character, a zero-width or bidirectional mark and a no-break space
are escaped: a character a reader cannot see must not hide in source.",
    }
    B0034 {
        slug: "negated-comparison",
        severity: Error,
        fix: Machine,
        law: "a negated equality is written with the other operator: `a != b`, never `not (a == b)`",
        witness: "a = 1\nnot (a == 2)\n",
        waivable: false,
        explanation: "\
`a != b` is exactly `not (a == b)` (okite D0002), so blue reads the negation
and writes the operator: one comparison, no parentheses. `not (a != b)` is
written `a == b`.",
    }
    B0035 {
        slug: "else-nil",
        severity: Error,
        fix: Machine,
        law: "an `if` has no `else` whose body is empty or `nil`",
        witness: "a = 1\nif a == 1\n  1\nelse\n  nil\nend\n",
        waivable: false,
        explanation: "\
An `if` whose condition fails is already `nil`, so `else nil` says nothing
the reader needs. blue reads it and drops it; an `else` holding only a
comment keeps its line.",
    }
    B0036 {
        slug: "builtin-synonym",
        severity: Error,
        fix: Machine,
        law: "a builtin with two names is called by its readable one: `first` not `car`, `rest` not `cdr` or `next`, `a % b` not `modulo`/`rem`, `boolean?` not `bool?`, `compose` not `comp`, `reduce` not `foldl`, `x != nil` not `some?(x)`, `e.kind`/`e.message` not `error_kind`/`error_message`",
        witness: "car([1])\n",
        explanation: "\
Each pair computes the same value; blue keeps the name a reader who has
never seen Lisp understands, so `car`, `cdr`, `next`, `modulo`, `rem`, `bool?`,
`comp`, `foldl`, `nil?`, `some?`, `error_kind` and `error_message` are read
and rewritten. `some?` is the one most worth losing: it reads as \"some
element\", which is `some(f, xs)`, a different word.

The rule follows resolution: a program's own `car` is left alone, and where a
listed import or a local shadows the readable name, the rewrite writes
`blue::first`.",
    }
    B0037 {
        slug: "error-spelling",
        severity: Error,
        fix: Machine,
        law: "an error is raised with `raise` and caught with `rescue`: never `throw(error(…))` or `try(…, catch(…))`",
        witness: "throw(error(:k, \"m\"))\n",
        explanation: "\
`raise(:not_found, \"no repo #{name}\")` builds and raises in one step;
`raise(:k, \"m\", {data: x, cause: e})` attaches data and the error being
wrapped, and `raise(e)` raises an error again. `throw(error(k, m))` is read
as `raise(k, m)` and `throw(x)` as `raise(x)`.

`x rescue fallback` is the value of `x`, or `fallback` when `x` raises; it
binds loosest of all. A block catches by kind and binds the error:

    begin
      fetch(url)
    rescue :timeout, :refused as e
      retry_later(e)
    rescue e
      raise(:fetch_failed, \"#{url}: #{e.message}\", {cause: e})
    ensure
      close(conn)
    end

A `def` body takes the same clauses without `begin`, which is how blue writes
a block that is a whole body. `try(x, catch(e(), h))` is read as that block,
and as `x rescue h` when it discards the error.",
    }
    B0038 {
        slug: "swallowed-error",
        severity: Error,
        fix: None,
        law: "a `rescue` that catches every error and does nothing names the error `_`",
        witness: "begin\n  1\nrescue e\n  nil\nend\n",
        waivable: false,
        explanation: "\
Silencing every error is sometimes right and never something a reader
should have to discover. A catch-all whose handler is empty or `nil` must
say so: `rescue _` and `nil`, or `x rescue nil` inline. It is not fixed
automatically, because the fix would make the silence deliberate without
anyone deciding it.",
    }
    B0039 {
        slug: "duplicate-test-name",
        severity: Error,
        fix: None,
        law: "the tests of a file have distinct names",
        witness: "test \"adds\"\n  assert 1 + 1 == 2\nend\n\ntest \"adds\"\n  assert 2 + 2 == 4\nend\n",
        waivable: false,
        explanation: "\
A test's name is how its failure is reported; two tests with one name make
the report ambiguous about which one failed. Rename one so each says what it
holds.",
    }
    B0040 {
        slug: "identifier-case",
        severity: Error,
        fix: None,
        law: "a function, parameter or local is named in lower snake_case (`retry_count`, never `retryCount`); a top-level constant may be UPPER_SNAKE",
        witness: "def addOne(x)\n  x + 1\nend\n",
        waivable: false,
        explanation: "\
One case for names means a reader never wonders whether `retryCount` and
`retry_count` are two things. A name may end in `?` (a question) or `!` (a
warning). A top-level value binding written wholly in capitals
(`UART0 = 268_435_456`) is a constant, and reads as one. Renaming is left to
the author, because a definition's name is also its callers'.",
    }
    B0041 {
        slug: "main-guard",
        severity: Error,
        fix: Machine,
        law: "a program's entry point is `def main()`, which `blue run` calls; never a top-level `if getenv(\"X_MAIN\", \"\") == \"1\"` guard",
        witness: "def getenv(_name, fallback)\n  fallback\nend\n\ndef go()\n  1\nend\n\nif getenv(\"GO_MAIN\", \"\") == \"1\"\n  go\nend\n",
        waivable: false,
        explanation: "\
`blue run FILE` evaluates the file and then calls its `main`, if it defines
one with no parameters; `blue test`, `blue check` and a `use` never do. So a
file is a program and a library at once, with no environment variable to
set. The guard `if getenv(\"X_MAIN\", \"\") == \"1\" … end` around one call is
read as that: the fix removes it and renames the function it called to
`main`. A guard of any other shape is left for the author.",
    }
    B0042 {
        slug: "splat",
        severity: Error,
        fix: Machine,
        law: "a list passed as a call's last arguments is written `f(a, *xs)`, never `apply(f, a, xs)` with `f` a name",
        witness: "apply(max, [1, 2])\n",
        waivable: false,
        explanation: "\
`f(a, *xs)` and `apply(f, a, xs)` are one tree. The splat keeps the function
where a call names it and marks the list being spread. `apply` stays where
the function is computed by an expression.",
    }
    B0043 {
        slug: "prefixed-program",
        severity: Error,
        fix: Machine,
        law: "a program does not prefix every definition with one short `x_`: the file is the namespace",
        witness: "def ro_argv()\n  []\nend\n\ndef ro_count()\n  0\nend\n\ndef ro_check()\n  ro_count\nend\n",
        waivable: false,
        explanation: "\
A program's definitions live in the file's own namespace, so nothing they
are named can collide with a bidama's or be reached from another file:
`ro_resolve_argv`, `ro_patch_argv` and `ro_main` say `ro_` three times for
nothing. The fix strips the prefix from every definition and every use in
the file, when no stripped name is already used there or reserved; `ro_main`
becomes `main`, which `blue run` calls (B0041). A bidama's own prefix is
B0013 and B0014.",
    }
    B0044 {
        slug: "eta-reduction",
        severity: Error,
        fix: Machine,
        law: "a function that only forwards its parameters to a named function is that name: `map(describe, vs)`, never `map((v) -> describe(v), vs)`",
        witness: "def describe(v)\n  v\nend\n\ndef go(vs)\n  map((v) -> describe(v), vs)\nend\n",
        waivable: false,
        explanation: "\
`(x) -> f(x)` and `f` are the same function, and the name is shorter. The rule
fires only where the swap cannot change the program: `f` is a plain `def` of
this file taking exactly the lambda's parameters, nothing in the form rebinds
`f`, and `f` is defined before the lambda is built (an earlier form, or the
lambda sits inside a `def`). Builtins, imported names, optional or rest
parameters and a different parameter count are left as written.",
    }
    B0045 {
        slug: "redundant-conversion",
        severity: Warning,
        fix: Machine,
        law: "a conversion is not applied to a value it leaves alone: `to_s(to_s(x))` is `to_s(x)`, never the longer chain",
        witness: "def f(x)\n  to_s(to_s(x))\nend\n",
        waivable: false,
        explanation: "\
`to_s` of a string is the string, `to_int!` of an Int is the Int, and so on:
when the inner expression is a builtin call that always returns the kind the
outer conversion leaves alone (or a literal of that kind), the outer call does
nothing, and the chain is its inner expression. A chain of any length
collapses from the inside out.

Every rewrite is a row of one table, `blue_lang_check::chains::RULES`, and each
row has a soundness law in okite (`D0013`) that evaluates both sides over
generated values: same value, or the same refusal. The table is the only
source: this report, the rewrite `blue fmt --write`, `blue run`, `blue test`
and `blue check --fix` write, and the form the evaluator runs all read it, so
unformatted code runs the simplified chain too.

A row is left out when the identity fails for some value the chain can see:
`to_int(to_int(x))` is not `to_int(x)`, because `to_int` of nil refuses where
`to_int(\"abc\")` is nil. The names are builtins only: a local or a definition
called `to_s` is never rewritten.",
    }
    B0046 {
        slug: "map-pun",
        severity: Error,
        fix: Machine,
        law: "a map entry whose value is the variable of the same name is written `{name:}`, never `{name: name}`",
        witness: "name = 1\n{name: name}\n",
        waivable: false,
        explanation: "\
`{name:}` is `{name: name}`: a label with no value takes the variable of the
same name, so a map built from locals names each one once. blue reads the long
spelling and writes the short one, and a mixed map keeps its explicit values:
`{name:, size: 3}`.",
    }
    B0047 {
        slug: "nil-test",
        severity: Error,
        fix: Machine,
        law: "a nil test is written `x.nil?`, never `nil?(x)`, `x == nil` or `nil == x`",
        witness: "name = 1\nname == nil\n",
        waivable: false,
        explanation: "\
`x.nil?` is true of nil and of nothing else, so the test reads as a question
put to the value. blue reads `nil?(x)`, `x == nil` and `nil == x` and writes
`x.nil?`; the three build the same answer on every value.

The opposite test stays `x != nil`, and `not x.nil?` is read as written.
A program's own `nil?` is left alone, and a map that holds a `nil?` key
answers `.nil?` with that key's value.",
    }
    B0048 {
        slug: "undeclared-field-read",
        severity: Error,
        fix: Suggested,
        law: "a fragment ref is read only for the fields its fragment declares; a parent never reads a child's field",
        witness: "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id]})\n\ndef user_card(user: UserCard)\n  user.name\nend\n",
        imports: [("danpen", "def fragment(name, spec)\n  [name, spec]\nend\n")],
        waivable: false,
        ratchet: 0,
        explanation: "\
A parameter whose type names a fragment receives a fragment ref:
`danpen::fragment(:user_card, …)` declares the type `UserCard`, and
`def user_card(user: UserCard)` reads `user` through it. Only the fields the
fragment lists can be read, by `user.name` or `get(user, :name)`; a nested
selection gives a ref to that selection.

A field that comes in through a spread (`\"...user_card\"`) belongs to the child
fragment. The parent passes the value on to the component that declared it
and never reads the field itself: that is masking, and it is what lets a
component change its data without breaking a parent.

To comply, add the field to the fragment's `fields`, or move the read into
the component whose fragment declares it. The suggestion adds the field.",
    }
    B0049 {
        slug: "fragment-not-composed",
        severity: Error,
        fix: Machine,
        law: "a view's operation is the union of the fragments of the components it renders: a ref passed to a component comes from a selection that spreads its fragment, and every spread names a declared fragment",
        witness: "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id]})\n\npage = danpen::fragment(:profile, {on: \"Query\", fields: [{user: [:id]}]})\n\ndef user_card(user: UserCard)\n  user.id\nend\n\ndef profile(data: Profile)\n  user_card(data.user)\nend\n",
        imports: [("danpen", "def fragment(name, spec)\n  [name, spec]\nend\n")],
        waivable: false,
        explanation: "\
Nobody writes a query. A view declares a fragment on the root type, each
component declares its own, and the view's operation is their union
(`danpen::compose`). For the union to hold, the selection a view passes to a
component must spread that component's fragment: `{user: [\"...user_card\"]}`
before `user_card(data.user)`. Otherwise the component is handed data
fetched for somebody else.

A spread of a fragment nobody declared cannot be composed either, and is
reported at the spread.

The fix adds the spread to the selection the value comes from.",
    }
    B0050 {
        slug: "field-not-in-schema",
        severity: Error,
        fix: None,
        law: "every fragment's type and field, and every `labels` enum and key, is in the frontend's schema",
        witness: "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :nmae]})\n",
        imports: [("danpen", "def fragment(name, spec)\n  [name, spec]\nend\n")],
        waivable: false,
        frontend: "{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {}}\n",
        explanation: "\
A frontend names its GraphQL SDL (`frontend(name, {schema: \"schema.graphql\"})`)
and generates a table from it (`generate(name, output, program,
[\"schema.graphql\"])`, the program calling `danpen::table_text`). The check
stage reads that table and refuses a fragment `on:` a type the SDL lacks, a
field its type does not define, a `labels` call on an enum the SDL lacks and
a label keyed by a value the enum does not have.

`checks.generated-<name>-fresh` keeps the table equal to what the SDL makes,
so the check never judges against an old schema. A file with no frontend
around it has no table, and these checks do not run for it.

To comply, select a field the type defines (the help names the nearest), or
change the SDL and regenerate.",
    }
    B0051 {
        slug: "enum-mirror",
        severity: Error,
        fix: None,
        law: "a literal list never mirrors an enum of the schema; display text is keyed by the enum with `labels`",
        witness: "TONES = [:WARM, :COOL]\n",
        frontend: "{types: {}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}\n",
        explanation: "\
Frontend data is entity-backed: the set of values an enum holds belongs to
the backend, and a copy of it in a view goes stale the day the backend adds a
value. A literal list whose items are exactly an enum's values is that copy.

The one frontend value is a display label, keyed by the backend value:
`gamen::labels(:Tone, {WARM: \"Warm\", COOL: \"Cool\"})`. The labels are
checked against the enum (B0050), so a value the backend drops is reported
where it is labelled.

A list that only happens to equal an enum can carry a waiver with the reason.",
    }
    B0052 {
        slug: "query-text",
        severity: Error,
        fix: None,
        law: "a view holds no GraphQL operation text; its operation is composed from fragments and sent by hash",
        witness: "me = \"query Me { me { id } }\"\n",
        ratchet: 0,
        frontend: "{types: {}, enums: {}}\n",
        explanation: "\
Law 3, persisted operations: each operation compiles to a hash, the browser
sends the hash, and hanabi refuses one it does not hold. No query text ships.
In a file a `frontend(...)` names as a view, a string that starts with
`query`, `mutation` or `subscription` and holds a selection is hand-written
operation text, which neither composition nor the hash table can see.

To comply, declare a fragment on the root type and let `danpen::compose` and
`danpen::hash` produce the operation and its id. GraphQL text in danpen's own
tests and in fixtures is not a view and is not reported.",
    }
    B0053 {
        slug: "discarded-value",
        severity: Error,
        fix: None,
        law: "the value of a word that only returns a value is read: `assoc`, `append`, `to_s` and their kin are never a statement",
        witness: "def put(m)\n  assoc(m, :a, 1)\n  m\nend\n",
        waivable: true,
        explanation: "\
blue's values do not change. `assoc(m, :a, 1)` returns a new map and leaves
`m` as it was, so a line that calls it and drops the result does nothing: the
author meant `m = assoc(m, :a, 1)`, or the line is dead. Rust marks such
functions `#[must_use]`; this is the same law for the first-order words that
only return a value (`append`, `assoc`, `concat`, `cons`, `dissoc`,
`distinct`, `downcase`, `drop`, `flatten`, `join`, `range`, `remove`,
`replace`, `reverse`, `split`, `string`, `take`, `to_float`, `to_int`, `to_s`,
`trim`, `upcase`, `zip`). `map`, `filter` and `reduce` are not in the list:
the function they call may write, so dropping their value is not dead code.

It fires on a statement that is not the last of its body. A name the file
defines or lists in a `use` is that definition, not the builtin, and is not
reported. Bind the value or return it. `# waive B0053: reason` keeps a line
that is there only for the error it may raise. docs/SAFETY.md, row 2.",
    }
    B0056 {
        slug: "undocumented-definition",
        severity: Error,
        fix: Machine,
        law: "a bidama's public definition has a `@doc` whose first sentence starts with its name",
        witness: "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\ndef kagi()\n  1\nend\n",
        ratchet: 2846,
        package: "kagi",
        explanation: "\
A reader of one bidama should be proficient in it, so every definition a `use`
can name (each top-level `def`, `defmacro` and `name = value` of a bidama;
blue has no private definition) says what it is for: `@doc` above it, its
first sentence starting with the definition's name.

    @doc \"\"\"
    clamp keeps a number inside a range.

        clamp(99, 1, 10) #=> 10
    \"\"\"
    def clamp(x, lo, hi)

Only intent and examples are written. The signature, types, rung, contract
row, space, callers and refusals are derived when asked (`blue doc`, hover).

`blue check --fix` writes the `@doc` from what a source holds: the `#` block
directly above the `def`, else the verb graph row's `meaning`, else the
builtin reference line, with the simplest assertion of the file's own tests as
the example. It writes nothing it cannot source; what stays is counted by
`blue census` until the count reaches zero.",
    }
    B0057 {
        slug: "doc-without-example",
        severity: Error,
        fix: Machine,
        law: "a `@doc` holds at least one example, an indented `expr #=> value` line",
        witness: "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi is one.\n\"\"\"\ndef kagi()\n  1\nend\n",
        ratchet: 902,
        package: "kagi",
        explanation: "\
An example shows how a definition is called and what it answers, and blue
runs it: each indented paragraph of a `@doc` holding a line `expr #=> value`
is a test (`blue test`), its other lines run first. An example that stops
holding is a red build, not a stale snippet.

`blue check --fix` adds the shortest assertion of the file's own tests that
calls the definition and reads no local of its test.",
    }
    B0058 {
        slug: "undocumented-bidama",
        severity: Error,
        fix: Machine,
        law: "a bidama's file opens with a `@moduledoc` holding its purpose and one whole example",
        witness: "@doc \"\"\"\nkagi is one.\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
        ratchet: 28,
        package: "kagi",
        explanation: "\
`@moduledoc` is the first form of a bidama's file: what the bidama is for,
then one whole example a reader can run in their head and `blue test` runs
for real. The mental model, invariants and see-also follow when they help.

`blue check --fix` lifts the comment block that heads the file (its first
line is the bidama's CATALOG line) into `@moduledoc`, and adds the shortest
assertion of the file's own tests as the example.",
    }
    B0059 {
        slug: "placeholder-doc",
        severity: Error,
        fix: None,
        law: "a `@doc` or `@moduledoc` says something: no empty text and no placeholder (`TODO`, `TBD`, `...`)",
        witness: "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi: TODO\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
        ratchet: 0,
        package: "kagi",
        explanation: "\
A placeholder passes a presence check and tells the reader nothing, so it is
refused: an empty text, an intent that is only a placeholder word, or one
holding `TODO`, `FIXME`, `TBD` or `XXX`. A fake doc cannot pass.

There is no fix: the intent is the one thing no source holds.",
    }
    B0060 {
        slug: "restated-doc",
        severity: Error,
        fix: Machine,
        law: "a `@doc` never restates a type, a signature or a contract field: blue derives them",
        witness: "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi is one.\n\nReturns: an Int.\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
        ratchet: 0,
        package: "kagi",
        explanation: "\
One meaning, one place. The signature and types come from the checker and the
blueshift, the arguments, options, returns and raises from the contract row
(`docs/verbs/contracts.tsv`), and `blue doc` and the editor show them. A
`Returns:`, `Args:`, `@param` or `f(a) -> T` line in a `@doc` is a second copy
that drifts the day the code changes.

`blue check --fix` deletes the line; say what the definition is for instead.",
    }
    B0061 {
        slug: "undeclared-option",
        severity: Error,
        fix: Suggested,
        law: "a function's option keys are a closed set: a call passes only keys the function reads, and a `checked(opts, [...])` list declares every key the function reads",
        witness: "def prepared(opts)\n  get(opts, :vars)\nend\n\nprepared({variables: 1})\n",
        waivable: true,
        explanation: "\
A record parameter's keys are the keys its function reads: `get(opts, :k)`,
`opts.k`, and the keys of every function it passes `opts` to. A call that
passes a map literal with a key outside that set passes a value nobody reads.
The function then sees nil for the key it does read, and fails far from the
call. outou's `prepared` read `opts[:vars]` while every caller passed
`variables:`, and four of thirteen tests failed for that one silent reason
(5f25221).

A `checked(opts, [:a, :b])` call declares the set, as moji's `checked` does at
run time; then a read of any other key is reported too. A parameter that
escapes (returned, stored in a value, passed to a function the checker cannot
resolve) has an open set and is not reported.

To comply, spell the key the function reads (the help names the set), or read
the new key in the function. `# waive B0061: reason` keeps one line.
docs/SAFETY.md, row 18.",
    }
    B0062 {
        slug: "argument-kind",
        severity: Error,
        fix: Suggested,
        law: "a value whose kind is known is never passed where a builtin, or the parameter it flows to, takes another kind",
        witness: "def kind_of(schema)\n  get(schema, :kind)\nend\n\nkind_of(\"type Query { a: Int }\")\n",
        waivable: true,
        fixes: "find((x) -> x > 1, [1, 2, 3])\n",
        explanation: "\
A builtin's signature names its parameters by kind: `m` is a map, `xs` a list,
`s` a string, `n` a number, `f` a function (`blue reference`;
`blue_lang_check::contracts::kinds_of_parameter`). A function's parameter
takes what the builtins and functions it reaches take, unless the function
tests its kind first (`string?(x)`, `map?(x)` and the other predicates).

A literal passed where another kind is taken is a type error the runtime
would raise later, far from the call. danpen's `schema_of` called
`get(schema, :kind)` on SDL text, a string, and the error came at run time.

A builtin that takes the collection first and a function second
(`find(xs, f)`, `flat_map(xs, f)`, `group_by(xs, f)`: every signature whose
first parameter is a list or map and whose second is a function), or a
definition whose parameters take the same (`retsu::flat_map`), called with a
function literal first and a value that is not a function second is fixed by
`blue check --fix`: it swaps the two arguments. Every other case is left to
you.

To comply, pass the kind the parameter takes, or test the kind in the
function. `# waive B0062: reason` keeps one line.
docs/SAFETY.md, row 18.",
    }
    B0063 {
        slug: "nullary-as-function",
        severity: Error,
        fix: Suggested,
        law: "a zero-argument definition passed where a function is taken is written `() -> name`; a bare zero-argument name is a call",
        witness: "def pin()\n  1\nend\n\ndef gate(f)\n  f()\nend\n\ngate(pin)\n",
        waivable: true,
        explanation: "\
blue calls a zero-argument definition when its bare name is evaluated:
`now_ms` is a number, not a clock. So `gate(\"pin\", gen_pin)` runs `gen_pin`
at the call and passes its value; `gate` then calls that value and fails.
The prepush gate died this way on every push (eb8f81a).

A parameter takes a function when its function calls it (`f()`), or passes
it where a builtin or another function takes one (`map(f, xs)`). A bare
zero-argument name in that place is reported with the suggestion
`() -> name`. `blue check --fix` leaves it, because it changes what the line
does: the bare name was a call. A `&name` reference form was rejected: the lambda is already the
one way to write a function value, and a second spelling would split the
corpus. `# waive B0063: reason` keeps a line that means the value.
docs/SAFETY.md, row 18.",
    }
    B0064 {
        slug: "unformatted-producer",
        severity: Error,
        fix: Suggested,
        law: "a program that writes a `.b` file writes it with `write_program`, which formats it; a producer owns the form of what it emits",
        witness: "write_file(\"gate.b\", \"x=1\")\n",
        waivable: true,
        explanation: "\
A generated program is read by people, diffed in review and checked by every
consumer. If its producer writes raw text, the first consumer that checks
form fails, far from the producer: mk-bidama.nix wrote gate.b unformatted and
bidama-collisions went red until fa7bfba formatted it (befbc13: the form is
the producer's).

`write_program(path, text)` formats `text` with blue's formatter and writes
it, and raises when the text does not parse. A `write_file` whose path is a
string ending in `.b`, an interpolation or `path_join` ending in one, or a
local bound to such a path, is reported with the suggestion `write_program`.
`blue check --fix` leaves it, because it changes the bytes written. `blue new` writes through the formatter, and the
`blue-fmt` flake check holds every committed `.b` file canonical.
`# waive B0064: reason` keeps a line that writes a malformed program on
purpose, such as a fixture for a layout rule. docs/SAFETY.md, row 18.",
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
