//! The lowering's contract, over representative programs: typed defs,
//! records, unions, closures, host calls, seams — and the refusals.
//!
//! Every test drives the REAL pipeline: `check_entry` on the source, then
//! `lower` on its `Checked` output. Nothing feeds the lowering a hand-built
//! tree, so a change in the pipeline's shapes fails here rather than
//! downstream.

use blue_lang_ir::lower;
use blue_lang_ir::module::{Callee, Inst, SeamKind, Terminator};
use blue_lang_ir::{Module, Posture};
use blue_lang_runtime::pipeline::{check_entry, Checked, Checking};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_waku::Capability;

/// A loader over fixed package sources, so cross-module postures need no
/// filesystem — the same seam the runtime's own tests drive resolution
/// through.
struct Fixed(Vec<(&'static str, &'static str)>);

impl Loader for Fixed {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, src)| vec![(format!("{n}.b"), (*src).to_string())])
            .ok_or_else(|| format!("no package named `{name}`"))
    }
}

fn checked_of(src: &str) -> Checked {
    let checked = check_entry(
        Entry::anonymous(src),
        &blue_lang_runtime::uses::NoLoader,
        None,
        Checking::Program,
    )
    .expect("the program checks");
    assert!(
        checked.outcome.ok(),
        "unexpected errors: {:?}",
        checked.outcome.errors().collect::<Vec<_>>()
    );
    checked
}

fn modules_of(src: &str) -> Vec<Module> {
    lower(&checked_of(src)).expect("the program lowers")
}

fn one(src: &str) -> Module {
    let mut modules = modules_of(src);
    assert_eq!(modules.len(), 1, "one module, got {:?}", modules.len());
    modules.pop().expect("just checked the length")
}

fn fn_named<'m>(module: &'m Module, name: &str) -> &'m blue_lang_ir::Function {
    module
        .functions
        .iter()
        .find(|f| f.name == name)
        .unwrap_or_else(|| panic!("no function {name} in {:?}", fn_names(module)))
}

fn fn_names(module: &Module) -> Vec<String> {
    module.functions.iter().map(|f| f.name.clone()).collect()
}

fn insts_of(fun: &blue_lang_ir::Function) -> Vec<&Inst> {
    fun.blocks.iter().flat_map(|b| b.insts.iter()).collect()
}

fn seams_of(fun: &blue_lang_ir::Function) -> Vec<&SeamKind> {
    insts_of(fun)
        .iter()
        .filter_map(|i| match i {
            Inst::SeamCall { seam, .. } => Some(seam),
            _ => None,
        })
        .collect()
}

#[test]
fn a_typed_signature_survives_lowering_exactly() {
    let module = one("def add(a: Int, b: Float) -> Float\n  a + b\nend\n");
    let add = fn_named(&module, "%root/add");
    let names: Vec<&str> = add.params.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, vec!["a", "b"]);
    assert_eq!(add.params[0].ty, blue_lang_check::Ty::Int);
    assert_eq!(add.params[1].ty, blue_lang_check::Ty::Float);
    assert_eq!(add.ret, blue_lang_check::Ty::Float);
    // The body's call keeps the declared return type on its value.
    assert!(
        insts_of(add).iter().any(
            |i| matches!(i, Inst::Call { ty, callee: Callee::Builtin(b), .. }
                if *b == "+" && *ty == blue_lang_check::Ty::Float)
        ),
        "the addition carries the declared Float: {:?}",
        insts_of(add)
    );
}

#[test]
fn an_untyped_def_lowers_with_dyn_types() {
    let module = one("def id(x)\n  x\nend\n");
    let id = fn_named(&module, "%root/id");
    assert_eq!(id.params[0].ty, blue_lang_check::Ty::Dyn);
    assert_eq!(id.ret, blue_lang_check::Ty::Dyn);
}

