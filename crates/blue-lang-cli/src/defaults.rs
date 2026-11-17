//! `blue shift --defaults`: each definition of a file, its facts, the
//! defaults they fire and the fact a default that does not fire is missing.
//! The runtime names what the passes decide
//! ([`blue_lang_runtime::defaults::explain`]); this adds the defaults the
//! store decides: the native tier (R7) and the fleet memo (R8).

use std::path::Path;

use blue_lang_runtime::defaults::{Atom, Verdict};

use crate::native::{Mode, HOT_NS};

/// The entry file's definitions, explained, with the store's verdicts added.
pub(crate) fn of(path: &Path, src: &str) -> Result<Vec<Atom>, crate::CliError> {
    let checked = blue_lang_runtime::pipeline::check_entry(
        blue_lang_runtime::uses::Entry {
            path: Some(path),
            text: src,
        },
        &blue_lang_pkg::load_path::LoadPath::for_entry(path),
        None,
        blue_lang_runtime::pipeline::Checking::Program,
    )?;
    if !checked.outcome.ok() {
        return Err(crate::CliError::Pkg(format!(
            "{} does not pass the check stage: run `blue check {}`",
            path.display(),
            path.display()
        )));
    }
    let lowered = checked.lowered();
    let documented = blue_lang_mondou::hash_checked(&checked.program, &lowered);
    let native = crate::native::mode();
    let mut atoms = blue_lang_runtime::defaults::explain(&lowered);
    atoms.retain(|a| {
        checked.program.owner_of(a.top_level)
            == Some(blue_lang_runtime::uses::ResolvedProgram::ENTRY)
    });
    for a in &mut atoms {
        if !a.function {
            continue;
        }
        if let Some(h) = documented.at(a.top_level) {
            if let Some(v) = native_verdict(native, &h.hash) {
                a.rules.push(("R7".to_string(), v));
            }
        }
        if a.pure {
            let held = crate::memo::costly_results(&a.hash);
            if held > 0 && blue_lang_runtime::kitei::fires("R8", &["pure", "stored_costly"]) {
                a.rules.push((
                    "R8".to_string(),
                    Verdict::Fires(format!(
                        "the store answers its calls: it holds {held} result(s) that cost {} ms or more",
                        crate::memo::COSTLY.as_millis()
                    )),
                ));
            }
        }
    }
    Ok(atoms)
}

fn native_verdict(mode: Mode, hash: &blue_lang_runtime::def_hash::DefHash) -> Option<Verdict> {
    if mode == Mode::Off {
        return None;
    }
    blue_lang_mondou::store::native_artifact(hash)?;
    let mean =
        blue_lang_mondou::store::profile(hash).and_then(blue_lang_mondou::store::Profiled::mean_ns);
    Some(match (mode, mean) {
        (Mode::On, _) => {
            Verdict::Fires("native code answers its calls (BLUE_NATIVE=on)".to_string())
        }
        (_, None) => Verdict::Fires(
            "the native tier times it: it has an artifact and no profile yet".to_string(),
        ),
        (_, Some(ns))
            if blue_lang_runtime::kitei::fires(
                "R7",
                &["artifact", if ns >= HOT_NS { "hot" } else { "" }],
            ) =>
        {
            Verdict::Fires(format!(
                "native code answers its calls: they ran {} ms on average",
                ns / 1_000_000
            ))
        }
        (_, Some(ns)) => Verdict::Missing(format!(
            "its calls ran {} ms on average; native code answers from {} ms",
            ns / 1_000_000,
            HOT_NS / 1_000_000
        )),
    })
}

fn facts(a: &Atom) -> String {
    let mut f = vec![if a.pure {
        "pure".to_string()
    } else {
        "volatile".to_string()
    }];
    if a.overlapping {
        f.push("calls itself twice".to_string());
    }
    if a.typed {
        f.push("typed".to_string());
    }
    if !a.function {
        f.push("value".to_string());
    }
    f.join(", ")
}

/// The report as text: one block per definition, a line per rule.
pub(crate) fn print(atoms: &[Atom]) {
    for a in atoms {
        println!(
            "{}  [{}]",
            blue_lang_runtime::observe::display_key(&a.key),
            facts(a)
        );
        if a.rules.is_empty() {
            if let Some(why) = &a.volatile {
                println!("  ➖ not pure: {why}");
            }
            println!("  ➖ no default fires");
        }
        for (rule, v) in &a.rules {
            match v {
                Verdict::Fires(what) => println!("  ✅ {rule}  {what}"),
                Verdict::Missing(why) => println!("  ⚠️ {rule}  missing: {why}"),
            }
        }
    }
}

/// The report as one JSON object.
pub(crate) fn json(atoms: &[Atom]) -> serde_json::Value {
    let defs: Vec<serde_json::Value> = atoms
        .iter()
        .map(|a| {
            let rules: Vec<serde_json::Value> = a
                .rules
                .iter()
                .map(|(rule, v)| match v {
                    Verdict::Fires(what) => {
                        serde_json::json!({"rule": rule, "fires": true, "detail": what})
                    }
                    Verdict::Missing(why) => {
                        serde_json::json!({"rule": rule, "fires": false, "missing": why})
                    }
                })
                .collect();
            serde_json::json!({
                "name": blue_lang_runtime::observe::display_key(&a.key),
                "key": a.key,
                "hash": a.hash.hex(),
                "function": a.function,
                "pure": a.pure,
                "volatile": a.volatile,
                "overlapping": a.overlapping,
                "typed": a.typed,
                "rules": rules,
            })
        })
        .collect();
    serde_json::json!({ "definitions": defs })
}
