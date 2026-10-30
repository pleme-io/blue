//! `doc_view(def)`: everything blue knows about a definition beyond its
//! `@doc`, derived when asked and never written into a file
//! (`theory/BLUE.md`, "The documentation requirement").
//!
//! | row | source |
//! |---|---|
//! | signature, parameter types, return type | the definition's tree |
//! | rung | the definition's blueshift position: `annotated` when it carries a type, else `dynamic` |
//! | args, opts, returns, raises, kind | its verb's row of `docs/verbs/contracts.tsv` |
//! | space, kind, shape, laterals, edges | the verb graph (`bidamas/mokuroku/graph`) |
//! | callers | the definitions of its file whose body names it |
//! | refusal kinds | the `refusal(:k, …)` and `raise(:k, …)` its body holds, each with `kyohi`'s ledger meaning |
//! | host reach | [`crate::Analysis::host_reach_of`], the reach `blue query '(reaches CAP)'` reads; absent when the program does not check |
//!
//! A shape a space shares is one row: a contract row is keyed by its verb and
//! a refusal kind by `kyohi`'s ledger, so every definition that shares it
//! renders the same text from the same place.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use blue_lang_syntax::doc as d;
use blue_lang_syntax::{Atom, Span, Spanned, SpannedForm};

use crate::HostReach;

/// A verb's row in the graph.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct VerbRow {
    pub space: String,
    pub kind: String,
    pub shape: String,
    pub laterals: Vec<String>,
}

/// The view of one definition.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DocView {
    pub name: String,
    pub bidama: Option<String>,
    /// The stored half: the `@doc` text.
    pub doc: Option<String>,
    pub signature: String,
    pub params: Vec<(String, Option<String>)>,
    pub returns: Option<String>,
    pub rung: &'static str,
    /// The verb's contract row, column by column.
    pub contract: Option<BTreeMap<String, String>>,
    pub verb: Option<VerbRow>,
    /// `kind target` for each graph edge from this verb.
    pub edges: Vec<String>,
    pub callers: Vec<String>,
    /// Each refusal kind with `kyohi`'s meaning of it.
    pub refusals: Vec<(String, Option<String>)>,
    pub reach: Option<HostReach>,
}

/// The view of the definition `name` in `text`, the file at `path` of bidama
/// `bidama`. `None` when the file defines no such name.
#[must_use]
pub fn of_file(
    text: &str,
    path: Option<&Path>,
    bidama: Option<&str>,
    name: &str,
) -> Option<DocView> {
    let forms = blue_lang_syntax::parse_program_documented(text).ok()?;
    of_forms(&forms, path, bidama, name)
}

fn parse_once(text: &str) -> Rc<crate::Parsed> {
    Rc::new(blue_lang_syntax::parse_program_documented(text).map(d::strip))
}

/// [`of_file`] over a documented parse already in hand.
#[must_use]
pub fn of_forms(
    forms: &[Spanned],
    path: Option<&Path>,
    bidama: Option<&str>,
    name: &str,
) -> Option<DocView> {
    let data = path.map(|p| RepoData::load(&Sources::of(p), &parse_once));
    view(forms, data.as_ref(), bidama, name)
}

