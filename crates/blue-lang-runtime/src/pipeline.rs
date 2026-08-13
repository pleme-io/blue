//! The blue pipeline: **parse → check → erase → run**, in that order, once.
//!
//! The order is the whole reason this module exists. Each stage is available
//! separately for tools that want one, but the *default* path is a single
//! function, because two of the four orderings are silently wrong:
//!
//! - **Erase before check** discards every annotation, so a program with type
//!   errors passes. The checker sees `(define …)` and has nothing to check.
//! - **Run before check** reports a type error after the side effects.
//!
//! Neither fails loudly. Both produce a green run on a program that should
//! have been rejected. Leaving the order to each caller means every caller
//! is one reordering away from turning the type checker off — so the order
//! lives here, and callers ask for a *result*, not a sequence of steps.

use tatara_lisp::Sexp;
use tatara_lisp_eval::Value;

use crate::erase::erase_types;
use crate::inputs::Inputs;
use crate::uses::Entry;

/// Why a run stopped short.
#[derive(Debug, thiserror::Error)]
pub enum RunError {
    #[error("parse error: {0}")]
    Parse(String),
    /// The type checker rejected the program. Carries every diagnostic, not
    /// just the first: a caller fixing one error wants to see the rest.
    ///
    /// Each one is already rendered `file:line:col: message` against the file
    /// the offending form came from — which, in a program with imports, is
    /// frequently not the file the user named. The rendering happens here
    /// rather than at the consumer because here is where the file table exists;
    /// see `uses::ResolvedProgram::locate`.
    #[error("{} type error(s):\n{}", .0.len(), .0.join("\n"))]
    Types(Vec<String>),
    /// **No longer reachable, and that is the point.** This reported "blue
    /// emitted a tree the reader could not read back" — a failure only a
    /// print-then-reparse hop could have. [`crate::lower_to_spanned`] deleted
    /// the hop, so there is nothing left to fail: the tree the evaluator gets
    /// IS the tree erasure produced, not a re-reading of its text.
    ///
    /// Kept rather than removed because it is public API on a released crate
    /// and a consumer may still match on it, per ★★ MODULARIZE, DON'T DELETE.
    /// It is retired, not orphaned — if a future stage ever serialises again
    /// it has a typed home. **Nothing constructs it today**; do not read its
    /// presence as evidence the pipeline can still fail this way.
    #[error("the emitted tatara-lisp could not be read back: {0}")]
    Lower(String),
    /// The program ran and raised.
    ///
    /// Rendered `file:line:col: message` against the file the failing form's
    /// top-level form came from — the same `uses::ResolvedProgram::locate`
    /// machinery, the same file table and the same join key the type errors
    /// above use. Until erasure learned to carry spans this was a bare
    /// message, because the evaluator was handed a tree whose every node had
    /// been stamped `Span::synthetic()` on the way in.
    ///
    /// **The honest limit, stated so nobody reads more into a position than is
    /// there.** The index names the top-level form that was EXECUTING; the span
    /// names where the failing text SITS. Those agree on the file whenever the
    /// failing code is in the same file as the top-level form that reached it —
    /// which is every single-file program, and an imported package whose own
    /// top-level code raises. They can disagree when a top-level form in file A
    /// calls a function defined in file B and the raise happens inside B: the
    /// path reported is A's. `locate` refuses to print a `line:col` it cannot
    /// justify (the span must be a real range in that file), so the usual shape
    /// of that case is a file with no position rather than a precise-looking
    /// wrong one — but a same-length pair of files can still put a plausible
    /// number on the wrong file. Closing it needs per-frame file identity at
    /// the evaluator, which is a call stack blue does not have.
    #[error("runtime error: {0}")]
    Eval(String),
    /// A `use("name")` could not be resolved.
    ///
    /// Its own variant rather than folded into `Parse`, because the reader's
    /// next action is different: a parse error is in the source in front of
    /// them, an import error is in their packaging — a missing bidama, a
    /// BLUE_PATH that does not contain it, or no loader at all.
    #[error("import error: {0}")]
    Import(String),
}

/// What a run produced, plus what the checker did on the way.
#[derive(Debug)]
pub struct Run {
    pub value: Value,
    /// Nodes the type walk visited. Zero for a fully untyped program — this
    /// is what makes "no annotations, no analysis" a *measurement* rather
    /// than a claim.
    pub visited: usize,
    /// Declarations that carried an annotation.
    pub typed_decls: usize,
    /// Boundaries where typed code meets untyped code.
    pub seams: usize,
}

/// Parse blue source to tatara-lisp forms.
pub fn parse(src: &str) -> Result<Vec<Sexp>, RunError> {
    parse_with_depth(src, blue_lang_syntax::MAX_EXPR_DEPTH)
}

