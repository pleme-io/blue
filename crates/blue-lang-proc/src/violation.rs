//! What a crash violated, and where.
//!
//! From version 3 a crash trace ([`crate::trace`]) carries a `violation`
//! block, read off the real exit and the tape:
//!
//! ```text
//! "violation": null | { "class": CLASS,
//!   "capability": LABEL | null, "host": NAME | null, "entry": n | null,
//!   "at": null | { "span": [start, end], "definition": KEY | null,
//!                  "file": PATH | null, "line": n | null, "column": n | null } }
//! ```
//!
//! A class is one of the five names a forensic reader uses
//! (`theory/IBUKI-FORENSICS.md`). Two are produced, each from one exit:
//!
//! | class | the exit |
//! |---|---|
//! | `LatticeCeilingBreach` | `fatal`, its tape ending on a `capability-breach` entry |
//! | `ThermodynamicCycleExhaustion` | `runaway`: the fuel or the call depth ran out |
//!
//! The other three name nothing a process exit is, so the type cannot hold
//! them and a reader refuses a file that claims one, naming why
//! ([`UNPRODUCED`]). A `crashed` or `killed` exit has no class: its block is
//! `null`, and the exit says what happened.
//!
//! For a breach the block names the host name the call reached, the
//! capability it demanded, the tape entry that recorded it, and its source
//! coordinate: the span the breaching call had, the definition in the
//! process's code holding a form at exactly that span, and that span's file,
//! line and column when the runtime gave the node its [`Places`].

use blue_lang_waku::Capability;
use serde_json::{json, Value as Json};
use tatara_lisp::{Span, Spanned, SpannedForm};

use crate::receipt::{Place, Places};
use crate::trace::TapeEntry;

/// The kind of the fatal error a capability breach raises.
pub const BREACH: &str = "capability-breach";

/// A violation a process exit can be.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Class {
    /// A call reached a host capability the process's hold withholds.
    LatticeCeilingBreach,
    /// The process spent its fuel or its call depth.
    ThermodynamicCycleExhaustion,
}

/// The classes a forensic reader names that no process exit produces, each
/// with why.
pub const UNPRODUCED: [(&str, &str); 3] = [
    (
        "ContractAssertionFailure",
        "an assert, doctest or typed-contract failure fails a test or a check, never a process: \
         `assert` is bound only inside a test",
    ),
    (
        "SpatialMemoryExhaustion",
        "blue bounds steps and call depth, not memory (docs/SAFETY.md, row 12)",
    ),
    (
        "CausalMerkleDivergence",
        "blue has no strands, so there is no state root to diverge from",
    ),
];

impl Class {
    /// Every class a trace may name.
    pub const ALL: [Class; 2] = [
        Class::LatticeCeilingBreach,
        Class::ThermodynamicCycleExhaustion,
    ];

    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Class::LatticeCeilingBreach => "LatticeCeilingBreach",
            Class::ThermodynamicCycleExhaustion => "ThermodynamicCycleExhaustion",
        }
    }

    /// The class `name` names.
    ///
    /// # Errors
    ///
    /// For a class no exit produces, naming why; for any other name, naming
    /// the classes there are.
    pub fn named(name: &str) -> Result<Self, String> {
        if let Some(c) = Self::ALL.into_iter().find(|c| c.name() == name) {
            return Ok(c);
        }
        if let Some((_, why)) = UNPRODUCED.iter().find(|(n, _)| *n == name) {
            return Err(format!(
                "`{name}` is not a class a process exit produces: {why}"
            ));
        }
        Err(format!(
            "`{name}` is not a violation class; a trace names {}",
            Self::ALL.map(Class::name).join(" or ")
        ))
    }
}

/// Where a breaching call was.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Coordinate {
    pub span: Span,
    /// The key of the definition holding a form at exactly [`Self::span`].
    pub definition: Option<String>,
    pub place: Option<Place>,
}

/// What a crash violated.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Violation {
    pub class: Class,
    /// The capability a breaching call demanded.
    pub capability: Option<Capability>,
    /// The host name a breaching call reached.
    pub host: Option<String>,
    /// The tape entry that recorded the breach.
    pub entry: Option<usize>,
    pub at: Option<Coordinate>,
}

fn capability_of(host: &str) -> Option<Capability> {
    Capability::host_effects()
        .into_iter()
        .find(|c| c.names().contains(&host))
}

