//! What it means for the emitted parser and blue's parser to agree.
//!
//! Blue's parser answers a source with a tree or a refusal; tree-sitter's
//! answers every source with a tree that may hold `ERROR` and `MISSING` nodes.
//! For a source `P` (a whole corpus file, or any prefix of one, cut at any
//! character boundary — a prefix is a buffer mid-edit), the two AGREE when:
//!
//! 1. **Acceptance.** Blue parses `P` exactly when tree-sitter's tree for `P`
//!    holds no `ERROR` and no `MISSING` node. A grammar looser than blue lets
//!    an editor show clean code the compiler refuses; a stricter one marks
//!    working code broken.
//! 2. **Meaning.** When both accept, the tree-sitter tree, lowered by the
//!    spec, is blue's tree, form for form.
//! 3. **Tolerance.** When both refuse, every top-level statement already
//!    CLOSED in `P` (its form ends, and the newline that terminates it lies
//!    inside `P`) is a top-level node of tree-sitter's tree with no error in
//!    it, and lowers to blue's tree for that statement.
//!
//! Inside the statement being typed nothing is required: blue has no tree
//! there, so any claim about tree-sitter's recovery would be compared with
//! nothing. Above it, everything is: an edit must not disturb the meaning, or
//! the highlighting, of the code before it.
//!
//! Tree-sitter is judged the two ways an editor meets a buffer. TYPING: every
//! prefix, each reached from the one before by appending a character and
//! reparsing incrementally, as a buffer grows under the cursor (a run starts
//! with a fresh parse every [`CHUNK`] prefixes). OPENING: every prefix that
//! ends a line, and the whole file, parsed fresh.
//!
//! Blue's verdict on a prefix is computed as its parse of the closed region
//! (once per region) followed by its parse of the rest alone. That is exact
//! because blue's parser carries no state from one top-level statement to the
//! next, and it is checked rather than assumed: at every OPENING prefix the
//! whole prefix is parsed too, and the two must be equal.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

use blue_lang_syntax::parse::{parse_program, parse_program_spanned};
use tatara_lisp::Sexp;

use crate::lower::{LowerError, Lowerer};
use crate::spec::Spec;
use crate::ts::{Node, Parser, Runtime, Tree};

/// Prefixes judged by one incremental run before the next fresh parse.
pub const CHUNK: usize = 512;

/// One way a prefix failed to agree.
#[derive(Debug, Clone)]
pub enum Disagreement {
    /// One parser accepted and the other did not.
    Acceptance { blue: Result<(), String>, tree_sitter_error_at: Option<usize> },
    /// Both accepted, and the trees differ at top-level form `form`.
    Meaning { form: usize, blue: Option<String>, kiwari: Result<Option<String>, LowerError> },
    /// Both refused, and closed statement `form` is not intact in tree-sitter's tree.
    Tolerance { form: usize, blue: String, kiwari: Result<String, String> },
    /// Blue's own answers disagree: a closed region it refuses, or the
    /// decomposed verdict differing from the whole prefix's.
    Oracle { why: String },
}

/// How tree-sitter met the prefix.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Typing,
    Opening,
}

#[derive(Debug, Clone)]
pub struct Finding {
    pub file: PathBuf,
    pub cut: usize,
    pub line: usize,
    pub col: usize,
    pub mode: Mode,
    pub what: Disagreement,
}

impl std::fmt::Display for Finding {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}:{} ({:?}, prefix of {} bytes): ", self.file.display(), self.line, self.col, self.mode, self.cut)?;
        match &self.what {
            Disagreement::Acceptance { blue, tree_sitter_error_at } => write!(
                f,
                "acceptance: blue {}, tree-sitter {}",
                match blue {
                    Ok(()) => "accepts".to_string(),
                    Err(e) => format!("refuses ({e})"),
                },
                match tree_sitter_error_at {
                    None => "accepts".to_string(),
                    Some(at) => format!("refuses (first error at byte {at})"),
                }
            ),
            Disagreement::Meaning { form, blue, kiwari } => write!(
                f,
                "meaning of form {form}: blue {} | kiwari {}",
                blue.as_deref().unwrap_or("(none)"),
                match kiwari {
                    Ok(k) => k.clone().unwrap_or_else(|| "(none)".into()),
                    Err(e) => format!("cannot lower: {e}"),
                }
            ),
            Disagreement::Tolerance { form, blue, kiwari } => write!(
                f,
                "tolerance: closed statement {form} is {blue} to blue and {} to tree-sitter",
                match kiwari {
                    Ok(k) => k.clone(),
                    Err(e) => e.clone(),
                }
            ),
            Disagreement::Oracle { why } => write!(f, "blue disagrees with itself: {why}"),
        }
    }
}

