//! The effect graph: E1 of docs/ENGINES.md.
//!
//! Each call in a definition that reaches the host is a site: the word, its
//! host capability, the resource it touches when its arguments make that a
//! literal, and the earlier sites it depends on. A site depends on another
//! when one of its arguments is computed from that site's answer (through a
//! local, directly or through other locals), or when it runs only because a
//! test computed from that answer said so. Two sites with no path between
//! them are independent; whether their effects also commute is E2's table.
//!
//! Sites are numbered in the order the walker evaluates them. A site inside a
//! function written in place (a callback, a lambda) is marked `deferred`: it
//! runs when the function is called, perhaps many times, so E3 never moves
//! it. A call to a definition of the program that reaches the host is a site
//! whose resource is unknown. Tier-honest: this reads names in the erased
//! tree, as `reach` does; a function value called through a local is not a
//! site, and a run that calls one keeps its order (E3 batches only sites).

use std::collections::{BTreeMap, BTreeSet};

use blue_lang_waku::Capability;
use tatara_lisp::{Span, Spanned};

use crate::reach::{self, Volatility};

/// One call that reaches the host.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Site {
    pub word: String,
    pub capability: Capability,
    pub resource: Option<String>,
    /// An HTTP request's method, when its argument is a literal.
    pub method: Option<String>,
    pub at: Span,
    pub depends_on: BTreeSet<usize>,
    pub deferred: bool,
}

/// A definition's sites, in evaluation order.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Graph {
    pub sites: Vec<Site>,
}

impl Graph {
    /// Whether site `b` depends on site `a`, through any chain.
    #[must_use]
    pub fn reaches(&self, a: usize, b: usize) -> bool {
        let mut seen = BTreeSet::new();
        let mut todo = vec![b];
        while let Some(s) = todo.pop() {
            for &d in &self.sites[s].depends_on {
                if d == a {
                    return true;
                }
                if seen.insert(d) {
                    todo.push(d);
                }
            }
        }
        false
    }

    /// Whether neither of sites `a` and `b` depends on the other.
    #[must_use]
    pub fn independent(&self, a: usize, b: usize) -> bool {
        a != b && !self.reaches(a, b) && !self.reaches(b, a)
    }
}

/// The effect graph of `form`, one erased top-level form. `effectful` names
/// the program's definitions that reach the host, each with the first
/// capability it reaches (`reach::host_reach`).
#[must_use]
pub fn graph(form: &Spanned, effectful: &BTreeMap<String, Capability>) -> Graph {
    let mut walk = Walk {
        effectful,
        frames: vec![BTreeMap::new()],
        sites: Vec::new(),
        control: Vec::new(),
        deferred: 0,
    };
    walk.form(form);
    Graph { sites: walk.sites }
}

/// The effect graph of each definition of a program, by key, in the order
/// of `hashes`. `erased` as for [`reach::host_reach`]: a call to a definition
/// that reaches the host is a site, with the first capability it reaches.
#[must_use]
pub fn graphs(erased: &[Spanned], hashes: &crate::def_hash::DefHashes) -> Vec<(String, Graph)> {
    let reaches = reach::host_reach(erased, hashes);
    let effectful: BTreeMap<String, Capability> = hashes
        .defs()
        .iter()
        .zip(&reaches)
        .filter_map(|(d, r)| Some((d.key.clone(), *r.keys().next()?)))
        .collect();
    hashes
        .defs()
        .iter()
        .filter_map(|d| {
            let form = erased.get(d.top_level)?;
            Some((d.key.clone(), graph(form, &effectful)))
        })
        .collect()
}

struct Walk<'a> {
    effectful: &'a BTreeMap<String, Capability>,
    frames: Vec<BTreeMap<String, BTreeSet<usize>>>,
    sites: Vec<Site>,
    control: Vec<BTreeSet<usize>>,
    deferred: usize,
}

