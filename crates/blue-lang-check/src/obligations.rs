//! The obligation registry: every "when blue sees X, evidence Y must exist"
//! the toolchain forces, as one table of data.
//!
//! An obligation is a row. It names what its detector sees ([`Obligation::when`]),
//! the evidence that discharges it ([`Evidence`]), where the detector runs
//! ([`Detector`]), how a missing piece of evidence is refused ([`Refusal`]),
//! the profile that owes it ([`Profile`]) and the debt it holds
//! ([`Obligation::held`]).
//!
//! **One refusal per row, through machinery that already exists.** A
//! [`Refusal::Code`] row is a rule in [`crate::RULES`]: the check stage reports
//! it on every door (`blue run`, `blue test`, `blue check`, the language
//! server, every bidama build), `# waive CODE: reason` above the one
//! definition is its waiver, and B0008 refuses a waiver that covers nothing.
//! A [`Refusal::Gate`] row is a flake check that judges a whole run (the
//! coverage gate `test-beside`). A [`Refusal::Design`] row is registered and
//! not yet forced; its text says what blocks it.
//!
//! **Debt is held, never hidden.** Existing debt of a code row is one
//! `# waive` per site, each with its reason, so a reader sees it where it is.
//! `held` is how many such waivers the corpus carries; `blue census` fails
//! unless it measures exactly that number, so a new waiver and a paid one are
//! both reviewed edits of the row. New debt with no waiver is an error at the
//! moment it is written. A code whose corpus count is not yet zero is
//! ratcheted instead (its rule's `ratchet`): `blue census` holds the count
//! exactly, so it may only fall, and at zero the rule is an error on every
//! door.
//!
//! **Registering an obligation** is one row in [`obligations!`]: an id
//! (`family/name`), the evidence, the detector, the refusal and the profile.
//! A code row's rule must exist, be enforced and be waivable;
//! `every_code_row_names_an_enforced_waivable_rule` fails otherwise.

use crate::rules::Code;

/// The evidence that discharges an obligation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Evidence {
    /// A test reaches the definition.
    Unit,
    /// A test declared `kind: :integration` reaches the point.
    Integration,
    /// A test declared `kind: :contract` checks the point's shape.
    Contract,
    /// A test declared `kind: :e2e` runs the service.
    EndToEnd,
    /// A test declared `kind: :rendering` feeds the output to its consumer.
    Rendering,
    /// Each outcome of a decision is taken by a test.
    Branch,
    /// A test expects the raised tag.
    Raise,
    /// A test asserts something.
    Assertion,
    /// A declaration exists for the structure.
    Declared,
    /// A mutant is caught by a test.
    Mutation,
}

impl Evidence {
    /// Every kind, in table order.
    pub const ALL: &'static [Evidence] = &[
        Evidence::Unit,
        Evidence::Integration,
        Evidence::Contract,
        Evidence::EndToEnd,
        Evidence::Rendering,
        Evidence::Branch,
        Evidence::Raise,
        Evidence::Assertion,
        Evidence::Declared,
        Evidence::Mutation,
    ];

    /// The word a report and `blue reference` spell it by.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Evidence::Unit => "unit",
            Evidence::Integration => "integration",
            Evidence::Contract => "contract",
            Evidence::EndToEnd => "e2e",
            Evidence::Rendering => "rendering",
            Evidence::Branch => "branch",
            Evidence::Raise => "raise",
            Evidence::Assertion => "assertion",
            Evidence::Declared => "declared",
            Evidence::Mutation => "mutation",
        }
    }
}

/// Where an obligation's detector runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Detector {
    /// The check stage, from the AST: every door, the moment the point is
    /// written.
    Static,
    /// The check stage, from the entry file's role in its project (a
    /// `generate` or `service` row of the Bluefile above it).
    Project,
    /// One instrumented run of the tests.
    Dynamic,
}

impl Detector {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Detector::Static => "static",
            Detector::Project => "project",
            Detector::Dynamic => "dynamic",
        }
    }
}

