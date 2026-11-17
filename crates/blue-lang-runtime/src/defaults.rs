//! Each definition's defaults, explained: W0.2 of `docs/FACTS.md`.
//!
//! For every top-level definition of a program this names the facts blue
//! holds about it (pure or why not, whether it calls itself at two or more
//! places, whether it is typed), the defaults those facts fire (the memo,
//! fusion, folding, the membership index) and, for a default that does not
//! fire, the one fact it is missing. It runs the same passes the prepare
//! stage runs, on the same tree, so what it reports is what a run does; each
//! pass's switch (`BLUE_FUSE`, `BLUE_FOLD`, `BLUE_INDEX`, `BLUE_MEMO`) is
//! honoured.
//!
//! The store-backed defaults (the native tier, the fleet memo) need the
//! store, which this crate does not reach: `blue shift --defaults` adds them.

use tatara_lisp::Spanned;

use crate::def_hash::DefKind;
use crate::reach::Reach;

/// One rule's verdict for one definition.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verdict {
    /// The default fires: what it does here.
    Fires(String),
    /// The default could apply and does not: the fact it is missing.
    Missing(String),
}

/// One definition's facts and the defaults they decide.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Atom {
    /// The key a run names it by.
    pub key: String,
    /// Its content hash, the key of every store-backed default.
    pub hash: crate::def_hash::DefHash,
    /// The index of its top-level form.
    pub top_level: usize,
    /// Whether it is a function (a value definition gets no call defaults).
    pub function: bool,
    /// Whether its answer is a function of its arguments alone.
    pub pure: bool,
    /// Why it is not pure, when it is not.
    pub volatile: Option<String>,
    /// Whether it calls itself at two or more places.
    pub overlapping: bool,
    /// Whether its parameters carry types.
    pub typed: bool,
    /// Each rule's verdict, by rule id (`R2`, `R3`, `R4`, `R10`).
    pub rules: Vec<(String, Verdict)>,
}

/// The facts and defaults of each definition of `lowered`, a program past the
/// check stage. `lowered` is what [`crate::pipeline::lower`] returns.
#[must_use]
pub fn explain(lowered: &[Spanned]) -> Vec<Atom> {
    let erased = crate::erase::unfused(lowered);
    let hashes = crate::def_hash::hash_program(lowered);
    let reach = crate::reach::reach_program(&erased, &hashes);
    let overlapping = crate::door::overlapping(&erased);
    let fused = if crate::fuse::enabled() {
        crate::fuse::fuse(erased.clone(), lowered).sites
    } else {
        Vec::new()
    };
    let folded = if crate::fold::enabled() {
        crate::fold::fold(erased.clone(), lowered).sites
    } else {
        Vec::new()
    };
    let indexed = if crate::member_index::enabled() {
        crate::member_index::index(erased.clone(), lowered).sites
    } else {
        Vec::new()
    };
    let memo_on = std::env::var("BLUE_MEMO").map_or(true, |v| v.trim().is_empty());
    let mut out = Vec::new();
    for (d, r) in hashes.defs().iter().zip(reach) {
        let Some((_, kind)) = lowered.get(d.top_level).and_then(crate::def_hash::defined) else {
            continue;
        };
        if kind == DefKind::Macro {
            continue;
        }
        let i = d.top_level;
        let function = kind == DefKind::Function;
        let typed = lowered[i]
            .as_list()
            .and_then(|items| items.first())
            .and_then(Spanned::as_symbol)
            == Some("define-typed");
        let (pure, volatile) = match &r {
            Reach::Pure => (true, None),
            Reach::Volatile(v) => (false, Some(v.to_string())),
        };
        let repeats = overlapping.iter().any(|(t, _)| *t == i);
        let mut rules = Vec::new();
        if repeats {
            let verdict = match (&volatile, memo_on) {
                (None, true) => Verdict::Fires(
                    "its repeated calls are answered from a table (it calls itself at two or more places)"
                        .to_string(),
                ),
                (None, false) => Verdict::Missing("BLUE_MEMO names a mode, so the planner stands aside".to_string()),
                (Some(why), _) => Verdict::Missing(format!("it is not pure: {why}")),
            };
            rules.push(("R2".to_string(), verdict));
        }
        for (_, chain) in fused.iter().filter(|(t, _)| *t == i) {
            rules.push((
                "R3".to_string(),
                Verdict::Fires(format!("the chain {chain} runs as one pass")),
            ));
        }
        for (_, call) in folded.iter().filter(|(t, _)| *t == i) {
            rules.push((
                "R4".to_string(),
                Verdict::Fires(format!(
                    "a call of `{}` on literals is answered before the run",
                    crate::observe::display_key(call)
                )),
            ));
        }
        for (_, list) in indexed.iter().filter(|(t, _)| *t == i) {
            rules.push((
                "R10".to_string(),
                Verdict::Fires(format!(
                    "membership in `{list}` is answered from a per-call index"
                )),
            ));
        }
        out.push(Atom {
            key: d.key.clone(),
            hash: d.hash,
            top_level: i,
            function,
            pure,
            volatile,
            overlapping: repeats,
            typed,
            rules,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn atoms(src: &str) -> Vec<Atom> {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        explain(&crate::pipeline::lower(&checked.program, &checked.names))
    }

    fn atom<'a>(all: &'a [Atom], key: &str) -> &'a Atom {
        all.iter().find(|a| a.key == key).expect("the definition")
    }

    fn fires(a: &Atom, rule: &str) -> bool {
        a.rules
            .iter()
            .any(|(r, v)| r == rule && matches!(v, Verdict::Fires(_)))
    }

    #[test]
    fn each_definition_names_the_defaults_its_facts_fire() {
        let all = atoms(
            "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\ndef area(w, h)\n  w * h\nend\n\ndef total(xs, allowed)\n  map((x) -> x + area(3, 4), filter((x) -> member?(x, allowed), xs))\nend\n",
        );
        let fib = atom(&all, "%root/fib");
        assert!(fib.pure && fib.overlapping && fires(fib, "R2"), "{fib:?}");
        let area = atom(&all, "%root/area");
        assert!(area.pure && area.rules.is_empty(), "{area:?}");
        let total = atom(&all, "%root/total");
        assert!(fires(total, "R4") && fires(total, "R10"), "{total:?}");
    }

    #[test]
    fn a_default_that_does_not_fire_names_the_missing_fact() {
        let all = atoms(
            "def walk(n)\n  if n < 2\n    now_ms\n  else\n    walk(n - 1) + walk(n - 2)\n  end\nend\n",
        );
        let walk = atom(&all, "%root/walk");
        assert!(!walk.pure);
        let memo = walk
            .rules
            .iter()
            .find(|(r, _)| r == "R2")
            .expect("an R2 verdict");
        assert!(
            matches!(&memo.1, Verdict::Missing(why) if why.contains("not pure") && why.contains("now_ms")),
            "{memo:?}"
        );
    }
}
