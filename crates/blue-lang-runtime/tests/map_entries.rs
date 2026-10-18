fn text(src: &str) -> String {
    let v = blue_lang_runtime::run(src)
        .unwrap_or_else(|e| panic!("{src}\n{e}"))
        .value;
    format!("{v:?}")
}

#[test]
fn a_maps_entries_come_back_ordered_by_key() {
    assert_eq!(
        text("map_entries({\"b\" => 2, \"a\" => 1, \"c\" => [3]})"),
        text("[[\"a\", 1], [\"b\", 2], [\"c\", [3]]]")
    );
    assert_eq!(
        text("map_entries({zeta: true, alpha: nil})"),
        text("[[:alpha, nil], [:zeta, true]]")
    );
}

#[test]
fn an_empty_or_absent_map_has_no_entries() {
    assert_eq!(text("map_entries({})"), text("[]"));
    assert_eq!(text("map_entries(nil)"), text("[]"));
}

#[test]
fn entries_rebuild_the_map_they_came_from() {
    assert_eq!(
        text("m = {\"x\" => 1, \"y\" => 2}\nreduce(fn(acc, e) assoc(acc, first(e), second(e)) end, {}, map_entries(m)) == m"),
        "Bool(true)"
    );
}

#[test]
fn a_list_is_not_a_map() {
    let e = blue_lang_runtime::run("map_entries([[\"a\", 1]])")
        .err()
        .map(|e| e.to_string())
        .unwrap_or_default();
    assert!(e.contains("a map"), "{e}");
}

#[test]
fn json_read_gives_maps_that_get_and_map_entries_open() {
    let src = r#"d = json_read("{\"b\":{\"x\":[1,{\"y\":null}]},\"a\":true}")
[get(d, "a"), first(get(get(d, "b"), "x")), map?(second(get(get(d, "b"), "x"))), map(fn(e) first(e) end, map_entries(d))]"#;
    assert_eq!(text(src), text(r#"[true, 1, true, ["a", "b"]]"#));
    assert_eq!(text(r#"json_read("[[\"a\", 1]]")"#), text(r#"[["a", 1]]"#));
    assert_eq!(text(r#"map?(json_read("{}"))"#), "Bool(true)");
}

#[test]
fn an_errors_message_and_kind_are_readable() {
    assert_eq!(
        text(
            r#"e = try(throw(error(:late, "after noon")), catch(x(), x))
[error_kind(e), error_message(e)]"#
        ),
        text(r#"[:late, "after noon"]"#)
    );
    let refused = blue_lang_runtime::run("error_message(\"no\")")
        .err()
        .map(|e| e.to_string())
        .unwrap_or_default();
    assert!(refused.contains("an error"), "{refused}");
}