/// How a missing piece of evidence is refused.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Refusal {
    /// A rule of the registry, enforced on every door.
    Code(Code),
    /// A flake check, by name, that judges a whole run or a whole tree.
    Gate(&'static str),
    /// Registered, not yet forced: what blocks it.
    Design(&'static str),
}

impl Refusal {
    #[must_use]
    pub fn label(self) -> String {
        match self {
            Refusal::Code(c) => c.as_str().to_string(),
            Refusal::Gate(g) => format!("checks.{g}"),
            Refusal::Design(_) => "design".to_string(),
        }
    }

    /// Is the obligation forced today?
    #[must_use]
    pub const fn forced(self) -> bool {
        !matches!(self, Refusal::Design(_))
    }
}

/// Who owes an obligation (docs/COVERAGE.md section 4).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Profile {
    /// Every project and bidama; a script owes nothing.
    Default,
    /// A package that opts in: crypto, the engine core, anything signed.
    Strict,
    /// A `service(...)`.
    Service,
}

impl Profile {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Profile::Default => "default",
            Profile::Strict => "strict",
            Profile::Service => "service",
        }
    }
}

/// One obligation.
#[derive(Clone, Copy, Debug)]
pub struct Obligation {
    pub id: &'static str,
    pub when: &'static str,
    pub evidence: Evidence,
    pub detector: Detector,
    pub refusal: Refusal,
    pub profile: Profile,
    pub held: u32,
    pub owner: &'static str,
}

macro_rules! held {
    () => {
        0
    };
    ($n:expr) => {
        $n
    };
}

macro_rules! obligations {
    ($(
        $id:literal {
            when: $when:literal,
            evidence: $evidence:ident,
            detector: $detector:ident,
            refusal: $refusal:ident($arg:expr),
            profile: $profile:ident,
            $(held: $held:expr,)?
            owner: $owner:literal $(,)?
        }
    )*) => {
        /// The registry, in table order.
        pub const OBLIGATIONS: &[Obligation] = &[$(
            Obligation {
                id: $id,
                when: $when,
                evidence: Evidence::$evidence,
                detector: Detector::$detector,
                refusal: Refusal::$refusal($arg),
                profile: Profile::$profile,
                held: held!($($held)?),
                owner: $owner,
            }
        ),*];
    };
}

