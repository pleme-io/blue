//! F1 of docs/pure-blue/front-tower-conformance.md: `blue ast --tree-json`
//! is the oracle blue's own reader is held to. It writes the tree
//! `parse_program_tree` gives, one `[start, end, kind, payload]` node per
//! form with byte spans. The spans below were counted by hand.

use std::process::Command;

fn tree(src: &str, name: &str) -> String {
    let dir = std::env::temp_dir().join(format!("blue-tree-json-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mkdir");
    let p = dir.join(name);
    std::fs::write(&p, src).expect("write");
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .args(["ast", "--tree-json", p.to_str().expect("utf-8")])
        .output()
        .expect("spawn");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).expect("utf-8")
}

#[test]
fn the_tree_json_gives_each_node_its_kind_and_span() {
    assert_eq!(
        tree("def sq(x)\n  x * x\nend\n", "sq.b"),
        "[[0,21,\"list\",[[0,3,\"sym\",\"define\"],[4,9,\"list\",[[4,6,\"sym\",\"sq\"],[7,8,\"sym\",\"x\"]]],[12,17,\"list\",[[14,15,\"sym\",\"*\"],[12,13,\"sym\",\"x\"],[16,17,\"sym\",\"x\"]]]]]]\n"
    );
    assert_eq!(
        tree("x = [1, \"a\"]\n", "assign.b"),
        "[[0,12,\"list\",[[0,1,\"sym\",\"define\"],[0,1,\"sym\",\"x\"],[4,12,\"list\",[[4,5,\"sym\",\"list\"],[5,6,\"int\",1],[8,11,\"str\",\"a\"]]]]]]\n"
    );
}
