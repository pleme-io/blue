//! blue's rewrites as rules over one e-graph: S3 of docs/ENGINES.md.
//!
//! Fusion becomes three form rules, one for each stage word: over a stage
//! call they offer the tree the program's fusion plan gives that call
//! ([`crate::fuse::Plan`]), so which chains fuse, and the purity and scope
//! that decide it, stay fusion's own, read from the whole program. A fused
//! tree keeps the unfused chain as its fallback, and in the graph that
//! fallback is the class the fused tree joins, so a fused tree goes in as an
//! opaque leaf (`%fused:N`) whose tree a side table holds: the price reads
//! the fused body from the table, and [`cheapest`] puts the tree back after
//! extraction.
//!
//! The price is [`crate::cost`]'s, node by node, as extraction needs: a word
//! the table prices costs its call and its elements, a function written in
//! place costs its body once per element, a `try` its body, a `catch`
//! nothing, any other node a step, each plus its children.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use blue_lang_saturate::{form_rule, Limits, Rule};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::check_cache::{CheckCache, Pass};
use crate::cost::{self, Table};
use crate::def_hash::DefHash;

const FUSED: &str = "%fused:";

/// The fused trees a set of rules made, by number, and the number each
/// matched tree was given: a rule that fires again on a tree it has seen
/// gives the leaf it gave before, so the graph saturates.
#[derive(Clone, Default)]
pub struct Held(Arc<Mutex<(Vec<Spanned>, BTreeMap<String, usize>)>>);

impl Held {
    fn lock(&self) -> std::sync::MutexGuard<'_, (Vec<Spanned>, BTreeMap<String, usize>)> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn seen(&self, matched: &str) -> Option<usize> {
        self.lock().1.get(matched).copied()
    }

    fn keep(&self, matched: String, form: Spanned) -> usize {
        let mut held = self.lock();
        held.0.push(form);
        let n = held.0.len() - 1;
        held.1.insert(matched, n);
        n
    }

    fn get(&self, n: usize) -> Option<Spanned> {
        self.lock().0.get(n).cloned()
    }
}

fn leaf(name: &str) -> Spanned {
    Spanned::new(
        Span::synthetic(),
        SpannedForm::Atom(Atom::Symbol(name.to_string())),
    )
}

/// The rules over the stage call `written`, whose tree the program's fusion
/// plan gives as `fused`: one fusion rule per stage word, each offering that
/// tree for that call and for nothing else.
#[must_use]
pub fn rules(written: &Spanned, fused: &Spanned, held: &Held) -> Vec<Rule> {
    let offer = Arc::new((written.to_sexp().to_string(), fused.clone()));
    [
        ("fuse-map", "(map ?f ?xs)"),
        ("fuse-filter", "(filter ?p ?xs)"),
        ("fuse-reduce", "(reduce ?f ?z ?xs)"),
    ]
    .into_iter()
    .filter_map(|(name, pattern)| {
        let offer = Arc::clone(&offer);
        let held = held.clone();
        form_rule(name, pattern, move |form: &Spanned| {
            let matched = form.to_sexp().to_string();
            if matched != offer.0 {
                return None;
            }
            let n = match held.seen(&matched) {
                Some(n) => n,
                None => held.keep(matched, offer.1.clone()),
            };
            Some(leaf(&format!("{FUSED}{n}")))
        })
        .ok()
    })
    .collect()
}

fn fused_number(op: &str) -> Option<usize> {
    op.strip_prefix(FUSED)?.parse().ok()
}

/// What a node costs, its children costing `children`, under `table` with
/// lists of `n` elements.
pub fn node_price<'a>(
    table: &'a Table,
    n: f64,
    held: &Held,
) -> impl FnMut(&str, &[f64]) -> f64 + 'a {
    let held = held.clone();
    let w = table.alloc_weight;
    move |op: &str, children: &[f64]| {
        let sum: f64 = children.iter().sum();
        if let Some(tree) = fused_number(op).and_then(|i| held.get(i)) {
            return cost::estimate(&tree, table, n).units(w);
        }
        match op {
            "lambda" => children.iter().skip(1).sum::<f64>() * n,
            "try" => children.first().copied().unwrap_or(0.0),
            "catch" | "quote" | "#quote" => 0.0,
            "#list" => sum,
            _ if children.is_empty() => 0.0,
            word => match table.words.get(word) {
                Some(p) => p.call.plus(p.element.times(n)).units(w) + sum,
                None => 1.0 + sum,
            },
        }
    }
}

fn expand(form: Spanned, held: &Held) -> Spanned {
    if let Some(tree) = form
        .as_symbol()
        .and_then(fused_number)
        .and_then(|i| held.get(i))
    {
        return expand(tree, held);
    }
    match form.form {
        SpannedForm::List(items) => Spanned::new(
            form.span,
            SpannedForm::List(items.into_iter().map(|i| expand(i, held)).collect()),
        ),
        other => Spanned::new(form.span, other),
    }
}