obligations! {
    "reach/definition" {
        when: "a definition in a project with `packages`",
        evidence: Unit,
        detector: Dynamic,
        refusal: Gate("test-beside"),
        profile: Default,
        owner: "TESTING.md T1, T2 (every project with `packages`; `skip(\"test-beside\", why)` is the one way off); COVERAGE.md R1",
    }
    "reach/target" {
        when: "a public definition no test names directly (`target:` or a call in a test body)",
        evidence: Unit,
        detector: Static,
        refusal: Code(Code::B0090),
        profile: Default,
        owner: "COVERAGE.md R2",
    }
    "reach/doctest" {
        when: "an `@doc` example",
        evidence: Unit,
        detector: Dynamic,
        refusal: Design("COVERAGE CV3: doctests run today (B0057 forces the example); a failing doctest is a red test, not yet a registry finding"),
        profile: Default,
        owner: "COVERAGE.md R3",
    }
    "reach/dead" {
        when: "a definition reachable from neither an entry point nor a test",
        evidence: Unit,
        detector: Static,
        refusal: Design("COVERAGE CV3: needs the call graph from every entry point"),
        profile: Default,
        owner: "COVERAGE.md R4",
    }
    "point/effect" {
        when: "a definition that names a network, process or other host builtin outside the ambient set (filesystem, environment, clock)",
        evidence: Integration,
        detector: Static,
        refusal: Code(Code::B0083),
        profile: Default,
        held: 97,
        owner: "TESTING.md section 5, T4",
    }
    "point/seam" {
        when: "a definition that calls an imported word which names such a builtin",
        evidence: Integration,
        detector: Static,
        refusal: Code(Code::B0084),
        profile: Default,
        held: 22,
        owner: "TESTING.md section 5, T4",
    }
    "point/rendering" {
        when: "the program of a Bluefile `generate` row",
        evidence: Rendering,
        detector: Project,
        refusal: Code(Code::B0085),
        profile: Default,
        held: 31,
        owner: "TESTING.md section 5, T4; COVERAGE.md C4",
    }
    "point/service" {
        when: "the program of a Bluefile `service(...)` row",
        evidence: EndToEnd,
        detector: Project,
        refusal: Code(Code::B0086),
        profile: Service,
        held: 2,
        owner: "TESTING.md section 5, T4",
    }
    "point/binding" {
        when: "a `cache` or `schema` binding of a `service(...)` row",
        evidence: Contract,
        detector: Project,
        refusal: Code(Code::B0087),
        profile: Service,
        held: 1,
        owner: "TESTING.md section 5, T4",
    }
    "flow/branch" {
        when: "an `if`, `unless`, ternary, `case` arm or guard",
        evidence: Branch,
        detector: Dynamic,
        refusal: Gate("test-beside"),
        profile: Default,
        owner: "COVERAGE.md B1, B2; each arm a probe of `blue test --coverage` (`blue_lang_test::Arms`), judged as `unbranched: <pkg> <n>` debt",
    }
    "flow/early-return" {
        when: "a `?` early return",
        evidence: Branch,
        detector: Dynamic,
        refusal: Gate("test-beside"),
        profile: Default,
        owner: "COVERAGE.md B4; `?` lowers to an `if`, so its two arms are probed",
    }
    "flow/loop" {
        when: "a loop or recursion that may run zero times",
        evidence: Branch,
        detector: Dynamic,
        refusal: Design("COVERAGE CV5: strict profile"),
        profile: Strict,
        owner: "COVERAGE.md B5",
    }
    "flow/condition" {
        when: "an `and` or `or` operand in a decision (MC/DC)",
        evidence: Branch,
        detector: Dynamic,
        refusal: Design("COVERAGE CV5: strict profile"),
        profile: Strict,
        owner: "COVERAGE.md B6",
    }
    "flow/boundary" {
        when: "a comparison with a literal in a branch",
        evidence: Branch,
        detector: Dynamic,
        refusal: Design("COVERAGE CV5: strict profile"),
        profile: Strict,
        owner: "COVERAGE.md B7",
    }
    "error/raise" {
        when: "a `raise` site",
        evidence: Branch,
        detector: Dynamic,
        refusal: Gate("test-beside"),
        profile: Default,
        owner: "COVERAGE.md E1; a raise in an arm is that arm, elsewhere it runs when its definition is reached",
    }
    "error/expected" {
        when: "a raised tag",
        evidence: Raise,
        detector: Static,
        refusal: Code(Code::B0091),
        profile: Default,
        owner: "COVERAGE.md E2",
    }
    "error/handler" {
        when: "a `rescue` handler",
        evidence: Branch,
        detector: Dynamic,
        refusal: Gate("test-beside"),
        profile: Default,
        owner: "COVERAGE.md E3; a `rescue` handler is an arm",
    }
    "data/variant" {
        when: "a variant of a declared union",
        evidence: Unit,
        detector: Static,
        refusal: Design("COVERAGE CV3"),
        profile: Default,
        owner: "COVERAGE.md D1",
    }
    "data/optional" {
        when: "an optional parameter or a nilable value",
        evidence: Branch,
        detector: Dynamic,
        refusal: Design("COVERAGE CV1: argument shapes per call site"),
        profile: Default,
        owner: "COVERAGE.md D2",
    }
    "config/flag" {
        when: "an `enable` or `enabled` field",
        evidence: Branch,
        detector: Static,
        refusal: Design("COVERAGE CV3"),
        profile: Default,
        owner: "COVERAGE.md C1",
    }
    "strength/assertion" {
        when: "a test block of a bidama",
        evidence: Assertion,
        detector: Static,
        refusal: Code(Code::B0088),
        profile: Default,
        owner: "COVERAGE.md S1",
    }
    "strength/tautology" {
        when: "an assertion that holds whatever the code does (`assert true`, `x == x`)",
        evidence: Assertion,
        detector: Static,
        refusal: Code(Code::B0089),
        profile: Default,
        owner: "COVERAGE.md S2",
    }
    "strength/slice" {
        when: "an assertion whose backward slice reaches no definition outside the test",
        evidence: Assertion,
        detector: Dynamic,
        refusal: Design("COVERAGE CV4: a data-flow slice in the recorder"),
        profile: Default,
        owner: "COVERAGE.md S3, S4",
    }
    "strength/deterministic" {
        when: "a test",
        evidence: Assertion,
        detector: Dynamic,
        refusal: Design("COVERAGE S6: `blue test --rerun N` finds a test whose verdict differs between runs (T8); no gate runs it by default, since a second run doubles a check until H3 rung 3 runs only what changed"),
        profile: Default,
        owner: "COVERAGE.md S6; TESTING.md T8",
    }
    "strength/mutant" {
        when: "a mutation site in a strict package",
        evidence: Mutation,
        detector: Dynamic,
        refusal: Design("COVERAGE CV5: heni per site, incremental by identity; the ratio ratchet holds today (checks.heni-mutations)"),
        profile: Strict,
        owner: "COVERAGE.md S5",
    }
    "pipeline/stage" {
        when: "the program of a Bluefile `check` row",
        evidence: Declared,
        detector: Project,
        refusal: Code(Code::B0092),
        profile: Default,
        owner: "TESTING.md T3; the `:push` rows are the pre-push gate list (`gen/prepush.b`), `blue test DIR --stage S` runs a stage",
    }
    "pipeline/ci" {
        when: "a CI workflow file of blue's own",
        evidence: Rendering,
        detector: Project,
        refusal: Gate("workflows"),
        profile: Default,
        owner: "TESTING.md T5: `.github/workflows/ci.yml` is rendered by `gen/ci.b`; `checks.workflows` refuses a workflow no `generate` row renders, beside the 7 hand-written ones `hand_workflows` holds, which only shrink",
    }
    "pipeline/release" {
        when: "a release or delivery step",
        evidence: Declared,
        detector: Project,
        refusal: Design("TESTING T7"),
        profile: Default,
        owner: "TESTING.md T7",
    }
}