fn view(
    forms: &[Spanned],
    data: Option<&RepoData>,
    bidama: Option<&str>,
    name: &str,
) -> Option<DocView> {
    let (doc, def) = forms.iter().find_map(|f| {
        let (doc, def) = d::documented(f).map_or((None, f), |(t, def)| (Some(t), def));
        (d::defined_name(def) == Some(name)).then_some((doc, def))
    })?;
    let items = def.as_list()?;
    let typed = items.first()?.as_symbol() == Some("define-typed");
    let params = params_of(items, typed);
    let returns = typed
        .then(|| items.get(2).map(type_text))
        .flatten()
        .filter(|t| t != "dyn");
    let contract = data.and_then(|r| r.contracts.get(name).cloned());
    let verb = data.and_then(|r| {
        bidama.and_then(|b| r.verbs.get(&(b.to_string(), name.to_string())).cloned())
    });
    let edges = match (data, &verb) {
        (Some(r), Some(v)) => r
            .edges
            .get(&format!("{}::{name}", v.space))
            .cloned()
            .unwrap_or_default(),
        _ => Vec::new(),
    };
    let mut kinds = BTreeSet::new();
    refusal_kinds(def, &mut kinds);
    let refusals = kinds
        .into_iter()
        .map(|k| {
            let meaning = data.and_then(|r| r.ledger.get(&k).cloned());
            (k, meaning)
        })
        .collect();
    let qualified = bidama.map(|b| blue_lang_syntax::qualify(b, name));
    let callers = forms
        .iter()
        .filter_map(|f| d::documented(f).map_or(Some(f), |(_, def)| Some(def)))
        .filter_map(|f| {
            let caller = d::defined_name(f)?;
            (caller != name && names(f, name, qualified.as_deref())).then(|| caller.to_string())
        })
        .collect();
    Some(DocView {
        name: name.to_string(),
        bidama: bidama.map(str::to_string),
        doc: doc.map(str::to_string),
        signature: crate::items::signature_of(def),
        params,
        returns,
        rung: if typed { "annotated" } else { "dynamic" },
        contract,
        verb,
        edges,
        callers,
        refusals,
        reach: None,
    })
}

fn type_text(t: &Spanned) -> String {
    t.to_sexp().to_string()
}

fn params_of(items: &[Spanned], typed: bool) -> Vec<(String, Option<String>)> {
    let Some(sig) = items.get(1).and_then(Spanned::as_list) else {
        return Vec::new();
    };
    sig.iter()
        .skip(1)
        .filter_map(|p| match p.as_list() {
            Some([n, t]) if typed => Some((
                n.as_symbol()?.to_string(),
                Some(type_text(t)).filter(|t| t != "dyn"),
            )),
            _ => p
                .as_symbol()
                .filter(|s| *s != blue_lang_syntax::OPTIONAL_MARKER)
                .map(|s| (s.to_string(), None)),
        })
        .collect()
}

fn names(form: &Spanned, name: &str, qualified: Option<&str>) -> bool {
    let body = form
        .as_list()
        .map_or(&[][..], |items| items.get(2..).unwrap_or_default());
    body.iter().any(|b| mentions(b, name, qualified))
}

fn mentions(node: &Spanned, name: &str, qualified: Option<&str>) -> bool {
    match &node.form {
        SpannedForm::Atom(Atom::Symbol(s)) => s.as_str() == name || Some(s.as_str()) == qualified,
        SpannedForm::List(items) => items.iter().any(|i| mentions(i, name, qualified)),
        SpannedForm::Quote(x)
        | SpannedForm::Quasiquote(x)
        | SpannedForm::Unquote(x)
        | SpannedForm::UnquoteSplice(x) => mentions(x, name, qualified),
        _ => false,
    }
}

fn refusal_kinds(node: &Spanned, out: &mut BTreeSet<String>) {
    if let Some(items) = node.as_list() {
        let head = items.first().and_then(Spanned::as_symbol);
        let refuses = matches!(head, Some("refusal" | "raise"))
            || head.is_some_and(|h| h == blue_lang_syntax::qualify("kyohi", "refusal"));
        if refuses {
            if let Some(SpannedForm::Atom(Atom::Keyword(k))) = items.get(1).map(|k| &k.form) {
                out.insert(format!(":{k}"));
            }
        }
        for i in items {
            refusal_kinds(i, out);
        }
    }
}