#[test]
fn a_record_keeps_its_field_definitions_and_types() {
    let module = one("record point(x: Int, y: Float)\n\ndef make(a)\n  point(a, 2.0).y\nend\n");
    let record = &module.records[0];
    assert_eq!(record.name, "point");
    let fields: Vec<(&str, String)> = record
        .fields
        .iter()
        .map(|f| (f.name.as_str(), f.ty.name()))
        .collect();
    assert_eq!(
        fields,
        vec![("x", "Int".to_string()), ("y", "Float".to_string())]
    );
    let make = fn_named(&module, "%root/make");
    assert!(
        insts_of(make).iter().any(
            |i| matches!(i, Inst::MakeRecord { record, ty, .. } if record == "point"
                && ty.name() == "point")
        ),
        "construction is a MakeRecord: {:?}",
        insts_of(make)
    );
    assert!(
        insts_of(make).iter().any(
            |i| matches!(i, Inst::FieldGet { field, ty, .. } if field == "y"
                && ty.name() == "Float")
        ),
        "the field read keeps the field's declared type: {:?}",
        insts_of(make)
    );
}

#[test]
fn a_union_case_lowers_to_one_tag_switch() {
    let module = one([
        "union shape = circle(r: Int) | rect(w: Int, h: Int)",
        "def area(s)",
        "  case s",
        "  when circle(r)",
        "    3 * r * r",
        "  when rect(w, h)",
        "    w * h",
        "  end",
        "end",
    ]
    .join("\n")
    .as_str());
    let union = &module.unions[0];
    assert_eq!(union.name, "shape");
    let arms: Vec<(String, usize)> = union
        .arms
        .iter()
        .map(|a| (a.record.clone(), a.fields.len()))
        .collect();
    assert_eq!(arms, vec![("circle".into(), 1), ("rect".into(), 2)]);

    let area = fn_named(&module, "%root/area");
    let switches: Vec<&Terminator> = area
        .blocks
        .iter()
        .map(|b| &b.term)
        .filter(|t| matches!(t, Terminator::SwitchTag { .. }))
        .collect();
    assert_eq!(switches.len(), 1, "one switch, not a predicate chain");
    let Terminator::SwitchTag {
        arms, otherwise, ..
    } = switches[0]
    else {
        unreachable!("just matched");
    };
    let tags: Vec<&str> = arms.iter().map(|(n, _)| n.as_str()).collect();
    assert_eq!(tags, vec!["circle", "rect"]);
    // The tree carries the case's implicit fallthrough as an explicit
    // `(else ())`, so the switch has an else arm that yields nil — the
    // tree's truth, not the surface's omission.
    assert!(otherwise.is_some(), "the implicit else is in the tree");
    // The destructuring arms read the payload through field gets.
    assert!(
        insts_of(area)
            .iter()
            .any(|i| matches!(i, Inst::FieldGet { field, .. } if field == "r")),
        "circle's payload binds r: {:?}",
        insts_of(area)
    );
}

#[test]
fn a_predicate_test_lowers_to_tag_is() {
    let module = one([
        "record point(x, y)",
        "def first_x(p)",
        "  if point?(p)",
        "    p.x",
        "  else",
        "    0",
        "  end",
        "end",
    ]
    .join("\n")
    .as_str());
    let fun = fn_named(&module, "%root/first_x");
    assert!(
        insts_of(fun)
            .iter()
            .any(|i| matches!(i, Inst::TagIs { predicate, .. } if predicate == "point?")),
        "point? is a TagIs: {:?}",
        insts_of(fun)
    );
    assert!(fun.blocks.len() >= 3, "if makes three blocks");
}

#[test]
fn a_closure_captures_its_environment() {
    let module = one([
        "def go(n)",
        "  f = fn(x) x + n end",
        "  map(f, [1, 2])",
        "end",
    ]
    .join("\n")
    .as_str());
    let go = fn_named(&module, "%root/go");
    assert!(
        insts_of(go)
            .iter()
            .any(|i| matches!(i, Inst::MakeClosure { fun, captures, .. }
                if captures.len() == 1 && captures[0].0 == "n" && fun.contains("lambda"))),
        "the lambda closes over n: {:?}",
        insts_of(go)
    );
    let lambda = module
        .functions
        .iter()
        .find(|f| f.name.contains("lambda"))
        .expect("the lambda is a function of the module");
    assert_eq!(lambda.captures, vec!["n".to_string()]);
    let param_names: Vec<&str> = lambda.params.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(
        param_names,
        vec!["n", "x"],
        "captures come first, in MakeClosure order"
    );
}