/// [`parse`] with the parser's nesting bound supplied by the caller.
///
/// The bound exists so a stack overflow — which `catch_unwind` cannot catch —
/// arrives as a typed `Err` instead. It is a *limit*, not a dialect: raising
/// it changes no program's meaning, which is exactly why it is safe to expose
/// as configuration (`blue-lang-cli`'s `config` module holds the rule).
pub fn parse_with_depth(src: &str, max_depth: usize) -> Result<Vec<Sexp>, RunError> {
    blue_lang_syntax::parse_program_with_depth(src, max_depth)
        .map_err(|e| RunError::Parse(e.to_string()))
}

/// [`parse_with_depth`] keeping **every node's** source span.
///
/// The door for anything that will report a position to a human. It exists here,
/// beside the spanless one, so a caller that wants spans still parses under the
/// CONFIGURED nesting bound — a separate `blue_lang_syntax` call would be the
/// second door `parse_with_depth`'s own docs exist to prevent, with
/// `max_expr_depth` true of some subcommands and not others.
pub fn parse_tree_with_depth(
    src: &str,
    max_depth: usize,
) -> Result<Vec<blue_lang_syntax::Spanned>, RunError> {
    blue_lang_syntax::parse_program_tree_with_depth(src, max_depth)
        .map_err(|e| RunError::Parse(e.to_string()))
}

/// [`parse`] keeping **every node's** source span.
///
/// The spanned twin of [`parse`], at the same default bound — the door for
/// anything downstream of a parse that will report a position, which since
/// `use` learned to carry file identity is every path through
/// [`run_in_surface`].
pub fn parse_tree(src: &str) -> Result<Vec<blue_lang_syntax::Spanned>, RunError> {
    parse_tree_with_depth(src, blue_lang_syntax::MAX_EXPR_DEPTH)
}

/// Run blue source with no build inputs.
pub fn run(src: &str) -> Result<Run, RunError> {
    run_with_inputs(src, Inputs::new())
}

/// Run blue source, giving the macro phase access to verified build inputs.
///
/// `inputs` is already verified — [`Inputs`] cannot hold bytes that do not match
/// their declared hash — so nothing here re-checks. The capability a macro gains
/// is exactly "these hashed bytes", never a path.
pub fn run_with_inputs(src: &str, inputs: Inputs) -> Result<Run, RunError> {
    run_with_loader(src, inputs, &crate::uses::NoLoader)
}

/// Run blue source with a loader, so `use("name")` can resolve.
///
/// Split from [`run_with_inputs`] rather than folded into it because loading a
/// package reads a filesystem, and this crate has a `wasm32-unknown-unknown`
/// consumer with zero host imports. The capability is injected by callers that
/// have it — `blue_lang_pkg::LoadPath` is the real one — and absent by default,
/// where a `use` is a typed error naming the package.
pub fn run_with_loader(
    src: &str,
    inputs: Inputs,
    loader: &dyn crate::uses::Loader,
) -> Result<Run, RunError> {
    run_in_surface(Entry::anonymous(src), inputs, loader, None)
}

