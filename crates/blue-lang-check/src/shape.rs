use std::collections::BTreeMap;

use tatara_lisp::{Atom, Sexp};

pub fn normalize(pkg: &str, params: &[String], body: &Sexp) -> Sexp {
    let own = format!("{pkg}/");
    match body {
        Sexp::Atom(Atom::Symbol(n)) => {
            if let Some(i) = params.iter().position(|p| p == n) {
                Sexp::Atom(Atom::Symbol(format!("%p{i}")))
            } else if let Some(rest) = n.strip_prefix(&own) {
                Sexp::Atom(Atom::Symbol(format!("self/{rest}")))
            } else {
                body.clone()
            }
        }
        Sexp::List(xs) => Sexp::List(xs.iter().map(|x| normalize(pkg, params, x)).collect()),
        Sexp::Quote(x) => Sexp::Quote(Box::new(normalize(pkg, params, x))),
        Sexp::Quasiquote(x) => Sexp::Quasiquote(Box::new(normalize(pkg, params, x))),
        Sexp::Unquote(x) => Sexp::Unquote(Box::new(normalize(pkg, params, x))),
        Sexp::UnquoteSplice(x) => Sexp::UnquoteSplice(Box::new(normalize(pkg, params, x))),
        other => other.clone(),
    }
}

