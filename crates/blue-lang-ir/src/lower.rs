//! The lowering: a checked program's resolved tree, plus the check stage's
//! own metadata, into [`Module`]s of SSA blocks.
//!
//! **The input is the pipeline's output, never a reassembly of its stages.**
//! The caller hands over the [`Checked`] value `check_entry` produced; this
//! file reads `lowered()` (the resolved tree — every reference already what
//! it binds to), `outcome` (the seams), and the program's file table. No
//! parsing, no reordering, no second checker.
//!
//! **Refusal is typed, not silent.** A construct the IR does not model yet
//! (rescue, eval, the process words, a named record update) fails the
//! lowering with a [`Refusal`] that names it and locates it. Nothing is
//! lowered as if it were something else.

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};

use blue_lang_check::Ty;
use blue_lang_runtime::pipeline::Checked;
use blue_lang_runtime::reach::host_capability;
use blue_lang_runtime::shift::{rung_of, Rung};
use blue_lang_syntax::record::record_parts;
use blue_lang_syntax::union::declared as union_declared;
use blue_lang_waku::Capability;
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::module::{
    Block, Callee, Const, FieldDef, Function, Inst, Module, Param, RecordDef, SeamKind, Terminator,
    UnionArm, UnionDef, ValueId,
};
use crate::posture::Posture;

/// The lowering stopped: `what` names the construct, `span` and `top_level`
/// locate it (`Checked::program` turns them into file:line:col).
#[derive(Clone, Debug, PartialEq)]
pub struct Refusal {
    pub what: String,
    pub top_level: usize,
    pub span: Span,
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "the IR does not lower `{}` yet", self.what)
    }
}

impl std::error::Error for Refusal {}

/// Words the IR refuses rather than lowers wrongly: the resident
/// evaluator's own machinery, which a compiled zone reaches only through a
/// seam later phases define — lowering one as a plain call would hide that
/// crossing.
const REFUSED_WORDS: &[&str] = &[
    "eval",
    "try",
    "delay",
    "spawn",
    "receive",
    "node",
    "provide",
    "require",
    "macroexpand",
    "macroexpand-1",
];

/// Lower a checked program, one module per package-or-file. A program whose
/// check found error-severity diagnostics is the CALLER's to refuse (the
/// CLI door does); lowering one anyway would only describe broken code.
///
/// # Errors
///
/// The first construct the IR does not model, located in the source.
pub fn lower(checked: &Checked) -> Result<Vec<Module>, Refusal> {
    Survey::of(checked)
}

// ---------------------------------------------------------------------------
// The survey: modules, postures, records, unions, signatures — read once,
// before any function is lowered, so a call anywhere can ask for a callee's
// posture and types.
// ---------------------------------------------------------------------------

struct FnInfo {
    module: usize,
    params: Vec<Param>,
    ret: Ty,
}

struct Survey<'a> {
    checked: &'a Checked,
    forms: &'a [Spanned],
    /// module key ("pkg" or "%root") -> index.
    module_at: BTreeMap<String, usize>,
    module_names: Vec<String>,
    module_posture: Vec<Posture>,
    /// constructor key ("%root/point") -> (module, record index).
    record_at: BTreeMap<String, (usize, usize)>,
    /// predicate key ("%root/point?") -> constructor key.
    record_predicate: BTreeMap<String, String>,
    /// union predicate key ("%root/shape?") -> (module, union index).
    union_at: BTreeMap<String, (usize, usize)>,
    /// runtime key ("%root/add") -> its signature.
    fns: BTreeMap<String, FnInfo>,
}

fn module_key(checked: &Checked, top: usize) -> String {
    checked
        .program
        .owner_of(top)
        .and_then(|id| checked.program.file(id))
        .and_then(|f| f.package.clone())
        .unwrap_or_else(|| "%root".to_string())
}

fn bare(key: &str) -> &str {
    key.rsplit('/').next().unwrap_or(key)
}

fn params_of(sig: &[Spanned], typed: bool) -> Vec<Param> {
    let mut params = Vec::new();
    let mut rest = false;
    for p in sig {
        if rest {
            rest = false;
            if let Some(n) = p.as_symbol() {
                params.push(Param {
                    name: n.to_string(),
                    ty: Ty::List(Box::new(Ty::Dyn)),
                });
            }
            continue;
        }
        if p.as_symbol().is_some_and(|s| s.starts_with('&')) {
            rest = true;
            continue;
        }
        if let Some(pair) = p.as_list() {
            if pair.len() == 2 {
                if let Some(n) = pair[0].as_symbol() {
                    params.push(Param {
                        name: n.to_string(),
                        ty: Ty::from_sexp(&pair[1].to_sexp()),
                    });
                    continue;
                }
            }
        }
        if let Some(n) = p.as_symbol() {
            params.push(Param {
                name: n.to_string(),
                ty: if typed { Ty::Dyn } else { Ty::Dyn },
            });
        }
    }
    params
}

