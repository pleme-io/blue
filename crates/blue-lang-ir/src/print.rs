//! The `blue ir` dump: one module per paragraph, human-readable, one
//! instruction per line, every value with its type.

use std::fmt;

use blue_lang_check::Ty;

use crate::module::{Callee, Const, Function, Inst, Module, Param, SeamKind, Terminator};

fn fields_of(fields: &[crate::module::FieldDef]) -> String {
    fields
        .iter()
        .map(|f| format!("{}: {}", f.name, f.ty.name()))
        .collect::<Vec<_>>()
        .join(", ")
}

impl fmt::Display for Module {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let caps = self
            .capabilities
            .iter()
            .map(|c| c.label().to_string())
            .collect::<Vec<_>>()
            .join(" ");
        writeln!(
            f,
            "module {} posture={} capabilities=[{}]",
            self.name,
            self.posture.label(),
            caps
        )?;
        for r in &self.records {
            writeln!(f, "  record {}({})", r.name, fields_of(&r.fields))?;
        }
        for u in &self.unions {
            let arms = u
                .arms
                .iter()
                .map(|a| format!("{}({})", a.record, fields_of(&a.fields)))
                .collect::<Vec<_>>()
                .join(" | ");
            writeln!(f, "  union {} = {}", u.name, arms)?;
        }
        for fun in &self.functions {
            print_fun(f, fun)?;
        }
        Ok(())
    }
}

fn params_of(params: &[Param]) -> String {
    params
        .iter()
        .map(|p| format!("{}: {}", p.name, p.ty.name()))
        .collect::<Vec<_>>()
        .join(", ")
}

fn print_fun(f: &mut fmt::Formatter<'_>, fun: &Function) -> fmt::Result {
    let captures = if fun.captures.is_empty() {
        String::new()
    } else {
        format!(" capturing [{}]", fun.captures.join(", "))
    }
    .to_string();
    writeln!(
        f,
        "  fn {}({}) -> {}{} {{",
        fun.name,
        params_of(&fun.params),
        fun.ret.name(),
        captures
    )?;
    for (i, block) in fun.blocks.iter().enumerate() {
        if i > 0 || !block.params.is_empty() {
            writeln!(f, "    b{}({}):", i, params_of(&block.params))?;
        }
        for inst in &block.insts {
            print_inst(f, fun, inst)?;
        }
        print_term(f, fun, &block.term)?;
    }
    writeln!(f, "  }}")
}

fn ty_of(fun: &Function, v: u32) -> String {
    fun.types.get(&v).map_or_else(|| Ty::Dyn.name(), Ty::name)
}

fn v(_fun: &Function, id: u32) -> String {
    format!("v{id}")
}

fn vs(fun: &Function, ids: &[u32]) -> String {
    ids.iter()
        .map(|id| v(fun, *id))
        .collect::<Vec<_>>()
        .join(", ")
}

