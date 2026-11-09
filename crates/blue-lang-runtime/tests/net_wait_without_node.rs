#![cfg(feature = "host")]

fn refusal(src: &str) -> String {
    let mut host = ();
    let mut interp: tatara_lisp_eval::Interpreter<()> = tatara_lisp_eval::Interpreter::new();
    blue_lang_runtime::net::stream::install(&mut interp);
    let forms = tatara_lisp_eval::read_spanned(src).expect("reads");
    match interp.eval_program(&forms, &mut host) {
        Ok(v) => panic!("{src} must refuse, answered {v:?}"),
        Err(e) => e.to_string(),
    }
}

#[test]
fn without_a_node_a_bad_handle_is_refused_as_the_node_refuses_it() {
    let err = refusal("(net_wait (quote ((1 :read))) 0)");
    assert!(
        err.contains("int is not a handle net_wait can wait on"),
        "the component and the cli must name the same fault: {err}"
    );
}

#[test]
fn without_a_node_a_well_formed_wait_names_the_missing_readiness_source() {
    let err = refusal("(net_wait (quote ()) 0)");
    assert!(
        err.contains("runs no node with a readiness source"),
        "{err}"
    );
}