/// The numbers a run produced.
#[derive(Debug, Default, Clone)]
pub struct Tally {
    pub files: usize,
    pub files_agreeing: usize,
    pub prefixes: usize,
    pub typing: usize,
    pub opening: usize,
    pub both_accept: usize,
    pub both_refuse: usize,
    pub closed_statements_checked: usize,
    pub disagreements: usize,
    pub findings: Vec<Finding>,
}

impl Tally {
    fn add(&mut self, o: &Tally) {
        self.prefixes += o.prefixes;
        self.typing += o.typing;
        self.opening += o.opening;
        self.both_accept += o.both_accept;
        self.both_refuse += o.both_refuse;
        self.closed_statements_checked += o.closed_statements_checked;
        self.disagreements += o.disagreements;
        self.findings.extend(o.findings.iter().cloned());
    }
}

/// One corpus file, read once and parsed once by blue in full.
struct Subject {
    path: PathBuf,
    src: String,
    /// Each character boundary, `0..=len`.
    cuts: Vec<usize>,
    /// For each top-level form of the whole file, the offset just past the
    /// newline that closes it.
    closes: Vec<usize>,
    /// Blue's forms for the prefix ending at each `closes[k]`, filled once.
    closed: Vec<Mutex<Option<Result<std::sync::Arc<Vec<Sexp>>, String>>>>,
}

impl Subject {
    fn read(path: &Path) -> Result<Self, String> {
        let src = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let spanned = parse_program_spanned(&src).map_err(|e| format!("{}: blue refuses it: {e}", path.display()))?;
        let closes: Vec<usize> = spanned
            .iter()
            .map_while(|(_, span)| src[span.end..].find('\n').map(|i| span.end + i + 1))
            .collect();
        let closed = closes.iter().map(|_| Mutex::new(None)).collect();
        let cuts = (0..=src.len()).filter(|i| src.is_char_boundary(*i)).collect();
        Ok(Self { path: path.to_path_buf(), src, cuts, closes, closed })
    }

    fn closed_count(&self, cut: usize) -> usize {
        self.closes.partition_point(|c| *c <= cut)
    }

    /// Blue's forms for the first `k` closed statements.
    fn closed_forms(&self, k: usize) -> Result<std::sync::Arc<Vec<Sexp>>, String> {
        if k == 0 {
            return Ok(std::sync::Arc::new(Vec::new()));
        }
        let mut slot = self.closed[k - 1].lock().expect("no panics while held");
        slot.get_or_insert_with(|| {
            parse_program(&self.src[..self.closes[k - 1]])
                .map(std::sync::Arc::new)
                .map_err(|e| format!("blue refuses the closed region ending at {}: {e}", self.closes[k - 1]))
        })
        .clone()
    }

    fn line_col(&self, at: usize) -> (usize, usize) {
        let before = &self.src[..at];
        let line = before.matches('\n').count() + 1;
        let col = before.rsplit('\n').next().map_or(0, |l| l.chars().count()) + 1;
        (line, col)
    }
}

fn first_error(node: Node<'_>) -> Option<usize> {
    if node.is_error() || node.is_missing() {
        return Some(node.start());
    }
    if !node.has_error() {
        return None;
    }
    node.children().into_iter().find_map(|c| first_error(c.node))
}

fn top_level(root: Node<'_>) -> Vec<Node<'_>> {
    root.children().into_iter().map(|c| c.node).filter(|n| n.is_named() && !n.is_extra()).collect()
}

/// Top-level subtrees already shown to lower to blue's form at their index,
/// keyed by identity; the trees holding them are kept alive beside the keys,
/// so no key can be reused by a different subtree.
#[derive(Default)]
struct Memo<'r> {
    seen: HashSet<(usize, usize, usize, usize)>,
    trees: Vec<Tree<'r>>,
}

struct Judge<'a> {
    spec: &'a Spec,
    subject: &'a Subject,
}