#[test]
fn a_host_call_is_a_seam_carrying_its_capability() {
    let module = one("def read(p)\n  write_stdout(read_file(p))\nend\n");
    let read = fn_named(&module, "%root/read");
    let seams = seams_of(read);
    assert_eq!(seams.len(), 1, "one seam: {seams:?}");
    assert_eq!(
        seams[0],
        &SeamKind::Host {
            capability: Capability::FileSystem
        }
    );
    assert_eq!(
        module.capabilities,
        vec![Capability::FileSystem].into_iter().collect(),
        "the module's capability set is witnessed by the seam itself"
    );
}

#[test]
fn a_bare_host_word_is_a_nullary_seam() {
    let module = one("def stamp()\n  now_ms\nend\n");
    let stamp = fn_named(&module, "%root/stamp");
    assert!(
        seams_of(stamp).iter().any(|s| **s
            == SeamKind::Host {
                capability: Capability::Clock
            }),
        "now_ms crosses to the host: {:?}",
        insts_of(stamp)
    );
}

#[test]
fn a_pure_program_has_no_seams_and_no_capabilities() {
    let module = one("def add(a, b)\n  a + b\nend\n\nadd(1, 2)\n");
    assert!(module.capabilities.is_empty());
    for fun in &module.functions {
        assert!(seams_of(fun).is_empty(), "{} has seams", fun.name);
    }
}

#[test]
fn a_check_seam_becomes_a_typed_seam_call() {
    let src = [
        "def source(u)",
        "  u",
        "end",
        "def sink(a: Int) -> Int",
        "  a + 1",
        "end",
        "def typed_caller(u: Int) -> Int",
        "  sink(source(u))",
        "end",
    ]
    .join("\n");
    // Independent evidence first: the CHECK stage recorded the seam. The IR
    // test derives from that, not from itself.
    let checked = checked_of(&src);
    assert_eq!(checked.outcome.seams.len(), 1);
    assert_eq!(checked.outcome.seams[0].expected, blue_lang_check::Ty::Int);

    let module = one(&src);
    let caller = fn_named(&module, "%root/typed_caller");
    let seams = seams_of(caller);
    assert_eq!(seams.len(), 1, "{seams:?}");
    assert_eq!(
        seams[0],
        &SeamKind::Checked {
            expected: blue_lang_check::Ty::Int,
            at: checked.outcome.seams[0].at.clone(),
        }
    );
}

#[test]
fn a_cross_module_call_is_a_posture_seam() {
    let entry = "use(\"geom\", [:twice])\n\ndef go(n)\n  twice(n)\nend\n";
    let geom = "def twice(a: Int) -> Int\n  a + a\nend\n";
    let checked = check_entry(
        Entry {
            path: None,
            text: entry,
        },
        &Fixed(vec![("geom", geom)]),
        None,
        Checking::Program,
    )
    .expect("checks");
    assert!(checked.outcome.ok());
    let modules = lower(&checked).expect("lowers");
    assert_eq!(modules.len(), 2, "entry and geom");
    let root = modules.iter().find(|m| m.name == "%root").unwrap();
    let geom_m = modules.iter().find(|m| m.name == "geom").unwrap();
    assert_eq!(root.posture, Posture::Dynamic);
    assert_eq!(geom_m.posture, Posture::Checked);

    let go = fn_named(root, "%root/go");
    let seams = seams_of(go);
    assert_eq!(seams.len(), 1, "{seams:?}");
    assert_eq!(
        seams[0],
        &SeamKind::Posture {
            from: Posture::Dynamic,
            to: Posture::Checked,
        }
    );
    let twice = fn_named(geom_m, "geom/twice");
    assert_eq!(twice.params[0].ty, blue_lang_check::Ty::Int);
}

#[test]
fn a_same_posture_call_is_not_a_seam() {
    // The same shape as the posture test, but the callee is UNTYPED: both
    // modules sit at dynamic, and the call crosses nothing. A lowering that
    // stamped a seam on every foreign call fails here.
    let entry = "use(\"geom\", [:twice])\n\ndef go(n)\n  twice(n)\nend\n";
    let geom = "def twice(a)\n  a + a\nend\n";
    let checked = check_entry(
        Entry {
            path: None,
            text: entry,
        },
        &Fixed(vec![("geom", geom)]),
        None,
        Checking::Program,
    )
    .expect("checks");
    let modules = lower(&checked).expect("lowers");
    let root = modules.iter().find(|m| m.name == "%root").unwrap();
    let go = fn_named(root, "%root/go");
    assert!(
        seams_of(go).is_empty(),
        "same posture, no seam: {:?}",
        insts_of(go)
    );
    assert!(
        insts_of(go)
            .iter()
            .any(|i| matches!(i, Inst::Call { callee: Callee::Fun(f), .. } if f == "geom/twice")),
        "the call is plain: {:?}",
        insts_of(go)
    );
}

