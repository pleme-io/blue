//! A program run as the root of a node the test configures.

#![allow(dead_code)]

use std::sync::Arc;

use blue_lang_proc::{install, ClockKind, Node, NodeConfig};
use tatara_lisp_eval::{Interpreter, Value};

/// A root interpreter and the node its program runs against: virtual clock,
/// traces kept in memory, the given quantum.
pub fn node(quantum: usize) -> (Interpreter<()>, Arc<Node>) {
    node_with(quantum, Arc::new(blue_lang_runtime::interpreter_hostless))
}

pub fn node_with(
    quantum: usize,
    child: Arc<dyn Fn() -> Interpreter<()> + Send + Sync>,
) -> (Interpreter<()>, Arc<Node>) {
    let mut config = NodeConfig::new(child);
    config.budget.quantum = Some(quantum);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    configure(config)
}

pub fn configure(config: NodeConfig) -> (Interpreter<()>, Arc<Node>) {
    let node = Node::new(config);
    let mut root = blue_lang_runtime::interpreter_hostless();
    install(&mut root, node.clone());
    (root, node)
}

/// Evaluate blue source as the root's program.
pub fn run(root: &mut Interpreter<()>, src: &str) -> Result<Value, String> {
    let forms = blue_lang_syntax::parse_program(src).map_err(|e| e.to_string())?;
    let text = forms
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text).map_err(|e| e.to_string())?;
    root.eval_program(&spanned, &mut ())
        .map_err(|e| e.to_string())
}

/// [`run`], rendered.
pub fn show(root: &mut Interpreter<()>, src: &str) -> String {
    match run(root, src) {
        Ok(v) => v.to_string(),
        Err(e) => format!("error: {e}"),
    }
}
