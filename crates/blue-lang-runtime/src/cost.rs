//! The cost model: S1 of docs/ENGINES.md.
//!
//! What one evaluation of a form costs, as the walker counts it: steps, and
//! allocations where the binary counts them. Each word blue prices has a
//! [`WordPrice`], a cost per call and a cost per element of the list it walks,
//! measured from probe programs ([`PROBES`]) at two sizes by
//! [`calibrate`]; [`estimate`] adds them up over an erased tree, taking a list
//! of unknown length to hold `n` elements, and a callback a word calls once
//! per element at its body's cost. Two equivalent forms are priced on the same
//! `n`, so their order is what an extraction reads.
//!
//! Tier-honest: a name the table does not price costs one step per call, a
//! call to a definition costs its own body once, recursion or not, and an
//! `if` costs its test and both branches, an upper bound. The gate is
//! that the model orders equivalent forms as they measure
//! (`tests/cost.rs`).

use std::collections::BTreeMap;

use tatara_lisp::Spanned;

/// What an evaluation costs, as the walker counts it.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Price {
    pub steps: f64,
    pub allocs: f64,
}

impl Price {
    #[must_use]
    pub fn plus(self, other: Price) -> Price {
        Price {
            steps: self.steps + other.steps,
            allocs: self.allocs + other.allocs,
        }
    }

    #[must_use]
    pub fn times(self, k: f64) -> Price {
        Price {
            steps: self.steps * k,
            allocs: self.allocs * k,
        }
    }

    #[must_use]
    pub fn minus(self, other: Price) -> Price {
        self.plus(other.times(-1.0))
    }

    /// One number to order prices by: steps, plus each allocation at
    /// `alloc_weight` steps.
    #[must_use]
    pub fn units(self, alloc_weight: f64) -> f64 {
        self.steps + self.allocs * alloc_weight
    }
}

/// What a word costs: once per call, and once per element of the list it is
/// handed.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct WordPrice {
    pub call: Price,
    pub element: Price,
}

/// A word [`calibrate`] prices, and the program that measures it: `XS` is a
/// list of the probe's size, built before the measured expression.
pub struct Probe {
    pub word: &'static str,
    pub expr: &'static str,
}

/// The words the model prices, each with its probe.
pub const PROBES: &[Probe] = &[
    Probe {
        word: "map",
        expr: "map((x) -> x, XS)",
    },
    Probe {
        word: "filter",
        expr: "filter((x) -> true, XS)",
    },
    Probe {
        word: "reduce",
        expr: "reduce((a, x) -> a, 0, XS)",
    },
    Probe {
        word: "reverse",
        expr: "reverse(XS)",
    },
    Probe {
        word: "length",
        expr: "length(XS)",
    },
    Probe {
        word: "concat",
        expr: "concat(XS, XS)",
    },
    Probe {
        word: "par_map",
        expr: "par_map((x) -> x, XS)",
    },
];

/// The probe program for `expr` on `n` elements; [`BASE`] is the same
/// program with nothing measured.
#[must_use]
pub fn probe_program(expr: &str, n: usize) -> String {
    format!("xs = range({n})\nkeep = {}\n", expr.replace("XS", "xs"))
}

/// The expression a probe's baseline measures: the list alone.
pub const BASE: &str = "XS";

/// The two sizes a word is measured at.
pub const SIZES: [usize; 2] = [1000, 2000];

/// The words' prices and the weight of one allocation in steps.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Table {
    pub words: BTreeMap<String, WordPrice>,
    pub alloc_weight: f64,
}

/// A table from probe measurements: `measure(expr, n)` is what the probe
/// program for `expr` on `n` elements costs, or `None` when it could not
/// run. The baseline at each size is taken away, and the difference between
/// the two sizes is the cost per element.
#[must_use]
pub fn calibrate(measure: &dyn Fn(&str, usize) -> Option<Price>, alloc_weight: f64) -> Table {
    let [small, large] = SIZES;
    let base = (measure(BASE, small), measure(BASE, large));
    let mut words = BTreeMap::new();
    if let (Some(base_small), Some(base_large)) = base {
        for probe in PROBES {
            let (Some(at_small), Some(at_large)) =
                (measure(probe.expr, small), measure(probe.expr, large))
            else {
                continue;
            };
            let at_small = at_small.minus(base_small);
            let at_large = at_large.minus(base_large);
            let element = at_large.minus(at_small).times(1.0 / (large - small) as f64);
            let call = at_small.minus(element.times(small as f64));
            words.insert(probe.word.to_string(), WordPrice { call, element });
        }
    }
    Table {
        words,
        alloc_weight,
    }
}