/// Run blue source written in a `yakugo` surface.
///
/// The pack applies at PARSE time and nowhere else — by the time the checker
/// sees the program it is canonical, so every stage below is identical whatever
/// surface the author wrote in. That is what makes a surface a surface: it
/// changes how a program is spelled and nothing about how it runs.
///
/// `entry` carries the source AND the file it was read from, because a type
/// error has to be reported somewhere: a caller with a path should pass it, and
/// one without ([`Entry::anonymous`]) gets diagnostics that say so rather than
/// diagnostics that guess. Imported packages name themselves through the
/// loader either way.
///
/// # Errors
///
/// As [`run_with_loader`].
pub fn run_in_surface(
    entry: Entry<'_>,
    inputs: Inputs,
    loader: &dyn crate::uses::Loader,
    surface: Option<&blue_lang_syntax::yakugo::Yakugo>,
) -> Result<Run, RunError> {
    let forms = match surface {
        Some(pack) => blue_lang_syntax::parse_program_tree_in(entry.text, pack)
            .map_err(|e| RunError::Parse(e.to_string()))?,
        None => parse_tree(entry.text)?,
    };

    // RESOLVE imports first, so everything below sees ONE program.
    //
    // Before the check on purpose: imported code is type-checked at the point
    // its consumer imports it, rather than at whatever later moment its code
    // first runs. A package that does not typecheck should break its importer's
    // build, not their production run.
    //
    // One program, but not one FILE: the result records which file each
    // top-level form came from, which is what lets a diagnostic below name a
    // place instead of only a problem.
    let mut program = crate::uses::resolve_uses(forms, entry, loader).map_err(RunError::Import)?;

    // `test` blocks are declarations for the harness, not code to run.
    //
    // Dropped here rather than in `resolve_uses`, because `blue test` calls
    // the resolver and then NEEDS the entry file's blocks — so the two
    // callers want different things and the split has to live at this level.
    //
    // Without this, `blue run` on a file containing its own tests fails with
    // `unbound symbol: deftest`: every package in the bidama distribution
    // carries tests, so every one of them was unrunnable.
    //
    // Through `retain`, which drops each form's owner with it. A plain filter
    // over the forms alone would slide every later form onto the wrong file.
    program.retain(|f| !crate::uses::is_test_form(f));

    // CHECK, on the annotated tree — the only tree that has annotations.
    //
    // **On the REAL spanned tree, including every imported package's.** This
    // was the one caller that checked a spanless lift, because `resolve_uses`
    // flattened the entry file and its imports into one list and `Span` is a
    // byte range with no file identity — so a real span here would have
    // reported an imported package's error at that offset in the ENTRY file, a
    // precise-looking answer pointing at unrelated code.
    //
    // The fix is not a wider `Span` (that type is upstream, and its own docs
    // put file identity on the caller: spans "are meaningful only relative to
    // the string that produced them, which the caller is responsible for
    // holding onto"). blue holds onto it BESIDE the span, per top-level form —
    // see `uses::ResolvedProgram`.
    let outcome = blue_lang_check::check_program(program.forms());
    if !outcome.ok() {
        return Err(RunError::Types(
            outcome
                .diagnostics
                .iter()
                // `file:line:col: message`, resolved against the file the form
                // actually came from. A typed `Display` builds it, per ★★ TYPED
                // EMISSION — `locate` returns the renderer, not a string.
                .map(|d| program.locate(d.top_level, d.span, &d.message).to_string())
                .collect(),
        ));
    }

    // ERASE, so the interpreter never sees a type — **on the spanned tree,
    // and back out as one.**
    //
    // This used to be `erase_types(&program.sexps())` followed by a
    // `lower_to_spanned` that stamped `Span::synthetic()` over every node, and
    // the comment here said carrying real positions through was "a larger
    // piece and is NOT built". It was not larger: erasure only ever DELETES
    // nodes — the single node it invents is the `define` replacing
    // `define-typed` — so there was never anything for a synthetic span to
    // stand in for. See `crate::erase`.
    //
    // No lowering step follows. The tree the evaluator receives IS the tree the
    // parser built, minus annotations, with the author's byte offsets intact.
    let erased = erase_types(program.forms());

    let mut interp = crate::interpreter_hostless();
    crate::inputs::install_input_primitives(&mut interp, inputs);

    // RUN, one top-level form at a time, **counting them**.
    //
    // This is literally the loop `Interpreter::eval_program` runs internally
    // (tatara-lisp-eval `eval.rs`) — unrolled here for exactly one reason: the
    // INDEX. `resolve_uses` flattens N files into one form list and a `Span` is
    // a byte range with no file identity, so an offset alone is ambiguous
    // across files — 66 means something in every one of them. The index is the
    // join key back to `ResolvedProgram`'s file table, and `eval_program`
    // consumes it internally and hands back only the error.
    //
    // The same key, the same renderer and the same file table the type errors
    // above already use. A runtime error was the one diagnostic in this
    // function still reporting a bare message.
    let mut value = Value::Nil;
    for (top_level, form) in erased.iter().enumerate() {
        value = interp.eval_top_form(form, &mut ()).map_err(|e| {
            // `span()` is `None` for the arms that genuinely have no position
            // (`Reader`, `Halted`, `NotImplemented`). Synthetic is the honest
            // stand-in — `locate` renders it as a file with no line rather
            // than inventing one.
            let at = e.span().unwrap_or_else(tatara_lisp::Span::synthetic);
            // `short_message`, NOT `Display`. Upstream's `Display` ends every
            // positioned arm with ` at {span}` — a raw byte range — and once
            // blue prefixes a resolved `path:line:col` that suffix is the same
            // fact told twice, the second time in a unit no reader can spend.
            //
            // Worse than redundant: a byte range is exactly the thing this
            // whole file-identity apparatus exists to stop being reported on
            // its own, because an offset means something different in every
            // file. On the one case blue deliberately declines to place — a
            // raise inside a callee from another file — `Display` would print
            // the CALLEE's offsets beside the CALLER's path, re-creating the
            // precise-looking wrong answer `locate`'s guard just refused.
            // `short_message` is upstream's own "no source context" accessor,
            // and blue supplies the context.
            let message = e.short_message();
            RunError::Eval(program.locate(top_level, at, &message).to_string())
        })?;
    }

    Ok(Run {
        value,
        visited: outcome.stats.visited,
        typed_decls: outcome.stats.typed_decls,
        seams: outcome.seams.len(),
    })
}

/// **A runtime error names a place.** The gates for the last stage that
/// reported a bare message.
///
/// Each fixture is sized so that resolving the failing span against ANY file
/// but the right one lands somewhere else — a different path and a different
/// line — so a green run here is evidence about the join and not about the
/// renderer being called at all.
#[cfg(test)]
mod position_tests {
    use super::*;
    use crate::uses::{Entry, Loader};
    use std::collections::BTreeMap;
    use std::path::Path;

    struct MemLoader(BTreeMap<&'static str, &'static str>);