impl<'a> Survey<'a> {
    fn of(checked: &'a Checked) -> Result<Vec<Module>, Refusal> {
        let forms = checked.lowered();
        let mut module_at: BTreeMap<String, usize> = BTreeMap::new();
        let mut module_names: Vec<String> = Vec::new();
        let mut module_forms: Vec<Vec<usize>> = Vec::new();
        for i in 0..forms.len() {
            let key = module_key(checked, i);
            let idx = *module_at.entry(key.clone()).or_insert_with(|| {
                module_names.push(key);
                module_forms.push(Vec::new());
                module_forms.len() - 1
            });
            module_forms[idx].push(i);
        }

        // Postures: the LOWEST rung of a module's files, exactly as a
        // document's rung is the lowest of its declarations.
        let mut module_posture = Vec::with_capacity(module_names.len());
        for forms_of_module in &module_forms {
            let mut by_file: BTreeMap<String, Vec<Spanned>> = BTreeMap::new();
            for &i in forms_of_module {
                let file = checked
                    .program
                    .owner_of(i)
                    .and_then(|id| checked.program.file(id))
                    .map(|f| {
                        format!(
                            "{}/{}",
                            f.package.as_deref().unwrap_or(""),
                            f.path
                                .as_ref()
                                .map_or_else(String::new, |p| p.display().to_string())
                        )
                    })
                    .unwrap_or_default();
                by_file.entry(file).or_default().push(forms[i].clone());
            }
            let rung = by_file
                .values()
                .filter_map(|fs| rung_of(fs))
                .min()
                .unwrap_or(Rung::Dynamic);
            module_posture.push(Posture::from_rung(rung));
        }

        let mut survey = Survey {
            checked,
            forms: &forms,
            module_at,
            module_names,
            module_posture,
            record_at: BTreeMap::new(),
            record_predicate: BTreeMap::new(),
            union_at: BTreeMap::new(),
            fns: BTreeMap::new(),
        };

        // Records first: unions name their arms by predicate.
        let mut records: Vec<Vec<RecordDef>> =
            (0..survey.module_names.len()).map(|_| Vec::new()).collect();
        for (i, form) in forms.iter().enumerate() {
            let module = survey.module_at[&module_key(checked, i)];
            let Some(r) = record_parts(form) else {
                continue;
            };
            let (Some(key), Some(pred)) = (r.name.as_symbol(), r.predicate.as_symbol()) else {
                continue;
            };
            let def = RecordDef {
                name: bare(key).to_string(),
                key: key.to_string(),
                predicate: bare(pred).to_string(),
                fields: r
                    .fields
                    .iter()
                    .map(|f| FieldDef {
                        name: f.name.to_string(),
                        ty: f.ty.map_or(Ty::Dyn, |t| Ty::from_sexp(&t.to_sexp())),
                    })
                    .collect(),
            };
            survey
                .record_at
                .insert(key.to_string(), (module, records[module].len()));
            survey
                .record_predicate
                .insert(pred.to_string(), key.to_string());
            records[module].push(def);
        }

        let mut unions: Vec<Vec<UnionDef>> =
            (0..survey.module_names.len()).map(|_| Vec::new()).collect();
        for (i, form) in forms.iter().enumerate() {
            let module = survey.module_at[&module_key(checked, i)];
            let Some(d) = union_declared(form) else {
                continue;
            };
            let (Some(name), Some(pred)) = (d.name.as_symbol(), d.predicate.as_symbol()) else {
                continue;
            };
            let mut arms = Vec::new();
            for arm in d.arms {
                let Some(arm_pred) = arm.as_symbol() else {
                    continue;
                };
                let Some(record_key) = survey.record_predicate.get(arm_pred) else {
                    continue;
                };
                let (r_module, r_idx) = survey.record_at[record_key];
                let rec = &records[r_module][r_idx];
                arms.push(UnionArm {
                    record: rec.name.clone(),
                    predicate: rec.predicate.clone(),
                    fields: rec.fields.clone(),
                });
            }
            survey
                .union_at
                .insert(pred.to_string(), (module, unions[module].len()));
            unions[module].push(UnionDef {
                name: name.to_string(),
                predicate: bare(pred).to_string(),
                arms,
            });
        }

        for (top, form) in forms.iter().enumerate() {
            let Some(items) = form.as_list() else {
                continue;
            };
            let Some(head) = items.first().and_then(Spanned::as_symbol) else {
                continue;
            };
            let typed = head == "define-typed";
            if !typed && head != "define" {
                continue;
            }
            let Some(sig) = items.get(1).and_then(Spanned::as_list) else {
                continue;
            };
            let Some(name) = sig.first().and_then(Spanned::as_symbol) else {
                continue;
            };
            let module = survey.module_at[&module_key(checked, top)];
            let ret = if typed {
                items
                    .get(2)
                    .map_or(Ty::Dyn, |t| Ty::from_sexp(&t.to_sexp()))
            } else {
                Ty::Dyn
            };
            survey.fns.insert(
                name.to_string(),
                FnInfo {
                    module,
                    params: params_of(&sig[1..], typed),
                    ret,
                },
            );
        }

        survey.lower_with(records, unions)
    }

    fn lower_with(
        self,
        records: Vec<Vec<RecordDef>>,
        unions: Vec<Vec<UnionDef>>,
    ) -> Result<Vec<Module>, Refusal> {
        // The skeleton carries the type tables while lowering; functions are
        // assembled into it afterwards, so the builder only ever borrows it.
        let mut skeleton: Vec<Module> = self
            .module_names
            .iter()
            .zip(&self.module_posture)
            .map(|(name, posture)| Module {
                name: name.clone(),
                posture: *posture,
                capabilities: BTreeSet::new(),
                records: Vec::new(),
                unions: Vec::new(),
                functions: Vec::new(),
            })
            .collect();
        for (m, recs) in records.iter().enumerate() {
            skeleton[m].records = recs.clone();
        }
        for (m, uns) in unions.iter().enumerate() {
            skeleton[m].unions = uns.clone();
        }

        let ctx = Ctx {
            survey: &self,
            skeleton: &skeleton,
            caps: RefCell::new(BTreeSet::new()),
        };

        // What each module owns: its definitions, and its top-level
        // statements (one %toplevel function, built in one pass).
        let mut defs: Vec<Vec<(String, usize)>> = (0..skeleton.len()).map(|_| Vec::new()).collect();
        let mut tops: Vec<Vec<usize>> = (0..skeleton.len()).map(|_| Vec::new()).collect();
        for (i, form) in self.forms.iter().enumerate() {
            let module = self.module_at[&module_key(self.checked, i)];
            let Some(items) = form.as_list() else {
                continue;
            };
            match items.first().and_then(Spanned::as_symbol) {
                Some("define") | Some("define-typed") => {
                    if let Some(name) = items
                        .get(1)
                        .and_then(Spanned::as_list)
                        .and_then(|s| s.first())
                        .and_then(Spanned::as_symbol)
                    {
                        defs[module].push((name.to_string(), i));
                    }
                }
                Some(
                    "blue-record" | "blue-union" | "use" | "defmacro" | "deftest" | "definput",
                ) => {}
                _ => {
                    if !matches!(form.form, SpannedForm::Nil) {
                        tops[module].push(i);
                    }
                }
            }
        }

        let mut functions: Vec<Vec<Function>> = (0..skeleton.len()).map(|_| Vec::new()).collect();
        for (module, module_defs) in defs.iter().enumerate() {
            for (name, top) in module_defs {
                let info = &self.fns[name];
                let form = &self.forms[*top];
                let items = form.as_list().expect("surveyed as a define");
                let body = if items[0].as_symbol() == Some("define-typed") {
                    items.get(3)
                } else {
                    items.get(2)
                };
                let Some(body) = body else {
                    continue;
                };
                let mut builder = FnBuilder::new(
                    &ctx,
                    module,
                    name.clone(),
                    &[],
                    info.params.clone(),
                    info.ret.clone(),
                    *top,
                );
                let value = builder.expr(body)?;
                builder.ret(value);
                let (fun, nested) = builder.finish();
                functions[module].push(fun);
                functions[module].extend(nested);
            }
        }
        for (module, statements) in tops.iter().enumerate() {
            if statements.is_empty() {
                continue;
            }
            let mut builder = FnBuilder::new(
                &ctx,
                module,
                "%toplevel".to_string(),
                &[],
                Vec::new(),
                Ty::Dyn,
                0,
            );
            let mut value = builder.const_nil();
            for &top in statements {
                builder.top = top;
                value = builder.expr(&self.forms[top])?;
            }
            builder.ret(value);
            let (fun, nested) = builder.finish();
            functions[module].push(fun);
            functions[module].extend(nested);
        }

        let caps = ctx.caps.into_inner();
        let mut modules = skeleton;
        for (m, module) in modules.iter_mut().enumerate() {
            module.functions = std::mem::take(&mut functions[m]);
            module.capabilities = caps
                .iter()
                .filter(|(i, _)| *i == m)
                .map(|(_, c)| *c)
                .collect();
        }
        Ok(modules)
    }
}