impl Walk<'_> {
    fn taint(&self, name: &str) -> Option<&BTreeSet<usize>> {
        self.frames.iter().rev().find_map(|f| f.get(name))
    }

    fn bind(&mut self, name: &str, from: BTreeSet<usize>) {
        if let Some(f) = self.frames.last_mut() {
            f.insert(name.to_string(), from);
        }
    }

    fn bound(&self, name: &str) -> bool {
        self.taint(name).is_some()
    }

    fn form(&mut self, form: &Spanned) -> BTreeSet<usize> {
        if let Some(name) = form.as_symbol() {
            return self.taint(name).cloned().unwrap_or_default();
        }
        let Some(items) = form.as_list() else {
            return BTreeSet::new();
        };
        let Some((head, args)) = items.split_first() else {
            return BTreeSet::new();
        };
        match head.as_symbol() {
            Some("quote") => BTreeSet::new(),
            Some("define") => self.define(args),
            Some("lambda") => self.lambda(args),
            Some("if") => self.branch(args),
            Some("begin" | "do") => {
                let mut last = BTreeSet::new();
                for a in args {
                    last = self.form(a);
                }
                last
            }
            Some(word) if !self.bound(word) => self.call(form, word, args),
            _ => {
                let mut from = BTreeSet::new();
                for i in items {
                    from.extend(self.form(i));
                }
                from
            }
        }
    }

    fn define(&mut self, args: &[Spanned]) -> BTreeSet<usize> {
        let Some((target, body)) = args.split_first() else {
            return BTreeSet::new();
        };
        if let Some(sig) = target.as_list() {
            let params: Vec<String> = sig
                .iter()
                .skip(1)
                .filter_map(|p| p.as_symbol().map(str::to_string))
                .collect();
            self.frames.push(BTreeMap::new());
            for p in &params {
                self.bind(p, BTreeSet::new());
            }
            for b in body {
                self.form(b);
            }
            self.frames.pop();
            return BTreeSet::new();
        }
        let mut from = BTreeSet::new();
        for b in body {
            from = self.form(b);
        }
        if let Some(name) = target.as_symbol() {
            self.bind(name, from.clone());
        }
        from
    }

    fn lambda(&mut self, args: &[Spanned]) -> BTreeSet<usize> {
        let Some((params, body)) = args.split_first() else {
            return BTreeSet::new();
        };
        self.frames.push(BTreeMap::new());
        for p in params.as_list().unwrap_or(&[]) {
            if let Some(name) = p.as_symbol() {
                self.bind(name, BTreeSet::new());
            }
        }
        self.deferred += 1;
        for b in body {
            self.form(b);
        }
        self.deferred -= 1;
        self.frames.pop();
        BTreeSet::new()
    }

    fn branch(&mut self, args: &[Spanned]) -> BTreeSet<usize> {
        let Some((test, arms)) = args.split_first() else {
            return BTreeSet::new();
        };
        let decided = self.form(test);
        self.control.push(decided.clone());
        let mut from = decided;
        for a in arms {
            from.extend(self.form(a));
        }
        self.control.pop();
        from
    }

    fn call(&mut self, form: &Spanned, word: &str, args: &[Spanned]) -> BTreeSet<usize> {
        let mut from = BTreeSet::new();
        for a in args {
            from.extend(self.form(a));
        }
        let capability = match reach::builtin(word) {
            Err(Volatility::Host { capability, .. }) => Some(capability),
            _ => self.effectful.get(word).copied(),
        };
        let Some(capability) = capability else {
            return from;
        };
        let mut depends_on = from.clone();
        for c in &self.control {
            depends_on.extend(c.iter().copied());
        }
        let resource = if self.effectful.contains_key(word) {
            None
        } else {
            resource_of(word, args)
        };
        let method = (word == "http_request")
            .then(|| args.first().and_then(string_of).map(str::to_string))
            .flatten();
        self.sites.push(Site {
            word: word.to_string(),
            capability,
            resource,
            method,
            at: form.span,
            depends_on,
            deferred: self.deferred > 0,
        });
        from.insert(self.sites.len() - 1);
        from
    }
}

fn string_of(form: &Spanned) -> Option<&str> {
    match &form.form {
        tatara_lisp::SpannedForm::Atom(tatara_lisp::Atom::Str(s)) => Some(s.as_str()),
        _ => None,
    }
}

/// The literal text an argument starts with: the string itself, or the
/// first piece of an interpolation (`concat`'s first literal).
fn literal_prefix(form: &Spanned) -> Option<String> {
    if let Some(s) = string_of(form) {
        return Some(s.to_string());
    }
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != "concat" {
        return None;
    }
    let mut out = String::new();
    for piece in &items[1..] {
        match string_of(piece) {
            Some(s) => out.push_str(s),
            None => match literal_prefix(piece) {
                Some(s) if out.is_empty() => {
                    out = s;
                    break;
                }
                _ => break,
            },
        }
    }
    (!out.is_empty()).then_some(out)
}

