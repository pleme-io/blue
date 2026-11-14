//! The obligation graph: relations between obligations, as one table of data.
//!
//! An obligation ([`crate::obligations`]) is a node. A relation is an edge
//! between two codes, of a [`Kind`] the registry declares once in [`kinds!`]:
//! the sources that may evidence it, what a ratified edge of the kind makes
//! the check stage do ([`Action`]), and whether the kind is on.
//!
//! **Discovery proposes, the registry decides.** `blue obligations discover`
//! (the `gaisou` bidama) mines edges from the corpus and prints each with its
//! evidence, its tier and its state. A mined edge is a candidate until a row
//! of [`relations!`] names it: [`State::Ratified`] makes it a compiler fact,
//! [`State::Rejected`] keeps discovery from proposing it again and says why,
//! [`State::Off`] keeps the row and its evidence while the check stage ignores
//! it. A kind with `enabled: false` turns every edge of the kind off without
//! deleting a row.
//!
//! **Tiers are evidence, not opinion.** [`Tier::Observed`] is one source,
//! [`Tier::Corroborated`] two or more independent ones. A row records the tier
//! it was ratified at; discovery fails its check when a live row's kind no
//! longer finds the edge, so a ratified fact the corpus stopped showing is
//! caught, not trusted.

use crate::rules::Code;
use crate::waiver::Waiver;
use crate::Diagnostic;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Source {
    Registry,
    Census,
    Consumers,
    History,
}

impl Source {
    pub const ALL: &'static [Source] = &[
        Source::Registry,
        Source::Census,
        Source::Consumers,
        Source::History,
    ];

    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Source::Registry => "registry",
            Source::Census => "census",
            Source::Consumers => "consumers",
            Source::History => "history",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    Order,
    Note,
    Refuse(Code),
}

impl Action {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Action::Order => "order",
            Action::Note => "note",
            Action::Refuse(c) => c.as_str(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Kind {
    Implies,
    CoOccurs,
    Exclusive,
    Trades,
    FixedTogether,
}

#[derive(Clone, Copy, Debug)]
pub struct KindRow {
    pub kind: Kind,
    pub symmetric: bool,
    pub sources: &'static [Source],
    pub action: Action,
    pub enabled: bool,
    pub law: &'static str,
}

macro_rules! kinds {
    ($(
        $kind:ident {
            label: $label:literal,
            symmetric: $sym:literal,
            sources: [$($source:ident),* $(,)?],
            action: $action:ident $(($code:expr))?,
            enabled: $enabled:literal,
            law: $law:literal $(,)?
        }
    )*) => {
        impl Kind {
            pub const ALL: &'static [Kind] = &[$(Kind::$kind),*];

            #[must_use]
            pub const fn label(self) -> &'static str {
                match self { $(Kind::$kind => $label),* }
            }

            #[must_use]
            pub fn parse(s: &str) -> Option<Kind> {
                match s { $($label => Some(Kind::$kind),)* _ => None }
            }
        }

        pub const KINDS: &[KindRow] = &[$(
            KindRow {
                kind: Kind::$kind,
                symmetric: $sym,
                sources: &[$(Source::$source),*],
                action: Action::$action $(($code))?,
                enabled: $enabled,
                law: $law,
            }
        ),*];
    };
}

kinds! {
    Implies {
        label: "implies",
        symmetric: false,
        sources: [Census, Consumers],
        action: Order,
        enabled: true,
        law: "where a holds, b holds: every site that owes b also owes a, so paying a is the first step to paying b",
    }
    CoOccurs {
        label: "co-occurs",
        symmetric: true,
        sources: [Census, Consumers],
        action: Note,
        enabled: true,
        law: "a and b are owed on the same sites more often than chance: a shared root no obligation names",
    }
    Exclusive {
        label: "exclusive",
        symmetric: true,
        sources: [Registry, Census],
        action: Refuse(Code::B0100),
        enabled: true,
        law: "a and b are never owed on one form, though chance expects them to be: one form cannot owe both, so a form that waives both waives one that covers nothing",
    }
    Trades {
        label: "trades",
        symmetric: false,
        sources: [History],
        action: Note,
        enabled: true,
        law: "a change that paid a's debt raised b's: fixing a tends to owe b next",
    }
    FixedTogether {
        label: "fixed-together",
        symmetric: true,
        sources: [History],
        action: Note,
        enabled: true,
        law: "a's debt and b's fell in the same changes: one fix pays both",
    }
}

impl Kind {
    #[must_use]
    pub fn row(self) -> &'static KindRow {
        KINDS
            .iter()
            .find(|k| k.kind == self)
            .expect("kinds! builds one row per kind")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tier {
    Observed,
    Corroborated,
}

impl Tier {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Tier::Observed => "observed",
            Tier::Corroborated => "corroborated",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Ratified,
    Rejected(&'static str),
    Off(&'static str),
}

impl State {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            State::Ratified => "ratified",
            State::Rejected(_) => "rejected",
            State::Off(_) => "off",
        }
    }