// ---------------------------------------------------------------------------
// The shared context: type tables, signatures, posture of every module, and
// the capability set the lowering's own seam calls witness.
// ---------------------------------------------------------------------------

struct Ctx<'a> {
    survey: &'a Survey<'a>,
    skeleton: &'a [Module],
    /// (module, capability) pairs, one per emitted host seam call.
    caps: RefCell<BTreeSet<(usize, Capability)>>,
}

impl Ctx<'_> {
    fn record_of_key(&self, key: &str) -> Option<&RecordDef> {
        let (m, r) = self.survey.record_at.get(key)?;
        self.skeleton.get(*m)?.records.get(*r)
    }

    fn record_of_predicate(&self, pred: &str) -> Option<&RecordDef> {
        self.record_of_key(self.survey.record_predicate.get(pred)?)
    }

    fn union_of_predicate(&self, pred: &str) -> Option<&UnionDef> {
        let (m, u) = self.survey.union_at.get(pred)?;
        self.skeleton.get(*m)?.unions.get(*u)
    }

    /// A field's declared type through whichever shape owns it.
    fn field_ty(&self, owner: &Ty, field: &str) -> Ty {
        match owner {
            Ty::Record(name) => self.skeleton.iter().find_map(|m| {
                m.records
                    .iter()
                    .find(|r| r.name == *name)
                    .and_then(|r| r.fields.iter().find(|f| f.name == field))
                    .map(|f| f.ty.clone())
            }),
            Ty::Union(name, _) => self.skeleton.iter().find_map(|m| {
                m.unions.iter().find(|u| u.name == *name).and_then(|u| {
                    u.arms
                        .iter()
                        .filter_map(|a| a.fields.iter().find(|f| f.name == field))
                        .next()
                        .map(|f| f.ty.clone())
                })
            }),
            _ => None,
        }
        .unwrap_or(Ty::Dyn)
    }

    fn host_seam(&self, module: usize, capability: Capability) {
        self.caps.borrow_mut().insert((module, capability));
    }
}

// ---------------------------------------------------------------------------
// The function builder: SSA blocks with block-parameter joins, one current
// block, a lexical environment of value ids.
// ---------------------------------------------------------------------------

struct BuilderBlock {
    params: Vec<Param>,
    param_values: Vec<ValueId>,
    insts: Vec<Inst>,
    term: Option<Terminator>,
}

struct FnBuilder<'a> {
    ctx: &'a Ctx<'a>,
    module: usize,
    name: String,
    top: usize,
    ret: Ty,
    capture_count: usize,
    blocks: Vec<BuilderBlock>,
    cur: usize,
    next_value: ValueId,
    env: BTreeMap<String, ValueId>,
    types: BTreeMap<ValueId, Ty>,
    /// Outcome seams this function already consumed, by index.
    seams_used: BTreeSet<usize>,
    lambda_count: usize,
    nested: Vec<Function>,
}

/// Names a form's subtree rebinds, for merge threading. `visible` is the
/// environment at the branch point: a name redefined inside a branch that
/// the join must carry.
fn assigned_in(form: &Spanned, visible: &BTreeSet<String>) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    collect_assigned(form, visible, &mut out);
    out.into_iter().filter(|n| visible.contains(n)).collect()
}

fn collect_assigned(form: &Spanned, visible: &BTreeSet<String>, out: &mut BTreeSet<String>) {
    let Some(items) = form.as_list() else {
        return;
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("quote" | "quasiquote" | "lambda") => return,
        Some("define") => {
            if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
                out.insert(n.to_string());
            }
        }
        Some("set!") => {
            if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
                out.insert(n.to_string());
            }
        }
        _ => {}
    }
    for item in items {
        collect_assigned(item, visible, out);
    }
}

fn nil_at(span: Span) -> Spanned {
    Spanned::new(span, SpannedForm::Nil)
}

fn sym_at(span: Span, name: &str) -> Spanned {
    Spanned::new(span, SpannedForm::Atom(Atom::Symbol(name.to_string())))
}

fn known_value_word(name: &str) -> bool {
    matches!(name, "argv" | "self_exe")
}

/// The result type of the pure operator and builtin words the IR lowers as
/// plain calls, from the same table the checker reads.
fn op_result(op: &str) -> Ty {
    blue_lang_check::builtin_result(op).unwrap_or(match op {
        "equal?" | "not=" | "<" | "<=" | ">" | ">=" | "not" => Ty::Bool,
        "concat" => Ty::Str,
        "split" | "chars" => Ty::List(Box::new(Ty::Str)),
        _ => Ty::Dyn,
    })
}

/// `(pred subject)` / `(equal? subject pred)`: the two shapes a `case` arm's
/// test takes in the lowered tree.
fn predicate_test(test: &Spanned) -> Option<(&str, &str)> {
    let items = test.as_list()?;
    match items {
        [pred, subject] => Some((pred.as_symbol()?, subject.as_symbol()?)),
        [eq, subject, pattern] if eq.as_symbol() == Some("equal?") => {
            Some((pattern.as_symbol()?, subject.as_symbol()?))
        }
        _ => None,
    }
}

