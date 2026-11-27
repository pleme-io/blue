//! The IR's data shapes: one [`Module`] per package-or-file, its type
//! tables, and functions as blocks of single-assignment instructions.
//!
//! **Type-preserving, not type-inferring.** Every type in a module comes from
//! the check stage's own output surface — a declared signature, a record
//! field, a union arm, a recorded seam — or is a literal's own type. The
//! checker's *inferred* per-expression types live inside its walk today, not
//! in `Outcome`, so this IR keeps `Ty::Dyn` where the checker said nothing;
//! erasing nothing the checker did say is the property that matters, and it
//! is what the tests pin.
//!
//! **SSA by block parameters.** Every instruction defines exactly one fresh
//! [`ValueId`] and uses only earlier ones; control-flow joins pass values as
//! block parameters (Cranelift's shape, which Phase 4a compiles to directly)
//! rather than phi nodes. Assignment in the source (`x = x + 1` lowers to a
//! nested `define`) is a rebinding in the lexical environment, so no value is
//! ever overwritten.

use std::collections::BTreeMap;
use std::collections::BTreeSet;

use blue_lang_check::Ty;
use blue_lang_waku::Capability;
use tatara_lisp::Sexp;

use crate::posture::Posture;

/// A whole instruction identifier, unique within its function.
pub type ValueId = u32;
/// A basic-block label, unique within its function. Block `0` is the entry.
pub type BlockId = u32;

/// One lowered module: a package, or a file no package owns (the entry
/// script's is `%root`, the runtime's own key for it).
#[derive(Debug)]
pub struct Module {
    /// The runtime key: the bidama's package name, or `%root`.
    pub name: String,
    /// The zone this module compiles for.
    pub posture: Posture,
    /// Every host capability this module's own code reaches, each witnessed
    /// by a [`Inst::SeamCall`] the lowering emitted.
    pub capabilities: BTreeSet<Capability>,
    /// The module's record declarations, in declaration order.
    pub records: Vec<RecordDef>,
    /// The module's union declarations, in declaration order.
    pub unions: Vec<UnionDef>,
    /// The module's functions: every `def`, the entry script's top-level
    /// statements as `%toplevel`, and every lambda the lowering closed.
    pub functions: Vec<Function>,
}

/// A record's field, with the type its declaration carried (`Dyn` when the
/// field was declared bare).
#[derive(Clone, Debug, PartialEq)]
pub struct FieldDef {
    pub name: String,
    pub ty: Ty,
}

/// `record point(x: Int, y: Int)` — the layout a backend lays out and the
/// constructor a call builds.
#[derive(Clone, Debug)]
pub struct RecordDef {
    /// The bare name: `point`.
    pub name: String,
    /// The runtime key of the constructor: `%root/point`.
    pub key: String,
    /// The runtime key of the predicate: `%root/point?`.
    pub predicate: String,
    pub fields: Vec<FieldDef>,
}

/// `union shape = circle(r: Int) | rect(w: Int, h: Int)` — a tagged union:
/// the tag is the arm's record, the payload is the arm's fields, and
/// [`Terminator::SwitchTag`] is the one instruction that dispatches on it.
#[derive(Clone, Debug)]
pub struct UnionDef {
    pub name: String,
    /// The runtime key of the union's predicate: `%root/shape?`.
    pub predicate: String,
    pub arms: Vec<UnionArm>,
}

/// One arm of a union: a record, so it carries everything a record does.
#[derive(Clone, Debug)]
pub struct UnionArm {
    pub record: String,
    pub predicate: String,
    pub fields: Vec<FieldDef>,
}

/// A function: declared params, a return type, and a body of blocks.
#[derive(Debug)]
pub struct Function {
    /// The runtime key (`%root/add`, `proj/helper`, `%lambda.1.of.%root/go`),
    /// or `%toplevel` for a module's top-level statements.
    pub name: String,
    /// Names this function closes over, when it was a lambda: the capture
    /// list in MakeClosure order, each a parameter of this function before
    /// its own params.
    pub captures: Vec<String>,
    pub params: Vec<Param>,
    pub ret: Ty,
    pub blocks: Vec<Block>,
    /// The type of every value the body defines, so a backend never guesses.
    pub types: BTreeMap<ValueId, Ty>,
}

/// A declared parameter with its type (`Dyn` when unannotated).
#[derive(Clone, Debug, PartialEq)]
pub struct Param {
    pub name: String,
    pub ty: Ty,
}

/// A basic block: parameters (the SSA join), straight-line instructions, and
/// exactly one terminator.
#[derive(Debug)]
pub struct Block {
    pub params: Vec<Param>,
    /// The value id each parameter carries, in the same order: a
    /// predecessor's Jump/Branch args line up with these.
    pub param_values: Vec<ValueId>,
    pub insts: Vec<Inst>,
    pub term: Terminator,
}