    impl Loader for MemLoader {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            self.0
                .get(name)
                .map(|s| vec![(format!("{name}.b"), (*s).to_owned())])
                .ok_or_else(|| format!("no bidama named \"{name}\""))
        }
    }

    /// A package whose OWN top-level code raises, deep inside a file that is
    /// deliberately taller than either of the other two.
    ///
    /// Byte 66 — where `kore_wa_sonzai_shinai` starts — is past the end of the
    /// entry file (30 bytes) and past the end of `kotae.b` (21 bytes). So the
    /// only file this span can honestly resolve against is this one, and the
    /// other two now refuse to answer rather than walking off their ends.
    const BAKUHATSU: &str = "\
def tsukawanai_a()
  1
end

def tsukawanai_b()
  2
end

def bakuhatsu()
  kore_wa_sonzai_shinai()
end

bakuhatsu()";

    const KOTAE: &str = "def kotae()\n  42\nend";

    /// The same failing call, but only ever reached by a CALLER in another
    /// file — the shape that exercises `RunError::Eval`'s stated limit.
    const BAKUHATSU2: &str = "def yobu()\n  kore_wa_sonzai_shinai()\nend";

    fn loader() -> MemLoader {
        MemLoader(BTreeMap::from([
            ("kotae", KOTAE),
            ("bakuhatsu", BAKUHATSU),
            ("bakuhatsu2", BAKUHATSU2),
        ]))
    }

    fn run_named(path: &str, src: &str) -> RunError {
        run_in_surface(
            Entry {
                path: Some(Path::new(path)),
                text: src,
            },
            Inputs::new(),
            &loader(),
            None,
        )
        .expect_err("the fixture must raise")
    }

    /// **The load-bearing gate: a raise inside an IMPORTED package reports the
    /// IMPORTED file's path and line.**
    ///
    /// Hand-computed. In `bakuhatsu.b` the failing call sits on line 10 at
    /// column 3, and the whole point of the fixture's height is that no other
    /// file in the program can produce that pair: the entry file has 2 lines
    /// and `kotae.b` has 3, so *any* mis-attribution is visible as a different
    /// path AND a different position, never as a coincidence.
    ///
    /// **Three red runs, one per edit this change makes** — each isolates a
    /// different half of the mechanism, which is what stops the gate being a
    /// tautology over "some renderer ran".
    ///
    /// 1. `eval_program` + `.map_err(|e| RunError::Eval(e.to_string()))`
    ///    restored (the pre-change code):
    ///    ```text
    ///    left:  "runtime error: unbound symbol: kore_wa_sonzai_shinai at 74..95"
    ///    right: "runtime error: bakuhatsu.b:10:3: unbound symbol `kore_wa_sonzai_shinai`"
    ///    ```
    ///    No place at all — the state this change is fixing — and the trailing
    ///    `at 74..95` is upstream's `Display`, an offset with no file, which is
    ///    why the loop renders `short_message` instead.
    ///
    /// 2. The loop kept, but `0` passed to `locate` in place of `top_level`:
    ///    ```text
    ///    left:  "runtime error: kotae.b: unbound symbol `kore_wa_sonzai_shinai`"
    ///    right: "runtime error: bakuhatsu.b:10:3: unbound symbol `kore_wa_sonzai_shinai`"
    ///    ```
    ///    **This is the one that proves the INDEX is load-bearing** rather than
    ///    the renderer: form 0 belongs to `kotae.b`, so the wrong file is named
    ///    — and named without a position, because the guard in `locate` sees
    ///    that byte 74 is not a range in a 21-byte file and declines to invent
    ///    one. A fixture with one imported package could not tell these apart.
    ///
    /// 3. `crate::lower_to_spanned(&crate::to_sexps(&erased))` reinstated
    ///    between erasure and the loop:
    ///    ```text
    ///    left:  "runtime error: bakuhatsu.b: unbound symbol `kore_wa_sonzai_shinai`"
    ///    right: "runtime error: bakuhatsu.b:10:3: unbound symbol `kore_wa_sonzai_shinai`"
    ///    ```
    ///    The right FILE with no position — which is exactly the shape of the
    ///    bug: the index survived the lift and every span did not.
    #[test]
    fn a_raise_inside_an_imported_package_names_that_package() {
        let err = run_named("entry.b", "use(\"kotae\")\nuse(\"bakuhatsu\")\n");
        assert_eq!(
            err.to_string(),
            "runtime error: bakuhatsu.b:10:3: unbound symbol `kore_wa_sonzai_shinai`"
        );
    }

    /// Anti-vacuity for the fixture itself: the position asserted above is a
    /// FACT ABOUT `bakuhatsu.b`, checked against the source text rather than
    /// against the thing that produced it.
    ///
    /// Without this, `10:3` is just a number that happened to come out of the
    /// code under test, and a change that moved every reported line by one
    /// would move this assertion with it.
    #[test]
    fn line_10_column_3_of_the_fixture_is_the_failing_call() {
        let line = BAKUHATSU.lines().nth(9).expect("line 10 exists");
        assert_eq!(line, "  kore_wa_sonzai_shinai()");
        assert_eq!(
            &line[2..],
            "kore_wa_sonzai_shinai()",
            "column 3 (1-indexed) is where the call starts"
        );
        // And the other two files cannot reach that far, which is what makes a
        // mis-attribution loud instead of plausible.
        let offset = BAKUHATSU.find("kore_wa_sonzai_shinai").expect("in fixture");
        assert!(
            offset > KOTAE.len(),
            "kotae.b could answer for byte {offset}"
        );
        assert!(
            offset > "use(\"kotae\")\nuse(\"bakuhatsu\")\n".len(),
            "the entry file could answer for byte {offset}"
        );
    }

    /// **The `FileId(0)` path: a raise in the ENTRY file reports the entry
    /// file.** The single-file case, which is every program that imports
    /// nothing — and the one where the index and the span cannot disagree.
    ///
    /// **Red run** (2026-08-12), `eval_program` +
    /// `.map_err(|e| RunError::Eval(e.to_string()))` restored:
    /// ```text
    /// left:  "runtime error: unbound symbol: nani_mo_nai at 17..28"
    /// right: "runtime error: honmono.b:5:1: unbound symbol `nani_mo_nai`"
    /// ```
    ///
    /// **Second red run**, `lower_to_spanned` reinstated after erasure — the
    /// one that isolates the SPAN half from the index half, since a
    /// single-file program cannot get its file wrong:
    /// ```text
    /// left:  "runtime error: honmono.b: unbound symbol `nani_mo_nai`"
    /// right: "runtime error: honmono.b:5:1: unbound symbol `nani_mo_nai`"
    /// ```
    #[test]
    fn a_raise_in_the_entry_file_names_the_entry_file() {
        let err = run_named("honmono.b", "def f()\n  1\nend\n\nnani_mo_nai()\n");
        assert_eq!(
            err.to_string(),
            "runtime error: honmono.b:5:1: unbound symbol `nani_mo_nai`"
        );
    }

    /// A raise from a form that came through the SURFACE-level erasure still
    /// reports a real position — the annotated path, where erasure rewrites
    /// the node rather than passing it through.
    ///
    /// Separate from the two above because the erasure rewrite is the only
    /// place a node is built rather than kept, and a synthetic span there
    /// would be invisible to a fixture whose failing form is untouched.
    ///
    /// **Red run** (2026-08-12), `lower_to_spanned` reinstated after erasure:
    /// ```text
    /// left:  "runtime error: chuu.b: unbound symbol `mada_nai`"
    /// right: "runtime error: chuu.b:2:3: unbound symbol `mada_nai`"
    /// ```
    #[test]
    fn a_raise_inside_an_annotated_def_still_names_its_line() {
        let err = run_named(
            "chuu.b",
            "def f(a: Int) -> Int\n  mada_nai(a)\nend\n\nf(1)\n",
        );
        assert_eq!(
            err.to_string(),
            "runtime error: chuu.b:2:3: unbound symbol `mada_nai`"
        );
    }

    /// **The stated limit, pinned rather than left to be discovered.**
    ///
    /// A top-level form in the entry file calls a function defined in an
    /// imported one, and the raise happens inside the callee. The index names
    /// the executing form (the entry's), the span names the callee's bytes,
    /// and the two disagree about the file. `locate`'s in-range guard is what
    /// keeps that from rendering as a precise-looking `entry:line:col`: the
    /// offset is not a range in the entry file, so no position is printed.
    ///
    /// This test asserts the CURRENT behaviour, including the part that is
    /// wrong — the path is the caller's. It is here so the next author reads
    /// the limit off a green suite instead of off a bug report. Closing it
    /// needs per-frame file identity at the evaluator; see `RunError::Eval`.
    ///
    /// **Red run** (2026-08-12), the `span.end <= file.text.len()` guard
    /// removed from `uses::ResolvedProgram::locate` — and it is the ONLY test
    /// in the crate that moves, which is the same run's evidence that the
    /// guard is a no-op on every check-time diagnostic:
    /// ```text
    /// left:  "runtime error: yobidashi.b:1:14: unbound symbol `kore_wa_sonzai_shinai`"
    /// right: "runtime error: yobidashi.b: unbound symbol `kore_wa_sonzai_shinai`"
    /// ```
    /// `1:14` lands in the middle of `use("bakuhatsu2")` — the callee's start
    /// offset happens to be in range for the caller's file even though its end
    /// is not, so a wrong file gets a precise number pointing at innocent
    /// code. Exactly the failure this repo's file-identity work exists to
    /// refuse, which is why the guard tests BOTH ends.
    #[test]
    fn a_raise_in_a_callee_from_another_file_reports_no_position_rather_than_a_wrong_one() {
        let err = run_named("yobidashi.b", "use(\"bakuhatsu2\")\nyobu()\n");
        assert_eq!(
            err.to_string(),
            "runtime error: yobidashi.b: unbound symbol `kore_wa_sonzai_shinai`",
            "the caller's file is named (the stated limit) but NOT with a \
             position it cannot justify"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn int(src: &str) -> i64 {
        match run(src).unwrap_or_else(|e| panic!("{src:?}: {e}")).value {
            Value::Int(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **The sliding scale, as one assertion.** Annotating changes the
    /// analysis and nothing else.
    #[test]
    fn annotating_buys_analysis_and_changes_nothing_else() {
        let plain = run("def add(a, b)\n  a + b\nend\nadd(2, 3)").expect("plain");
        let typed = run("def add(a: Int, b: Int) -> Int\n  a + b\nend\nadd(2, 3)").expect("typed");

        assert!(matches!(plain.value, Value::Int(5)));
        assert!(
            matches!(typed.value, Value::Int(5)),
            "the annotated program must compute the same answer"
        );
        assert_eq!(plain.visited, 0, "no annotations means no analysis");
        assert!(
            typed.visited > 0,
            "an annotation must actually buy analysis, not just decorate"
        );
        assert_eq!(plain.typed_decls, 0);
        assert_eq!(typed.typed_decls, 1);
    }

    /// **Checking happens before erasure.** This is the test that catches the
    /// reordering: a program with a declared-type violation must be rejected,
    /// and it can only be rejected while the annotations still exist.
    #[test]
    fn a_type_error_is_reported_and_the_program_does_not_run() {
        let err = run("def add(a: Int, b: Int) -> Str\n  a + b\nend\nadd(1, 2)")
            .expect_err("a declared Str return from an Int body must be rejected");
        assert!(
            matches!(err, RunError::Types(ref d) if !d.is_empty()),
            "expected type diagnostics, got {err}"
        );
    }

    /// And the untyped version of the same program runs, so the rejection
    /// above is the annotation's doing rather than a parse failure.
    #[test]
    fn the_same_program_without_annotations_runs() {
        assert_eq!(int("def add(a, b)\n  a + b\nend\nadd(1, 2)"), 3);
    }

    #[test]
    fn a_parse_error_is_reported_as_one() {
        assert!(matches!(run("def (").unwrap_err(), RunError::Parse(_)));
    }

    /// Every stage reports in its own vocabulary, so a failure names which
    /// stage failed rather than surfacing as a generic error.
    #[test]
    fn a_runtime_error_is_reported_as_one() {
        let err = run("no_such_function(1)").expect_err("unbound");
        assert!(matches!(err, RunError::Eval(_)), "got {err}");
    }

    /// Stdlib and primitives are both reachable through the pipeline — the
    /// gap that made `6 % 3` fail.
    #[test]
    fn the_pipeline_reaches_both_runtime_layers() {
        assert_eq!(int("6 % 3"), 0);
        assert_eq!(int("7 % 3"), 1);
        assert_eq!(int("2 + 3 * 4"), 14);
    }

    /// **The deleted hop was a no-op on everything blue emits — so removing it
    /// is a swap, not a behaviour change.**
    ///
    /// The old lowering printed the erased tree and read it back through
    /// `tatara_lisp::read_spanned`. This walks a corpus and asserts the two
    /// paths land on the same tree, which is the equivalence the swap rests on.
    /// It is stated as a *measurement over this corpus*, not as a theorem:
    /// the round trip is not identity in general (that is precisely why it had
    /// to go), it merely happened to be identity for the bytes blue emits.
    #[test]
    fn the_deleted_round_trip_agreed_with_the_direct_lowering() {
        let corpus = [
            "def add(a, b)\n  a + b\nend\nadd(2, 3)",
            "def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nfact(5)",
            "def f(a, b)\n  c = a + b\n  c * 2\nend\nf(1, 2)",
            "defmacro sq(e)\n  quote\n    unquote(e) * unquote(e)\n  end\nend\nsq(2 + 3)",
            "\"a string with spaces, a ( and a )\"",
            "def g(a: Int) -> Int\n  a + 1\nend\ng(1)",
            "6 % 3",
            "1.5 + 2.25",
        ];
        for src in corpus {
            // Projected to `Sexp` because that is what the deleted hop
            // operated on. Erasure itself no longer goes near it.
            let erased = crate::to_sexps(&erase_types(&parse_tree(src).expect("parse")));

            let direct: Vec<Sexp> = crate::lower_to_spanned(&erased)
                .iter()
                .map(tatara_lisp::Spanned::to_sexp)
                .collect();
            assert_eq!(direct, erased, "the direct lowering must be the identity");

            let text = erased
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join("\n");
            let round_tripped: Vec<Sexp> = tatara_lisp::read_spanned(&text)
                .unwrap_or_else(|e| panic!("{src:?}: the old path could not read back: {e:?}"))
                .iter()
                .map(tatara_lisp::Spanned::to_sexp)
                .collect();
            assert_eq!(
                round_tripped, erased,
                "{src:?}: the old print-and-reparse path changed the tree"
            );
        }
    }

    /// Anti-vacuity for the test above: the round trip really is *not* the
    /// identity in general, so agreeing on the corpus was a property of what
    /// blue happens to emit rather than a property of the reader.
    ///
    /// **`Atom::Symbol`'s `Display` writes the name raw, with no escaping.**
    /// `Atom::Str` escapes and its docs explain at length why; the symbol arm
    /// is `f.write_str(s)`. So print-then-read is not inverse over the symbol
    /// domain, and the failure is *silent*: a symbol containing a space prints
    /// as two tokens, reads back as two symbols, and the result is a perfectly
    /// well-formed tree with a different meaning. No error, nothing to catch.
    ///
    /// Measured 2026-08-02 across the separators: `a b` and `x'y` come back
    /// `Ok` with a different tree; `x)y`, `x"y` and `x;y` come back `Err`;
    /// `x{y` and `x[y` DO round-trip at this level — those two are one symbol
    /// in and one symbol out, so the brace-fusion reported in tatara *source*
    /// is not what bites a printed tree. The silent pair is what makes this a
    /// miscompile class rather than a noisy one.
    #[test]
    fn the_round_trip_is_not_the_identity_in_general() {
        let tree = Sexp::List(vec![
            Sexp::Atom(tatara_lisp::Atom::Symbol("f".into())),
            Sexp::Atom(tatara_lisp::Atom::Symbol("a b".into())),
        ]);
        let text = tree.to_string();
        let back: Vec<Sexp> = tatara_lisp::read_spanned(&text)
            .expect("it reads back cleanly — that IS the problem")
            .iter()
            .map(tatara_lisp::Spanned::to_sexp)
            .collect();
        assert_ne!(
            back,
            vec![tree.clone()],
            "if print-then-read became inverse over symbols, the class would be \
             closed upstream and this test should be deleted rather than relaxed"
        );
        // …and the direct lowering is unaffected by any of it.
        let direct: Vec<Sexp> = crate::lower_to_spanned(std::slice::from_ref(&tree))
            .iter()
            .map(tatara_lisp::Spanned::to_sexp)
            .collect();
        assert_eq!(direct, vec![tree]);
    }
}

#[cfg(test)]
mod macro_tests {
    use super::*;

    fn int(src: &str) -> i64 {
        match run(src).unwrap_or_else(|e| panic!("{src:?}: {e}")).value {
            Value::Int(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **A blue macro expands and runs.** Tenet 2's surface, end to end.
    #[test]
    fn a_macro_expands_and_runs() {
        assert_eq!(
            int("defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\ndouble(21)"),
            42
        );
    }

    /// A macro receives *source forms*, not values — so it can duplicate its
    /// argument, which a function cannot do without re-evaluating it.
    #[test]
    fn a_macro_operates_on_syntax_not_values() {
        assert_eq!(
            int("defmacro sq(e)\n  quote\n    unquote(e) * unquote(e)\n  end\nend\nsq(2 + 3)"),
            25,
            "the argument form `2 + 3` must be substituted twice"
        );
    }

    /// **A runaway macro is a typed error, not a dead compiler.** This is the
    /// property that makes the metaprogramming surface safe to hand to a user.
    ///
    /// The assertion was `contains("expansion limit")` and now reads
    /// `contains("expansion")`, because the pipeline renders `short_message`
    /// rather than `Display`: upstream words the same fact as "exceeded 256
    /// expansion steps" instead of "exceeded the expansion limit of 256
    /// rewrites". The PROPERTY is unchanged and still asserted — the macro is
    /// named, and the failure is attributed to expansion rather than to
    /// evaluation. **This reword was the whole measured blast radius of that
    /// switch**, one test in the workspace.
    ///
    /// The number is deliberately NOT pinned. It is upstream's constant, this
    /// test owns none of it, and matching it would turn an upstream bump into
    /// a red run here that proves nothing about blue.
    ///
    /// The third clause is new capability rather than repair: the message now
    /// carries `<anonymous>:6:1`, so a runaway macro says WHERE it ran away.
    #[test]
    fn a_runaway_macro_fails_the_compilation_rather_than_the_process() {
        let err =
            run("defmacro forever(x)\n  quote\n    forever(unquote(x))\n  end\nend\nforever(1)")
                .expect_err("a self-referential macro must be rejected");
        let msg = err.to_string();
        assert!(
            msg.contains("forever") && msg.contains("expansion"),
            "the error must name the macro and the limit it hit: {msg}"
        );
        assert!(
            msg.contains("<anonymous>:6:1"),
            "and must place the call that ran away — line 6 is `forever(1)`: {msg}"
        );
    }
}

#[cfg(test)]
mod input_tests {
    use super::*;
    use crate::inputs::{Declaration, Inputs};

    /// A schema a macro will generate code from.
    const SCHEMA: &[u8] = b"3";

    fn with_schema(src: &str) -> Result<Run, RunError> {
        let hash = Inputs::hash_of(SCHEMA);
        let mut inputs = Inputs::new();
        inputs
            .bind(
                &Declaration {
                    name: "schema".to_string(),
                    hash,
                },
                SCHEMA.to_vec(),
            )
            .expect("bind");
        run_with_inputs(src, inputs)
    }

    fn decl_line() -> String {
        let mut s = String::from("definput(\"schema\", \"");
        s.push_str(&Inputs::hash_of(SCHEMA));
        s.push_str("\")\n");
        s
    }

    /// **A macro reads a declared build input.** This is §VI OPEN #6 closed —
    /// the spec names it as gating blue's whole "stronger than Ruby's
    /// metaprogramming" claim, because a macro that cannot read a schema cannot
    /// generate code from one.
    #[test]
    fn a_macro_can_read_a_declared_build_input() {
        let src = decl_line() + "input(\"schema\")";
        let out = with_schema(&src).expect("run");
        assert!(
            matches!(out.value, Value::Str(ref s) if &**s == "3"),
            "got {:?}",
            out.value
        );
    }

    /// **An undeclared input is an error, not a file read and not nil.**
    /// Returning nil is how a macro generates an empty table and nobody notices
    /// until runtime.
    #[test]
    fn an_undeclared_input_is_an_error() {
        let err = with_schema("input(\"not_declared\")").expect_err("must fail");
        let msg = err.to_string();
        assert!(msg.contains("not_declared"), "must name it: {msg}");
        assert!(msg.contains("definput"), "and say how to declare it: {msg}");
    }

    /// **There is no path-based read at all.** The capability is the absence of
    /// the primitive, not a check inside one — so this is an unbound symbol.
    ///
    /// Holds for the DEFAULT surface — the one every embedder gets. The `sys`
    /// cargo feature (CLI only) is the one declared exception: it is the
    /// operator's own trusted host surface, and is asserted in
    /// `sys_read_file_is_the_trusted_cli_only_exception` below.
    #[cfg(not(feature = "sys"))]
    #[test]
    fn there_is_no_ambient_file_read() {
        for attempt in [
            "read_file(\"/etc/passwd\")",
            "File(\"/etc/passwd\")",
            "slurp(\"/etc/passwd\")",
            "open(\"/etc/passwd\")",
        ] {
            let err = with_schema(attempt).expect_err("must not resolve");
            assert!(
                err.to_string().contains("unbound"),
                "{attempt} must be UNBOUND — a capability removed by absence, \
                 not guarded by a check: {err}"
            );
        }
    }

    /// With the `sys` feature compiled in, `read_file` IS bound — that is the
    /// point of the feature. The doctrine does not move: this is the operator's
    /// own machine (the CLI), not an embedder's sandbox. Pin the boundary so a
    /// future default-build change is heard, and assert that `input()` still
    /// works beside it.
    #[cfg(feature = "sys")]
    #[test]
    fn sys_read_file_is_the_trusted_cli_only_exception() {
        let err = with_schema("definitely_not_a_primitive(\"x\")").expect_err("must not resolve");
        assert!(err.to_string().contains("unbound"), "{err}");
        assert!(
            with_schema("read_file(\"/etc/passwd\")").is_ok(),
            "with `sys` on, read_file is the trusted CLI surface"
        );
        let out = with_schema("input(\"schema\")").expect("run");
        assert!(
            matches!(out.value, Value::Str(ref s) if &**s == "3"),
            "input() still binds beside the sys surface: {:?}",
            out.value
        );
    }

    /// Anti-vacuity: with no inputs supplied at all, even a declared name fails
    /// — so the success above is the binding's doing.
    #[test]
    fn a_declared_input_with_no_bytes_supplied_fails() {
        let src = decl_line() + "input(\"schema\")";
        assert!(run(&src).is_err(), "no bytes were supplied");
    }
}

#[cfg(test)]
mod tier2_tests {
    use super::*;
    use crate::inputs::{Declaration, Inputs};

    /// **The Tier-2 conversion §V.6.3 said was gated: a macro that emits real
    /// declarations FROM A SCHEMA.**
    ///
    /// `theory/BLUE.md` §VI OPEN #6 states the blocker plainly — "tenet 2
    /// installs a `NoLoader`, so a macro cannot read a schema — which gates
    /// every Tier-2 conversion in §V.6 and therefore blue's whole 'stronger than
    /// Ruby's metaprogramming' claim."
    ///
    /// Here the schema supplies a *value the generated code depends on*, read at
    /// expansion time. Ruby and Elixir can both do this — with the whole
    /// filesystem open. blue does it through a name bound to a content hash.
    #[test]
    fn a_macro_generates_code_from_a_schema() {
        let schema = b"7";
        let mut inputs = Inputs::new();
        inputs
            .bind(
                &Declaration {
                    name: "arity".to_string(),
                    hash: Inputs::hash_of(schema),
                },
                schema.to_vec(),
            )
            .expect("bind");

        // The macro reads the input at EXPANSION time and splices the value it
        // found into the code it emits.
        let mut src = String::from("definput(\"arity\", \"");
        src.push_str(&Inputs::hash_of(schema));
        src.push_str("\")\n");
        src.push_str(
            "defmacro from_schema()\n  quote\n    unquote(to_int(input(\"arity\")))\n  end\nend\n\
             from_schema() * 6",
        );

        let out = run_with_inputs(&src, inputs).expect("run");
        assert!(
            matches!(out.value, Value::Int(42)),
            "the schema's 7 must reach the generated code: got {:?}",
            out.value
        );
    }
}