/// Free bare names of `form`: used, and not lexically bound inside it.
/// Runtime keys (containing `/`) resolve through the function table, not the
/// environment, so they are never free.
fn free_symbols(form: &Spanned, bound: &mut BTreeSet<String>, out: &mut BTreeSet<String>) {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(n)) => {
            if !bound.contains(n) && !n.contains('/') && !n.starts_with('%') {
                out.insert(n.clone());
            }
        }
        SpannedForm::Nil
        | SpannedForm::Atom(_)
        | SpannedForm::Quote(_)
        | SpannedForm::Quasiquote(_)
        | SpannedForm::Unquote(_)
        | SpannedForm::UnquoteSplice(_) => {}
        SpannedForm::List(items) => match items.first().and_then(Spanned::as_symbol) {
            Some("quote" | "quasiquote") => return,
            Some("lambda") => {
                let mut inner = bound.clone();
                if let Some(params) = items.get(1).and_then(Spanned::as_list) {
                    for p in params {
                        if let Some(n) = p.as_symbol() {
                            inner.insert(n.to_string());
                        }
                        if let Some(n) = p
                            .as_list()
                            .and_then(|l| l.first())
                            .and_then(Spanned::as_symbol)
                        {
                            inner.insert(n.to_string());
                        }
                    }
                }
                if let Some(body) = items.last() {
                    if items.len() >= 3 {
                        free_symbols(body, &mut inner, out);
                    }
                }
            }
            Some("let") => {
                if let Some(bindings) = items.get(1).and_then(Spanned::as_list) {
                    for b in bindings {
                        if let Some(expr) = b.as_list().and_then(|l| l.get(1)) {
                            free_symbols(expr, bound, out);
                        }
                    }
                    let mut inner = bound.clone();
                    for b in bindings {
                        if let Some(n) = b
                            .as_list()
                            .and_then(|l| l.first())
                            .and_then(Spanned::as_symbol)
                        {
                            inner.insert(n.to_string());
                        }
                    }
                    if let Some(body) = items.get(2) {
                        free_symbols(body, &mut inner, out);
                    }
                }
            }
            Some("define") => {
                if let Some(target) = items.get(1) {
                    if let Some(sig) = target.as_list() {
                        let mut inner = bound.clone();
                        if let Some(name) = sig.first().and_then(Spanned::as_symbol) {
                            inner.insert(name.to_string());
                        }
                        for p in &sig[1..] {
                            if let Some(n) = p.as_symbol() {
                                inner.insert(n.to_string());
                            }
                        }
                        if let Some(body) = items.get(2) {
                            free_symbols(body, &mut inner, out);
                        }
                    } else if let Some(body) = items.get(2) {
                        free_symbols(body, bound, out);
                    }
                }
            }
            _ => {
                for item in items {
                    free_symbols(item, bound, out);
                }
            }
        },
    }
}

impl<'a> FnBuilder<'a> {
    fn new(
        ctx: &'a Ctx<'a>,
        module: usize,
        name: String,
        captures: &[String],
        params: Vec<Param>,
        ret: Ty,
        top: usize,
    ) -> Self {
        let mut builder = FnBuilder {
            ctx,
            module,
            name: name.clone(),
            top,
            ret,
            capture_count: captures.len(),
            blocks: vec![BuilderBlock {
                params: Vec::new(),
                param_values: Vec::new(),
                insts: Vec::new(),
                term: None,
            }],
            cur: 0,
            next_value: 0,
            env: BTreeMap::new(),
            types: BTreeMap::new(),
            seams_used: BTreeSet::new(),
            lambda_count: 0,
            nested: Vec::new(),
        };
        for cap in captures {
            builder.entry_param(cap, Ty::Dyn);
        }
        for p in params {
            builder.entry_param(&p.name, p.ty.clone());
        }
        builder
    }

    fn entry_param(&mut self, name: &str, ty: Ty) -> ValueId {
        let id = self.fresh();
        self.blocks[0].params.push(Param {
            name: name.to_string(),
            ty: ty.clone(),
        });
        self.blocks[0].param_values.push(id);
        self.env.insert(name.to_string(), id);
        self.types.insert(id, ty);
        id
    }

    fn fresh(&mut self) -> ValueId {
        let id = self.next_value;
        self.next_value += 1;
        id
    }

    fn open(&self) -> bool {
        self.blocks[self.cur].term.is_none()
    }

    fn push(&mut self, inst: Inst) {
        if let Some(ty) = inst_ty(&inst) {
            self.types.insert(inst_to(&inst), ty);
        }
        self.blocks[self.cur].insts.push(inst);
    }

    fn terminate(&mut self, term: Terminator) {
        if self.blocks[self.cur].term.is_none() {
            self.blocks[self.cur].term = Some(term);
        }
    }

    fn new_block(&mut self) -> usize {
        self.blocks.push(BuilderBlock {
            params: Vec::new(),
            param_values: Vec::new(),
            insts: Vec::new(),
            term: None,
        });
        self.blocks.len() - 1
    }

    fn ret(&mut self, value: ValueId) {
        self.terminate(Terminator::Ret { value });
    }

    fn const_nil(&mut self) -> ValueId {
        let id = self.fresh();
        self.push(Inst::Const {
            to: id,
            value: Const::Nil,
            ty: Ty::Nil,
        });
        id
    }

    fn refuse(&self, what: impl Into<String>, at: &Spanned) -> Refusal {
        Refusal {
            what: what.into(),
            top_level: self.top,
            span: at.span,
        }
    }

    // -- expressions ---------------------------------------------------------

    fn expr(&mut self, form: &Spanned) -> Result<ValueId, Refusal> {
        match &form.form {
            SpannedForm::Atom(atom) => self.atom(atom, form),
            SpannedForm::List(items) => {
                if items.is_empty() {
                    return Ok(self.const_nil());
                }
                self.list(items, form)
            }
            SpannedForm::Nil => Ok(self.const_nil()),
            SpannedForm::Quote(inner) => {
                let id = self.fresh();
                self.push(Inst::Const {
                    to: id,
                    value: Const::Quoted(inner.to_sexp()),
                    ty: Ty::Dyn,
                });
                Ok(id)
            }
            SpannedForm::Quasiquote(_)
            | SpannedForm::Unquote(_)
            | SpannedForm::UnquoteSplice(_) => Err(self.refuse("quasiquotation", form)),
        }
    }

    fn atom(&mut self, atom: &Atom, at: &Spanned) -> Result<ValueId, Refusal> {
        let (value, ty) = match atom {
            Atom::Int(i) => (Const::Int(*i), Ty::Int),
            Atom::Float(x) => (Const::Float(*x), Ty::Float),
            Atom::Str(s) => (Const::Str(s.to_string()), Ty::Str),
            Atom::Bool(b) => (Const::Bool(*b), Ty::Bool),
            Atom::Keyword(k) => (Const::Keyword(k.to_string()), Ty::Sym),
            Atom::Symbol(name) => return self.name(name, at),
        };
        let id = self.fresh();
        self.push(Inst::Const { to: id, value, ty });
        Ok(id)
    }

