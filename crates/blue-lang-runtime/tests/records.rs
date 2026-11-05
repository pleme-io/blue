use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{run_in_surface, RunError};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_syntax::{parse_program, record::RECORD_ALIASES};
use tatara_lisp_eval::Value;

const GEO: &str = "@moduledoc \"\"\"\ngeo holds points.\n\n    point(1, 2).x #=> 1\n\"\"\"\n\n@doc \"\"\"\npoint is a place.\n\n    point(1, 2).y #=> 2\n\"\"\"\nrecord point(x: Int, y: Int)\n";

struct Geo;

impl Loader for Geo {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        if name == "geo" {
            return Ok(vec![("geo.b".to_string(), GEO.to_string())]);
        }
        Err(format!("no bidama named \"{name}\""))
    }
}

fn run(src: &str) -> Result<Value, RunError> {
    run_in_surface(Entry::anonymous(src), Inputs::new(), &Geo, None).map(|r| r.value)
}

fn yes(src: &str) {
    let got = run(src).unwrap_or_else(|e| panic!("{src}\n{e}"));
    assert!(matches!(got, Value::Bool(true)), "{src}\n{got:?}");
}

fn refused_at_check(src: &str, says: &str) {
    match run(src) {
        Err(RunError::Types(errors)) => {
            let all = errors.join("\n");
            assert!(all.contains("B0079"), "{all}");
            assert!(all.contains(says), "{says}: {all}");
        }
        other => panic!("{src}: not refused at check: {other:?}"),
    }
}

fn refused_at_run(src: &str, says: &str) {
    match run(src) {
        Err(RunError::Types(errors)) => panic!("{src}: refused at check: {errors:?}"),
        Err(e) => assert!(e.to_string().contains(says), "{says}: {e}"),
        Ok(v) => panic!("{src}: ran to {v:?}"),
    }
}

const POINT: &str = "record point(x, y)\nrecord spot(x, y)\n";

fn with_point(body: &str) -> String {
    format!("{POINT}{body}")
}

#[test]
fn the_constructor_takes_the_fields_in_order_or_by_name() {
    yes(&with_point("point(1, 2) == point({y: 2, x: 1})"));
    yes(&with_point("point(1, 2).y == 2"));
    yes(&with_point("x = 1\ny = 2\npoint({x:, y:}) == point(1, 2)"));
}

#[test]
fn a_missing_field_stops_at_the_check_stage() {
    refused_at_check(&with_point("point(1)"), "takes 2 fields");
    refused_at_check(&with_point("point({x: 1})"), "missing `y`");
    refused_at_check(&with_point("point(1, 2, 3)"), "takes 2 fields");
}

#[test]
fn an_unknown_field_stops_at_the_check_stage() {
    refused_at_check(&with_point("point({x: 1, y: 2, z: 3})"), "no field `z`");
    refused_at_check(
        &with_point("p = point(1, 2)\npoint(**p, z: 3)"),
        "no field `z`",
    );
}

#[test]
fn the_check_reaches_a_record_of_another_bidama_however_it_is_named() {
    refused_at_check("use(\"geo\")\n\ngeo::point(1)", "takes 2 fields");
    refused_at_check(
        "use(\"geo\", [:point])\n\npoint({x: 1, z: 2})",
        "no field `z`",
    );
    refused_at_check("use(\"geo\")\n\ngeo::point(\"s\", 2)", "`x` is Int");
    yes("use(\"geo\")\n\ngeo::point(1, 2).y == 2");
    yes("use(\"geo\", [:point])\n\npoint(1, 2) == point({x: 1, y: 2})");
    yes("use(\"geo\")\n\ngeo::point?(geo::point(1, 2))");
}

#[test]
fn a_local_named_like_a_record_is_not_checked_as_one() {
    yes(&with_point(
        "def f(point)\n  point(1, 2, 3)\nend\nf((a, b, c) -> a + b + c) == 6",
    ));
}

#[test]
fn a_value_the_check_cannot_see_is_refused_when_it_runs() {
    refused_at_run(&with_point("f = point\nf(1)"), "takes 2 fields");
    refused_at_run(&with_point("f = point\nf({x: 1})"), "missing `y`");
    refused_at_run(
        &with_point("f = point\nf({x: 1, y: 2, z: 3})"),
        "no field `z`",
    );
    refused_at_run(
        &with_point("m = {x: 1, y: 2, z: 3}\npoint(**m)"),
        "no field `z`",
    );
    yes(&with_point(
        "f = point\ne = begin\n  f({x: 1, z: 2})\nrescue :record as err\n  err\nend\ne.data == {record: \"point\", missing: [:y], unknown: [:z]}",
    ));
}