/// The resource a call touches when its arguments make it a literal: an
/// HTTP request's host and port, a file word's path.
fn resource_of(word: &str, args: &[Spanned]) -> Option<String> {
    match word {
        "http_request" => {
            let url = literal_prefix(args.get(1)?)?;
            let rest = url.strip_prefix("http://")?;
            let authority = rest.split('/').next()?;
            if authority.is_empty() {
                return None;
            }
            Some(if authority.contains(':') {
                authority.to_string()
            } else {
                format!("{authority}:80")
            })
        }
        _ => args.first().and_then(string_of).map(str::to_string),
    }
}

/// How a host word touches what it names: E2 of docs/ENGINES.md.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Access {
    /// It reads; two reads commute.
    Read,
    /// It changes the resource its first argument names; it commutes with a
    /// call on a different named resource.
    Write,
    /// Its order is observable (a clock, entropy, a process, a session, a
    /// device), so it commutes with nothing.
    Ordered,
}

/// The requests HTTP defines as safe and idempotent (RFC 9110 §9.2.1,
/// §9.2.2): GET, HEAD and OPTIONS. A request with one reads; R15 sends one
/// again on a transient failure. PUT and DELETE are idempotent too, but a
/// retry of one whose first try reached the server repeats its effect.
pub const SAFE_METHODS: [&str; 3] = ["GET", "HEAD", "OPTIONS"];

/// Every host word that only reads.
pub const READS: &[&str] = &[
    "read_file",
    "read_bytes",
    "read_u32s",
    "file_size",
    "file_mtime_ms",
    "is_dir?",
    "is_file?",
    "path_exists",
    "glob",
    "walk_dir",
    "ls",
    "cwd",
    "temp_dir",
    "path_join",
    "path_basename",
    "path_dirname",
    "path_extension",
    "getenv",
    "env_required",
    "argv",
    "argv_get",
    "self_exe",
    "read_log",
];

/// Every host word that changes the one resource its first argument names.
pub const WRITES: &[&str] = &[
    "write_file",
    "write_bytes",
    "write_program",
    "append_file",
    "mkdir",
    "mkdir_p",
    "rm",
    "rm_rf",
    "append_log",
];

/// The access of a site: an HTTP request reads when its method is one RFC 9110
/// calls safe and idempotent (R15's), and is ordered otherwise; every other
/// word as [`READS`] and [`WRITES`] say, else ordered.
#[must_use]
pub fn access(site: &Site) -> Access {
    if site.word == "http_request" {
        return match &site.method {
            Some(m) if SAFE_METHODS.contains(&m.as_str()) => Access::Read,
            _ => Access::Ordered,
        };
    }
    if READS.contains(&site.word.as_str()) {
        Access::Read
    } else if WRITES.contains(&site.word.as_str()) {
        Access::Write
    } else {
        Access::Ordered
    }
}