fn print_inst(f: &mut fmt::Formatter<'_>, fun: &Function, inst: &Inst) -> fmt::Result {
    let to =
        |id: u32, f: &mut fmt::Formatter<'_>| write!(f, "    {}:{} = ", v(fun, id), ty_of(fun, id));
    match inst {
        Inst::Const { to: id, value, .. } => {
            to(*id, f)?;
            writeln!(f, "const {}", show_const(value))
        }
        Inst::List { to: id, items, .. } => {
            to(*id, f)?;
            writeln!(f, "list [{}]", vs(fun, items))
        }
        Inst::Map { to: id, pairs, .. } => {
            to(*id, f)?;
            let shown = pairs
                .iter()
                .map(|(k, val)| format!("{k}:{}", v(fun, *val)))
                .collect::<Vec<_>>()
                .join(", ");
            writeln!(f, "map {{{shown}}}")
        }
        Inst::Call {
            to: id,
            callee,
            args,
            ..
        } => {
            to(*id, f)?;
            writeln!(f, "call {}({})", show_callee(fun, callee), vs(fun, args))
        }
        Inst::SeamCall {
            to: id,
            callee,
            args,
            seam,
            ..
        } => {
            to(*id, f)?;
            writeln!(
                f,
                "seam-call {} [{}] {}({})",
                show_seam(seam),
                seam_typed(seam),
                show_callee(fun, callee),
                vs(fun, args)
            )
        }
        Inst::MakeRecord {
            to: id,
            record,
            fields,
            ..
        } => {
            to(*id, f)?;
            let shown = fields
                .iter()
                .map(|(n, val)| format!("{n}:{}", v(fun, *val)))
                .collect::<Vec<_>>()
                .join(", ");
            writeln!(f, "make-record {record}({shown})")
        }
        Inst::FieldGet {
            to: id, of, field, ..
        } => {
            to(*id, f)?;
            writeln!(f, "field-get {}.{}", v(fun, *of), field)
        }
        Inst::TagIs {
            to: id,
            of,
            predicate,
        } => {
            to(*id, f)?;
            writeln!(f, "tag-is {} {}", v(fun, *of), predicate)
        }
        Inst::MakeClosure {
            to: id,
            fun: name,
            captures,
            ..
        } => {
            to(*id, f)?;
            let shown = captures
                .iter()
                .map(|(n, val)| format!("{n}:{}", v(fun, *val)))
                .collect::<Vec<_>>()
                .join(", ");
            writeln!(f, "make-closure {name} [{shown}]")
        }
    }
}

fn print_term(f: &mut fmt::Formatter<'_>, fun: &Function, term: &Terminator) -> fmt::Result {
    match term {
        Terminator::Ret { value } => writeln!(f, "    ret {}", v(fun, *value)),
        Terminator::Jump { to, args } => {
            writeln!(f, "    jump b{to}({})", vs(fun, args))
        }
        Terminator::Branch {
            cond,
            then,
            otherwise,
        } => writeln!(
            f,
            "    branch {} ? b{}({}) : b{}({})",
            v(fun, *cond),
            then.0,
            vs(fun, &then.1),
            otherwise.0,
            vs(fun, &otherwise.1)
        ),
        Terminator::SwitchTag {
            subject,
            arms,
            otherwise,
        } => {
            let shown = arms
                .iter()
                .map(|(n, b)| format!("{n}:b{b}"))
                .collect::<Vec<_>>()
                .join(", ");
            let else_ = otherwise.map_or_else(String::new, |b| format!(" else:b{b}"));
            writeln!(f, "    switch-tag {} [{shown}]{else_}", v(fun, *subject))
        }
        Terminator::Raise {
            kind,
            message,
            site,
        } => writeln!(
            f,
            "    raise {} {}{}",
            v(fun, *kind),
            v(fun, *message),
            site.as_ref()
                .map_or_else(String::new, |s| format!(" at {s}"))
        ),
        Terminator::Refused { what } => writeln!(f, "    refused: {what}"),
    }
}

fn show_callee(fun: &Function, callee: &Callee) -> String {
    match callee {
        Callee::Fun(name) => name.clone(),
        Callee::Builtin(name) => name.clone(),
        Callee::Value(id) => v(fun, *id),
    }
}

fn show_seam(seam: &SeamKind) -> String {
    match seam {
        SeamKind::Host { capability } => format!("host:{}", capability.label()),
        SeamKind::Posture { from, to } => format!("posture:{}->{}", from.label(), to.label()),
        SeamKind::Checked { .. } => "checked".to_string(),
    }
}

fn seam_typed(seam: &SeamKind) -> String {
    match seam {
        SeamKind::Checked { expected, at } => format!("expected {} ({at})", expected.name()),
        _ => String::new(),
    }
}

fn show_const(value: &Const) -> String {
    match value {
        Const::Int(i) => i.to_string(),
        Const::Float(x) => x.to_string(),
        Const::Str(s) => format!("{s:?}"),
        Const::Bool(b) => b.to_string(),
        Const::Sym(s) => format!(":{s}"),
        Const::Keyword(k) => format!(":{k}"),
        Const::Nil => "nil".to_string(),
        Const::Quoted(sexp) => sexp.to_string(),
    }
}