pub fn size(s: &Sexp) -> usize {
    match s {
        Sexp::List(xs) => 1 + xs.iter().map(size).sum::<usize>(),
        Sexp::Quote(x) | Sexp::Quasiquote(x) | Sexp::Unquote(x) | Sexp::UnquoteSplice(x) => {
            1 + size(x)
        }
        _ => 1,
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Generalization {
    pub tree: Sexp,
    pub holes: Vec<Vec<Sexp>>,
}

impl Generalization {
    pub fn shared(&self) -> usize {
        size(&self.tree) - self.hole_sites()
    }

    pub fn hole_sites(&self) -> usize {
        fn count(s: &Sexp) -> usize {
            match s {
                Sexp::Atom(Atom::Symbol(n)) if is_hole(n) => 1,
                Sexp::List(xs) => xs.iter().map(count).sum(),
                Sexp::Quote(x)
                | Sexp::Quasiquote(x)
                | Sexp::Unquote(x)
                | Sexp::UnquoteSplice(x) => count(x),
                _ => 0,
            }
        }
        count(&self.tree)
    }

    pub fn instance(&self, which: usize) -> Sexp {
        fn fill(s: &Sexp, holes: &[Vec<Sexp>], which: usize) -> Sexp {
            match s {
                Sexp::Atom(Atom::Symbol(n)) if is_hole(n) => {
                    let i: usize = n[2..].parse().expect("hole index");
                    holes[i][which].clone()
                }
                Sexp::List(xs) => Sexp::List(xs.iter().map(|x| fill(x, holes, which)).collect()),
                Sexp::Quote(x) => Sexp::Quote(Box::new(fill(x, holes, which))),
                Sexp::Quasiquote(x) => Sexp::Quasiquote(Box::new(fill(x, holes, which))),
                Sexp::Unquote(x) => Sexp::Unquote(Box::new(fill(x, holes, which))),
                Sexp::UnquoteSplice(x) => Sexp::UnquoteSplice(Box::new(fill(x, holes, which))),
                other => other.clone(),
            }
        }
        fill(&self.tree, &self.holes, which)
    }
}

fn is_hole(n: &str) -> bool {
    n.len() > 2 && n.starts_with("%h") && n[2..].bytes().all(|b| b.is_ascii_digit())
}

pub fn generalize(terms: &[Sexp]) -> Option<Generalization> {
    let first = terms.first()?;
    let mut table: BTreeMap<Vec<String>, usize> = BTreeMap::new();
    let mut holes: Vec<Vec<Sexp>> = Vec::new();
    let tree = lgg(
        &terms.iter().collect::<Vec<_>>(),
        first,
        &mut table,
        &mut holes,
    );
    Some(Generalization { tree, holes })
}

fn lgg(
    terms: &[&Sexp],
    first: &Sexp,
    table: &mut BTreeMap<Vec<String>, usize>,
    holes: &mut Vec<Vec<Sexp>>,
) -> Sexp {
    if terms.iter().all(|t| *t == first) {
        return first.clone();
    }
    fn unary(s: &Sexp) -> Option<(u8, &Sexp)> {
        match s {
            Sexp::Quote(x) => Some((0, x)),
            Sexp::Quasiquote(x) => Some((1, x)),
            Sexp::Unquote(x) => Some((2, x)),
            Sexp::UnquoteSplice(x) => Some((3, x)),
            _ => None,
        }
    }
    if let Sexp::List(head) = first {
        let lists: Option<Vec<&Vec<Sexp>>> = terms
            .iter()
            .map(|t| match t {
                Sexp::List(xs) if xs.len() == head.len() => Some(xs),
                _ => None,
            })
            .collect();
        if let Some(lists) = lists {
            return Sexp::List(
                (0..head.len())
                    .map(|i| {
                        let column: Vec<&Sexp> = lists.iter().map(|xs| &xs[i]).collect();
                        lgg(&column, &head[i], table, holes)
                    })
                    .collect(),
            );
        }
    }
    if let Some((tag, inner)) = unary(first) {
        let inners: Option<Vec<&Sexp>> = terms
            .iter()
            .map(|t| unary(t).filter(|(k, _)| *k == tag).map(|(_, x)| x))
            .collect();
        if let Some(inners) = inners {
            let g = lgg(&inners, inner, table, holes);
            return match tag {
                0 => Sexp::Quote(Box::new(g)),
                1 => Sexp::Quasiquote(Box::new(g)),
                2 => Sexp::Unquote(Box::new(g)),
                _ => Sexp::UnquoteSplice(Box::new(g)),
            };
        }
    }
    let key: Vec<String> = terms.iter().map(|t| t.to_string()).collect();
    let next = holes.len();
    let i = *table.entry(key).or_insert_with(|| {
        holes.push(terms.iter().map(|t| (*t).clone()).collect());
        next
    });
    Sexp::Atom(Atom::Symbol(format!("%h{i}")))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Near {
    pub enabled: bool,
    pub max_holes: usize,
    pub min_size: usize,
    pub min_shared_pct: usize,
}

impl Near {
    pub const DEFAULT: Near = Near {
        enabled: true,
        max_holes: 2,
        min_size: 12,
        min_shared_pct: 80,
    };

    pub fn admits(&self, a: &Sexp, b: &Sexp) -> Option<Generalization> {
        if !self.enabled || a == b {
            return None;
        }
        let (sa, sb) = (size(a), size(b));
        if sa.min(sb) < self.min_size || sa.max(sb) * self.min_shared_pct > sa.min(sb) * 100 {
            return None;
        }
        let g = generalize(&[a.clone(), b.clone()])?;
        let ok = !g.holes.is_empty()
            && g.holes.len() <= self.max_holes
            && g.shared() * 100 >= sa.max(sb) * self.min_shared_pct;
        ok.then_some(g)
    }

    pub fn groups<'a>(
        &self,
        shapes: &'a BTreeMap<String, Sexp>,
    ) -> Vec<(Vec<&'a str>, Generalization)> {
        if !self.enabled {
            return Vec::new();
        }
        let keys: Vec<&str> = shapes.keys().map(String::as_str).collect();
        let root = |s: &Sexp| -> String {
            match s {
                Sexp::List(xs) => format!(
                    "{}:{}",
                    xs.len(),
                    xs.first().map(|h| h.to_string()).unwrap_or_default()
                ),
                other => other.to_string(),
            }
        };
        let mut buckets: BTreeMap<String, Vec<usize>> = BTreeMap::new();
        for (i, k) in keys.iter().enumerate() {
            buckets.entry(root(&shapes[*k])).or_default().push(i);
        }
        let mut parent: Vec<usize> = (0..keys.len()).collect();
        fn find(p: &mut [usize], mut i: usize) -> usize {
            while p[i] != i {
                p[i] = p[p[i]];
                i = p[i];
            }
            i
        }
        for members in buckets.values() {
            for (x, &i) in members.iter().enumerate() {
                for &j in &members[x + 1..] {
                    if self.admits(&shapes[keys[i]], &shapes[keys[j]]).is_some() {
                        let (ri, rj) = (find(&mut parent, i), find(&mut parent, j));
                        parent[ri.max(rj)] = ri.min(rj);
                    }
                }
            }
        }
        let mut comps: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
        for i in 0..keys.len() {
            let r = find(&mut parent, i);
            comps.entry(r).or_default().push(i);
        }
        comps
            .into_values()
            .filter(|c| c.len() > 1)
            .filter_map(|c| {
                let terms: Vec<Sexp> = c.iter().map(|&i| shapes[keys[i]].clone()).collect();
                let g = generalize(&terms)?;
                Some((c.iter().map(|&i| keys[i]).collect(), g))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tatara_lisp::read;

    fn t(src: &str) -> Sexp {
        read(src).expect("reads").remove(0)
    }

    #[test]
    fn identical_terms_generalize_to_themselves_with_no_holes() {
        let a = t("(if (nil? %p0) (raise :x) (get %p0 :k))");
        let g = generalize(&[a.clone(), a.clone()]).unwrap();
        assert_eq!(g.tree, a);
        assert!(g.holes.is_empty());
    }

    #[test]
    fn nothing_to_generalize_is_none() {
        assert_eq!(generalize(&[]), None);
    }

    #[test]
    fn one_differing_constant_is_one_hole() {
        let g = generalize(&[t("(get %p0 :name)"), t("(get %p0 :kind)")]).unwrap();
        assert_eq!(g.tree, t("(get %p0 %h0)"));
        assert_eq!(g.holes, vec![vec![t(":name"), t(":kind")]]);
    }

    #[test]
    fn the_same_difference_twice_reuses_one_hole() {
        let g = generalize(&[t("(f :a (g :a))"), t("(f :b (g :b))")]).unwrap();
        assert_eq!(g.tree, t("(f %h0 (g %h0))"));
        assert_eq!(g.holes.len(), 1);
    }

    #[test]
    fn different_differences_get_different_holes() {
        let g = generalize(&[t("(f :a :a)"), t("(f :b :c)")]).unwrap();
        assert_eq!(g.tree, t("(f %h0 %h1)"));
    }

    #[test]
    fn lists_of_different_length_become_one_hole() {
        let g = generalize(&[t("(f (a b))"), t("(f (a b c))")]).unwrap();
        assert_eq!(g.tree, t("(f %h0)"));
    }

    #[test]
    fn filling_the_holes_gives_back_every_input() {
        let terms = [
            t("(when (> %p0 1) (raise (error :too_big \"a\")))"),
            t("(when (> %p0 2) (raise (error :too_small \"b\")))"),
            t("(when (> %p0 3) (raise (error :too_wide \"c\")))"),
        ];
        let g = generalize(&terms).unwrap();
        for (i, term) in terms.iter().enumerate() {
            assert_eq!(&g.instance(i), term);
        }
        assert_eq!(g.holes.len(), 3);
    }

    #[test]
    fn near_admits_a_one_hole_pair_and_refuses_a_rewrite() {
        let near = Near {
            min_size: 4,
            ..Near::DEFAULT
        };
        let a = t("(map (fn (x) (get x :name)) (filter ok? %p0))");
        let b = t("(map (fn (x) (get x :kind)) (filter ok? %p0))");
        let c = t("(reduce + 0 (vals %p0))");
        assert!(near.admits(&a, &b).is_some());
        assert!(near.admits(&a, &c).is_none());
        assert!(near.admits(&a, &a).is_none());
    }

    #[test]
    fn off_admits_nothing_and_groups_nothing() {
        let off = Near {
            enabled: false,
            min_size: 1,
            min_shared_pct: 50,
            ..Near::DEFAULT
        };
        let a = t("(get %p0 :name)");
        let b = t("(get %p0 :kind)");
        assert!(off.admits(&a, &b).is_none());
        let shapes = BTreeMap::from([("p/a".to_owned(), a), ("p/b".to_owned(), b)]);
        assert!(off.groups(&shapes).is_empty());
        let on = Near {
            min_size: 1,
            min_shared_pct: 50,
            ..Near::DEFAULT
        };
        let groups = on.groups(&shapes);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].0, vec!["p/a", "p/b"]);
        assert_eq!(groups[0].1.tree, t("(get %p0 %h0)"));
    }
}
