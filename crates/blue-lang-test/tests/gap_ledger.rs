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
    let dir = repo().join("spec/rows");
    let (rows, unread) = rows::load(&dir);
    let found = gaps::gate(
        &ledger,
        &gaps::row_marks(&rows),
        gaps::marks_written(&dir),
        &gaps::door_marks(),
    );
    assert!(
        found.is_empty(),
        "{}\n{}",
        found.join("\n"),
        unread.join("\n")
    );
}

#[test]
fn marks_falling_as_gaps_close_pass_and_a_mark_the_loader_misses_is_refused() {
    let ledger = [gaps::Gap {
        id: "G1".into(),
        open: true,
    }];
    let none: Vec<(String, String)> = Vec::new();
    let one = vec![("row a".to_owned(), "G1".to_owned())];
    assert_eq!(
        gaps::gate(&ledger, &none, Ok(0), &none),
        Vec::<String>::new()
    );
    assert_eq!(
        gaps::gate(&ledger, &one, Ok(1), &none),
        Vec::<String>::new()
    );
    assert_eq!(
        gaps::gate(&ledger, &none, Ok(1), &none),
        ["spec/rows/ writes 1 pending and flaky marks, and the loader read 0; a mark the loader does not read is held by no gate"]
    );
    assert_eq!(
        gaps::gate(&ledger, &one, Err("spec/rows: gone".into()), &none),
        ["the text of spec/rows/ could not be read to count its marks: spec/rows: gone"]
    );
    let text = [
        "# a header that names pending(\"G9\") is not a mark",
        "row(\"a\", \"1\", value(\"1\"), pending(\"G1\"), flaky(\"G2\", \"component\"))",
        "row(\"b\", \"assert_pending(1)\", value(\"1\"))",
    ]
    .join("\n");
    assert_eq!(gaps::written_in(&text), 2);
}

#[test]
fn a_repeated_id_a_malformed_row_an_unknown_gap_and_a_closed_gap_are_each_refused() {
    let text = [
        "gap(\"G1\", :open, \"a\", opened(\"2026-01-01\"))",
        "gap(\"G1\", :open, \"b\", opened(\"2026-01-01\"))",
        "gap(\"G2\", :closed, \"c\", opened(\"2026-01-01\"), closed(\"2026-01-02\"))",
        "gap(\"G3\", :open, \"d\", opened(\"2026-01-01\"), closed(\"2026-01-02\"))",
        "gap(\"R7\", :open, \"e\", opened(\"2026-01-01\"))",
        "gap(\"G4\", :closed, \"f\", opened(\"2026-01-01\"), closed(\"2026-01-02\"), closed(\"2026-01-03\"))",
    ]
    .join("\n");
    let (ledger, refused) = gaps::parse(&text, "<ledger>");
    assert_eq!(
        refused,
        [
            "<ledger>: gap G1 has two rows; one id names one gap",
            "<ledger>: gap G3: a closed gap says closed(DATE), and an open one does not",
            "<ledger>: `R7` is not a gap id: G and a number",
            "<ledger>: gap G4: closed(…) is said twice; a row says each option once",
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
