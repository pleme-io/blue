use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use apollo_compiler::{ast, ExecutableDocument, Schema};
use blue_lang_host::{Canonical, Entry, Program, Value};
use blue_lang_pkg::load_path::LoadPath;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn fixtures() -> PathBuf {
    root().join("bidamas/danpen/fixtures")
}

fn graphql_files(dir: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|x| x == "graphql"))
        .collect();
    files.sort();
    files
}

struct Blue {
    program: Program<()>,
}

impl Blue {
    fn load() -> Self {
        let text = std::fs::read_to_string(root().join("crates/blue-lang-danpen-diff/tests/agree.b")).unwrap();
        let loader = LoadPath::new([root().join("bidamas")]);
        let program = Program::<()>::builder(Entry::anonymous(Box::leak(text.into_boxed_str())))
            .loader(Box::leak(Box::new(loader)))
            .canonical(Canonical::Required)
            .load(&mut ())
            .expect("agree.b loads with danpen");
        Self { program }
    }

    fn printed(&mut self, text: &str, compact: bool) -> String {
        self.program
            .call::<String>("printed", (text.to_owned(), compact), &mut ())
            .expect("printed answers")
    }

    fn schema_findings(&mut self, text: &str) -> Vec<String> {
        self.program
            .call::<Vec<String>>("schema_findings", (text.to_owned(),), &mut ())
            .expect("schema_findings answers")
    }

    fn prepared(&mut self, text: &str) -> Value {
        self.program
            .call::<Value>("prepared", (text.to_owned(),), &mut ())
            .expect("prepared answers")
    }

    fn document_findings(&mut self, text: &str, schema: &Value) -> Vec<String> {
        self.program
            .call::<Vec<String>>("document_findings", (text.to_owned(), schema.clone()), &mut ())
            .expect("document_findings answers")
    }
}

fn apollo_print(text: &str, path: &Path, compact: bool) -> Option<String> {
    let doc = ast::Document::parse(text, path).ok()?;
    Some(if compact {
        doc.serialize().no_indent().to_string()
    } else {
        doc.to_string()
    })
}

fn apollo_errors(result: Result<(), String>) -> Vec<String> {
    match result {
        Ok(()) => Vec::new(),
        Err(e) => vec![e],
    }
}

#[derive(Default)]
struct Tally {
    documents: usize,
    agreed: usize,
    valid: usize,
    faults: Vec<String>,
}

impl Tally {
    fn record(&mut self, path: &Path, valid: bool, faults: Vec<String>) {
        self.documents += 1;
        if valid {
            self.valid += 1;
        }
        if faults.is_empty() {
            self.agreed += 1;
        } else {
            let name = path.strip_prefix(fixtures()).unwrap_or(path).display().to_string();
            self.faults.extend(faults.into_iter().map(|f| format!("{name}: {f}")));
        }
    }
}

fn print_faults(blue: &mut Blue, text: &str, path: &Path) -> Vec<String> {
    let mut faults = Vec::new();
    for compact in [false, true] {
        let ours = blue.printed(text, compact);
        match apollo_print(text, path, compact) {
            Some(theirs) if theirs == ours => {}
            Some(theirs) => faults.push(format!(
                "{} print differs:\n--- apollo-compiler\n{theirs}\n--- blue\n{ours}",
                if compact { "compact" } else { "graphql" }
            )),
            None if ours.starts_with("!parse_error") => {}
            None => faults.push("apollo-compiler refuses to parse it and blue printed it".to_owned()),
        }
    }
    faults
}

fn verdict_faults(theirs: &[String], ours: &[String]) -> Vec<String> {
    match (theirs.is_empty(), ours.is_empty()) {
        (true, true) | (false, false) => Vec::new(),
        (true, false) => vec![format!("apollo-compiler finds it valid, blue finds: {}", ours.join("; "))],
        (false, true) => vec![format!("blue finds it valid, apollo-compiler finds: {}", theirs.join("; "))],
    }
}

fn agreement() -> Tally {
    let mut blue = Blue::load();
    let mut tally = Tally::default();
    let mut schemas = BTreeMap::new();
    for path in graphql_files(&fixtures().join("schema")) {
        let text = std::fs::read_to_string(&path).unwrap();
        let theirs = apollo_errors(Schema::parse_and_validate(&text, &path).map(|_| ()).map_err(|e| e.errors.to_string()));
        let ours = blue.schema_findings(&text);
        let mut faults = print_faults(&mut blue, &text, &path);
        faults.extend(verdict_faults(&theirs, &ours));
        tally.record(&path, theirs.is_empty(), faults);
        if theirs.is_empty() {
            let valid = Schema::parse_and_validate(&text, &path).unwrap();
            let prepared = blue.prepared(&text);
            schemas.insert(path.file_stem().unwrap().to_string_lossy().to_string(), (valid, prepared));
        }
    }
    let mut dirs: Vec<PathBuf> = std::fs::read_dir(fixtures().join("executable"))
        .unwrap()
        .map(|d| d.unwrap().path())
        .collect();
    dirs.sort();
    for dir in dirs {
        let name = dir.file_name().unwrap().to_string_lossy().to_string();
        let (schema, prepared) = schemas
            .get(&name)
            .unwrap_or_else(|| panic!("executable/{name} has no valid schema/{name}.graphql"));
        for path in graphql_files(&dir) {
            let text = std::fs::read_to_string(&path).unwrap();
            let theirs = apollo_errors(
                ExecutableDocument::parse_and_validate(schema, &text, &path)
                    .map(|_| ())
                    .map_err(|e| e.errors.to_string()),
            );
            let ours = blue.document_findings(&text, prepared);
            let mut faults = print_faults(&mut blue, &text, &path);
            faults.extend(verdict_faults(&theirs, &ours));
            tally.record(&path, theirs.is_empty(), faults);
        }
    }
    tally
}

#[test]
fn blue_and_apollo_compiler_agree_on_every_document() {
    let tally = agreement();
    eprintln!(
        "danpen agreement: {} documents ({} valid), {} agree",
        tally.documents, tally.valid, tally.agreed
    );
    assert!(tally.documents >= 200, "the corpus shrank to {} documents", tally.documents);
    assert!(
        tally.faults.is_empty(),
        "{} fault(s):\n{}",
        tally.faults.len(),
        tally.faults.join("\n\n")
    );
}