impl DocView {
    /// The derived rows as Markdown lines, for hover and `blue doc`.
    #[must_use]
    pub fn derived_lines(&self) -> Vec<String> {
        let mut out = vec![format!(
            "signature `{}` · rung {}",
            self.signature, self.rung
        )];
        if let Some(reach) = &self.reach {
            out.push(if reach.is_empty() {
                "pure: reaches no host capability".to_string()
            } else {
                let caps: Vec<String> = reach.keys().map(|c| format!("`{}`", c.label())).collect();
                format!("reaches {}", caps.join(", "))
            });
        }
        if let Some(c) = &self.contract {
            let field = |k: &str| {
                c.get(k)
                    .map(String::as_str)
                    .filter(|v| !v.is_empty() && *v != "-")
                    .unwrap_or("—")
                    .to_string()
            };
            out.push(format!(
                "contract: args {} · opts {} · returns {} · raises {} · kind {}",
                field("args"),
                field("opts"),
                field("returns"),
                field("raises"),
                field("kind")
            ));
        }
        if let Some(v) = &self.verb {
            let laterals = if v.laterals.is_empty() {
                "—".to_string()
            } else {
                v.laterals.join(", ")
            };
            out.push(format!(
                "space `{}` · {} · `{}` · laterals {laterals}",
                v.space, v.kind, v.shape
            ));
        }
        if !self.edges.is_empty() {
            out.push(format!("edges: {}", self.edges.join("; ")));
        }
        if !self.callers.is_empty() {
            out.push(format!("callers: {}", self.callers.join(", ")));
        }
        for (k, meaning) in &self.refusals {
            out.push(match meaning {
                Some(m) => format!("refuses {k}: {m}"),
                None => format!("refuses {k}"),
            });
        }
        out
    }
}

/// The repository tables a view reads, found from a file's directory.
#[derive(Default)]
pub(crate) struct RepoData {
    contracts: HashMap<String, BTreeMap<String, String>>,
    verbs: HashMap<(String, String), VerbRow>,
    edges: HashMap<String, Vec<String>>,
    ledger: HashMap<String, String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub(crate) struct Sources {
    contracts: Option<PathBuf>,
    graph: Option<PathBuf>,
    ledger: Option<PathBuf>,
}

impl Sources {
    pub(crate) fn of(path: &Path) -> Self {
        let dir = path.parent().unwrap_or(path);
        let mut s = Self::default();
        for a in dir.ancestors() {
            let contracts = a.join("docs/verbs/contracts.tsv");
            if s.contracts.is_none() && contracts.is_file() {
                s.contracts = Some(contracts);
            }
            let graph = a.join("mokuroku").join("graph");
            if s.graph.is_none() && graph.is_dir() {
                s.graph = Some(graph);
                s.ledger = Some(a.join("kyohi").join("kyohi.b"));
            }
        }
        s
    }

    pub(crate) fn holds(&self, path: &Path) -> bool {
        self.contracts.as_deref() == Some(path)
            || self.ledger.as_deref() == Some(path)
            || self.graph.as_deref().is_some_and(|g| path.starts_with(g))
    }
}

impl RepoData {
    fn load(sources: &Sources, parse: &dyn Fn(&str) -> Rc<crate::Parsed>) -> Self {
        let mut data = Self::default();
        if let Some(t) = sources
            .contracts
            .as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
        {
            data.contracts = contracts(&t);
        }
        if let Some(graph) = &sources.graph {
            graph_rows(graph, &mut data, parse);
        }
        if let Some(t) = sources
            .ledger
            .as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
        {
            data.ledger = ledger(&parse(&t));
        }
        data
    }
}

fn contracts(text: &str) -> HashMap<String, BTreeMap<String, String>> {
    let mut lines = text.lines();
    let Some(header) = lines.next() else {
        return HashMap::new();
    };
    let columns: Vec<&str> = header.split('\t').collect();
    lines
        .filter_map(|l| {
            let row: BTreeMap<String, String> = columns
                .iter()
                .zip(l.split('\t'))
                .map(|(k, v)| ((*k).to_string(), v.to_string()))
                .collect();
            Some((row.get("verb")?.clone(), row))
        })
        .collect()
}

fn str_of(s: &blue_lang_syntax::Sexp) -> Option<String> {
    s.as_string().or_else(|| s.as_keyword()).map(str::to_string)
}

fn graph_rows(dir: &Path, data: &mut RepoData, parse: &dyn Fn(&str) -> Rc<crate::Parsed>) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    let mut files: Vec<PathBuf> = rd
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "b"))
        .collect();
    files.sort();
    for f in files {
        let Ok(text) = std::fs::read_to_string(&f) else {
            continue;
        };
        let parsed = parse(&text);
        let Ok(forms) = parsed.as_ref() else {
            continue;
        };
        for form in forms.iter().map(Spanned::to_sexp) {
            let Some(items) = form.as_list() else {
                continue;
            };
            match items {
                [h, space, verb, fields] if h.as_symbol() == Some("verb") => {
                    let (Some(space), Some(verb)) = (str_of(space), str_of(verb)) else {
                        continue;
                    };
                    let mut row = VerbRow {
                        space,
                        ..VerbRow::default()
                    };
                    let mut today = String::new();
                    for pair in fields
                        .as_list()
                        .unwrap_or_default()
                        .get(1..)
                        .unwrap_or_default()
                        .chunks(2)
                    {
                        let [k, v] = pair else { continue };
                        match k.as_keyword() {
                            Some("kind") => row.kind = str_of(v).unwrap_or_default(),
                            Some("shape") => row.shape = str_of(v).unwrap_or_default(),
                            Some("today") => today = str_of(v).unwrap_or_default(),
                            Some("laterals") => {
                                row.laterals = v
                                    .as_list()
                                    .unwrap_or_default()
                                    .iter()
                                    .skip(1)
                                    .filter_map(str_of)
                                    .collect();
                            }
                            _ => {}
                        }
                    }
                    for part in today.split(['|', ',']) {
                        if let Some((state, b)) = part.trim().split_once(':') {
                            if matches!(state, "exists" | "partial") {
                                data.verbs
                                    .insert((b.to_string(), verb.clone()), row.clone());
                            }
                        }
                    }
                }
                [h, from, kind, to, ..] if h.as_symbol() == Some("edge") => {
                    if let (Some(from), Some(kind), Some(to)) =
                        (str_of(from), str_of(kind), str_of(to))
                    {
                        data.edges
                            .entry(from)
                            .or_default()
                            .push(format!("{kind} {to}"));
                    }
                }
                _ => {}
            }
        }
    }
}