/// The cheapest form the rules prove equal to the stage call `written`,
/// whose fused tree is `fused`, under `table` with lists of 1000 elements,
/// and its price before and after; `written` itself when nothing is cheaper.
#[must_use]
pub fn cheapest(
    written: &Spanned,
    fused: &Spanned,
    table: &Table,
    limits: Limits,
) -> (Spanned, f64, f64) {
    let held = Held::default();
    let rules = rules(written, fused, &held);
    let (out, before, after) =
        blue_lang_saturate::cheapest(written, &rules, limits, node_price(table, 1000.0, &held));
    (expand(out, &held), before, after)
}

/// Whether rule R19 runs: a measured cost table is installed
/// ([`cost::installed`]), `BLUE_SATURATE=off` is not set, and no command
/// holds the rewrites off.
#[must_use]
pub fn enabled() -> bool {
    cost::installed().is_some() && !crate::fuse::held_off() && !crate::kitei::switched_off("R19")
}

/// Rule R19 (S4 of docs/ENGINES.md): each outermost stage call in which the
/// program's fusion plan ([`crate::fuse::Plan`]) fuses a chain is saturated
/// within the default limits, and becomes the plan's tree for it when that
/// is cheaper under `table`, the written call on a tie. A call the plan
/// leaves alone is left alone, so R19 takes only what fusion takes, and
/// every other form keeps its positions. The choice is kept in the check
/// cache by the call's text, in the bucket of the hash of the definition it
/// is in (the top-level form's digest outside one), and recalled after: a
/// recalled `fused` takes the plan's tree again, so a stale choice can cost a
/// speedup and never an answer.
#[must_use]
pub fn program(erased: Vec<Spanned>, defined: &[Spanned], table: &Table) -> crate::fuse::Fused {
    let cache = crate::check_cache::installed();
    let fused = {
        let plan = crate::fuse::Plan::of(&erased, defined);
        (!plan.is_empty()).then(|| {
            plan.fuse(Some(&mut |top, written, fused| {
                let memory = cache.as_ref().map(|c| {
                    let bucket = plan.hashes().at(top).map_or_else(
                        || DefHash(crate::check_cache::tree_digest(&erased[top])),
                        |d| d.hash,
                    );
                    (c, bucket)
                });
                decided(memory, table, written, fused)
            }))
        })
    };
    if let Some(cache) = &cache {
        cache.flush();
    }
    fused.unwrap_or_else(|| crate::fuse::Fused::written(erased))
}