    /// A bare name: a local, a nullary host word (a seam), a nullary
    /// definition, or a builtin value word. Unbound is refused — the check
    /// stage refused it for real programs already.
    fn name(&mut self, name: &str, at: &Spanned) -> Result<ValueId, Refusal> {
        if let Some(id) = self.env.get(name) {
            return Ok(*id);
        }
        if REFUSED_WORDS.contains(&name) {
            return Err(self.refuse(name, at));
        }
        if let Some(capability) = host_capability(name) {
            let id = self.fresh();
            self.push(Inst::SeamCall {
                to: id,
                callee: Callee::Builtin(name.to_string()),
                args: Vec::new(),
                ty: Ty::Dyn,
                seam: SeamKind::Host { capability },
            });
            self.ctx.host_seam(self.module, capability);
            return Ok(id);
        }
        if self.ctx.survey.fns.contains_key(name) {
            return self.call_fn(name, Vec::new(), at);
        }
        if known_value_word(name) {
            let id = self.fresh();
            self.push(Inst::Call {
                to: id,
                callee: Callee::Builtin(name.to_string()),
                args: Vec::new(),
                ty: Ty::Dyn,
            });
            return Ok(id);
        }
        Err(self.refuse(format!("the bare name `{name}`"), at))
    }

    fn list(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let head_sym = items[0].as_symbol();
        if let Some(h) = head_sym {
            match h {
                "if" => return self.if_(items, form),
                "cond" => return self.cond(items, form),
                "when" if items.len() == 3 => {
                    let rebuilt = vec![
                        items[0].clone(),
                        items[1].clone(),
                        items[2].clone(),
                        nil_at(items[0].span),
                    ];
                    return self.if_(&rebuilt, form);
                }
                "unless" if items.len() == 3 => {
                    let rebuilt = vec![
                        sym_at(items[0].span, "if"),
                        items[1].clone(),
                        nil_at(items[0].span),
                        items[2].clone(),
                    ];
                    return self.if_(&rebuilt, form);
                }
                "and" | "or" => return self.bool_chain(h, items),
                "let" => return self.let_(items, form),
                "lambda" => return self.lambda(items, form),
                "define" => return self.define(items, form),
                "begin" => return self.begin(&items[1..]),
                "set!" => return self.set(items, form),
                "blue-field" | "blue-shape-at" if items.len() == 3 => {
                    return self.field_get(items, form)
                }
                "raise" => return self.raise(items, form, false),
                blue_lang_runtime::errors::RAISE_AT => return self.raise(items, form, true),
                _ => {}
            }
            if REFUSED_WORDS.contains(&h) {
                return Err(self.refuse(h, form));
            }
        }
        self.call(items, form)
    }

    fn if_(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let (cond, then_f, else_f) = match items {
            [_, c, t, e] => (c, t, e),
            [_, c, t] => (c, t, &nil_at(items[0].span)),
            _ => return Err(self.refuse("an if", form)),
        };
        let cond_v = self.expr(cond)?;
        let visible: BTreeSet<String> = self.env.keys().cloned().collect();
        let at = assigned_in(then_f, &visible);
        let ae = assigned_in(else_f, &visible);
        let thread: Vec<String> = at
            .union(&ae)
            .filter(|n| visible.contains(*n))
            .cloned()
            .collect();

        let then_b = self.new_block();
        let else_b = self.new_block();
        let merge = self.new_block();
        self.terminate(Terminator::Branch {
            cond: cond_v,
            then: (then_b as u32, Vec::new()),
            otherwise: (else_b as u32, Vec::new()),
        });

        self.cur = then_b;
        let then_v = self.expr(then_f)?;
        let then_open = self.open();
        if then_open {
            let mut args = vec![then_v];
            for n in &thread {
                args.push(self.env[n]);
            }
            self.terminate(Terminator::Jump {
                to: merge as u32,
                args,
            });
        }

        self.cur = else_b;
        let else_v = self.expr(else_f)?;
        let else_open = self.open();
        if else_open {
            let mut args = vec![else_v];
            for n in &thread {
                args.push(self.env[n]);
            }
            self.terminate(Terminator::Jump {
                to: merge as u32,
                args,
            });
        }

        Ok(self.join(merge, &[(then_v, then_open), (else_v, else_open)], &thread))
    }

    /// Finish a join block: parameters for every producing predecessor, an
    /// unreachable const when none produces, and rebinding for threaded
    /// names. Returns the join's value.
    fn join(&mut self, merge: usize, producers: &[(ValueId, bool)], thread: &[String]) -> ValueId {
        self.cur = merge;
        let value = self.fresh();
        let produced: Vec<ValueId> = producers
            .iter()
            .filter(|(_, open)| *open)
            .map(|(v, _)| *v)
            .collect();
        if produced.is_empty() {
            self.blocks[merge].insts.push(Inst::Const {
                to: value,
                value: Const::Nil,
                ty: Ty::Nil,
            });
            self.types.insert(value, Ty::Nil);
            return value;
        }
        let ty = produced
            .iter()
            .filter_map(|v| self.types.get(v))
            .fold(None, |acc: Option<Ty>, t| match acc {
                None => Some(t.clone()),
                Some(prev) => Some(prev.join(t)),
            })
            .unwrap_or(Ty::Dyn);
        self.blocks[merge].params.push(Param {
            name: format!("%join.{value}"),
            ty: ty.clone(),
        });
        self.blocks[merge].param_values.push(value);
        self.types.insert(value, ty);
        for n in thread {
            let id = self.fresh();
            self.blocks[merge].params.push(Param {
                name: format!("%{n}"),
                ty: Ty::Dyn,
            });
            self.blocks[merge].param_values.push(id);
            self.env.insert(n.clone(), id);
            self.types.insert(id, Ty::Dyn);
        }
        value
    }

    fn cond(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        if items.len() == 1 {
            return Ok(self.const_nil());
        }
        if let Some(v) = self.try_switch_tag(items)? {
            return Ok(v);
        }
        // The generic shape: a chain of ifs over the clauses in order.
        let Some(clause) = items.get(1).and_then(Spanned::as_list) else {
            return Err(self.refuse("a cond clause", form));
        };
        let (test, body) = (
            clause.first().unwrap_or(form),
            clause.get(1).unwrap_or(form),
        );
        if test.as_symbol() == Some("else") {
            return self.expr(body);
        }
        let rest: Vec<Spanned> = std::iter::once(items[0].clone())
            .chain(items[2..].iter().cloned())
            .chain([sym_at(form.span, "else"), nil_at(form.span)])
            .collect();
        let rebuilt: Vec<Spanned> = vec![
            sym_at(form.span, "if"),
            test.clone(),
            body.clone(),
            Spanned::new(form.span, SpannedForm::List(rest)),
        ];
        self.if_(&rebuilt, form)
    }

