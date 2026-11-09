use blue_lang_syntax::Spanned;

pub use blue_lang_runtime::def_hash::*;

/// [`identified`] for a checked `program`, its `lowered` tree and the key of
/// its entry's `main`, computed when first asked: the texts the `@doc`
/// lookup reads are taken now, the parse and the hashing wait. The
/// `blue_lang_runtime::Identify` a run is handed.
pub fn identify(
    program: &blue_lang_runtime::uses::ResolvedProgram,
    lowered: std::sync::Arc<Vec<Spanned>>,
    main: Option<String>,
) -> blue_lang_runtime::Identified {
    let sources = crate::DocSources::of(program);
    Box::new(move || identified(&lowered, &sources.docs(), main.as_deref()))
}

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, HashMap};

    use super::*;

    fn lowered(src: &str) -> Vec<Spanned> {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        blue_lang_runtime::pipeline::lower(&checked.program, &checked.names)
    }

    fn hash_of(src: &str, name: &str) -> DefHash {
        let key = format!("%root/{name}");
        hash_program(&lowered(src))
            .of_key(&key)
            .unwrap_or_else(|| panic!("{key} is not defined"))
            .hash
    }

    const BASE: &str =
        "def g(x)\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n\ndef h(x)\n  x - 1\nend\n";

    #[test]
    fn identify_names_every_definition_and_the_run_and_the_run_reaches_them_all() {
        let run = blue_lang_runtime::receipt::RUN;
        let ids_of =
            |src: &str, main: Option<&str>| identified(&lowered(src), &HashMap::new(), main);
        let program = format!("{BASE}\nf(2)\n");
        let ids = ids_of(&program, None);
        assert_eq!(
            ids.get("%root/f"),
            Some(&hash_of(&program, "f").to_string()),
            "an undocumented definition's hash is hash_program's"
        );
        assert!(ids["%root/f"].starts_with("b3:") && ids["%root/f"].len() == 67);
        let changed_callee = ids_of(&format!("{}\nf(2)\n", BASE.replace("x - 1", "x - 2")), None);
        assert_ne!(
            ids[run], changed_callee[run],
            "a definition the run holds changes its hash"
        );
        let changed_top = ids_of(&format!("{BASE}\nf(3)\n"), None);
        assert_ne!(ids[run], changed_top[run], "a top-level form changes it");
        let moved = ids_of(&format!("# a note\n{BASE}\n\nf(2)\n"), None);
        assert_eq!(ids[run], moved[run], "layout and comments do not");
        let with_main = ids_of(&program, Some("%root/f"));
        assert_ne!(
            ids[run], with_main[run],
            "the call to main is part of the run"
        );
        assert_eq!(ids["%root/f"], with_main["%root/f"]);
    }

    #[test]
    fn identify_names_a_definition_as_the_engine_does_doc_included() {
        let src = format!("@doc \"\"\"\ndoubles\n\"\"\"\n{BASE}");
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(&src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
        let engine = crate::hash_checked(&checked.program, &lowered);
        let ids = identify(&checked.program, std::sync::Arc::new(lowered.clone()), None)();
        assert_eq!(
            ids["%root/g"],
            engine.of_key("%root/g").expect("g").hash.to_string(),
            "a documented definition is named as the engine names it"
        );
        assert_ne!(
            ids["%root/g"],
            hash_of(BASE, "g").to_string(),
            "its doc is in its hash"
        );
    }

    struct Kagi(&'static str, String);

    impl blue_lang_runtime::uses::Loader for Kagi {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            (name == "kagi")
                .then(|| vec![(self.0.to_string(), self.1.clone())])
                .ok_or_else(|| format!("no bidama named \"{name}\""))
        }

        fn entry_package(&self, path: &std::path::Path) -> Option<String> {
            (path.file_stem()? == "kagi").then(|| "kagi".to_string())
        }
    }

    const KAGI: &str = "@moduledoc \"\"\"\nkagi guards a number against going below zero.\n\n    guard(1) #=> 1\n\"\"\"\n\n@doc \"\"\"\nguard: x, refused below zero.\n\"\"\"\n\
                        def guard(x)\n  if x < 0\n    raise(:negative, \"below zero\")\n  else\n    x\n  end\nend\n";

    fn kagi_ids(entry: Option<&str>, label: &'static str, src: &str) -> BTreeMap<String, String> {
        let loader = Kagi(label, src.to_string());
        let text = match entry {
            Some(_) => src.to_string(),
            None => "use(\"kagi\")\n\nkagi::guard(1)\n".to_string(),
        };
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry {
                path: entry.map(std::path::Path::new),
                text: &text,
            },
            &loader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
        let engine = crate::hash_checked(&checked.program, &lowered)
            .of_key("kagi/guard")
            .expect("kagi/guard")
            .hash
            .to_string();
        let ids = identify(&checked.program, std::sync::Arc::new(lowered), None)();
        assert_eq!(ids.get("kagi/guard"), Some(&engine));
        ids
    }

    /// Red run (2026-10-31): without `located_raise` in `Unit::node`, the
    /// four reaches named four hashes, since `lower` writes each `raise` as
    /// `blue-raise-at` and the path and line it was reached by.
    #[test]
    fn a_definition_hashes_alike_however_its_package_is_reached_and_wherever_its_raise_sits() {
        let as_entry = kagi_ids(Some("bidamas/kagi/kagi.b"), "", KAGI)["kagi/guard"].clone();
        let moved_entry = kagi_ids(Some("/srv/other/kagi/kagi.b"), "", KAGI)["kagi/guard"].clone();
        let used = kagi_ids(None, "/srv/dist/bidamas/kagi/kagi.b", KAGI)["kagi/guard"].clone();
        let lower_down = KAGI.replacen(
            "@doc",
            "# a note\n\n\ndef unrelated(y)\n  y\nend\n\n@doc",
            1,
        );
        let laid_out = kagi_ids(None, "kagi.b", &lower_down)["kagi/guard"].clone();
        assert_eq!(as_entry, moved_entry, "the entry's path is not in the hash");
        assert_eq!(as_entry, used, "an entry and an import hash alike");
        assert_eq!(as_entry, laid_out, "the raise's line is not in the hash");
        let other_kind = KAGI.replace(":negative", ":below");
        assert_ne!(
            as_entry,
            kagi_ids(None, "kagi.b", &other_kind)["kagi/guard"],
            "the raise itself is"
        );
    }

    #[test]
    fn layout_comments_and_position_are_not_in_the_hash() {
        let moved = "# a comment\n\n\ndef h(x)\n  x - 1\nend\n\ndef g(x)\n  # doubled\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n";
        for name in ["f", "g", "h"] {
            assert_eq!(hash_of(BASE, name), hash_of(moved, name), "{name}");
        }
    }

    fn documented_hash_of(src: &str, name: &str) -> DefHash {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        let docs = crate::program_docs(&checked.program);
        let key = format!("%root/{name}");
        hash_program_documented(
            &blue_lang_runtime::pipeline::lower(&checked.program, &checked.names),
            &|i| docs.get(&i).cloned(),
        )
        .of_key(&key)
        .unwrap_or_else(|| panic!("{key} is not defined"))
        .hash
    }

    /// Red run (2026-10-24): with the `tag::DOC` block removed from
    /// `encode`, the first assertion failed: both texts hashed alike.
    #[test]
    fn a_doc_is_in_its_definitions_hash_and_every_callers() {
        let doc = |t: &str| format!("@doc \"\"\"\n{t}\n\"\"\"\n{BASE}");
        let a = doc("g doubles a number.");
        let b = doc("g triples a number.");
        assert_ne!(documented_hash_of(&a, "g"), documented_hash_of(&b, "g"));
        assert_ne!(documented_hash_of(&a, "f"), documented_hash_of(&b, "f"));
        assert_eq!(documented_hash_of(&a, "h"), documented_hash_of(&b, "h"));
        assert_ne!(documented_hash_of(&a, "g"), documented_hash_of(BASE, "g"));
        assert_eq!(documented_hash_of(BASE, "g"), hash_of(BASE, "g"));
    }

    #[test]
    fn an_edit_to_a_callee_changes_every_caller_and_nothing_else() {
        let edited = BASE.replace("x * 2", "x * 3");
        assert_ne!(hash_of(BASE, "g"), hash_of(&edited, "g"), "the edited def");
        assert_ne!(hash_of(BASE, "f"), hash_of(&edited, "f"), "its caller");
        assert_eq!(
            hash_of(BASE, "h"),
            hash_of(&edited, "h"),
            "an unrelated def"
        );
    }

    #[test]
    fn a_rename_changes_names_and_no_hash() {
        let renamed = BASE.replace("g(", "twice(");
        assert_eq!(hash_of(BASE, "g"), hash_of(&renamed, "twice"));
        assert_eq!(hash_of(BASE, "f"), hash_of(&renamed, "f"));
    }

    #[test]
    fn equal_trees_hash_equal_and_different_kinds_do_not() {
        let src = "def a(x)\n  x + 1\nend\n\ndef b(x)\n  x + 1\nend\n\nc = fn(x) x + 1 end\n";
        assert_eq!(hash_of(src, "a"), hash_of(src, "b"));
        assert_ne!(hash_of(src, "a"), hash_of(src, "c"));
    }

    #[test]
    fn mutual_recursion_hashes_as_one_unit_with_distinct_members() {
        let src = "def ev(n)\n  if n == 0\n    true\n  else\n    od(n - 1)\n  end\nend\n\ndef od(n)\n  if n == 0\n    false\n  else\n    ev(n - 1)\n  end\nend\n";
        let hashes = hash_program(&lowered(src));
        let ev = hashes.of_key("%root/ev").expect("ev");
        let od = hashes.of_key("%root/od").expect("od");
        assert_eq!(ev.unit.len(), 2);
        assert_eq!(ev.unit, od.unit);
        assert_ne!(ev.hash, od.hash);
        // Swapping the names swaps nothing: each member is its shape.
        let swapped = src
            .replace("ev", "TMP")
            .replace("od", "ev")
            .replace("TMP", "od");
        assert_eq!(hash_of(src, "ev"), hash_of(&swapped, "od"));
        // An edit to one member changes both.
        let edited = src.replace("false", "nil");
        assert_ne!(hash_of(src, "ev"), hash_of(&edited, "ev"));
        assert_ne!(hash_of(src, "od"), hash_of(&edited, "od"));
    }

    #[test]
    fn a_value_definition_a_function_reads_is_part_of_its_hash() {
        let src = "limit = 3\n\ndef over(x)\n  x > limit\nend\n";
        let edited = src.replace("= 3", "= 4");
        assert_ne!(hash_of(src, "over"), hash_of(&edited, "over"));
    }

    #[test]
    fn components_are_emitted_callees_first() {
        // 0 -> 1 -> 2 -> 1, 3 alone.
        let graph = vec![vec![1], vec![2], vec![1], vec![]];
        let units = components(&graph);
        let place = |v: usize| units.iter().position(|u| u.contains(&v)).expect("placed");
        assert_eq!(units.iter().filter(|u| u.len() == 2).count(), 1);
        assert!(place(1) < place(0));
        assert_eq!(place(1), place(2));
    }

    #[test]
    fn a_long_chain_does_not_overflow() {
        let graph: Vec<Vec<usize>> = (0..200_000)
            .map(|i| if i == 0 { vec![] } else { vec![i - 1] })
            .collect();
        assert_eq!(components(&graph).len(), 200_000);
    }

    #[test]
    fn the_hash_prints_as_a_b3_declaration() {
        let h = hash_of(BASE, "f").to_string();
        assert!(h.starts_with("b3:") && h.len() == 67, "{h}");
    }

    fn with_tests(src: &str) -> TestIdentities {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::WithTests,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
        test_identities(&lowered, &HashMap::new())
    }

    fn only_test(ids: &TestIdentities) -> String {
        assert_eq!(ids.tests.len(), 1, "{ids:?}");
        ids.tests.values().next().cloned().unwrap_or_default()
    }

    const TESTED: &str = "def g(x)\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n\n\
                          test \"f adds\", {satisfies: [:nist_ac_6], target: f}\n  assert f(1) == 3\nend\n";

    #[test]
    fn a_test_is_identified_by_its_tree_and_what_it_reaches_never_by_its_name() {
        let base = with_tests(TESTED);
        let test = only_test(&base);
        assert!(test.starts_with("b3:") && test.len() == 67, "{test}");
        assert_eq!(
            base.definitions.get("%root/f"),
            Some(&hash_of(BASE, "f").to_string())
        );
        assert!(!base.definitions.keys().any(|k| k.starts_with("%test/")));
        let renamed = with_tests(&TESTED.replace("\"f adds\"", "\"f adds one\""));
        assert_eq!(only_test(&renamed), test, "a renamed test is the same test");
        let body = with_tests(&TESTED.replace("f(1) == 3", "f(2) == 5"));
        assert_ne!(only_test(&body), test, "a changed body is another test");
        let callee = with_tests(&TESTED.replace("x * 2", "x * 3"));
        assert_ne!(only_test(&callee), test, "a changed callee is another test");
        let declared = with_tests(&TESTED.replace("[:nist_ac_6]", "%i[nist_ac_6 nist_cm_7]"));
        assert_ne!(
            only_test(&declared),
            test,
            "a changed declaration is another test"
        );
    }

    #[test]
    fn the_preamble_identity_moves_with_values_and_expressions_never_with_a_function() {
        let src = "k = 2\n\ndef g(x)\n  x * k\nend\n\ndef h(x)\n  x\nend\n\n\
                   test \"g\"\n  assert g(1) == 2\nend\n";
        let base = with_tests(src);
        assert!(base.preamble.starts_with("b3:"), "{base:?}");
        assert_eq!(
            with_tests(&src.replace("  x\nend", "  x + 1\nend")).preamble,
            base.preamble,
            "a function bound once runs nothing in the preamble"
        );
        assert_ne!(
            with_tests(&src.replace("k = 2", "k = 3")).preamble,
            base.preamble,
            "a value runs in the preamble"
        );
        assert_ne!(
            with_tests(&format!("{src}\nh(1)\n")).preamble,
            base.preamble,
            "a top-level expression runs in the preamble"
        );
        assert_eq!(
            with_tests(&src.replace("assert g(1) == 2", "assert g(1) == 2 && true")).preamble,
            base.preamble,
            "a test is not the preamble"
        );
    }

    fn shapes_of(src: &str) -> BTreeMap<String, Shape> {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        checked
            .entry_written_shapes()
            .into_iter()
            .map(|s| (s.name().to_string(), s))
            .collect()
    }

    fn same_shape(src: &str, a: &str, b: &str) -> bool {
        let shapes = shapes_of(src);
        shapes[a].hash == shapes[b].hash
    }

    #[test]
    fn a_renamed_parameter_or_local_keeps_the_shape() {
        for src in [
            "def a(x, y)\n  x - y\nend\n\ndef b(p, q)\n  p - q\nend\n",
            "def a(xs)\n  map((r) -> r + 1, xs)\nend\n\ndef b(ys)\n  map((v) -> v + 1, ys)\nend\n",
            "def a(x)\n  y = x + 1\n  y * 2\nend\n\ndef b(p)\n  q = p + 1\n  q * 2\nend\n",
            "def a(x)\n  begin\n    x + 1\n  rescue e\n    e.kind\n  end\nend\n\n\
             def b(p)\n  begin\n    p + 1\n  rescue why\n    why.kind\n  end\nend\n",
        ] {
            assert!(same_shape(src, "a", "b"), "{src}");
        }
    }

    #[test]
    fn a_parameter_order_a_literal_or_an_operator_is_another_shape() {
        for src in [
            "def a(x, y)\n  x - y\nend\n\ndef b(x, y)\n  y - x\nend\n",
            "def a(x)\n  x + 1\nend\n\ndef b(x)\n  x + 2\nend\n",
            "def a(x)\n  x + 1\nend\n\ndef b(x)\n  x - 1\nend\n",
            "def a(x)\n  x[:name]\nend\n\ndef b(x)\n  x[:kind]\nend\n",
        ] {
            assert!(!same_shape(src, "a", "b"), "{src}");
        }
    }

    #[test]
    fn a_local_that_shadows_a_builtin_is_numbered_only_where_it_binds() {
        let src = "def a(xs)\n  first(map((first) -> first, xs))\nend\n\n\
                   def b(xs)\n  first(map((v) -> v, xs))\nend\n\n\
                   def c(xs)\n  size(map((v) -> v, xs))\nend\n";
        assert!(same_shape(src, "a", "b"), "the head is the builtin in both");
        assert!(
            !same_shape(src, "b", "c"),
            "another builtin is another shape"
        );
    }

    #[test]
    fn a_doc_moves_the_def_hash_and_never_the_shape() {
        let documented = format!("@doc \"\"\"\ng doubles.\n\"\"\"\n{BASE}");
        let shape = |src: &str| shapes_of(src)["g"].hash;
        assert_eq!(shape(BASE), shape(&documented));
        assert_ne!(
            documented_hash_of(BASE, "g"),
            documented_hash_of(&documented, "g"),
            "the control: the same edit moves def_hash"
        );
    }

    #[test]
    fn an_own_callee_is_its_hash_not_its_name() {
        let twins = "def h1(x)\n  x * 2\nend\n\ndef a(x)\n  h1(x) + 1\nend\n\n\
                     def h2(x)\n  x * 2\nend\n\ndef b(x)\n  h2(x) + 1\nend\n";
        assert!(same_shape(twins, "a", "b"), "the helpers are one shape");
        let others = "def h1(x)\n  x * 2\nend\n\ndef a(x)\n  h1(x) + 1\nend\n\n\
                      def h2(x)\n  x * 3\nend\n\ndef b(x)\n  h2(x) + 1\nend\n";
        assert!(!same_shape(others, "a", "b"), "the helpers differ");
        let recursive = "def a(n)\n  if n == 0\n    0\n  else\n    a(n - 1)\n  end\nend\n\n\
                         def b(m)\n  if m == 0\n    0\n  else\n    b(m - 1)\n  end\nend\n";
        assert!(
            same_shape(recursive, "a", "b"),
            "self-recursion by any name"
        );
    }

    fn kagi_caller_shape(kagi: &str) -> DefHash {
        let loader = Kagi("kagi.b", kagi.to_string());
        let text = "use(\"kagi\")\n\ndef caller(x)\n  kagi::guard(x) + 1\nend\n";
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(text),
            &loader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        checked.entry_written_shapes()[0].hash
    }

    #[test]
    fn another_bidamas_word_is_its_name_so_its_edit_moves_no_caller() {
        assert_eq!(
            kagi_caller_shape(KAGI),
            kagi_caller_shape(&KAGI.replace(":negative", ":below"))
        );
    }

    #[test]
    fn a_shape_is_never_a_def_hash_and_its_size_counts_the_tree() {
        let shape = &shapes_of(BASE)["h"];
        assert_ne!(shape.hash, hash_of(BASE, "h"), "two domains");
        assert_eq!(shape.size, 7, "(1 ((- x 1))): 2 + the body list's 5");
        assert_eq!(
            shapes_of("x = 1\n\ndef f()\n  x\nend\n").len(),
            1,
            "a value is hashed as a callee and reported as no shape"
        );
    }
}