impl Judge<'_> {
    /// Does top-level `node` mean blue's form `want` at index `i`?
    fn form(&self, node: Node<'_>, i: usize, want: &Sexp, lowerer: &Lowerer<'_>, memo: Option<&mut HashSet<(usize, usize, usize, usize)>>) -> Result<(), Result<String, String>> {
        let key = (node.id(), node.start(), node.end(), i);
        if memo.as_ref().is_some_and(|m| m.contains(&key)) {
            return Ok(());
        }
        if node.has_error() {
            return Err(Err(format!("a `{}` holding an error", node.kind())));
        }
        match lowerer.lower_one(node) {
            Ok(got) if &got == want => {
                if let Some(m) = memo {
                    m.insert(key);
                }
                Ok(())
            }
            Ok(got) => Err(Ok(got.to_string())),
            Err(e) => Err(Err(e.to_string())),
        }
    }

    fn judge(&self, cut: usize, root: Node<'_>, mode: Mode, mut memo: Option<&mut HashSet<(usize, usize, usize, usize)>>, tally: &mut Tally) -> Option<Disagreement> {
        let s = self.subject;
        let prefix = &s.src[..cut];
        let k = s.closed_count(cut);
        let closed = match s.closed_forms(k) {
            Ok(c) => c,
            Err(why) => return Some(Disagreement::Oracle { why }),
        };
        let from = if k == 0 { 0 } else { s.closes[k - 1] };
        let tail = parse_program(&s.src[from..cut]).map_err(|e| e.to_string());
        if mode == Mode::Opening {
            let whole = parse_program(prefix).map_err(|e| e.to_string());
            let decomposed = tail.clone().map(|t| closed.iter().cloned().chain(t).collect::<Vec<_>>());
            if whole.is_ok() != decomposed.is_ok() || whole.as_ref().ok() != decomposed.as_ref().ok() {
                return Some(Disagreement::Oracle {
                    why: format!("the prefix parses {} whole and {} split at byte {from}", verdict(&whole), verdict(&decomposed)),
                });
            }
        }
        let ts_error = if root.has_error() { first_error(root).or(Some(root.start())) } else { None };
        let lowerer = Lowerer::new(self.spec, prefix);
        let nodes = top_level(root);
        match (tail, ts_error) {
            (Ok(tail), None) => {
                tally.both_accept += 1;
                if nodes.len() != k + tail.len() {
                    return Some(Disagreement::Meaning {
                        form: k.min(nodes.len()),
                        blue: Some(format!("{} forms", k + tail.len())),
                        kiwari: Ok(Some(format!("{} top-level nodes", nodes.len()))),
                    });
                }
                for (i, want) in closed.iter().chain(tail.iter()).enumerate() {
                    if let Err(got) = self.form(nodes[i], i, want, &lowerer, memo.as_deref_mut()) {
                        return Some(Disagreement::Meaning {
                            form: i,
                            blue: Some(want.to_string()),
                            kiwari: got.map(Some).map_err(|why| LowerError { kind: nodes[i].kind().into(), start: nodes[i].start(), end: nodes[i].end(), why }),
                        });
                    }
                }
                None
            }
            (Err(_), Some(_)) => {
                tally.both_refuse += 1;
                for (i, want) in closed.iter().enumerate() {
                    tally.closed_statements_checked += 1;
                    let got = match nodes.get(i) {
                        None => Err(Err("absent".to_string())),
                        Some(n) => self.form(*n, i, want, &lowerer, memo.as_deref_mut()),
                    };
                    if let Err(kiwari) = got {
                        return Some(Disagreement::Tolerance { form: i, blue: want.to_string(), kiwari });
                    }
                }
                None
            }
            (blue, ts) => Some(Disagreement::Acceptance { blue: blue.map(|_| ()), tree_sitter_error_at: ts }),
        }
    }
}

fn verdict<T>(r: &Result<T, String>) -> String {
    match r {
        Ok(_) => "accepted".into(),
        Err(e) => format!("refused ({e})"),
    }
}

/// Every `.b` file and `Bluefile` under `roots`, sorted.
pub fn corpus(roots: &[PathBuf]) -> Vec<PathBuf> {
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else { return };
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                walk(&p, out);
            } else if p.extension().is_some_and(|x| x == "b") || p.file_name().is_some_and(|n| n == "Bluefile") {
                out.push(p);
            }
        }
    }
    let mut out = Vec::new();
    for r in roots {
        walk(r, &mut out);
    }
    out.sort();
    out
}

