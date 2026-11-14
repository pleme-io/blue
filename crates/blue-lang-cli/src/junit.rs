//! `blue test --junit FILE`: the run as JUnit XML, the report CI systems read.
//! One `testsuite` per file, one `testcase` per test; a failed test carries
//! its `failure`, a skipped one its `skipped`, a quarantined one is a
//! `skipped` that names its quarantine, and a file the check stage rejected is
//! one `error`.

use std::fmt::Write as _;
use std::path::Path;

/// One file's run, as the report reads it.
pub struct Suite<'a> {
    pub path: &'a Path,
    pub report: Option<&'a blue_lang_test::Report>,
    pub errors: &'a str,
    pub quarantined: &'a [(String, String)],
}

#[must_use]
pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            c if (c as u32) < 0x20 && !matches!(c, '\n' | '\r' | '\t') => {}
            c => out.push(c),
        }
    }
    out
}

/// The whole run as one `testsuites` document.
#[must_use]
pub fn render(suites: &[Suite<'_>]) -> String {
    let mut body = String::new();
    let (mut tests, mut failures, mut errors, mut skipped) = (0, 0, 0, 0);
    for s in suites {
        let name = escape(&s.path.display().to_string());
        let Some(report) = s.report else {
            tests += 1;
            errors += 1;
            let _ = write!(
                body,
                "  <testsuite name=\"{name}\" tests=\"1\" failures=\"0\" errors=\"1\" skipped=\"0\">\n    <testcase classname=\"{name}\" name=\"check\">\n      <error message=\"the check stage rejected the file\">{}</error>\n    </testcase>\n  </testsuite>\n",
                escape(s.errors)
            );
            continue;
        };
        let mut cases = String::new();
        let (mut t, mut f, mut k) = (0, 0, 0);
        let mut seen = std::collections::BTreeSet::new();
        for o in &report.outcomes {
            seen.insert(o.name.clone());
            t += 1;
            let failure = report.failures.iter().find(|x| x.test() == o.name);
            let quarantine = s.quarantined.iter().find(|(n, _)| *n == o.name);
            let _ = write!(
                cases,
                "    <testcase classname=\"{name}\" name=\"{}\" assertions=\"{}\">",
                escape(&o.name),
                o.assertions.passed + o.assertions.failed
            );
            match (failure, quarantine) {
                (Some(_), Some((_, why))) => {
                    k += 1;
                    let _ = write!(cases, "<skipped message=\"quarantined: {}\"/>", escape(why));
                }
                (Some(x), None) => {
                    f += 1;
                    let _ = write!(cases, "<failure message=\"{}\"/>", escape(&x.to_string()));
                }
                _ => {}
            }
            cases.push_str("</testcase>\n");
        }
        for x in &report.failures {
            if seen.insert(x.test().to_string()) {
                t += 1;
                f += 1;
                let _ = writeln!(
                    cases,
                    "    <testcase classname=\"{name}\" name=\"{}\"><failure message=\"{}\"/></testcase>",
                    escape(x.test()),
                    escape(&x.to_string())
                );
            }
        }
        for x in &report.skipped {
            if seen.insert(x.test.clone()) {
                t += 1;
                k += 1;
                let _ = writeln!(
                    cases,
                    "    <testcase classname=\"{name}\" name=\"{}\"><skipped message=\"{}\"/></testcase>",
                    escape(&x.test),
                    escape(&x.why)
                );
            }
        }
        for c in &report.cached {
            if seen.insert(c.clone()) {
                t += 1;
                let _ = writeln!(
                    cases,
                    "    <testcase classname=\"{name}\" name=\"{}\"/>",
                    escape(c)
                );
            }
        }
        tests += t;
        failures += f;
        skipped += k;
        let _ = write!(
            body,
            "  <testsuite name=\"{name}\" tests=\"{t}\" failures=\"{f}\" errors=\"0\" skipped=\"{k}\">\n{cases}  </testsuite>\n"
        );
    }
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites name=\"blue test\" tests=\"{tests}\" failures=\"{failures}\" errors=\"{errors}\" skipped=\"{skipped}\">\n{body}</testsuites>\n"
    )
}
