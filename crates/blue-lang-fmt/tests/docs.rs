use blue_lang_fmt::{format_source, format_source_lossless, format_tree_lossless, FormatError};

const MESSY: &str = "# the file\n@moduledoc   \"\"\"\n    m holds f.   \n\n\n        f(1) #=> 2\n    \"\"\"\nuse(\"retsu\", [:first])\n# waive B0002: kept\n@doc \"\"\"\nf adds one.\n\n    f(1) #=> 2\n\"\"\"\n\ndef f(n)\n  # the step\n  n + 1\nend\nx = first([f(1)])\n";

const CANONICAL: &str = "# the file\n@moduledoc \"\"\"\nm holds f.\n\n\n    f(1) #=> 2\n\"\"\"\n\nuse(\"retsu\", [:first])\n\n# waive B0002: kept\n@doc \"\"\"\nf adds one.\n\n    f(1) #=> 2\n\"\"\"\ndef f(n)\n  # the step\n  n + 1\nend\n\nx = first([f(1)])\n";

#[test]
fn a_documented_file_has_one_layout() {
    let out = format_source_lossless(MESSY).unwrap();
    assert_eq!(out, CANONICAL, "\n{out}");
    assert_eq!(format_source_lossless(&out).unwrap(), out);
}

#[test]
fn a_tree_without_its_documentation_is_given_it_back() {
    let tree = blue_lang_syntax::parse_program_tree(MESSY).unwrap();
    assert_eq!(format_tree_lossless(MESSY, &tree).unwrap(), CANONICAL);
}

#[test]
fn the_tree_rendering_has_no_documentation_and_means_the_same_program() {
    let plain = format_source(CANONICAL).unwrap();
    assert!(!plain.contains("@doc"), "{plain}");
    assert_eq!(
        blue_lang_syntax::parse_program(&plain).unwrap(),
        blue_lang_syntax::parse_program(CANONICAL).unwrap()
    );
}

#[test]
fn a_comment_between_a_doc_and_its_definition_is_refused_not_dropped() {
    let src = "@doc \"\"\"\nf is one.\n\"\"\"\n# here\ndef f()\n  1\nend\n";
    assert!(matches!(
        format_source_lossless(src),
        Err(FormatError::UnplaceableComments { .. })
    ));
}
