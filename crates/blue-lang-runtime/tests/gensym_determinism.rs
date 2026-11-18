use blue_lang_runtime::pipeline::run;

fn shown(src: &str) -> String {
    let out = run(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
    blue_lang_runtime::literal::render_value(&out.value)
}

const THREE: &str = "[gensym(\"t\"), gensym(\"t\"), gensym()]";

#[test]
fn one_program_run_twice_in_one_process_names_the_same_symbols() {
    assert_eq!(shown(THREE), shown(THREE));
}

#[test]
fn a_program_run_after_other_work_names_the_same_symbols_as_when_run_first() {
    let first = shown(THREE);
    for _ in 0..5 {
        shown("gensym()");
    }
    assert_eq!(shown(THREE), first);
}

#[test]
fn within_one_run_every_symbol_is_distinct() {
    let out = shown("[gensym(\"a\"), gensym(\"a\"), gensym(\"a\")]");
    let names: Vec<&str> = out.split(',').collect();
    let mut seen = std::collections::BTreeSet::new();
    for n in &names {
        assert!(seen.insert(n.trim()), "{out} repeats a symbol");
    }
    assert_eq!(seen.len(), 3);
}
