use std::collections::BTreeSet;

use tatara_lisp::{Atom, Spanned, SpannedForm};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Construct {
    Word(&'static str),
    FunctionEquality,
    CallThroughValue,
    FunctionAsValue,
    HostEffect,
}

impl Construct {
    #[must_use]
    pub fn label(self) -> String {
        match self {
            Construct::Word(w) => format!("`{w}`"),
            Construct::FunctionEquality => "a comparison of function values".into(),
            Construct::CallThroughValue => {
                "a call through a value (a local function, a macro, a renamed word)".into()
            }
            Construct::FunctionAsValue => {
                "a function passed as a value (a lambda, or a definition's name as an argument)"
                    .into()
            }
            Construct::HostEffect => "a host effect (a word a capability grants)".into(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reason {
    Disagrees {
        gap: &'static str,
        row: &'static str,
    },
    Slower {
        measured: &'static str,
    },
    Unreplayable {
        why: &'static str,
    },
}

#[derive(Clone, Copy, Debug)]
pub struct Rule {
    pub construct: Construct,
    pub reason: Reason,
}

const fn disagrees(construct: Construct, gap: &'static str, row: &'static str) -> Rule {
    Rule {
        construct,
        reason: Reason::Disagrees { gap, row },
    }
}

pub const TABLE: &[Rule] = &[
    disagrees(Construct::Word("procedure?"), "G18", "pred.procedure"),
    disagrees(Construct::FunctionEquality, "G18", "eq.functions_by_identity"),
    disagrees(Construct::Word("dolist"), "G19", "lisp.dolist"),
    disagrees(Construct::Word("doseq"), "G19", "lisp.doseq"),
    disagrees(Construct::Word("dotimes"), "G19", "lisp.dotimes"),
    disagrees(Construct::Word("provide"), "G19", "lisp.provide"),
    disagrees(Construct::Word("require"), "G19", "lisp.require"),
    disagrees(Construct::Word("defcommand"), "G19", "lisp.defcommand"),
    disagrees(Construct::Word("defquery"), "G19", "lisp.defquery"),
    disagrees(Construct::CallThroughValue, "G19", "fn.arity"),
    disagrees(Construct::CallThroughValue, "G19", "fn.rest.too_few"),
    disagrees(Construct::CallThroughValue, "G19", "check.waiver.runs"),
    Rule {
        construct: Construct::HostEffect,
        reason: Reason::Unreplayable {
            why: "an error on the vm carries no place or stack, and a run that reached the host cannot run again on the walker to place it",
        },
    },
    Rule {
        construct: Construct::FunctionAsValue,
        reason: Reason::Slower {
            measured: "docs/PERFORMANCE.md 1.4 and 2.2: a function handed to a native word is lifted back to the walker on each call",
        },
    },
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ran {
    Vm,
    Walker,
}

impl Ran {
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Ran::Vm => "vm",
            Ran::Walker => "walker",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Door {
    pub ran: Ran,
    pub why: String,
    pub constructs: Vec<String>,
}

impl Door {
    #[must_use]
    pub fn chosen(ran: Ran, why: impl Into<String>) -> Self {
        Door {
            ran,
            why: why.into(),
            constructs: Vec::new(),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "format": "blue-door",
            "version": 1,
            "door": self.ran.name(),
            "why": self.why,
            "constructs": self.constructs,
        })
    }
}

#[must_use]
pub fn choose(forms: &[Spanned], bound: &dyn Fn(&str) -> bool) -> Door {
    let used = constructs(forms, bound);
    let hit = |disagreeing: bool| {
        TABLE.iter().find(|r| {
            matches!(r.reason, Reason::Disagrees { .. }) == disagreeing
                && used.contains(&r.construct)
        })
    };
    let names = used.iter().map(|c| c.label()).collect();
    match hit(true).or_else(|| hit(false)) {
        None => Door {
            ran: Ran::Vm,
            why: "every construct the program uses is agreed by the conformance columns".into(),
            constructs: names,
        },
        Some(rule) => Door {
            ran: Ran::Walker,
            why: match rule.reason {
                Reason::Disagrees { gap, row } => format!(
                    "it uses {}, where the vm column disagrees ({gap}, row {row})",
                    rule.construct.label()
                ),
                Reason::Slower { measured } => format!(
                    "it uses {}, which the vm runs slower ({measured})",
                    rule.construct.label()
                ),
                Reason::Unreplayable { why } => {
                    format!("it uses {}: {why}", rule.construct.label())
                }
            },
            constructs: names,
        },
    }
}

#[must_use]
pub fn constructs(forms: &[Spanned], bound: &dyn Fn(&str) -> bool) -> BTreeSet<Construct> {
    let functions: BTreeSet<String> = forms.iter().filter_map(defined_function).collect();
    let globals: BTreeSet<String> = forms.iter().filter_map(defined_name).collect();
    let mut walk = Walk {
        functions: &functions,
        globals: &globals,
        bound,
        found: BTreeSet::new(),
    };
    for form in forms {
        walk.top(form);
    }
    walk.found
}

fn symbol(s: &Spanned) -> Option<&str> {
    match &s.form {
        SpannedForm::Atom(Atom::Symbol(n)) => Some(n),
        _ => None,
    }
}

fn list(s: &Spanned) -> Option<&[Spanned]> {
    match &s.form {
        SpannedForm::List(items) => Some(items),
        _ => None,
    }
}

fn is_lambda(s: &Spanned) -> bool {
    list(s)
        .and_then(|l| l.first())
        .and_then(symbol)
        .is_some_and(|h| h == "lambda")
}

fn defined_function(form: &Spanned) -> Option<String> {
    let items = list(form)?;
    if items.first().and_then(symbol)? != "define" {
        return None;
    }
    match items.get(1).map(|s| &s.form) {
        Some(SpannedForm::List(sig)) => sig.first().and_then(symbol).map(str::to_string),
        Some(SpannedForm::Atom(Atom::Symbol(n))) if items.get(2).is_some_and(is_lambda) => {
            Some(n.clone())
        }
        _ => None,
    }
}

fn defined_name(form: &Spanned) -> Option<String> {
    let items = list(form)?;
    if items.first().and_then(symbol)? != "define" {
        return None;
    }
    match items.get(1).map(|s| &s.form) {
        Some(SpannedForm::List(sig)) => sig.first().and_then(symbol).map(str::to_string),
        Some(SpannedForm::Atom(Atom::Symbol(n))) => Some(n.clone()),
        _ => None,
    }
}

struct Walk<'a> {
    functions: &'a BTreeSet<String>,
    globals: &'a BTreeSet<String>,
    bound: &'a dyn Fn(&str) -> bool,
    found: BTreeSet<Construct>,
}

pub const OUTPUT: &[&str] = &[
    "write_stdout",
    "write_stderr",
    "println",
    "print",
    "display",
    "newline",
];

const EQUALITY: &[&str] = &["equal?", "not=", "eq?", "eqv?", "=", "=="];

impl Walk<'_> {
    fn top(&mut self, form: &Spanned) {
        if let Some(items) = list(form) {
            if items.first().and_then(symbol) == Some("define") {
                match items.get(1).map(|s| &s.form) {
                    Some(SpannedForm::List(sig)) => {
                        let locals = params(&sig[1.min(sig.len())..]);
                        self.body(&items[2..], locals);
                        return;
                    }
                    Some(SpannedForm::Atom(Atom::Symbol(_))) => {
                        if let Some(value) = items.get(2) {
                            if is_lambda(value) {
                                self.lambda(value, &BTreeSet::new());
                            } else {
                                self.expr(value, &BTreeSet::new());
                            }
                        }
                        return;
                    }
                    _ => {}
                }
            }
        }
        self.expr(form, &BTreeSet::new());
    }

    fn lambda(&mut self, form: &Spanned, outer: &BTreeSet<String>) {
        let Some(items) = list(form) else { return };
        let mut locals = outer.clone();
        if let Some(ps) = items.get(1).and_then(list) {
            locals.extend(params(ps));
        } else if let Some(p) = items.get(1).and_then(symbol) {
            locals.insert(p.to_string());
        }
        self.body(items.get(2..).unwrap_or(&[]), locals);
    }

    fn body(&mut self, forms: &[Spanned], mut locals: BTreeSet<String>) {
        for f in forms {
            collect_local_defines(f, &mut locals);
        }
        for f in forms {
            self.expr(f, &locals);
        }
    }

    fn value_position(&mut self, arg: &Spanned, locals: &BTreeSet<String>) {
        if is_lambda(arg) {
            self.found.insert(Construct::FunctionAsValue);
        }
        self.expr(arg, locals);
    }

    fn is_function_value(&self, arg: &Spanned, locals: &BTreeSet<String>) -> bool {
        is_lambda(arg)
            || symbol(arg).is_some_and(|n| !locals.contains(n) && self.functions.contains(n))
    }

    fn expr(&mut self, form: &Spanned, locals: &BTreeSet<String>) {
        match &form.form {
            SpannedForm::Atom(Atom::Symbol(n)) => {
                if !locals.contains(n) && self.functions.contains(n) {
                    self.found.insert(Construct::FunctionAsValue);
                }
            }
            SpannedForm::List(items) => self.call(items, locals),
            SpannedForm::Quasiquote(inner) => self.quasi(inner, locals),
            _ => {}
        }
    }

    fn quasi(&mut self, form: &Spanned, locals: &BTreeSet<String>) {
        match &form.form {
            SpannedForm::Unquote(inner) | SpannedForm::UnquoteSplice(inner) => {
                self.expr(inner, locals);
            }
            SpannedForm::List(items) => {
                for i in items {
                    self.quasi(i, locals);
                }
            }
            _ => {}
        }
    }

    fn call(&mut self, items: &[Spanned], locals: &BTreeSet<String>) {
        let Some(head) = items.first() else { return };
        let Some(name) = symbol(head) else {
            self.found.insert(Construct::CallThroughValue);
            for i in items {
                self.expr(i, locals);
            }
            return;
        };
        let args = &items[1..];
        let word = name_of(name);
        if !locals.contains(name)
            && !self.functions.contains(name)
            && blue_lang_waku::Capability::host_effects()
                .into_iter()
                .any(|c| c.grants(word))
        {
            self.found.insert(Construct::HostEffect);
        }
        if let Some(rule) = TABLE
            .iter()
            .find(|r| matches!(r.construct, Construct::Word(w) if w == word))
        {
            self.found.insert(rule.construct);
        }
        if locals.contains(name) {
            self.found.insert(Construct::CallThroughValue);
        }
        match name {
            "quote" => {}
            "lambda" => {
                self.lambda(
                    &Spanned::new(head.span, SpannedForm::List(items.to_vec())),
                    locals,
                );
            }
            "define" => match args.first().map(|s| &s.form) {
                Some(SpannedForm::List(sig)) => {
                    let mut inner = locals.clone();
                    inner.extend(params(&sig[1.min(sig.len())..]));
                    self.body(&args[1..], inner);
                }
                _ => {
                    for a in args.iter().skip(1) {
                        if is_lambda(a) {
                            self.lambda(a, locals);
                        } else {
                            self.expr(a, locals);
                        }
                    }
                }
            },
            "let" | "let*" | "letrec" => self.binding_form(args, locals),
            "set!" => {
                for a in args.iter().skip(1) {
                    self.expr(a, locals);
                }
            }
            "if" | "cond" | "when" | "unless" | "begin" | "and" | "or" | "not" | "try" => {
                for a in args {
                    if is_lambda(a) {
                        self.found.insert(Construct::FunctionAsValue);
                    }
                    self.expr(a, locals);
                }
            }
            _ => {
                if !locals.contains(name)
                    && !self.functions.contains(name)
                    && !self.globals.contains(name)
                    && tatara_lisp_eval::special::SpecialForm::from_symbol(name).is_none()
                    && !(self.bound)(name)
                {
                    self.found.insert(Construct::CallThroughValue);
                }
                if !locals.contains(name)
                    && self.globals.contains(name)
                    && !self.functions.contains(name)
                {
                    self.found.insert(Construct::CallThroughValue);
                }
                if EQUALITY.contains(&name)
                    && args.iter().any(|a| self.is_function_value(a, locals))
                {
                    self.found.insert(Construct::FunctionEquality);
                }
                for a in args {
                    self.value_position(a, locals);
                }
            }
        }
    }

    fn binding_form(&mut self, args: &[Spanned], locals: &BTreeSet<String>) {
        let mut inner = locals.clone();
        if let Some(bindings) = args.first().and_then(list) {
            for b in bindings {
                if let Some(pair) = list(b) {
                    if let Some(n) = pair.first().and_then(symbol) {
                        inner.insert(n.to_string());
                    }
                    for v in pair.iter().skip(1) {
                        self.value_position(v, &inner);
                    }
                }
            }
        }
        self.body(args.get(1..).unwrap_or(&[]), inner);
    }
}

fn name_of(name: &str) -> &str {
    name.rsplit("::").next().unwrap_or(name)
}

fn params(ps: &[Spanned]) -> BTreeSet<String> {
    ps.iter()
        .filter_map(symbol)
        .filter(|p| !p.starts_with('&'))
        .map(str::to_string)
        .collect()
}

fn collect_local_defines(form: &Spanned, locals: &mut BTreeSet<String>) {
    let Some(items) = list(form) else { return };
    match items.first().and_then(symbol) {
        Some("define") => {
            if let Some(n) = defined_name(form) {
                locals.insert(n);
            }
        }
        Some("begin") => {
            for i in &items[1..] {
                collect_local_defines(i, locals);
            }
        }
        _ => {}
    }
}