fn ledger(parsed: &crate::Parsed) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let Ok(forms) = parsed else {
        return out;
    };
    fn walk(s: &blue_lang_syntax::Sexp, out: &mut HashMap<String, String>) {
        if let Some(items) = s.as_list() {
            if let [h, k, m, ..] = items {
                if h.as_symbol() == Some("ledger_row") {
                    if let (Some(k), Some(m)) = (k.as_keyword(), m.as_string()) {
                        out.insert(format!(":{k}"), m.to_string());
                    }
                }
            }
            for i in items {
                walk(i, out);
            }
        }
    }
    for f in forms {
        walk(&f.to_sexp(), &mut out);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_waku::Capability;

    const SRC: &str = "@doc \"\"\"\nget_one reads one.\n\n    get_one(1) #=> 1\n\"\"\"\ndef get_one(k: Int) -> Int\n  if k < 0\n    raise(:not_found, \"no\")\n  end\n  k\nend\n\ndef twice(k)\n  get_one(k) + get_one(k)\nend\n";

    #[test]
    fn the_view_derives_signature_types_rung_callers_and_refusals() {
        let v = of_file(SRC, None, Some("m"), "get_one").expect("defined");
        assert_eq!(
            v.doc.as_deref(),
            Some("get_one reads one.\n\n    get_one(1) #=> 1")
        );
        assert_eq!(v.signature, "def get_one(k: Int) -> Int");
        assert_eq!(v.params, vec![("k".to_string(), Some("Int".to_string()))]);
        assert_eq!(v.returns.as_deref(), Some("Int"));
        assert_eq!(v.rung, "annotated");
        assert_eq!(v.callers, vec!["twice".to_string()]);
        assert_eq!(v.refusals, vec![(":not_found".to_string(), None)]);
        let t = of_file(SRC, None, Some("m"), "twice").expect("defined");
        assert_eq!((t.rung, t.doc), ("dynamic", None));
        assert!(of_file(SRC, None, None, "absent").is_none());
    }

    #[test]
    fn a_shared_shape_renders_from_its_one_row() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bidamas/retsu/retsu.b");
        let text = std::fs::read_to_string(&root).expect("retsu");
        let v = of_file(&text, Some(&root), Some("retsu"), "at").expect("at");
        let c = v.contract.clone().expect("at has a contract row");
        assert_eq!(c.get("verb").map(String::as_str), Some("at"));
        let verb = v.verb.clone().expect("at has a graph row");
        assert_eq!(verb.space, "retsu");
        let lines = v.derived_lines();
        assert!(
            lines.iter().any(|l| l.starts_with("contract: ")),
            "{lines:?}"
        );
    }

    #[test]
    fn the_view_names_the_host_capabilities_a_definition_reaches() {
        let mut e = crate::Engine::new(Box::new(blue_lang_runtime::uses::NoLoader));
        let src = "def add(a, b)\n  a + b\nend\n\ndef slurp(p)\n  read_file(p)\nend\n\ndef stamp()\n  now_ms\nend\n\ndef later()\n  stamp + 1\nend\n";
        e.set_document("t.b", None, src);
        let lines = |name: &str| {
            e.doc_view_in("t.b", None, name)
                .unwrap_or_else(|| panic!("{name}"))
                .derived_lines()
        };
        let reaches = |name: &str| {
            e.doc_view_in("t.b", None, name)
                .and_then(|v| v.reach)
                .map(|r| r.into_keys().collect::<Vec<_>>())
        };
        assert_eq!(reaches("add"), Some(Vec::new()));
        assert_eq!(reaches("slurp"), Some(vec![Capability::FileSystem]));
        assert_eq!(reaches("stamp"), Some(vec![Capability::Clock]));
        assert_eq!(reaches("later"), Some(vec![Capability::Clock]));
        assert!(
            lines("add").contains(&"pure: reaches no host capability".to_string()),
            "{:?}",
            lines("add")
        );
        assert!(
            lines("slurp").contains(&"reaches `filesystem`".to_string()),
            "{:?}",
            lines("slurp")
        );
        assert!(
            lines("stamp").contains(&"reaches `clock`".to_string()),
            "{:?}",
            lines("stamp")
        );
        let syntactic = of_file(src, None, None, "slurp").expect("slurp");
        assert_eq!(syntactic.reach, None);
        assert!(!syntactic
            .derived_lines()
            .iter()
            .any(|l| l.contains("reaches")));
    }
}