#[test]
fn the_predicate_tells_two_same_shaped_records_apart() {
    yes(&with_point("point?(point(1, 2))"));
    yes(&with_point("not spot?(point(1, 2))"));
    yes(&with_point("not point?({x: 1, y: 2})"));
    yes(&with_point("not point?(1)"));
    yes(&with_point("not point?(nil)"));
    yes(&with_point("not point?(assoc(point(1, 2), :z, 3))"));
    yes(&with_point("not point?(dissoc(point(1, 2), :y))"));
}

#[test]
fn an_update_is_a_copy_and_takes_only_its_own_kind() {
    yes(&with_point(
        "p = point(1, 2)\nq = point(**p, x: 9)\n[q.x, q.y, p.x] == [9, 2, 1]",
    ));
    yes(&with_point("point?(point(**point(1, 2), x: 9))"));
    refused_at_run(
        &with_point("s = spot(1, 2)\npoint(**s, x: 9)"),
        "cannot take the fields of a `spot`",
    );
}

#[test]
fn equality_includes_the_name() {
    yes(&with_point("point(1, 2) == point(1, 2)"));
    yes(&with_point("point(1, 2) != spot(1, 2)"));
    yes(&with_point("point(1, 2) != {x: 1, y: 2}"));
    yes(&with_point("point(1, 2) != point(1, 3)"));
    yes(&with_point("point(4, 2) == point(4.0, 2)"));
}

#[test]
fn a_record_nests_and_a_typed_field_holds_only_its_type() {
    let src = "record point(x: Int, y: Int)\nrecord seg(a: point, b: point)\nrecord path(legs: List(seg), name: Str)\n";
    yes(&format!(
        "{src}p = path([seg(point(1, 2), point(3, 4))], \"p\")\np.legs[0].b.y == 4"
    ));
    refused_at_check(&format!("{src}seg(1, point(1, 2))"), "`a` is point");
    refused_at_check(&format!("{src}point(1.5, 2)"), "`x` is Int");
    refused_at_check(&format!("{src}path([1], \"p\")"), "`legs` is List(seg)");
    refused_at_run(
        &format!("{src}f = point\nf(\"s\", 2)"),
        "`x` is Int, and it was given",
    );
    refused_at_run(&format!("{src}f = seg\nf(1, 2)"), "`a` is point");
    refused_at_run(
        &format!("{src}v = [1]\npath(v, \"p\")"),
        "`legs` is List(seg)",
    );
}

