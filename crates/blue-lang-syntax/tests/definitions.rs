use blue_lang_syntax::scope::{
    bindings_of, definition, definitions_in, definitions_of, Declared, Definition, DefinitionKind,
    Role,
};
use Declared as D;
use DefinitionKind as K;
use Role as R;

type Read = (String, DefinitionKind, Declared, Vec<(String, Role)>);

fn read(d: &Definition<'_>) -> Read {
    (
        d.name().to_string(),
        d.kind,
        d.declared,
        d.binds
            .iter()
            .map(|b| (b.name().to_string(), b.role))
            .collect(),
    )
}

fn row(name: &str, kind: K, declared: D, binds: &[(&str, R)]) -> Read {
    (
        name.to_string(),
        kind,
        declared,
        binds.iter().map(|(n, r)| ((*n).to_string(), *r)).collect(),
    )
}

fn shapes() -> Vec<(&'static str, Vec<Read>)> {
    let circle = row(
        "circle",
        K::Record,
        D::Record,
        &[("circle", R::Name), ("circle?", R::Predicate)],
    );
    let square = row(
        "square",
        K::Record,
        D::Record,
        &[("square", R::Name), ("square?", R::Predicate)],
    );
    vec![
        (
            "def f(x)\n  x\nend\n",
            vec![row("f", K::Function, D::Def, &[("f", R::Name)])],
        ),
        (
            "def f()\n  1\nend\n",
            vec![row("f", K::Function, D::Def, &[("f", R::Name)])],
        ),
        (
            "def f(x: Int) -> Int\n  x\nend\n",
            vec![row("f", K::Function, D::Typed, &[("f", R::Name)])],
        ),
        (
            "x = 3\n",
            vec![row("x", K::Value, D::Binding, &[("x", R::Name)])],
        ),
        (
            "f = (x) -> x\n",
            vec![row("f", K::Function, D::Binding, &[("f", R::Name)])],
        ),
        (
            "f = fn(x)\n  x\nend\n",
            vec![row("f", K::Function, D::Binding, &[("f", R::Name)])],
        ),
        (
            "defmacro m(x)\n  x\nend\n",
            vec![row("m", K::Macro, D::Macro, &[("m", R::Name)])],
        ),
        (
            "record point(x, y: Int)\n",
            vec![row(
                "point",
                K::Record,
                D::Record,
                &[("point", R::Name), ("point?", R::Predicate)],
            )],
        ),
        (
            "union shape = circle(r) | square(s)\n",
            vec![
                row("shape", K::Union, D::Union, &[("shape?", R::Predicate)]),
                circle,
                square,
            ],
        ),
        ("test \"t\"\n  assert true\nend\n", vec![]),
        ("use(\"retsu\")\n", vec![]),
        ("f(1)\n", vec![]),
    ]
}

#[test]
fn every_definition_shape_names_what_it_binds_in_either_tree() {
    for (source, want) in shapes() {
        let written = blue_lang_syntax::parse_program_documented(source).expect(source);
        let got: Vec<Read> = written
            .iter()
            .flat_map(definitions_in)
            .map(|d| read(&d))
            .collect();
        assert_eq!(got, want, "{source}");
        let lowered = blue_lang_syntax::parse_program_tree(source).expect(source);
        let mut got: Vec<Read> = lowered
            .iter()
            .flat_map(definitions_in)
            .map(|d| read(&d))
            .collect();
        let mut want = want.clone();
        got.sort_by(|a, b| a.0.cmp(&b.0));
        want.sort_by(|a, b| a.0.cmp(&b.0));
        assert_eq!(got, want, "{source}, lowered");
        for forms in [&written, &lowered] {
            let bound: Vec<String> = forms
                .iter()
                .flat_map(bindings_of)
                .map(|b| b.name().to_string())
                .collect();
            let resolved: Vec<String> = forms
                .iter()
                .flat_map(definitions_of)
                .map(|(n, _, _)| n)
                .collect();
            assert_eq!(bound, resolved, "{source}");
        }
    }
}

#[test]
fn a_form_is_its_first_definition_and_keyed_by_what_it_binds_first() {
    let forms = blue_lang_syntax::parse_program_documented("union shape = circle(r) | square(s)\n")
        .expect("parses");
    let d = definition(&forms[0]).expect("a union");
    assert_eq!((d.name(), d.key(), d.kind), ("shape", "shape?", K::Union));
    let forms = blue_lang_syntax::parse_program_tree("record point(x)\n").expect("parses");
    let d = definition(&forms[0]).expect("a record");
    assert_eq!((d.name(), d.key(), d.kind), ("point", "point", K::Record));
}

#[test]
fn a_binding_alone_may_be_rebound() {
    let rebound: Vec<bool> = [D::Def, D::Typed, D::Binding, D::Macro, D::Record, D::Union]
        .into_iter()
        .map(D::rebindable)
        .collect();
    assert_eq!(rebound, [false, false, true, false, false, false]);
}

#[test]
fn each_kind_has_one_word() {
    for k in K::ALL {
        assert_eq!(K::of_word(k.word()), Some(k));
    }
    assert_eq!(K::of_word("test"), None);
}