impl crate::Engine {
    /// The view of the definition `name` of namespace `ns` that `l` locates:
    /// what hover and `blue doc` show beside its `@doc`.
    #[must_use]
    pub fn doc_view(
        &self,
        a: &crate::Analysis,
        l: &crate::Located,
        ns: &blue_lang_check::Namespace,
        name: &str,
    ) -> Option<DocView> {
        let (text, path): (String, Option<PathBuf>) = match &l.file {
            crate::FileRef::Document(id) => (
                self.document_text(id)?.to_string(),
                self.documents.get(id).and_then(|d| d.path.clone()),
            ),
            crate::FileRef::Path(p) => (a.file_text(&l.file)?.to_string(), Some(p.clone())),
        };
        let bidama = match ns {
            blue_lang_check::Namespace::Bidama(b) => Some(b.as_str()),
            _ => None,
        };
        let forms = self.memo.documented(&text, true);
        let data = path.as_deref().map(|p| self.repo_data(p));
        let mut v = view(forms.as_ref().as_ref().ok()?, data.as_deref(), bidama, name)?;
        v.reach = a.host_reach_of(ns, name).cloned();
        Some(v)
    }

    #[must_use]
    pub fn doc_view_in(&self, id: &str, bidama: Option<&str>, name: &str) -> Option<DocView> {
        let a = self.analysis(id)?;
        let ns = bidama.map_or_else(
            || a.own_namespace(),
            |b| blue_lang_check::Namespace::Bidama(b.to_string()),
        );
        let at = crate::Located {
            file: crate::FileRef::Document(id.to_string()),
            span: Span::new(0, 0),
        };
        self.doc_view(&a, &at, &ns, name)
    }

    pub fn prepare_doc_views(&self, id: &str) {
        if let Some(p) = self.documents.get(id).and_then(|d| d.path.clone()) {
            self.repo_data(&p);
        }
    }

    fn repo_data(&self, path: &Path) -> Rc<RepoData> {
        let sources = Sources::of(&crate::canonical(path));
        if let Some(hit) = self.repo.borrow().get(&sources) {
            return hit.clone();
        }
        let data = Rc::new(RepoData::load(&sources, &|t| self.memo.parse(t, true)));
        self.repo.borrow_mut().insert(sources, data.clone());
        data
    }
}