/// How much of each file to judge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    /// The whole file only, opened: M0's round trip.
    Whole,
    /// Every prefix typed, and every line-end prefix and the whole file opened.
    EveryPrefix,
}

fn record(tally: &mut Tally, failed: &mut Vec<usize>, keep: usize, s: &Subject, i: usize, cut: usize, mode: Mode, what: Option<Disagreement>) {
    tally.prefixes += 1;
    match mode {
        Mode::Typing => tally.typing += 1,
        Mode::Opening => tally.opening += 1,
    }
    if let Some(what) = what {
        tally.disagreements += 1;
        failed.push(i);
        if tally.findings.len() < keep {
            let (line, col) = s.line_col(cut);
            tally.findings.push(Finding { file: s.path.clone(), cut, line, col, mode, what });
        }
    }
}

fn run_chunk<'r>(parser: &mut Parser<'r>, spec: &Spec, s: &Subject, i: usize, from: usize, to: usize, scope: Scope, keep: usize, tally: &mut Tally, failed: &mut Vec<usize>) {
    let judge = Judge { spec, subject: s };
    let last = s.cuts.len() - 1;
    if scope == Scope::Whole {
        let tree = parser.parse(&s.src);
        let what = judge.judge(s.src.len(), tree.root(), Mode::Opening, None, tally);
        record(tally, failed, keep, s, i, s.src.len(), Mode::Opening, what);
        return;
    }
    let mut memo = Memo::default();
    for c in from..to {
        let cut = s.cuts[c];
        let tree = if c == from {
            parser.parse(&s.src[..cut])
        } else {
            let prev = s.cuts[c - 1];
            let old = memo.trees.last_mut().expect("the chunk's first prefix parsed");
            parser.reparse_appended(old, &s.src[..cut], prev)
        };
        let what = judge.judge(cut, tree.root(), Mode::Typing, Some(&mut memo.seen), tally);
        record(tally, failed, keep, s, i, cut, Mode::Typing, what);
        memo.trees.push(tree);
        if c == last || (cut > 0 && s.src.as_bytes()[cut - 1] == b'\n') {
            let fresh = parser.parse(&s.src[..cut]);
            let what = judge.judge(cut, fresh.root(), Mode::Opening, None, tally);
            record(tally, failed, keep, s, i, cut, Mode::Opening, what);
        }
    }
}

/// Judge every file in `files` over `scope` on `threads` threads, keeping at
/// most `keep` findings in full.
pub fn run(rt: &Runtime, spec: &Spec, files: &[PathBuf], scope: Scope, threads: usize, keep: usize) -> Result<Tally, String> {
    let subjects: Vec<Subject> = files.iter().map(|p| Subject::read(p)).collect::<Result<_, _>>()?;
    let work: Vec<(usize, usize, usize)> = subjects
        .iter()
        .enumerate()
        .flat_map(|(i, s)| match scope {
            Scope::Whole => vec![(i, 0, 0)],
            Scope::EveryPrefix => (0..s.cuts.len()).step_by(CHUNK).map(|f| (i, f, (f + CHUNK).min(s.cuts.len()))).collect(),
        })
        .collect();
    let next = AtomicUsize::new(0);
    let total = Mutex::new(Tally::default());
    let failed_files = Mutex::new(std::collections::BTreeSet::new());
    std::thread::scope(|scope_| {
        for _ in 0..threads.max(1) {
            scope_.spawn(|| {
                let mut parser = rt.parser();
                let mut local = Tally::default();
                let mut local_failed = Vec::new();
                loop {
                    let w = next.fetch_add(1, Ordering::Relaxed);
                    let Some(&(i, from, to)) = work.get(w) else { break };
                    run_chunk(&mut parser, spec, &subjects[i], i, from, to, scope, keep, &mut local, &mut local_failed);
                }
                total.lock().expect("no panics while held").add(&local);
                failed_files.lock().expect("no panics while held").extend(local_failed);
            });
        }
    });
    let mut t = total.into_inner().expect("threads joined");
    t.files = subjects.len();
    t.files_agreeing = subjects.len() - failed_files.into_inner().expect("threads joined").len();
    t.findings.sort_by(|a, b| (&a.file, a.cut).cmp(&(&b.file, b.cut)));
    t.findings.truncate(keep);
    Ok(t)
}