/// A literal. `Quoted` carries the data whole — quoted source is a value,
/// not code, so the IR does not walk into it.
#[derive(Clone, Debug, PartialEq)]
pub enum Const {
    Int(i64),
    Float(f64),
    Str(String),
    Bool(bool),
    Sym(String),
    Keyword(String),
    Nil,
    Quoted(Sexp),
}

/// What a call reaches.
#[derive(Clone, Debug, PartialEq)]
pub enum Callee {
    /// A named function by runtime key.
    Fun(String),
    /// A builtin word, by the name the tree carries.
    Builtin(String),
    /// A value in a register (a closure): the indirect call.
    Value(ValueId),
}

/// Why a call is a seam rather than a plain instruction. Every
/// posture/backend crossing is one of these, and nothing else is.
#[derive(Clone, Debug, PartialEq)]
pub enum SeamKind {
    /// A host word under a capability: the call leaves the zone for the host
    /// backend, where Phase 5 routes it through the capability vtable.
    Host { capability: Capability },
    /// A call into a module compiled for a different posture.
    Posture { from: Posture, to: Posture },
    /// A check-stage seam: the checker recorded a runtime check here, where
    /// an unannotated value crosses into typed code. `expected` is the type
    /// the typed side requires — the one fact the seam exists to carry.
    Checked { expected: Ty, at: String },
}

/// One instruction. Each defines exactly one value.
#[derive(Clone, Debug, PartialEq)]
pub enum Inst {
    Const {
        to: ValueId,
        value: Const,
        ty: Ty,
    },
    /// Build a list from element values.
    List {
        to: ValueId,
        items: Vec<ValueId>,
        ty: Ty,
    },
    /// Build a map from key/value pairs; keys are keyword constants.
    Map {
        to: ValueId,
        pairs: Vec<(String, ValueId)>,
        ty: Ty,
    },
    /// A call that stays inside one posture and one backend.
    Call {
        to: ValueId,
        callee: Callee,
        args: Vec<ValueId>,
        ty: Ty,
    },
    /// A call across a seam — see [`SeamKind`]. Explicit in the instruction
    /// stream, never implied, so a backend cannot lower a crossing as if it
    /// were local.
    SeamCall {
        to: ValueId,
        callee: Callee,
        args: Vec<ValueId>,
        ty: Ty,
        seam: SeamKind,
    },
    /// `point(1, 2)`: place field values in declared order.
    MakeRecord {
        to: ValueId,
        record: String,
        fields: Vec<(String, ValueId)>,
        ty: Ty,
    },
    /// `p.x` and a union arm's `blue-shape-at`: read one field. The type is
    /// the field's declared type when the subject's record is known, `Dyn`
    /// when it is not.
    FieldGet {
        to: ValueId,
        of: ValueId,
        field: String,
        ty: Ty,
    },
    /// `point?(v)`, `shape?(v)`: which tag a value carries.
    TagIs {
        to: ValueId,
        of: ValueId,
        /// The bare predicate name: `point?`, `shape?`.
        predicate: String,
    },
    /// `fn(x) ... end` closed over its environment: the named function takes
    /// its captures as leading parameters, in this order.
    MakeClosure {
        to: ValueId,
        fun: String,
        captures: Vec<(String, ValueId)>,
        ty: Ty,
    },
}

/// How a block ends. Exactly one per block.
#[derive(Clone, Debug, PartialEq)]
pub enum Terminator {
    /// Return a value from the function.
    Ret {
        value: ValueId,
    },
    Jump {
        to: BlockId,
        args: Vec<ValueId>,
    },
    Branch {
        cond: ValueId,
        then: (BlockId, Vec<ValueId>),
        otherwise: (BlockId, Vec<ValueId>),
    },
    /// A union `case`: dispatch on the subject's tag to the arm's block. This
    /// is the instruction that makes a tagged union's layout load-bearing —
    /// a backend lowers it to a tag test, never a chain of predicates.
    SwitchTag {
        subject: ValueId,
        /// (bare record name, block) in declaration order.
        arms: Vec<(String, BlockId)>,
        /// The `else` arm, when the case had one.
        otherwise: Option<BlockId>,
    },
    /// `raise`: control leaves the function with an error value.
    Raise {
        kind: ValueId,
        message: ValueId,
        site: Option<String>,
    },
    /// Lowering stopped here: the rest of this path used a construct the IR
    /// refuses. Unreachable in a fully-lowered module (the refusal fails the
    /// lowering), present so a partially-lowered function is still a valid
    /// block graph.
    Refused {
        what: String,
    },
}