/// The row for `id`.
#[must_use]
pub fn by_id(id: &str) -> Option<&'static Obligation> {
    OBLIGATIONS.iter().find(|o| o.id == id)
}

/// The row whose refusal is `code`.
#[must_use]
pub fn of_code(code: Code) -> Option<&'static Obligation> {
    OBLIGATIONS
        .iter()
        .find(|o| o.refusal == Refusal::Code(code))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_unique_and_spelled_family_slash_name() {
        let mut seen = std::collections::BTreeSet::new();
        for o in OBLIGATIONS {
            assert!(seen.insert(o.id), "`{}` is registered twice", o.id);
            let (family, name) = o.id.split_once('/').unwrap_or_else(|| {
                panic!("`{}` is not family/name", o.id);
            });
            for part in [family, name] {
                assert!(
                    !part.is_empty()
                        && part
                            .chars()
                            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-'),
                    "`{}`: each part is lowercase words joined by hyphens",
                    o.id
                );
            }
        }
    }

    #[test]
    fn every_code_row_names_an_enforced_waivable_rule_of_its_own() {
        let mut codes = std::collections::BTreeSet::new();
        for o in OBLIGATIONS {
            match o.refusal {
                Refusal::Code(c) => {
                    assert!(codes.insert(c), "{c} refuses two obligations");
                    let r = c.rule();
                    assert!(
                        r.active() || o.held == 0,
                        "{}: {c} is still ratcheted, so its debt is the census's ratchet and the row holds no waivers",
                        o.id
                    );
                    assert!(
                        r.waivable,
                        "{}: {c} admits no waiver, so debt has no place to be held",
                        o.id
                    );
                }
                Refusal::Gate(g) => assert!(!g.is_empty(), "{}", o.id),
                Refusal::Design(why) => {
                    assert!(
                        !why.is_empty(),
                        "{}: a design row says what blocks it",
                        o.id
                    );
                    assert_eq!(o.held, 0, "{}: a design row holds no debt", o.id);
                }
            }
        }
    }

    #[test]
    fn a_code_finds_its_row_and_an_id_its_row() {
        for o in OBLIGATIONS {
            assert_eq!(by_id(o.id).map(|r| r.id), Some(o.id));
            if let Refusal::Code(c) = o.refusal {
                assert_eq!(of_code(c).map(|r| r.id), Some(o.id));
            }
        }
        assert!(by_id("reach/none").is_none());
    }
}