    /// A `case` over one union's arms lowers to one [`Terminator::SwitchTag`]
    /// — the tag test the union's layout exists for. Fires only when every
    /// non-else clause tests the same bound subject against a record
    /// predicate; anything else falls back to chained ifs.
    fn try_switch_tag(&mut self, items: &[Spanned]) -> Result<Option<ValueId>, Refusal> {
        let mut subject: Option<String> = None;
        let mut arms: Vec<(String, &Spanned)> = Vec::new();
        let mut otherwise: Option<&Spanned> = None;
        for clause in &items[1..] {
            let Some(parts) = clause.as_list() else {
                return Ok(None);
            };
            let Some(test) = parts.first() else {
                return Ok(None);
            };
            let body = parts.get(1).unwrap_or(clause);
            if test.as_symbol() == Some("else") {
                otherwise = Some(body);
                continue;
            }
            let Some((pred, subj)) = predicate_test(test) else {
                return Ok(None);
            };
            let Some(record) = self.ctx.record_of_predicate(pred) else {
                return Ok(None);
            };
            match &subject {
                None => subject = Some(subj.to_string()),
                Some(s) if s == subj => {}
                Some(_) => return Ok(None),
            }
            let subj = subject.as_ref().expect("just set");
            if !self.env.contains_key(subj) {
                return Ok(None);
            }
            arms.push((record.name.clone(), body));
        }
        if arms.len() < 2 {
            return Ok(None);
        }
        let subject = subject.expect(">=2 arms implies a subject");
        let subject_v = self.env[&subject];

        let visible: BTreeSet<String> = self.env.keys().cloned().collect();
        let mut thread: BTreeSet<String> = BTreeSet::new();
        for (_, body) in &arms {
            thread.extend(assigned_in(body, &visible));
        }
        if let Some(body) = otherwise {
            thread.extend(assigned_in(body, &visible));
        }
        let thread: Vec<String> = thread.into_iter().collect();

        let mut arm_blocks = Vec::new();
        for _ in &arms {
            arm_blocks.push(self.new_block());
        }
        let else_b = otherwise.map(|_| self.new_block());
        let merge = self.new_block();
        self.terminate(Terminator::SwitchTag {
            subject: subject_v,
            arms: arms
                .iter()
                .zip(&arm_blocks)
                .map(|((name, _), b)| (name.clone(), *b as u32))
                .collect(),
            otherwise: else_b.map(|b| b as u32),
        });

        let mut producers: Vec<(ValueId, bool)> = Vec::new();
        for ((_, body), block) in arms.iter().zip(&arm_blocks) {
            self.cur = *block;
            let v = self.expr(body)?;
            let open = self.open();
            if open {
                let mut args = vec![v];
                for n in &thread {
                    args.push(self.env[n]);
                }
                self.terminate(Terminator::Jump {
                    to: merge as u32,
                    args,
                });
            }
            producers.push((v, open));
        }
        if let (Some(body), Some(b)) = (otherwise, else_b) {
            self.cur = b;
            let v = self.expr(body)?;
            let open = self.open();
            if open {
                let mut args = vec![v];
                for n in &thread {
                    args.push(self.env[n]);
                }
                self.terminate(Terminator::Jump {
                    to: merge as u32,
                    args,
                });
            }
            producers.push((v, open));
        }

        Ok(Some(self.join(merge, &producers, &thread)))
    }

    /// `and`/`or`: a short-circuit chain, one branch per step, each join
    /// carrying the chain's value so far.
    fn bool_chain(&mut self, word: &str, items: &[Spanned]) -> Result<ValueId, Refusal> {
        let values = &items[1..];
        if values.is_empty() {
            let id = self.fresh();
            let (v, ty) = if word == "and" {
                (Const::Bool(true), Ty::Bool)
            } else {
                (Const::Nil, Ty::Nil)
            };
            self.push(Inst::Const {
                to: id,
                value: v,
                ty,
            });
            return Ok(id);
        }
        let mut acc = self.expr(&values[0])?;
        for next in &values[1..] {
            let next_v = self.expr(next)?;
            // `and`: if acc then next else acc. `or`: if acc then acc else next.
            let (then_v, else_v) = if word == "and" {
                (next_v, acc)
            } else {
                (acc, next_v)
            };
            let merge = self.new_block();
            let then_b = self.new_block();
            let else_b = self.new_block();
            self.terminate(Terminator::Branch {
                cond: acc,
                then: (then_b as u32, Vec::new()),
                otherwise: (else_b as u32, Vec::new()),
            });
            self.cur = then_b;
            self.terminate(Terminator::Jump {
                to: merge as u32,
                args: vec![then_v],
            });
            self.cur = else_b;
            self.terminate(Terminator::Jump {
                to: merge as u32,
                args: vec![else_v],
            });
            acc = self.join(merge, &[(then_v, true), (else_v, true)], &[]);
        }
        Ok(acc)
    }

    fn let_(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let Some(bindings) = items.get(1).and_then(Spanned::as_list) else {
            return Err(self.refuse("a let", form));
        };
        let body = items.get(2).unwrap_or(form);
        // Parallel: every expression sees the OUTER environment.
        let mut bound: Vec<(String, ValueId)> = Vec::new();
        for b in bindings {
            let Some(pair) = b.as_list() else {
                continue;
            };
            let Some(name) = pair.first().and_then(Spanned::as_symbol) else {
                continue;
            };
            let value = match pair.get(1) {
                Some(expr) => self.expr(expr)?,
                None => self.const_nil(),
            };
            bound.push((name.to_string(), value));
        }
        for (name, value) in bound {
            self.env.insert(name, value);
        }
        self.expr(body)
    }

    fn lambda(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let Some(params_form) = items.get(1).and_then(Spanned::as_list) else {
            return Err(self.refuse("a lambda", form));
        };
        let body = items.get(2).unwrap_or(form);
        let params = params_of(params_form, false);
        self.closure(params, body, form, "lambda")
    }