/// One step: what a name the table does not price costs per call.
const UNPRICED: Price = Price {
    steps: 1.0,
    allocs: 0.0,
};

/// What evaluating `form` once costs under `table`, a list of unknown length
/// taken to hold `n` elements.
#[must_use]
pub fn estimate(form: &Spanned, table: &Table, n: f64) -> Price {
    let Some(items) = form.as_list() else {
        return Price::default();
    };
    let Some((head, args)) = items.split_first() else {
        return Price::default();
    };
    match head.as_symbol() {
        Some("lambda" | "quote") => Price::default(),
        Some("define" | "let" | "if" | "begin" | "do") => args
            .iter()
            .fold(Price::default(), |p, a| p.plus(estimate(a, table, n))),
        Some(word) => {
            let own = args
                .iter()
                .filter(|a| !is_lambda(a))
                .fold(Price::default(), |p, a| p.plus(estimate(a, table, n)));
            let callbacks = args
                .iter()
                .filter_map(lambda_body)
                .fold(Price::default(), |p, body| {
                    p.plus(body_price(body, table, n))
                });
            match table.words.get(word) {
                Some(w) => own
                    .plus(w.call)
                    .plus(w.element.times(n))
                    .plus(callbacks.times(n)),
                None => own.plus(UNPRICED).plus(callbacks),
            }
        }
        None => items
            .iter()
            .fold(Price::default(), |p, a| p.plus(estimate(a, table, n))),
    }
}

fn is_lambda(form: &Spanned) -> bool {
    lambda_body(form).is_some()
}

fn lambda_body(form: &Spanned) -> Option<&[Spanned]> {
    let items = form.as_list()?;
    (items.first()?.as_symbol()? == "lambda" && items.len() >= 3).then(|| &items[2..])
}

fn body_price(body: &[Spanned], table: &Table, n: f64) -> Price {
    body.iter()
        .fold(UNPRICED, |p, f| p.plus(estimate(f, table, n)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table() -> Table {
        let mut words = BTreeMap::new();
        let price = |steps, allocs| Price { steps, allocs };
        words.insert(
            "map".to_string(),
            WordPrice {
                call: price(2.0, 1.0),
                element: price(3.0, 2.0),
            },
        );
        words.insert(
            "reduce".to_string(),
            WordPrice {
                call: price(2.0, 0.0),
                element: price(3.0, 0.0),
            },
        );
        Table {
            words,
            alloc_weight: 4.0,
        }
    }

    fn erased(src: &str) -> Spanned {
        let forms = blue_lang_syntax::parse_program_tree(src).expect("parses");
        forms.into_iter().next().expect("one form")
    }

    #[test]
    fn a_word_costs_its_call_its_elements_and_its_callback_once_per_element() {
        let p = estimate(&erased("map((x) -> x + 1, xs)"), &table(), 10.0);
        assert_eq!(p.steps, 2.0 + 30.0 + 20.0, "{p:?}");
        assert_eq!(p.allocs, 1.0 + 20.0);
    }

    #[test]
    fn calibration_takes_the_baseline_away_and_splits_call_from_element() {
        let measure = |expr: &str, n: usize| {
            let n = n as f64;
            Some(if expr == BASE {
                Price {
                    steps: n,
                    allocs: n,
                }
            } else {
                Price {
                    steps: n + 5.0 + 3.0 * n,
                    allocs: n + 2.0 * n,
                }
            })
        };
        let t = calibrate(&measure, 1.0);
        let map = t.words["map"];
        assert!((map.call.steps - 5.0).abs() < 1e-9, "{map:?}");
        assert!((map.element.steps - 3.0).abs() < 1e-9);
        assert!((map.element.allocs - 2.0).abs() < 1e-9);
        assert!(map.call.allocs.abs() < 1e-9);
    }

    #[test]
    fn an_unpriced_name_costs_a_step_and_a_word_with_no_measure_is_left_out() {
        assert_eq!(estimate(&erased("frob(1)"), &table(), 10.0).steps, 1.0);
        let t = calibrate(&|_, _| None, 1.0);
        assert!(t.words.is_empty());
    }
}