#[test]
fn an_unknown_field_type_is_an_unbound_name() {
    match run("record point(x: Nope)\n1") {
        Err(RunError::Types(errors)) => assert!(errors.join("\n").contains("B0001"), "{errors:?}"),
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_record_crosses_json_with_its_name_and_comes_back_equal() {
    let src = "record point(x, y)\nrecord seg(a: point, b: point)\ns = seg(point(1, [2, nil]), point(\"t\", 2.5))\n";
    yes(&format!("{src}json_read(json_stringify(s)) == s"));
    yes(&format!("{src}seg?(json_read(json_stringify(s)))"));
    yes(&format!(
        "{src}json_stringify(point(1, 2)) == \"{{\\\"$record\\\":\\\"point(x,y)\\\",\\\"x\\\":1,\\\"y\\\":2}}\""
    ));
    yes(&format!(
        "{src}json_get(json_parse(json_stringify(s)), \"$record\") == \"seg(a,b)\""
    ));
    yes(&format!(
        "{src}point(**json_read(\"{{\\\"x\\\":1,\\\"y\\\":2}}\")) == point(1, 2)"
    ));
    yes("record point(x, y)\nrecord_name(json_read(\"{\\\"$record\\\":\\\"point(x,y)\\\",\\\"x\\\":1,\\\"y\\\":2}\")) == \"point\"");
    yes("get(json_read(\"{\\\"x\\\":1}\"), \"x\") == 1");
    refused_at_run(
        "record point(x, y)\npoint(**json_read(\"{\\\"$record\\\":\\\"spot\\\",\\\"x\\\":1,\\\"y\\\":2}\"))",
        "cannot take the fields of a `spot`",
    );
    yes("record point(x, y)\njson_read(json_stringify(point(1, {a: :b}))) != point(1, {a: :b})");
}

#[test]
fn a_record_crosses_a_process_as_data() {
    yes(&with_point(
        "def worker(parent)\n  send(parent, point(**receive(), x: 9))\nend\nw = spawn(worker, [self])\nsend(w, point(1, 2))\nreceive() == point(9, 2)",
    ));
}

#[test]
fn a_record_prints_as_the_call_that_builds_it() {
    yes(&with_point(
        "to_s(point(1, \"a\")) == \"point({x: 1, y: \\\"a\\\"})\"",
    ));
    yes(&with_point(
        "to_s([point(1, 2)]) == \"[point({x: 1, y: 2})]\"",
    ));
    yes("use(\"geo\")\n\nto_s(geo::point(1, 2)) == \"geo::point({x: 1, y: 2})\"");
    yes("use(\"geo\")\n\nrecord_name(geo::point(1, 2)) == \"geo::point\"");
    yes(&with_point("record_name({x: 1}).nil?"));
    yes(&with_point("record_fields(point(1, 2)) == {x: 1, y: 2}"));
    refused_at_run(&with_point("record_fields({x: 1})"), "a record");
}

#[test]
fn a_missing_read_names_the_fields_and_never_the_tag() {
    refused_at_run(&with_point("point(1, 2).z"), "its fields: x, y)");
}

#[test]
fn one_field_takes_a_literal_map_by_name_and_any_other_value_as_itself() {
    let src = "record box(v)\n";
    yes(&format!("{src}box({{v: 1}}).v == 1"));
    yes(&format!("{src}m = {{a: 1}}\nbox(m).v == m"));
    yes(&format!("{src}box({{v: {{a: 1}}}}).v == {{a: 1}}"));
    refused_at_check(&format!("{src}box({{a: 1}})"), "no field `a`");
}

#[test]
fn case_matches_a_record_by_its_predicate_and_by_value() {
    let src = with_point(
        "def kind(v)\n  case v\n  when spot?\n    :spot\n  when point(0, 0)\n    :origin\n  when point?\n    :point\n  else\n    :other\n  end\nend\n",
    );
    yes(&format!(
        "{src}[kind(spot(1, 2)), kind(point(0, 0)), kind(point(1, 2)), kind(1)] == [:spot, :origin, :point, :other]"
    ));
    yes("def p?(_v)\n  true\nend\ncase 1\nwhen p?\n  false\nelse\n  true\nend");
}

#[test]
fn record_stays_a_name_everywhere_a_declaration_cannot_be() {
    yes("record = 1\nrecord == 1");
    yes("def record(a, b)\n  a + b\nend\nrecord(1, 2) == 3");
    yes("def record?(x)\n  x\nend\nrecord?(true)");
    yes("class = 1\nstruct = 2\nclass + struct == 3");
    yes("record = false\nrecord or true");
    yes("record = nil\nv = record rescue 1\nv.nil?");
    yes("def f(record)\n  record and true\nend\nf(true)");
}

#[test]
fn a_second_spelling_is_refused_naming_the_first() {
    for word in RECORD_ALIASES {
        let e = parse_program(&format!("{word} Point(x, y)"))
            .unwrap_err()
            .to_string();
        assert!(e.contains("record point(x, y)"), "{word}: {e}");
    }
    for (src, says) in [
        ("def f()\n  record q(x)\nend", "top level"),
        ("record q()", "names no field"),
        ("record q(a, a)", "named twice"),
        ("record q?(a)", "ends in neither"),
        ("record q(a?)", "every field is required"),
        ("record q(*a)", "field name"),
    ] {
        let e = parse_program(src).unwrap_err().to_string();
        assert!(e.contains(says), "{src}: {e}");
    }
}

#[test]
fn a_map_whose_keys_no_longer_match_its_name_is_a_plain_map() {
    for forged in [
        "assoc(point(1, 2), :z, 3)",
        "dissoc(point(1, 2), :y)",
        "{**point(1, 2), z: 3}",
    ] {
        yes(&with_point(&format!("record_name({forged}).nil?")));
        yes(&with_point(&format!("not point?({forged})")));
        yes(&with_point(&format!(
            "not starts_with?(to_s({forged}), \"point(\")"
        )));
        refused_at_run(&with_point(&format!("record_fields({forged})")), "a record");
    }
    yes(&with_point("point?(assoc(point(1, 2), :x, 9))"));
    yes(&with_point("assoc(point(1, 2), :x, 9) == point(9, 2)"));
    yes(&with_point("point?({**point(1, 2), x: 9})"));
    for doc in [
        "{\\\"$record\\\":\\\"point(x,y)\\\",\\\"x\\\":1}",
        "{\\\"$record\\\":\\\"point(x,y)\\\",\\\"x\\\":1,\\\"y\\\":2,\\\"z\\\":3}",
        "{\\\"$record\\\":\\\"point\\\",\\\"x\\\":1,\\\"y\\\":2}",
    ] {
        yes(&with_point(&format!(
            "record_name(json_read(\"{doc}\")).nil?"
        )));
        yes(&with_point(&format!(
            "get(json_read(\"{doc}\"), \"x\") == 1"
        )));
    }
}

#[test]
fn a_record_declared_again_with_other_fields_is_another_value() {
    let old = "json_read(\"{\\\"$record\\\":\\\"point(x,y)\\\",\\\"x\\\":1,\\\"y\\\":2}\")";
    yes(&format!("record point(x, y, z)\nnot point?({old})"));
    refused_at_run(
        &format!("record point(x, y, z)\npoint(**{old}, z: 3)"),
        "cannot take the fields of a `point(x,y)`",
    );
}
