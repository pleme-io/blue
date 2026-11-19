//! blue's rewrites as rules over one e-graph: S3 of docs/ENGINES.md.
//!
//! Fusion becomes three form rules, one for each stage word: each hands the
//! tree its pattern matched to [`crate::fuse::fuse`], so which chains fuse,
//! and the purity that decides it, stay fusion's own. A fused tree keeps the
//! unfused chain as its fallback, and in the graph that fallback is the class
//! the fused tree joins, so a fused tree goes in as an opaque leaf
//! (`%fused:N`) whose tree a side table holds: the price reads the fused body
//! from the table, and [`cheapest`] puts the tree back after extraction.
//!
//! The price is [`crate::cost`]'s, node by node, as extraction needs: a word
//! the table prices costs its call and its elements, a function written in
//! place costs its body once per element, a `try` its body, a `catch`
//! nothing, any other node a step, each plus its children.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use blue_lang_saturate::{form_rule, Limits, Rule};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::cost::{self, Table};

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

/// The rules over a program whose definitions are `defined` (the lowered
/// program fusion reads purity from): one fusion rule per stage word.
#[must_use]
pub fn rules(defined: &Arc<Vec<Spanned>>, held: &Held) -> Vec<Rule> {
    [
        ("fuse-map", "(map ?f ?xs)"),
        ("fuse-filter", "(filter ?p ?xs)"),
        ("fuse-reduce", "(reduce ?f ?z ?xs)"),
    ]
    .into_iter()
    .filter_map(|(name, pattern)| {
        let defined = Arc::clone(defined);
        let held = held.clone();
        form_rule(name, pattern, move |form: &Spanned| {
            let matched = form.to_sexp().to_string();
            if let Some(n) = held.seen(&matched) {
                return Some(leaf(&format!("{FUSED}{n}")));
            }
            let fused = crate::fuse::fuse(vec![form.clone()], &defined);
            if fused.chains.is_empty() {
                return None;
            }
            let tree = fused.forms.into_iter().next()?;
            Some(leaf(&format!("{FUSED}{}", held.keep(matched, tree))))
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

/// The cheapest form the rules prove equal to `form`, under `table` with
/// lists of 1000 elements, and its price before and after; `form` itself
/// when nothing is cheaper.
#[must_use]
pub fn cheapest(
    form: &Spanned,
    defined: &Arc<Vec<Spanned>>,
    table: &Table,
    limits: Limits,
) -> (Spanned, f64, f64) {
    let held = Held::default();
    let rules = rules(defined, &held);
    let (out, before, after) =
        blue_lang_saturate::cheapest(form, &rules, limits, node_price(table, 1000.0, &held));
    (expand(out, &held), before, after)
}

/// The words a stage call is headed by: what R19 saturates.
const STAGE_WORDS: [&str; 3] = ["map", "filter", "reduce"];

/// Whether rule R19 runs: a measured cost table is installed
/// ([`cost::installed`]), `BLUE_SATURATE=off` is not set, and no command
/// holds the rewrites off.
#[must_use]
pub fn enabled() -> bool {
    cost::installed().is_some() && !crate::fuse::held_off() && !crate::kitei::switched_off("R19")
}

/// What rule R19 did to a program: the forms, and the chains it fused.
pub struct Saturated {
    pub forms: Vec<Spanned>,
    pub chains: Vec<String>,
}

/// Rule R19 (S4 of docs/ENGINES.md): each outermost call headed by a stage
/// word that no local binds is saturated within the default limits and
/// replaced by the cheapest form under `table`, the written one on a tie.
/// Only that call is rebuilt, so the rest of the definition keeps its
/// positions, and a fused call is fusion's own tree, with fusion's. The
/// choice is kept in the check cache by the call's text and recalled after,
/// so a call is saturated once per build: a fused one is fused again, which
/// is cheap, a kept one is left.
#[must_use]
pub fn program(erased: Vec<Spanned>, defined: &[Spanned], table: &Table) -> Saturated {
    let defined = Arc::new(defined.to_vec());
    let cache = crate::check_cache::installed();
    let mut chains = Vec::new();
    let forms = erased
        .iter()
        .map(|f| {
            let mut walk = Walk {
                defined: &defined,
                table,
                cache: cache.as_ref(),
                bound: Vec::new(),
                chains: &mut chains,
            };
            walk.form(f)
        })
        .collect();
    if let Some(cache) = &cache {
        cache.flush();
    }
    Saturated { forms, chains }
}

struct Walk<'a, 'c> {
    defined: &'a Arc<Vec<Spanned>>,
    table: &'a Table,
    cache: Option<&'a crate::check_cache::CheckCache<'c>>,
    bound: Vec<String>,
    chains: &'a mut Vec<String>,
}

impl Walk<'_, '_> {
    fn form(&mut self, form: &Spanned) -> Spanned {
        let Some(items) = form.as_list() else {
            return form.clone();
        };
        let head = items.first().and_then(Spanned::as_symbol);
        if let Some(word) = head {
            if STAGE_WORDS.contains(&word) && !self.bound.iter().any(|b| b == word) {
                return self.stage(form);
            }
        }
        let depth = self.bound.len();
        self.bound.extend(binders(form));
        let out: Vec<Spanned> = items.iter().map(|i| self.form(i)).collect();
        self.bound.truncate(depth);
        Spanned::new(form.span, SpannedForm::List(out))
    }

    fn stage(&mut self, form: &Spanned) -> Spanned {
        let text = form.to_sexp().to_string();
        let remembered = self.cache.map(|c| {
            let entry = c.key(crate::check_cache::Pass::Saturate, &[text.as_bytes()]);
            let bucket = crate::def_hash::DefHash(crate::check_cache::digest(&[b"saturate"]));
            (c, bucket, entry)
        });
        let fuse_it = |s: &mut Self| {
            let fused = crate::fuse::fuse(vec![form.clone()], s.defined);
            s.chains.extend(fused.chains);
            fused
                .forms
                .into_iter()
                .next()
                .unwrap_or_else(|| form.clone())
        };
        if let Some((cache, bucket, entry)) = &remembered {
            if let Some(kept) = cache.get(crate::check_cache::Pass::Saturate, bucket, entry) {
                return if kept == b"fused" {
                    fuse_it(self)
                } else {
                    form.clone()
                };
            }
        }
        let (out, before, after) = cheapest(form, self.defined, self.table, Limits::default());
        let fused = after < before;
        if let Some((cache, bucket, entry)) = remembered {
            let decision: &[u8] = if fused { b"fused" } else { b"kept" };
            cache.put(&bucket, entry, decision.to_vec());
        }
        if fused {
            crate::timings::count("saturated", 1);
            fuse_it(self)
        } else {
            let _ = out;
            form.clone()
        }
    }
}

fn binders(form: &Spanned) -> Vec<String> {
    let Some(items) = form.as_list() else {
        return Vec::new();
    };
    let names = |l: Option<&Spanned>, skip: usize| -> Vec<String> {
        l.and_then(Spanned::as_list)
            .map(|ps| {
                ps.iter()
                    .skip(skip)
                    .filter_map(|p| p.as_symbol().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default()
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("lambda") => names(items.get(1), 0),
        Some("define") => match items.get(1) {
            Some(t) if t.as_list().is_some() => names(Some(t), 1),
            Some(t) => t.as_symbol().map(str::to_string).into_iter().collect(),
            None => Vec::new(),
        },
        Some("let") => items
            .get(1)
            .and_then(Spanned::as_list)
            .map(|bs| {
                bs.iter()
                    .filter_map(|b| b.as_list()?.first()?.as_symbol().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default(),
        _ => Vec::new(),
    }
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

    fn program(src: &str) -> (Vec<Spanned>, Vec<Spanned>) {
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

    fn parity(src: &str) -> (String, String) {
        let (erased, lowered) = program(src);
        let fused = crate::fuse::fuse(erased.clone(), &lowered);
        let defined = Arc::new(lowered);
        let last = erased.len() - 1;
        let (got, _, _) = cheapest(&erased[last], &defined, &measured_like(), Limits::default());
        (
            fused.forms[last].to_sexp().to_string(),
            got.to_sexp().to_string(),
        )
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
            let (fusion, saturation) = parity(src);
            assert_eq!(saturation, fusion, "{src}");
        }
    }

    #[test]
    fn a_rule_that_fires_again_on_a_tree_it_has_seen_lets_the_graph_saturate() {
        let (erased, lowered) =
            program("def f(xs)\n  reduce((a, x) -> a + x, 0, map((x) -> x * 3, xs))\nend\n");
        let held = Held::default();
        let rules = rules(&Arc::new(lowered), &held);
        let form = &erased[erased.len() - 1];
        let started = std::time::Instant::now();
        let _ = blue_lang_saturate::cheapest(
            form,
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
        let (erased, lowered) =
            program("def f(xs)\n  reduce((a, x) -> a + x, 0, map((x) -> x * 3, xs))\nend\n");
        let (_, before, after) = cheapest(
            &erased[erased.len() - 1],
            &Arc::new(lowered),
            &measured_like(),
            Limits::default(),
        );
        assert!(after < before, "{after} against {before}");
        let (erased, lowered) = program("def g(xs)\n  map((x) -> x, xs)\nend\n");
        let (_, before, after) = cheapest(
            &erased[erased.len() - 1],
            &Arc::new(lowered),
            &measured_like(),
            Limits::default(),
        );
        assert_eq!(after, before);
    }
}