/// The key a top-level `define` binds: `(define (key …) …)` or
/// `(define key value)`.
#[must_use]
pub fn defined_key(form: &Spanned) -> Option<&str> {
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != "define" {
        return None;
    }
    let head = items.get(1)?;
    head.as_list()
        .map_or_else(|| head.as_symbol(), |h| h.first()?.as_symbol())
}

fn holds(form: &Spanned, span: Span) -> bool {
    form.span == span
        || match &form.form {
            SpannedForm::List(items) => items.iter().any(|c| holds(c, span)),
            SpannedForm::Quote(x)
            | SpannedForm::Quasiquote(x)
            | SpannedForm::Unquote(x)
            | SpannedForm::UnquoteSplice(x) => holds(x, span),
            SpannedForm::Nil | SpannedForm::Atom(_) => false,
        }
}

/// The key of the definition in `defs` holding a form at exactly `span`.
#[must_use]
pub fn enclosing(defs: &[Spanned], span: Span) -> Option<&str> {
    defs.iter().find(|d| holds(d, span)).and_then(defined_key)
}

impl Violation {
    /// The violation an exit of `kind` names, read off its tape. The
    /// coordinate's definition is found in `defs`, its place in `places`.
    #[must_use]
    pub fn of(kind: &str, tape: &[TapeEntry], defs: &[Spanned], places: &Places) -> Option<Self> {
        match kind {
            "runaway" => Some(Self {
                class: Class::ThermodynamicCycleExhaustion,
                capability: None,
                host: None,
                entry: None,
                at: None,
            }),
            "fatal" => {
                let (entry, e) = tape
                    .iter()
                    .enumerate()
                    .rev()
                    .find(|(_, e)| e.fatal.as_deref() == Some(BREACH))?;
                let at = e.at.filter(|s| !s.is_synthetic()).map(|span| {
                    let definition = enclosing(defs, span).map(str::to_string);
                    let place = definition.as_deref().and_then(|d| places.locate(d, span));
                    Coordinate {
                        span,
                        definition,
                        place,
                    }
                });
                Some(Self {
                    class: Class::LatticeCeilingBreach,
                    capability: capability_of(&e.call),
                    host: Some(e.call.clone()),
                    entry: Some(entry),
                    at,
                })
            }
            _ => None,
        }
    }

    /// This violation as trace JSON.
    #[must_use]
    pub fn to_json(&self) -> Json {
        json!({
            "class": self.class.name(),
            "capability": self.capability.map(Capability::label),
            "host": self.host,
            "entry": self.entry,
            "at": self.at.as_ref().map_or(Json::Null, |c| json!({
                "span": [c.span.start, c.span.end],
                "definition": c.definition,
                "file": c.place.as_ref().map(|p| p.file.clone()),
                "line": c.place.as_ref().map(|p| p.line),
                "column": c.place.as_ref().map(|p| p.column),
            })),
        })
    }