    #[must_use]
    pub const fn why(self) -> Option<&'static str> {
        match self {
            State::Ratified => None,
            State::Rejected(w) | State::Off(w) => Some(w),
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Relation {
    pub kind: Kind,
    pub a: Code,
    pub b: Code,
    pub state: State,
    pub tier: Tier,
    pub evidence: &'static str,
}

impl Relation {
    #[must_use]
    pub fn live(&self) -> bool {
        self.state == State::Ratified && self.kind.row().enabled
    }

    #[must_use]
    pub fn joins(&self, x: Code, y: Code) -> bool {
        (self.a == x && self.b == y) || (self.kind.row().symmetric && self.a == y && self.b == x)
    }
}

macro_rules! relations {
    ($(
        $kind:ident($a:ident, $b:ident) {
            state: $state:ident $(($why:literal))?,
            tier: $tier:ident,
            evidence: $evidence:literal $(,)?
        }
    )*) => {
        pub const RELATIONS: &[Relation] = &[$(
            Relation {
                kind: Kind::$kind,
                a: Code::$a,
                b: Code::$b,
                state: State::$state $(($why))?,
                tier: Tier::$tier,
                evidence: $evidence,
            }
        ),*];
    };
}

relations! {
    Exclusive(B0090, B0095) {
        state: Ratified,
        tier: Corroborated,
        evidence: "census: 0 of 15236 forms owe both where chance expects 2; registry: B0095 hands a definition no test calls to B0090",
    }
    Exclusive(B0056, B0085) {
        state: Rejected("population, not law: B0085 judges the first form of a generate program and B0056 a bidama's definition, so the zero says where each rule applies, not that one excludes the other"),
        tier: Observed,
        evidence: "census: 0 of 15236 forms owe both where chance expects 3",
    }
    Exclusive(B0085, B0090) {
        state: Rejected("population, not law: B0085 judges the first form of a generate program and B0090 a bidama's definition, so the zero says where each rule applies, not that one excludes the other"),
        tier: Observed,
        evidence: "census: 0 of 15236 forms owe both where chance expects 6",
    }
    Trades(B0012, B0016) {
        state: Ratified,
        tier: Observed,
        evidence: "history: 18 of 86 changes paid B0012 and raised B0016",
    }
    Trades(B0015, B0016) {
        state: Ratified,
        tier: Observed,
        evidence: "history: 10 of 86 changes paid B0015 and raised B0016",
    }
    FixedTogether(B0012, B0015) {
        state: Ratified,
        tier: Observed,
        evidence: "history: 20 of 86 changes paid both",
    }
    FixedTogether(B0056, B0057) {
        state: Ratified,
        tier: Observed,
        evidence: "history: 4 of 86 changes paid both",
    }
    FixedTogether(B0056, B0058) {
        state: Ratified,
        tier: Observed,
        evidence: "history: 4 of 86 changes paid both",
    }
}

#[derive(Clone, Copy, Debug)]
pub struct CandidateDecision {
    pub kind: &'static str,
    pub code: Code,
    pub state: State,
}

pub const CANDIDATES: &[CandidateDecision] = &[
    CandidateDecision {
        kind: "unregistered-debt",
        code: Code::B0056,
        state: State::Ratified,
    },
    CandidateDecision {
        kind: "unregistered-debt",
        code: Code::B0057,
        state: State::Ratified,
    },
    CandidateDecision {
        kind: "recurring-waiver",
        code: Code::B0083,
        state: State::Rejected(BULK),
    },
    CandidateDecision {
        kind: "recurring-waiver",
        code: Code::B0084,
        state: State::Rejected(BULK),
    },
    CandidateDecision {
        kind: "recurring-waiver",
        code: Code::B0085,
        state: State::Rejected(BULK),
    },
];

const BULK: &str = "bulk debt: one template written the day the obligation landed; the reason records when the debt was taken, not a shape a new obligation could name";

pub fn live(kind: Kind) -> impl Iterator<Item = &'static Relation> {
    RELATIONS.iter().filter(move |r| r.kind == kind && r.live())
}

#[must_use]
pub fn refuse_exclusive_waivers(waivers: &mut Vec<Waiver>) -> Vec<Diagnostic> {
    refuse_with(waivers, RELATIONS)
}

#[must_use]
pub fn refuse_with(waivers: &mut Vec<Waiver>, relations: &[Relation]) -> Vec<Diagnostic> {
    let mut refused = Vec::new();
    let mut dropped = Vec::new();
    for r in relations.iter().filter(|r| r.live()) {
        let Action::Refuse(code) = r.kind.row().action else {
            continue;
        };
        for (i, first) in waivers.iter().enumerate() {
            for (j, second) in waivers.iter().enumerate().skip(i + 1) {
                if first.top_level != second.top_level || !r.joins(first.code, second.code) {
                    continue;
                }
                let (early, later) = if first.span.start <= second.span.start {
                    (first, second)
                } else {
                    (second, first)
                };
                refused.push(
                    Diagnostic::new(
                        code,
                        format!(
                            "this form waives {} and {}, which are {}: one form never owes both",
                            early.code,
                            later.code,
                            r.kind.label()
                        ),
                        later.span,
                    )
                    .at_top_level(later.top_level)
                    .with_help(format!(
                        "waive only the code this form owes ({})",
                        r.evidence
                    )),
                );
                dropped.push(i);
                dropped.push(j);
            }
        }
    }
    dropped.sort_unstable();
    dropped.dedup();
    for i in dropped.into_iter().rev() {
        waivers.remove(i);
    }
    refused
}

pub fn annotate(diagnostics: &mut [Diagnostic]) {
    annotate_with(diagnostics, RELATIONS);
}

pub fn annotate_with(diagnostics: &mut [Diagnostic], relations: &[Relation]) {
    let live: Vec<&Relation> = relations.iter().filter(|r| r.live()).collect();
    let mut notes: Vec<(usize, String)> = Vec::new();
    for (i, d) in diagnostics.iter().enumerate() {
        for r in &live {
            let symmetric = r.kind.row().symmetric;
            match r.kind.row().action {
                Action::Order if d.code == r.b => {
                    if diagnostics
                        .iter()
                        .any(|o| o.code == r.a && o.top_level == d.top_level)
                    {
                        notes.push((
                            i,
                            format!("pay {} first: {} {} {}", r.a, r.a, r.kind.label(), r.b),
                        ));
                    }
                }
                Action::Note if d.code == r.a || (symmetric && d.code == r.b) => {
                    let other = if d.code == r.a { r.b } else { r.a };
                    notes.push((
                        i,
                        format!(
                            "{} {} {} ({}): {}",
                            d.code,
                            r.kind.label(),
                            other,
                            r.evidence,
                            other.rule().law
                        ),
                    ));
                }
                _ => {}
            }
        }
    }
    for (i, note) in notes {
        let d = &mut diagnostics[i];
        d.help = Some(match d.help.take() {
            Some(h) => format!("{h}; {note}"),
            None => note,
        });
    }
    let rank = |d: &Diagnostic| {
        live.iter()
            .filter(|r| r.kind.row().action == Action::Order && r.b == d.code)
            .count()
    };
    let mut start = 0;
    while start < diagnostics.len() {
        let form = diagnostics[start].top_level;
        let end = diagnostics[start..]
            .iter()
            .position(|d| d.top_level != form)
            .map_or(diagnostics.len(), |n| start + n);
        diagnostics[start..end].sort_by_key(rank);
        start = end;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_kind_has_a_row_a_law_and_a_source() {
        for k in Kind::ALL {
            let row = k.row();
            assert!(!row.law.trim().is_empty(), "{}", k.label());
            assert!(!row.sources.is_empty(), "{}", k.label());
            assert_eq!(Kind::parse(k.label()), Some(*k));
        }
        assert_eq!(KINDS.len(), Kind::ALL.len());
    }

    #[test]
    fn a_refusing_kind_names_an_enforced_rule_of_the_registry() {
        for k in KINDS {
            if let Action::Refuse(code) = k.action {
                assert!(code.rule().active(), "{code} refuses, so it is enforced");
            }
        }
    }

    #[test]
    fn every_row_joins_two_node_codes_once_with_its_why() {
        let mut seen = std::collections::BTreeSet::new();
        for r in RELATIONS {
            assert_ne!(r.a, r.b, "{} joins a code to itself", r.a);
            let key = if r.kind.row().symmetric && r.b < r.a {
                (r.kind, r.b, r.a)
            } else {
                (r.kind, r.a, r.b)
            };
            assert!(seen.insert(key), "{key:?} is decided twice");
            assert!(
                !r.kind.row().symmetric || r.a < r.b,
                "{key:?}: a symmetric row names the lesser code first, as discovery keys it"
            );
            for c in [r.a, r.b] {
                assert!(
                    crate::obligations::of_code(c).is_some() || c.rule().ratchet.is_some(),
                    "{c} is neither an obligation nor a ratcheted rule"
                );
            }
            if let Some(why) = r.state.why() {
                assert!(!why.trim().is_empty(), "{key:?} says why");
            }
            assert!(!r.evidence.trim().is_empty(), "{key:?} has evidence");
            assert!(
                r.state != State::Ratified
                    || r.kind.row().sources.len() < 2
                    || r.tier == Tier::Corroborated,
                "{key:?}: a kind two sources may show is ratified only when corroborated"
            );
        }
        for c in CANDIDATES {
            assert!(
                matches!(c.kind, "unregistered-debt" | "recurring-waiver"),
                "{}",
                c.kind
            );
        }
    }

    #[test]
    fn a_kind_configured_off_takes_its_ratified_rows_with_it() {
        for r in RELATIONS {
            assert_eq!(r.live(), r.state == State::Ratified && r.kind.row().enabled);
        }
        let off = Relation {
            kind: Kind::Exclusive,
            a: Code::B0090,
            b: Code::B0095,
            state: State::Off("configured off"),
            tier: Tier::Corroborated,
            evidence: "e",
        };
        assert!(!off.live());
        let mut ws = vec![waiver(Code::B0090, 0, 0), waiver(Code::B0095, 0, 9)];
        assert!(refuse_with(&mut ws, &[off]).is_empty());
        assert_eq!(ws.len(), 2);
    }

    fn row(kind: Kind, a: Code, b: Code) -> Relation {
        Relation {
            kind,
            a,
            b,
            state: State::Ratified,
            tier: Tier::Corroborated,
            evidence: "fixture",
        }
    }

    fn waiver(code: Code, top_level: usize, at: usize) -> Waiver {
        Waiver {
            code,
            reason: "r".into(),
            span: tatara_lisp::Span::new(at, at + 1),
            top_level,
        }
    }

    #[test]
    fn a_form_waiving_both_of_a_live_exclusive_pair_is_refused_once_and_loses_both() {
        let rels = [row(Kind::Exclusive, Code::B0090, Code::B0095)];
        let mut ws = vec![
            waiver(Code::B0095, 3, 10),
            waiver(Code::B0090, 3, 40),
            waiver(Code::B0090, 4, 90),
        ];
        let refused = refuse_with(&mut ws, &rels);
        assert_eq!(refused.len(), 1, "{refused:?}");
        assert_eq!(refused[0].code, Code::B0100);
        assert_eq!(refused[0].top_level, 3);
        assert_eq!(refused[0].span.start, 40);
        assert_eq!(
            ws.iter().map(|w| (w.code, w.top_level)).collect::<Vec<_>>(),
            vec![(Code::B0090, 4)]
        );
    }

    #[test]
    fn waivers_on_different_forms_or_of_an_unrelated_pair_are_not_refused() {
        let rels = [row(Kind::Exclusive, Code::B0090, Code::B0095)];
        let mut ws = vec![waiver(Code::B0090, 1, 0), waiver(Code::B0095, 2, 20)];
        assert!(refuse_with(&mut ws, &rels).is_empty());
        let mut ws = vec![waiver(Code::B0083, 1, 0), waiver(Code::B0084, 1, 20)];
        assert!(refuse_with(&mut ws, &rels).is_empty());
        assert_eq!(ws.len(), 2);
    }

    #[test]
    fn an_ordered_pair_on_one_form_reports_the_implied_first_and_names_it() {
        let rels = [row(Kind::Implies, Code::B0090, Code::B0096)];
        let span = tatara_lisp::Span::new(0, 1);
        let mut ds = vec![
            Diagnostic::new(Code::B0096, "b", span).at_top_level(0),
            Diagnostic::new(Code::B0090, "a", span).at_top_level(0),
            Diagnostic::new(Code::B0096, "elsewhere", span).at_top_level(1),
        ];
        annotate_with(&mut ds, &rels);
        assert_eq!(ds[0].code, Code::B0090);
        assert_eq!(ds[1].code, Code::B0096);
        assert!(ds[1]
            .help
            .as_deref()
            .unwrap_or("")
            .contains("pay B0090 first"));
        assert!(ds[2].help.is_none());
    }

    #[test]
    fn a_noted_edge_names_the_other_code_and_its_law_from_either_side_when_symmetric() {
        let rels = [
            row(Kind::Trades, Code::B0012, Code::B0016),
            row(Kind::FixedTogether, Code::B0012, Code::B0015),
        ];
        let span = tatara_lisp::Span::new(0, 1);
        let mut ds = vec![
            Diagnostic::new(Code::B0012, "a", span).at_top_level(0),
            Diagnostic::new(Code::B0015, "b", span).at_top_level(1),
            Diagnostic::new(Code::B0016, "c", span).at_top_level(2),
        ];
        annotate_with(&mut ds, &rels);
        let help = |i: usize| ds[i].help.clone().unwrap_or_default();
        assert!(help(0).contains("B0012 trades B0016"), "{}", help(0));
        assert!(help(0).contains(Code::B0016.rule().law));
        assert!(
            help(0).contains("B0012 fixed-together B0015"),
            "{}",
            help(0)
        );
        assert!(
            help(1).contains("B0015 fixed-together B0012"),
            "{}",
            help(1)
        );
        assert!(
            ds[2].help.is_none(),
            "trades runs one way: {:?}",
            ds[2].help
        );
    }
}