    fn closure(
        &mut self,
        params: Vec<Param>,
        body: &Spanned,
        form: &Spanned,
        what: &str,
    ) -> Result<ValueId, Refusal> {
        let mut bound: BTreeSet<String> = params.iter().map(|p| p.name.clone()).collect();
        let mut free: BTreeSet<String> = BTreeSet::new();
        free_symbols(body, &mut bound, &mut free);
        let captures: Vec<String> = free
            .iter()
            .filter(|n| self.env.contains_key(*n))
            .cloned()
            .collect();
        // A closure that mutates a captured binding would need shared-state
        // semantics the SSA IR does not carry; refuse rather than lower it
        // wrongly.
        for cap in &captures {
            let mut cap_bound = bound.clone();
            cap_bound.insert(cap.clone());
            let mut mutated = BTreeSet::new();
            collect_assigned(body, &cap_bound, &mut mutated);
            if mutated.contains(cap) {
                return Err(self.refuse(
                    format!("the captured binding `{cap}` mutated inside a {what}"),
                    form,
                ));
            }
        }

        self.lambda_count += 1;
        let name = format!("%lambda.{}.of.{}", self.lambda_count, self.name);
        let mut inner = FnBuilder::new(
            self.ctx,
            self.module,
            name.clone(),
            &captures,
            params,
            Ty::Dyn,
            self.top,
        );
        let value = inner.expr(body)?;
        inner.ret(value);
        let (fun, nested) = inner.finish();
        let capture_values: Vec<(String, ValueId)> =
            captures.iter().map(|c| (c.clone(), self.env[c])).collect();
        let closure_ty = Ty::Fn(Vec::new(), Box::new(Ty::Dyn));

        let id = self.fresh();
        self.push(Inst::MakeClosure {
            to: id,
            fun: name,
            captures: capture_values,
            ty: closure_ty.clone(),
        });
        self.nested.push(fun);
        self.nested.extend(nested);
        Ok(id)
    }

    fn define(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let target = items.get(1).unwrap_or(form);
        if let Some(sig) = target.as_list() {
            // A nested function definition: a closure, closed or not.
            let Some(name) = sig.first().and_then(Spanned::as_symbol) else {
                return Err(self.refuse("a nested define", form));
            };
            let params = params_of(&sig[1..], false);
            let body = items.get(2).unwrap_or(form);
            let id = self.closure(params, body, form, "define")?;
            self.env.insert(name.to_string(), id);
            return Ok(id);
        }
        let Some(name) = target.as_symbol() else {
            return Err(self.refuse("a define", form));
        };
        let value = match items.get(2) {
            Some(expr) => self.expr(expr)?,
            None => self.const_nil(),
        };
        self.env.insert(name.to_string(), value);
        Ok(value)
    }

    fn begin(&mut self, items: &[Spanned]) -> Result<ValueId, Refusal> {
        let Some((first, rest)) = items.split_first() else {
            return Ok(self.const_nil());
        };
        let mut value = self.expr(first)?;
        for item in rest {
            value = self.expr(item)?;
        }
        Ok(value)
    }

    fn set(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let Some(name) = items.get(1).and_then(Spanned::as_symbol) else {
            return Err(self.refuse("a set!", form));
        };
        let value = match items.get(2) {
            Some(expr) => self.expr(expr)?,
            None => self.const_nil(),
        };
        self.env.insert(name.to_string(), value);
        Ok(value)
    }

    fn field_get(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let of = self.expr(&items[1])?;
        let field = items[2]
            .as_symbol()
            .map(str::to_string)
            .or_else(|| match &items[2].form {
                tatara_lisp::SpannedForm::Atom(Atom::Keyword(k)) => Some(k.clone()),
                _ => None,
            })
            .ok_or_else(|| self.refuse("a field read", form))?;
        let owner = self.types.get(&of).cloned().unwrap_or(Ty::Dyn);
        let ty = self.ctx.field_ty(&owner, &field);
        let id = self.fresh();
        self.push(Inst::FieldGet {
            to: id,
            of,
            field,
            ty,
        });
        Ok(id)
    }

    fn raise(
        &mut self,
        items: &[Spanned],
        _form: &Spanned,
        located: bool,
    ) -> Result<ValueId, Refusal> {
        let (site, rest) = if located {
            (
                items.get(1).and_then(|s| match &s.form {
                    SpannedForm::Atom(Atom::Str(s)) => Some(s.clone()),
                    _ => None,
                }),
                &items[2..],
            )
        } else {
            (None, &items[1..])
        };
        let kind = match rest.first() {
            Some(k) => self.expr(k)?,
            None => self.const_nil(),
        };
        let message = match rest.get(1) {
            Some(m) => self.expr(m)?,
            None => self.const_nil(),
        };
        self.terminate(Terminator::Raise {
            kind,
            message,
            site,
        });
        // No value: the path ends here. Callers in value position are
        // lowering unreachable code and get a value no instruction defines.
        let poison = self.fresh();
        self.types.insert(poison, Ty::Dyn);
        Ok(poison)
    }

    // -- calls ----------------------------------------------------------------

    fn call(&mut self, items: &[Spanned], form: &Spanned) -> Result<ValueId, Refusal> {
        let head = &items[0];
        let args = &items[1..];

        if let Some(h) = head.as_symbol() {
            match h {
                "list" => {
                    let mut values = Vec::new();
                    for a in args {
                        values.push(self.expr(a)?);
                    }
                    let id = self.fresh();
                    self.push(Inst::List {
                        to: id,
                        items: values,
                        ty: Ty::List(Box::new(Ty::Dyn)),
                    });
                    return Ok(id);
                }
                blue_lang_syntax::LOWERED_MAP => {
                    if let Some(id) = self.map_literal(args)? {
                        return Ok(id);
                    }
                }
                blue_lang_syntax::LOWERED_KWARGS
                | blue_lang_syntax::LOWERED_MERGE
                | "blue-splice" => {
                    return Err(self.refuse(h, form));
                }
                _ => {}
            }
            if let Some(record) = self.ctx.record_of_key(h) {
                if args.len() != record.fields.len() {
                    return Err(self.refuse(
                        format!(
                            "a construction of `{}` with {} of {} fields",
                            record.name,
                            args.len(),
                            record.fields.len()
                        ),
                        form,
                    ));
                }
                let mut fields = Vec::new();
                for (a, f) in args.iter().zip(&record.fields) {
                    fields.push((f.name.clone(), self.expr(a)?));
                }
                let id = self.fresh();
                self.push(Inst::MakeRecord {
                    to: id,
                    record: record.name.clone(),
                    fields,
                    ty: Ty::Record(record.name.clone()),
                });
                return Ok(id);
            }
            if let Some(shape) = self
                .ctx
                .record_of_predicate(h)
                .map(|r| (r.name.clone(), true))
                .or_else(|| {
                    self.ctx
                        .union_of_predicate(h)
                        .map(|u| (u.name.clone(), false))
                })
            {
                let of = self.expr(&args[0])?;
                let id = self.fresh();
                self.push(Inst::TagIs {
                    to: id,
                    of,
                    predicate: format!("{}?", shape.0),
                });
                return Ok(id);
            }
            if let Some(&id) = self.env.get(h) {
                let mut values = Vec::new();
                for a in args {
                    values.push(self.expr(a)?);
                }
                let target = self.fresh();
                self.push(Inst::Call {
                    to: target,
                    callee: Callee::Value(id),
                    args: values,
                    ty: Ty::Dyn,
                });
                return Ok(target);
            }
        }

        // Arguments first: an inner call consumes its own seams before this
        // one looks for the ones left inside its span.
        let mut values = Vec::new();
        for a in args {
            values.push(self.expr(a)?);
        }

        if let Some(h) = head.as_symbol() {
            if self.ctx.survey.fns.contains_key(h) {
                return self.call_fn(h, values, form);
            }
            if let Some(capability) = host_capability(h) {
                let id = self.fresh();
                self.push(Inst::SeamCall {
                    to: id,
                    callee: Callee::Builtin(h.to_string()),
                    args: values,
                    ty: op_result(h),
                    seam: SeamKind::Host { capability },
                });
                self.ctx.host_seam(self.module, capability);
                return Ok(id);
            }
            let id = self.fresh();
            let ty = self.builtin_result_of(h, &values);
            self.push(Inst::Call {
                to: id,
                callee: Callee::Builtin(h.to_string()),
                args: values,
                ty,
            });
            return Ok(id);
        }

        // A computed head: an inline lambda, or a call through an expression.
        let callee = self.expr(head)?;
        let id = self.fresh();
        self.push(Inst::Call {
            to: id,
            callee: Callee::Value(callee),
            args: values,
            ty: Ty::Dyn,
        });
        Ok(id)
    }

