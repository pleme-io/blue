//! `blue test DIR --stage S`: the Bluefile's `check` rows of one stage, run
//! in the lock's order, each as `blue test` runs its file.

use std::path::Path;
use std::process::ExitCode;

use crate::CliError;

/// The rows of `checks` a stage and an optional kind select, by name.
#[must_use]
pub fn selected<'a>(
    checks: &'a std::collections::BTreeMap<String, blue_lang_pkg::bluefile::Check>,
    stage: &str,
    kind: Option<&str>,
) -> Vec<(&'a String, &'a blue_lang_pkg::bluefile::Check)> {
    checks
        .iter()
        .filter(|(_, c)| c.stage.as_deref() == Some(stage))
        .filter(|(_, c)| kind.is_none() || c.kind.as_deref() == kind)
        .collect()
}

pub fn run(dir: &Path, stage: &str, kind: Option<&str>) -> Result<ExitCode, CliError> {
    if !blue_lang_pkg::bluefile::CHECK_STAGES.contains(&stage) {
        return Err(CliError::Usage(format!(
            "--stage is \"{stage}\"; it takes {}",
            blue_lang_pkg::bluefile::CHECK_STAGES.join(", ")
        )));
    }
    if let Some(k) = kind.filter(|k| !blue_lang_syntax::TEST_KINDS.contains(k)) {
        return Err(CliError::Usage(format!(
            "--kind is \"{k}\"; it takes {}",
            blue_lang_syntax::TEST_KINDS.join(", ")
        )));
    }
    let checks = blue_lang_pkg::lock::locked_checks(dir).ok_or_else(|| {
        CliError::Usage(format!(
            "{} holds no Bluefile.lock blue can read; --stage runs a project's check rows (blue lock {} first)",
            dir.display(),
            dir.display()
        ))
    })?;
    let rows = selected(&checks, stage, kind);
    if rows.is_empty() {
        eprintln!(
            "➖ stage {stage}: no check row of {} declares it",
            dir.display()
        );
        return Ok(ExitCode::SUCCESS);
    }
    let exe = std::env::current_exe().map_err(|e| CliError::Usage(e.to_string()))?;
    let root = std::fs::canonicalize(dir).map_err(|source| CliError::Read {
        path: dir.display().to_string(),
        source,
    })?;
    let mut red = Vec::new();
    for (name, check) in &rows {
        let mut cmd = std::process::Command::new(&exe);
        cmd.arg("test")
            .arg(root.join(&check.file))
            .current_dir(&root);
        let ok = cmd.status().is_ok_and(|s| s.success());
        eprintln!(
            "{} check {name} ({})",
            if ok { "✅" } else { "❌" },
            check.file
        );
        if !ok {
            red.push(name.as_str());
        }
    }
    if red.is_empty() {
        eprintln!("🟢 stage {stage}: {} row(s) green", rows.len());
        Ok(ExitCode::SUCCESS)
    } else {
        eprintln!(
            "🔴 stage {stage}: {} of {} row(s) red: {}",
            red.len(),
            rows.len(),
            red.join(", ")
        );
        Ok(ExitCode::FAILURE)
    }
}
