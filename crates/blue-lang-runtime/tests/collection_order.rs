fn text(src: &str) -> String {
    let v = blue_lang_runtime::run(src)
        .unwrap_or_else(|e| panic!("{src}\n{e}"))
        .value;
    format!("{v:?}")
}

fn holds(src: &str) {
    assert_eq!(text(src), "Bool(true)", "{src}");
}

fn refusal(src: &str) -> String {
    match blue_lang_runtime::run(src) {
        Ok(v) => panic!("{src}\nran to {:?}", v.value),
        Err(e) => e.to_string(),
    }
}

#[test]
fn find_takes_the_collection_first_and_returns_the_first_match() {
    holds("find([1, 2, 3, 4], (x) -> x > 1) == 2");
    holds("find([\"a\", \"bb\", \"cc\"], (s) -> length(s) == 2) == \"bb\"");
}

#[test]
fn find_returns_nil_when_nothing_matches() {
    holds("find([1, 2, 3], (x) -> x > 9).nil?");
}

#[test]
fn find_on_an_empty_or_absent_collection_is_nil() {
    holds("find([], (x) -> true).nil?");
    holds("find(nil, (x) -> true).nil?");
}

#[test]
fn find_stops_at_the_first_match() {
    holds(&format!(
        "{}{}",
        "def pick(x)\n  if x == 3\n    raise(:late, \"reached\")\n  else\n    x == 2\n  end\nend\n",
        "find([1, 2, 3], pick) == 2"
    ));
}

#[test]
fn find_still_answers_the_old_order_for_the_tatara_forms_that_call_it() {
    holds("find((x) -> x > 1, [1, 2, 3]) == 2");
    holds("find((x) -> true, []).nil?");
    holds("find((x) -> true, nil).nil?");
}

#[test]
fn find_with_a_function_first_and_no_list_second_says_which_is_new() {
    let e = refusal("find((x) -> x, 5)");
    assert!(e.contains("takes the collection first"), "{e}");
}

#[test]
fn find_refuses_a_subject_that_is_not_a_list() {
    let e = refusal("find(5, (x) -> true)");
    assert!(e.contains("a list"), "{e}");
}

#[test]
fn find_refuses_a_query_that_is_not_a_function() {
    let e = refusal("find([1, 2], 2)");
    assert!(e.contains("takes a function second"), "{e}");
}

#[test]
fn find_lets_an_error_in_the_predicate_through() {
    let e = refusal("find([1], (x) -> raise(:boom, \"inside\"))");
    assert!(e.contains("inside"), "{e}");
}

#[test]
fn flat_map_joins_what_f_returns_in_order() {
    holds("flat_map([1, 2, 3], (x) -> [x, x * 10]) == [1, 10, 2, 20, 3, 30]");
}

#[test]
fn flat_map_joins_one_level_only() {
    holds("flat_map([1, 2], (x) -> [[x]]) == [[1], [2]]");
}

#[test]
fn flat_map_skips_a_nil_and_an_empty_result() {
    holds("def skip(x)\n  if x == 2\n    nil\n  else\n    [x]\n  end\nend\nflat_map([1, 2, 3], skip) == [1, 3]");
    holds("flat_map([1, 2], (x) -> []) == []");
}

#[test]
fn flat_map_on_an_empty_or_absent_collection_is_empty() {
    holds("flat_map([], (x) -> [x]) == []");
    holds("flat_map(nil, (x) -> [x]) == []");
}

#[test]
fn flat_map_refuses_a_result_that_is_not_a_list() {
    let e = refusal("flat_map([1], (x) -> x)");
    assert!(e.contains("a list from f"), "{e}");
}

#[test]
fn flat_map_refuses_the_old_order() {
    let e = refusal("flat_map((x) -> [x], [1, 2])");
    assert!(e.contains("takes the collection first"), "{e}");
}

#[test]
fn flat_map_refuses_a_subject_that_is_not_a_list_and_a_function_that_is_not() {
    assert!(refusal("flat_map(\"ab\", (x) -> [x])").contains("a list"));
    assert!(refusal("flat_map([1], nil)").contains("takes a function second"));
}

#[test]
fn group_by_collects_each_key_in_element_order() {
    holds("group_by([1, 2, 3, 4, 5], (n) -> n % 2) == {1 => [1, 3, 5], 0 => [2, 4]}");
}

#[test]
fn group_by_keys_may_be_text_keywords_or_bools() {
    holds("group_by([\"a\", \"bb\", \"c\"], (s) -> length(s)) == {1 => [\"a\", \"c\"], 2 => [\"bb\"]}");
    holds("def size_of(n)\n  if n > 1\n    :big\n  else\n    :small\n  end\nend\ngroup_by([1, 2, 3], size_of) == {big: [2, 3], small: [1]}");
    holds("group_by([1, 2, 3], (n) -> n > 1) == {true => [2, 3], false => [1]}");
}

#[test]
fn group_by_on_an_empty_or_absent_collection_is_an_empty_map() {
    holds("group_by([], (x) -> x) == {}");
    holds("group_by(nil, (x) -> x) == {}");
}

#[test]
fn group_by_refuses_a_key_that_is_not_a_scalar() {
    let e = refusal("group_by([1, 2], (x) -> [x])");
    assert!(e.contains("a group key must be a scalar, got list"), "{e}");
}

#[test]
fn group_by_refuses_the_old_order() {
    let e = refusal("group_by((x) -> x, [1, 2])");
    assert!(e.contains("takes the collection first"), "{e}");
}

#[test]
fn group_by_refuses_a_subject_that_is_not_a_list_and_a_function_that_is_not() {
    assert!(refusal("group_by(7, (x) -> x)").contains("a list"));
    assert!(refusal("group_by([1], 1)").contains("takes a function second"));
}

#[test]
fn empty_is_true_of_nil_and_the_empty_list_and_false_of_any_item() {
    holds("empty?([])");
    holds("empty?(nil)");
    holds("not empty?([nil])");
    holds("not empty?([1, 2])");
}

#[test]
fn a_state_machine_still_finds_its_transition_row() {
    holds(
        "defsm(\n  door,\n  :initial,\n  :closed,\n  :transitions,\n  [[:closed, :open, :opened], [:opened, :close, :closed]]\n)\n[door(:send, :open), door(:current)] == [:opened, :opened]",
    );
}