/// Whether the effects of sites `a` and `b` commute: running them in either
/// order leaves the same answers and the same world.
#[must_use]
pub fn commute(a: &Site, b: &Site) -> bool {
    let apart = || matches!((&a.resource, &b.resource), (Some(x), Some(y)) if x != y);
    match (access(a), access(b)) {
        (Access::Ordered, _) | (_, Access::Ordered) => false,
        (Access::Read, Access::Read) => true,
        _ => apart(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn graph_of(src: &str) -> Graph {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        let erased = crate::erase::unfused(&lowered);
        graph(erased.last().expect("a form"), &BTreeMap::new())
    }

    const FETCH: &str = "def fetch(base)\n  a = http_request(\"GET\", \"http://example.test/a\", nil, nil, nil)\n  b = http_request(\"GET\", \"http://example.test:8080/b\", nil, nil, nil)\n  c = http_request(\"GET\", \"#{base}/#{a.status}\", nil, nil, nil)\n  if b.status == 200\n    write_file(\"/tmp/x\", to_s(c))\n  end\n  [a, b, c]\nend\n";

    #[test]
    fn two_requests_that_share_nothing_are_independent_and_a_third_that_reads_one_is_not() {
        let g = graph_of(FETCH);
        let words: Vec<&str> = g.sites.iter().map(|s| s.word.as_str()).collect();
        assert_eq!(
            words,
            ["http_request", "http_request", "http_request", "write_file"]
        );
        assert!(g.independent(0, 1));
        assert!(!g.independent(0, 2), "c's url reads a's answer");
        assert!(g.independent(1, 2));
        assert!(
            g.reaches(1, 3),
            "the write runs only when b's status says so"
        );
        assert!(g.reaches(2, 3), "the write writes c");
        assert!(g.reaches(0, 3), "through c");
    }

    #[test]
    fn a_resource_is_named_only_when_the_arguments_make_it_a_literal() {
        let g = graph_of(FETCH);
        assert_eq!(g.sites[0].resource.as_deref(), Some("example.test:80"));
        assert_eq!(g.sites[1].resource.as_deref(), Some("example.test:8080"));
        assert_eq!(g.sites[2].resource, None);
        assert_eq!(g.sites[3].resource.as_deref(), Some("/tmp/x"));
        assert_eq!(g.sites[0].capability, Capability::Network);
    }

    #[test]
    fn a_call_to_a_definition_that_reaches_the_host_is_a_site_with_no_known_resource() {
        let src =
            "def stamp()\n  now_ms\nend\n\ndef twice()\n  a = stamp\n  b = stamp\n  [a, b]\nend\n";
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        let hashes = crate::def_hash::hash_program(&lowered);
        let all = graphs(&crate::erase::unfused(&lowered), &hashes);
        let twice = &all
            .iter()
            .find(|(k, _)| k.ends_with("twice"))
            .expect("twice")
            .1;
        assert_eq!(twice.sites.len(), 2, "{twice:?}");
        assert!(twice.sites.iter().all(|s| s.resource.is_none()));
        assert_eq!(twice.sites[0].capability, Capability::Clock);
        assert!(twice.independent(0, 1));
    }

    #[test]
    fn reads_commute_a_write_commutes_only_with_another_resource_and_order_commutes_with_nothing() {
        let g = graph_of(FETCH);
        assert!(commute(&g.sites[0], &g.sites[1]), "two GETs");
        assert!(
            commute(&g.sites[0], &g.sites[3]),
            "a GET and a write to a file"
        );
        let src = "def files()\n  a = read_file(\"/a\")\n  write_file(\"/a\", \"x\")\n  write_file(\"/b\", \"y\")\n  write_file(path_join(\"/\", a), \"z\")\n  b = now_ms\n  c = http_request(\"POST\", \"http://example.test/p\", nil, nil, nil)\n  [b, c]\nend\n";
        let f = graph_of(src);
        let words: Vec<&str> = f.sites.iter().map(|s| s.word.as_str()).collect();
        assert_eq!(
            words,
            [
                "read_file",
                "write_file",
                "write_file",
                "path_join",
                "write_file",
                "now_ms",
                "http_request"
            ]
        );
        assert!(
            !commute(&f.sites[0], &f.sites[1]),
            "a read and a write of one file"
        );
        assert!(commute(&f.sites[1], &f.sites[2]), "writes to two files");
        assert!(
            !commute(&f.sites[2], &f.sites[4]),
            "a write to a path not known"
        );
        assert!(!commute(&f.sites[5], &f.sites[5]), "the clock is ordered");
        assert_eq!(access(&f.sites[6]), Access::Ordered, "a POST");
        assert_eq!(access(&g.sites[0]), Access::Read, "a GET");
    }

    #[test]
    fn every_listed_word_is_a_host_word_and_none_is_both_a_read_and_a_write() {
        let host: Vec<&str> = Capability::host_effects()
            .into_iter()
            .flat_map(Capability::names)
            .collect();
        for w in READS.iter().chain(WRITES) {
            assert!(host.contains(w), "{w} is no host word");
        }
        for w in READS {
            assert!(!WRITES.contains(w), "{w} is both");
        }
    }

    #[test]
    fn a_site_inside_a_callback_is_deferred_and_a_local_that_shadows_a_word_is_no_site() {
        let g = graph_of("def all(paths, read_file)\n  map((p) -> now_ms + length(p), paths)\n  read_file(1)\nend\n");
        assert_eq!(g.sites.len(), 1, "{g:?}");
        assert!(g.sites[0].deferred);
        assert_eq!(g.sites[0].capability, Capability::Clock);
    }
}
