#[allow(dead_code)]
#[path = "conformance/gaps.rs"]
mod gaps;
#[allow(dead_code)]
#[path = "conformance/rows.rs"]
mod rows;

use std::path::PathBuf;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root")
        .to_path_buf()
}

#[test]
fn every_mark_and_door_rule_names_an_open_gap_of_the_ledger() {
    let (ledger, refused) = gaps::load(&repo().join(gaps::LEDGER));
    assert!(refused.is_empty(), "{}", refused.join("\n"));
    assert!(ledger.len() >= 30, "only {} gaps", ledger.len());
    let (rows, _) = rows::load(&repo().join("spec/rows"));
    let mut marks = gaps::row_marks(&rows);
    let from_rows = marks.len();
    marks.extend(gaps::door_marks());
    assert!(from_rows >= 70, "only {from_rows} marks in spec/rows");
    assert!(marks.len() > from_rows, "no door::TABLE rule names a gap");
    let found = gaps::refusals(&ledger, &marks);
    assert!(found.is_empty(), "{}", found.join("\n"));
}

#[test]
fn a_repeated_id_a_malformed_row_an_unknown_gap_and_a_closed_gap_are_each_refused() {
    let text = [
        "gap(\"G1\", :open, \"a\", opened(\"2026-01-01\"))",
        "gap(\"G1\", :open, \"b\", opened(\"2026-01-01\"))",
        "gap(\"G2\", :closed, \"c\", opened(\"2026-01-01\"), closed(\"2026-01-02\"))",
        "gap(\"G3\", :open, \"d\", opened(\"2026-01-01\"), closed(\"2026-01-02\"))",
        "gap(\"R7\", :open, \"e\", opened(\"2026-01-01\"))",
    ]
    .join("\n");
    let (ledger, refused) = gaps::parse(&text, "<ledger>");
    assert_eq!(
        refused,
        [
            "<ledger>: gap G1 has two rows; one id names one gap",
            "<ledger>: gap G3: a closed gap says closed(DATE), and an open one does not",
            "<ledger>: `R7` is not a gap id: G and a number",
        ]
    );
    assert_eq!(
        ledger,
        [
            gaps::Gap {
                id: "G1".into(),
                open: true
            },
            gaps::Gap {
                id: "G2".into(),
                open: false
            },
        ]
    );
    let marks: Vec<(String, String)> = [("row a", "G1"), ("row b", "G2"), ("row c", "G9")]
        .iter()
        .map(|(at, gap)| ((*at).to_owned(), (*gap).to_owned()))
        .collect();
    assert_eq!(
        gaps::refusals(&ledger, &marks),
        [
            format!(
                "row b names gap G2, which {} has closed; remove the mark",
                gaps::LEDGER
            ),
            format!(
                "row c names gap G9, which {} does not hold; add its row there",
                gaps::LEDGER
            ),
        ]
    );
}