    /// Read a violation back.
    ///
    /// # Errors
    ///
    /// When the class is missing, unproduced or unknown, a capability label
    /// names none, or a span is not two offsets.
    pub fn from_json(j: &Json) -> Result<Self, String> {
        let class = Class::named(
            j.get("class")
                .and_then(Json::as_str)
                .ok_or("a violation without a class")?,
        )?;
        let capability = match j.get("capability").and_then(Json::as_str) {
            None => None,
            Some(l) => Some(
                Capability::host_effects()
                    .into_iter()
                    .find(|c| c.label() == l)
                    .ok_or_else(|| format!("`{l}` is not a host capability"))?,
            ),
        };
        let usize_of = |v: Option<&Json>| {
            v.and_then(Json::as_u64)
                .and_then(|n| usize::try_from(n).ok())
        };
        let at = match j.get("at") {
            None | Some(Json::Null) => None,
            Some(a) => {
                let span = match a.get("span").and_then(Json::as_array).map(Vec::as_slice) {
                    Some([s, e]) => Span::new(
                        usize_of(Some(s)).ok_or("a span offset")?,
                        usize_of(Some(e)).ok_or("a span offset")?,
                    ),
                    _ => return Err("a coordinate without a span".into()),
                };
                let place = match (
                    a.get("file").and_then(Json::as_str),
                    usize_of(a.get("line")),
                    usize_of(a.get("column")),
                ) {
                    (Some(file), Some(line), Some(column)) => Some(Place {
                        file: file.to_string(),
                        line,
                        column,
                    }),
                    _ => None,
                };
                Some(Coordinate {
                    span,
                    definition: a
                        .get("definition")
                        .and_then(Json::as_str)
                        .map(str::to_string),
                    place,
                })
            }
        };
        Ok(Self {
            class,
            capability,
            host: j.get("host").and_then(Json::as_str).map(str::to_string),
            entry: usize_of(j.get("entry")),
            at,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::sync::Arc;
    use tatara_lisp_eval::Value;

    fn entry(call: &str, fatal: Option<&str>, at: Option<Span>) -> TapeEntry {
        TapeEntry {
            call: call.into(),
            outcome: fatal.map_or(Ok(Value::Nil), |_| Err("refused".into())),
            fatal: fatal.map(str::to_string),
            at,
        }
    }

    const SRC: &str = "(define (%root/w p) (receive) (read_file p))";

    fn defs() -> Vec<Spanned> {
        tatara_lisp::read_spanned(SRC).expect("reads")
    }

    fn call_span() -> Span {
        let start = SRC.find("(read_file").expect("call");
        Span::new(start, start + "(read_file p)".len())
    }

    #[test]
    fn a_breach_names_its_host_its_capability_its_entry_and_its_definition() {
        let places = Places::default();
        places.defer(|| {
            BTreeMap::from([(
                "%root/w".to_string(),
                crate::receipt::Source {
                    file: "w.b".into(),
                    text: Arc::from(SRC),
                },
            )])
        });
        let tape = [
            entry("receive", None, None),
            entry("read_file", Some(BREACH), Some(call_span())),
        ];
        let v = Violation::of("fatal", &tape, &defs(), &places).expect("a breach");
        assert_eq!(v.class, Class::LatticeCeilingBreach);
        assert_eq!(v.host.as_deref(), Some("read_file"));
        assert_eq!(v.capability, Some(Capability::FileSystem));
        assert_eq!(v.entry, Some(1));
        let at = v.at.clone().expect("a coordinate");
        assert_eq!(at.definition.as_deref(), Some("%root/w"));
        assert_eq!(
            at.place.map(|p| p.to_string()).as_deref(),
            Some(format!("w.b:1:{}", call_span().start + 1).as_str())
        );
        assert_eq!(Violation::from_json(&v.to_json()).expect("reads"), v);
    }

    #[test]
    fn only_a_breach_and_a_runaway_are_violations() {
        let none = Places::default();
        let tape = [entry("read_file", Some(BREACH), None)];
        for (kind, class) in [
            ("fatal", Some(Class::LatticeCeilingBreach)),
            ("runaway", Some(Class::ThermodynamicCycleExhaustion)),
            ("crashed", None),
            ("killed", None),
            ("normal", None),
        ] {
            assert_eq!(
                Violation::of(kind, &tape, &[], &none).map(|v| v.class),
                class,
                "{kind}"
            );
        }
        assert!(
            Violation::of("fatal", &[entry("x", Some("other"), None)], &[], &none).is_none(),
            "a fatal exit whose tape holds no breach names no class"
        );
        let v = Violation::of("fatal", &tape, &[], &none).expect("breach");
        assert!(v.at.is_none(), "a breach with no span has no coordinate");
    }

    #[test]
    fn a_trace_naming_an_unproduced_class_is_refused_with_why() {
        for (name, why) in UNPRODUCED {
            let err = Violation::from_json(&json!({"class": name})).expect_err(name);
            assert!(err.contains(why), "{err}");
        }
        let err = Class::named("Gremlin").expect_err("unknown");
        assert!(
            err.contains("LatticeCeilingBreach or ThermodynamicCycleExhaustion"),
            "{err}"
        );
        for c in Class::ALL {
            assert_eq!(Class::named(c.name()), Ok(c));
        }
    }

    #[test]
    fn the_enclosing_definition_holds_a_form_at_exactly_the_span() {
        let defs = defs();
        assert_eq!(enclosing(&defs, call_span()), Some("%root/w"));
        assert_eq!(enclosing(&defs, Span::new(1, 2)), None);
        let value = tatara_lisp::read_spanned("(define %root/v (lambda () 1))").expect("reads");
        assert_eq!(defined_key(&value[0]), Some("%root/v"));
    }
}