#[test]
fn assignment_through_a_branch_joins_on_a_block_parameter() {
    let module = one([
        "def pick(c)",
        "  n = 1",
        "  if c",
        "    n = 2",
        "  else",
        "    n = 3",
        "  end",
        "  n",
        "end",
    ]
    .join("\n")
    .as_str());
    let pick = fn_named(&module, "%root/pick");
    let joins: Vec<&blue_lang_ir::Param> = pick
        .blocks
        .iter()
        .flat_map(|b| b.params.iter())
        .filter(|p| p.name == "%n")
        .collect();
    assert_eq!(
        joins.len(),
        1,
        "exactly one join carries n: {:?}",
        pick.blocks
            .iter()
            .map(|b| b.params.iter().map(|p| p.name.clone()).collect::<Vec<_>>())
            .collect::<Vec<_>>()
    );
    // The returned value flows through a block parameter, so no value is
    // ever overwritten: the ret's value is a join parameter of the merge.
    let Terminator::Ret { value } = &pick.blocks.last().expect("blocks").term else {
        panic!("the function returns");
    };
    let merge_has_value = pick.blocks.iter().any(|b| b.param_values.contains(value));
    assert!(
        merge_has_value,
        "the returned value is a block parameter (SSA join), not a register"
    );
}

#[test]
fn a_module_declares_its_posture() {
    let dynamic = one("def id(x)\n  x\nend\n");
    assert_eq!(dynamic.posture, Posture::Dynamic);
    let checked_module = one("def id(x: Int) -> Int\n  x\nend\n");
    assert_eq!(checked_module.posture, Posture::Checked);
}

#[test]
fn top_level_statements_lower_into_one_toplevel_function() {
    let module = one("def main()\n  1\nend\n\nwrite_stdout(\"hi\")\n");
    let toplevel = fn_named(&module, "%toplevel");
    assert!(
        insts_of(toplevel).iter().any(
            |i| matches!(i, Inst::Call { callee: Callee::Builtin(b), .. } if b == "write_stdout")
        ),
        "{:?}",
        insts_of(toplevel)
    );
    assert!(fn_named(&module, "%root/main").blocks.len() >= 1);
}

#[test]
fn every_defined_value_has_a_type() {
    // Type preservation is total: no value exists in the types table as an
    // accident of the walk — every instruction's target is recorded.
    let module = one([
        "record point(x: Int, y: Int)",
        "def go(a, b)",
        "  p = point(a, b)",
        "  if a > b",
        "    p.x",
        "  else",
        "    p.y",
        "  end",
        "end",
    ]
    .join("\n")
    .as_str());
    for fun in &module.functions {
        for block in &fun.blocks {
            for inst in &block.insts {
                let to = match inst {
                    Inst::Const { to, .. }
                    | Inst::List { to, .. }
                    | Inst::Map { to, .. }
                    | Inst::Call { to, .. }
                    | Inst::SeamCall { to, .. }
                    | Inst::MakeRecord { to, .. }
                    | Inst::FieldGet { to, .. }
                    | Inst::TagIs { to, .. }
                    | Inst::MakeClosure { to, .. } => *to,
                };
                assert!(
                    fun.types.contains_key(&to),
                    "{} defines v{to} with no type",
                    fun.name
                );
            }
            for v in &block.param_values {
                assert!(fun.types.contains_key(v), "param value v{v} with no type");
            }
        }
    }
}

// -- refusals: typed, named, located ---------------------------------------

#[test]
fn rescue_is_refused_by_name() {
    let checked = checked_of("def inc(n)\n  n rescue 0\nend\n");
    let refusal = lower(&checked).expect_err("try is refused");
    assert!(refusal.what.contains("try"), "{:?}", refusal.what);
}

#[test]
fn eval_is_refused_by_name() {
    let src = "def run_it(s)\n  s\nend\n";
    let checked = checked_of(&format!("{src}\ndef later(x)\n  eval(x)\nend\n"));
    let refusal = lower(&checked).expect_err("eval is refused");
    assert!(refusal.what.contains("eval"), "{:?}", refusal.what);
}