    /// The result type of a builtin call, from the operand types the IR
    /// already holds — the checker's own arithmetic rule (`numeric_op`):
    /// Int operands answer Int, a Float among them answers Float, and
    /// anything it cannot see stays `Dyn`.
    fn builtin_result_of(&self, word: &str, args: &[ValueId]) -> Ty {
        let numeric = matches!(word, "+" | "-" | "*" | "/");
        if !numeric || args.is_empty() {
            return op_result(word);
        }
        let tys: Vec<&Ty> = args.iter().filter_map(|v| self.types.get(v)).collect();
        if tys.len() != args.len() {
            return Ty::Dyn;
        }
        let int = |t: &Ty| matches!(t, Ty::Int | Ty::IntOf { .. });
        let float = |t: &Ty| matches!(t, Ty::Int | Ty::IntOf { .. } | Ty::Float);
        if tys.iter().all(|t| int(t)) {
            Ty::Int
        } else if tys.iter().all(|t| float(t)) {
            Ty::Float
        } else {
            Ty::Dyn
        }
    }

    /// `hash-map` with constant keys builds a [`Inst::Map`]; anything else
    /// falls back to the builtin call.
    fn map_literal(&mut self, args: &[Spanned]) -> Result<Option<ValueId>, Refusal> {
        let mut pairs = Vec::new();
        let mut i = 0;
        while i < args.len() {
            let key = match &args[i].form {
                SpannedForm::Atom(Atom::Keyword(k)) => k.to_string(),
                SpannedForm::Atom(Atom::Str(s)) => s.to_string(),
                _ => return Ok(None),
            };
            if i + 1 >= args.len() {
                return Ok(None);
            }
            let value = self.expr(&args[i + 1])?;
            pairs.push((key, value));
            i += 2;
        }
        let id = self.fresh();
        self.push(Inst::Map {
            to: id,
            pairs,
            ty: Ty::Map(Box::new(Ty::Sym), Box::new(Ty::Dyn)),
        });
        Ok(Some(id))
    }

    fn call_fn(
        &mut self,
        name: &str,
        values: Vec<ValueId>,
        at: &Spanned,
    ) -> Result<ValueId, Refusal> {
        let info = &self.ctx.survey.fns[name];
        let from = self.ctx.survey.module_posture[self.module];
        let to = self.ctx.survey.module_posture[info.module];
        let ty = info.ret.clone();

        // A check-stage seam inside this call's span: the innermost one not
        // yet consumed (inner calls already took theirs during argument
        // lowering).
        let seam = self
            .ctx
            .survey
            .checked
            .outcome
            .seams
            .iter()
            .enumerate()
            .find(|(i, s)| {
                !self.seams_used.contains(i)
                    && s.span.start >= at.span.start
                    && s.span.end <= at.span.end
            })
            .map(|(i, s)| {
                self.seams_used.insert(i);
                SeamKind::Checked {
                    expected: s.expected.clone(),
                    at: s.at.clone(),
                }
            });

        let id = self.fresh();
        let callee = Callee::Fun(name.to_string());
        match seam {
            Some(seam) => self.push(Inst::SeamCall {
                to: id,
                callee,
                args: values,
                ty,
                seam,
            }),
            None if from != to => self.push(Inst::SeamCall {
                to: id,
                callee,
                args: values,
                ty,
                seam: SeamKind::Posture { from, to },
            }),
            None => self.push(Inst::Call {
                to: id,
                callee,
                args: values,
                ty,
            }),
        }
        Ok(id)
    }

    // -- finishing --------------------------------------------------------------

    fn finish(self) -> (Function, Vec<Function>) {
        let mut blocks: Vec<Block> = Vec::with_capacity(self.blocks.len());
        let mut params = Vec::new();
        for (i, b) in self.blocks.into_iter().enumerate() {
            if i == 0 {
                params = b.params.clone();
            }
            blocks.push(Block {
                params: b.params,
                param_values: b.param_values,
                insts: b.insts,
                term: b.term.unwrap_or(Terminator::Refused {
                    what: "unreachable".to_string(),
                }),
            });
        }
        let captures: Vec<String> = params
            .iter()
            .take(self.capture_count)
            .map(|p| p.name.clone())
            .collect();
        (
            Function {
                name: self.name,
                captures,
                params,
                ret: self.ret,
                blocks,
                types: self.types,
            },
            self.nested,
        )
    }
}

fn inst_to(inst: &Inst) -> ValueId {
    match inst {
        Inst::Const { to, .. }
        | Inst::List { to, .. }
        | Inst::Map { to, .. }
        | Inst::Call { to, .. }
        | Inst::SeamCall { to, .. }
        | Inst::MakeRecord { to, .. }
        | Inst::FieldGet { to, .. }
        | Inst::TagIs { to, .. }
        | Inst::MakeClosure { to, .. } => *to,
    }
}

fn inst_ty(inst: &Inst) -> Option<Ty> {
    match inst {
        Inst::Const { ty, .. }
        | Inst::List { ty, .. }
        | Inst::Map { ty, .. }
        | Inst::Call { ty, .. }
        | Inst::SeamCall { ty, .. }
        | Inst::MakeRecord { ty, .. }
        | Inst::FieldGet { ty, .. }
        | Inst::MakeClosure { ty, .. } => Some(ty.clone()),
        Inst::TagIs { .. } => Some(Ty::Bool),
    }
}