fn decided(
    memory: Option<(&CheckCache<'_>, DefHash)>,
    table: &Table,
    written: &Spanned,
    fused: &Spanned,
) -> bool {
    let text = written.to_sexp().to_string();
    let memory = memory.map(|(c, bucket)| (c, bucket, c.key(Pass::Saturate, &[text.as_bytes()])));
    if let Some((c, bucket, entry)) = &memory {
        if let Some(kept) = c.get(Pass::Saturate, bucket, entry) {
            return kept == b"fused";
        }
    }
    let (_, before, after) = cheapest(written, fused, table, Limits::default());
    let take = after < before;
    if let Some((c, bucket, entry)) = memory {
        let decision: &[u8] = if take { b"fused" } else { b"kept" };
        c.put(&bucket, entry, decision.to_vec());
    }
    if take {
        crate::timings::count("saturated", 1);
    }
    take
}

/// A table with no measured word: every node a step, an allocation a step.
#[must_use]
pub fn unmeasured() -> Table {
    Table {
        words: BTreeMap::new(),
        alloc_weight: 1.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cost::{Price, WordPrice};

    fn measured_like() -> Table {
        let p = |steps, allocs| Price { steps, allocs };
        let mut words = BTreeMap::new();
        for (w, call, element) in [
            ("map", p(3.0, 23.0), p(2.0, 3.0)),
            ("filter", p(3.0, 27.0), p(2.0, 3.0)),
            ("reduce", p(4.0, 17.0), p(2.0, 4.0)),
        ] {
            words.insert(w.to_string(), WordPrice { call, element });
        }
        Table {
            words,
            alloc_weight: 2.45,
        }
    }

    fn lowered(src: &str) -> (Vec<Spanned>, Vec<Spanned>) {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        (crate::erase::unfused(&lowered), lowered)
    }

    fn shown(forms: &[Spanned]) -> Vec<String> {
        forms.iter().map(|f| f.to_sexp().to_string()).collect()
    }

    fn asked(src: &str) -> Vec<(Spanned, Spanned)> {
        let (erased, lowered) = lowered(src);
        let plan = crate::fuse::Plan::of(&erased, &lowered);
        let mut asked = Vec::new();
        let _ = plan.fuse(Some(&mut |_, written: &Spanned, fused: &Spanned| {
            asked.push((written.clone(), fused.clone()));
            true
        }));
        asked
    }

    #[test]
    fn saturation_then_extraction_gives_the_tree_fusion_gives() {
        for src in [
            "def f(xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> x % 2 == 0, map((x) -> x * 3, xs)))\nend\n",
            "def g(xs)\n  map((x) -> x + 1, map((x) -> x * 2, xs))\nend\n",
            "def h(xs)\n  filter((x) -> x > 1, filter((x) -> x < 9, xs))\nend\n",
            "def k(xs)\n  reduce((a, x) -> a + x, 0, map(fn(x)\n    print(x)\n    x\n  end, xs))\nend\n",
            "def m(xs)\n  length(xs)\nend\n",
        ] {
            let (erased, lowered) = lowered(src);
            let fusion = shown(&crate::fuse::fuse(erased.clone(), &lowered).forms);
            let saturation = shown(&program(erased, &lowered, &measured_like()).forms);
            assert_eq!(saturation, fusion, "{src}");
        }
    }

    #[test]
    fn r19_fuses_only_what_fusion_fuses_whatever_the_callbacks_reach_and_wherever_they_are_defined()
    {
        let writes = "def first()\n  1\nend\n\ndef shout(x)\n  write_stdout(unlines([\"map #{x}\"]))\n  x * 10\nend\n\ndef check(x)\n  write_stdout(unlines([\"filter #{x}\"]))\n  x > 10\nend\n\ndef tally(xs)\n  reduce((a, x) -> a + x, 0, filter(check, map(shout, xs)))\nend\n";
        let first = "def sq(x)\n  x * x\nend\n\ndef named(xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> x > 2, map(sq, xs)))\nend\n";
        let later = "def pad()\n  0\nend\n\ndef sq(x)\n  x * x\nend\n\ndef named(xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> x > 2, map(sq, xs)))\nend\n";
        let closes = "def area(w, h)\n  w * h\nend\n\ndef total(xs, allowed)\n  reduce((a, x) -> a + x, 0, map((x) -> x + area(3, 4), filter((x) -> member?(x, allowed), xs)))\nend\n";
        let shadows = "def tally(log, abs, xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> abs(x), map((x) -> log(x), xs)))\nend\n";
        let declared = "def pad()\n  0\nend\n\ndef tick(x)\n  x * 3\nend\n\nvolatile(tick)\n\ndef total(xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> x > 1, map(tick, xs)))\nend\n";
        let raises = "def pad()\n  0\nend\n\ndef parse(x)\n  if x == 3\n    raise(:bad, \"three\")\n  end\n  x * 10\nend\n\ndef save(x)\n  write_stdout(unlines([\"saved #{x}\"]))\n  x\nend\n\ndef store(xs)\n  reduce((a, x) -> a + x, 0, map(save, map(parse, xs)))\nend\n";
        for (src, chains) in [
            (writes, &[][..]),
            (first, &["reduce∘filter∘map"][..]),
            (later, &["reduce∘filter∘map"][..]),
            (closes, &["reduce∘map∘filter"][..]),
            (shadows, &[][..]),
            (declared, &["reduce∘filter"][..]),
            (raises, &[][..]),
        ] {
            let (erased, lowered) = lowered(src);
            let fusion = crate::fuse::fuse(erased.clone(), &lowered);
            assert_eq!(fusion.chains, chains, "{src}");
            let saturation = program(erased, &lowered, &measured_like());
            assert_eq!(shown(&saturation.forms), shown(&fusion.forms), "{src}");
        }
    }

    #[test]
    fn a_rule_that_fires_again_on_a_tree_it_has_seen_lets_the_graph_saturate() {
        let site = asked("def f(xs)\n  reduce((a, x) -> a + x, 0, map((x) -> x * 3, xs))\nend\n");
        let [(written, fused)] = site.as_slice() else {
            panic!("one stage call is asked: {}", site.len());
        };
        let held = Held::default();
        let rules = rules(written, fused, &held);
        let started = std::time::Instant::now();
        let _ = blue_lang_saturate::cheapest(
            written,
            &rules,
            Limits::default(),
            node_price(&measured_like(), 1000.0, &held),
        );
        assert!(
            started.elapsed() < Limits::default().time / 2,
            "saturation ran to its time limit: {:?}",
            started.elapsed()
        );
        assert_eq!(held.lock().0.len(), 1, "one fused tree, made once");
    }

    #[test]
    fn a_fused_chain_is_cheaper_and_a_lone_stage_keeps_its_price() {
        let site = asked("def f(xs)\n  reduce((a, x) -> a + x, 0, map((x) -> x * 3, xs))\nend\n");
        let [(written, fused)] = site.as_slice() else {
            panic!("one stage call is asked: {}", site.len());
        };
        let (_, before, after) = cheapest(written, fused, &measured_like(), Limits::default());
        assert!(after < before, "{after} against {before}");
        let (_, before, after) = cheapest(written, written, &measured_like(), Limits::default());
        assert_eq!(after, before);
        assert!(asked("def g(xs)\n  map((x) -> x, xs)\nend\n").is_empty());
    }
}
