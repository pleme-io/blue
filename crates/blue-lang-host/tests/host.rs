use blue_lang_host::{
    host, host_effect_names, Arity, Budget, CallError, Canonical, Entry, Error, Host, NoLoader,
    Program, Value,
};

#[derive(Default)]
struct Ledger {
    entries: Vec<String>,
    limit: usize,
}

#[host(prefix = "ledger_")]
impl Ledger {
    /// Record one entry.
    fn add(&mut self, entry: String) -> Result<i64, String> {
        if self.entries.len() >= self.limit {
            return Err(format!("full at {} entries", self.limit));
        }
        self.entries.push(entry);
        Ok(i64::try_from(self.entries.len()).unwrap_or(i64::MAX))
    }

    /// Every entry so far.
    fn all(&self) -> Vec<String> {
        self.entries.clone()
    }

    #[blue(name = "repeat")]
    fn repeat(word: String, times: u8) -> String {
        word.repeat(usize::from(times))
    }

    fn note(&mut self, text: String, level: Option<i64>) -> i64 {
        self.entries.push(format!("{text}:{}", level.unwrap_or(0)));
        level.unwrap_or(0)
    }

    #[blue(skip)]
    fn len(&self) -> usize {
        self.entries.len()
    }
}

const PROGRAM: &str = "\
def record(a, b)
  ledger_add(a)
  ledger_add(b)
end

def everything()
  ledger_all()
end

def twice(word)
  repeat(word, 2)
end
";

fn load(host: &mut Ledger) -> Program<Ledger> {
    Program::load_with(Entry::anonymous(PROGRAM), &NoLoader, host).expect("the program loads")
}

#[test]
fn the_surface_names_every_exposed_method_and_only_those() {
    let names: Vec<_> = Ledger::SURFACE.iter().map(|f| f.name).collect();
    assert_eq!(names, ["ledger_add", "ledger_all", "repeat", "ledger_note"]);
    assert_eq!(Ledger::SURFACE[0].params, ["entry"]);
    assert_eq!(Ledger::SURFACE[0].doc, "Record one entry.");
}

#[test]
fn blue_calls_the_host_and_the_host_reads_typed_results() {
    let mut host = Ledger {
        limit: 5,
        ..Ledger::default()
    };
    let mut p = load(&mut host);
    let n: i64 = p.call("record", ("a", "b"), &mut host).unwrap();
    assert_eq!(n, 2);
    let all: Vec<String> = p.call("everything", (), &mut host).unwrap();
    assert_eq!(all, ["a", "b"]);
    assert_eq!(host.len(), 2);
    let twice: String = p.call("twice", ("ab",), &mut host).unwrap();
    assert_eq!(twice, "abab");
}

#[test]
fn a_host_error_reaches_the_caller_naming_the_function() {
    let mut host = Ledger {
        limit: 1,
        ..Ledger::default()
    };
    let mut p = load(&mut host);
    let err = p
        .call::<i64>("record", ("a", "b"), &mut host)
        .unwrap_err()
        .to_string();
    assert!(
        err.contains("ledger_add") && err.contains("full at 1 entries"),
        "{err}"
    );
}

#[test]
fn a_wrong_argument_names_the_function_position_and_parameter() {
    let mut host = Ledger {
        limit: 5,
        ..Ledger::default()
    };
    let mut p = load(&mut host);
    let err = p
        .call::<i64>("record", (1i64, "b"), &mut host)
        .unwrap_err()
        .to_string();
    assert!(
        err.contains("ledger_add") && err.contains("argument 1 (entry)"),
        "{err}"
    );
}

#[test]
fn an_unreadable_return_is_its_own_error() {
    let mut host = Ledger {
        limit: 5,
        ..Ledger::default()
    };
    let mut p = load(&mut host);
    let err = p.call::<i64>("everything", (), &mut host).unwrap_err();
    assert!(
        matches!(err, Error::Returned { ref name, .. } if name == "everything"),
        "{err}"
    );
}

#[test]
fn a_program_naming_an_unknown_host_function_is_refused_at_load() {
    let mut host = Ledger::default();
    let src = "def f()\n  ledger_remove(1)\nend\n";
    let err = Program::<Ledger>::load_with(Entry::anonymous(src), &NoLoader, &mut host);
    assert!(matches!(err, Err(Error::Load(_))));
}

#[test]
fn a_failure_inside_a_call_is_a_call_error_not_a_load_error() {
    let mut host = Ledger {
        limit: 1,
        ..Ledger::default()
    };
    let mut p = load(&mut host);
    let err = p.call::<i64>("record", ("a", "b"), &mut host).unwrap_err();
    assert!(
        matches!(err, Error::Call(CallError::Raised { ref name, .. }) if name == "record"),
        "{err}"
    );
    let err = p.call::<i64>("absent", (), &mut host).unwrap_err();
    assert!(
        matches!(err, Error::Call(CallError::Undefined(ref n)) if n == "absent"),
        "{err}"
    );
}

#[test]
fn a_program_with_no_host_functions_needs_no_host_type() {
    let src = "def double(x)\n  x * 2\nend\n";
    let mut p = Program::<()>::load_with(Entry::anonymous(src), &NoLoader, &mut ()).unwrap();
    let n: i64 = p.call("double", (21i64,), &mut ()).unwrap();
    assert_eq!(n, 42);
    assert!(<() as Host>::SURFACE.is_empty());
}

#[test]
fn a_trailing_option_parameter_may_be_left_out() {
    let note = Ledger::SURFACE
        .iter()
        .find(|f| f.name == "ledger_note")
        .unwrap();
    assert_eq!((note.params.len(), note.required), (2, 1));
    let mut host = Ledger::default();
    let src =
        "def short()\n  ledger_note(\"a\")\nend\n\ndef long()\n  ledger_note(\"b\", 3)\nend\n";
    let mut p = Program::<Ledger>::load_with(Entry::anonymous(src), &NoLoader, &mut host).unwrap();
    assert_eq!(p.call::<i64>("short", (), &mut host).unwrap(), 0);
    assert_eq!(p.call::<i64>("long", (), &mut host).unwrap(), 3);
    assert_eq!(host.entries, ["a:0", "b:3"]);
}

#[test]
fn an_extension_registers_after_the_host_and_its_names_check() {
    let mut host = Ledger::default();
    host.entries.push("x".into());
    let src = "def count()\n  ledger_count_extra()\nend\n";
    let mut p = Program::<Ledger>::builder(Entry::anonymous(src))
        .loader(&NoLoader)
        .extend(|interp| {
            interp.register_fn(
                "ledger_count_extra",
                Arity::Exact(0),
                |_: &[Value], h: &mut Ledger, _| {
                    Ok(Value::Int(
                        i64::try_from(h.entries.len()).unwrap_or(i64::MAX),
                    ))
                },
            );
        })
        .load(&mut host)
        .unwrap();
    assert_eq!(p.call::<i64>("count", (), &mut host).unwrap(), 1);
    let without = Program::<Ledger>::builder(Entry::anonymous(src))
        .loader(&NoLoader)
        .load(&mut host);
    assert!(matches!(without, Err(Error::Load(_))));
}

#[test]
fn a_frame_built_from_host_effect_names_refuses_a_host_effect() {
    let effects = host_effect_names();
    assert!(effects.contains(&"rm_rf") && effects.contains(&"read_file"));
    let permits = |name: &str| !effects.contains(&name);
    let mut host = Ledger::default();
    let bad = Program::<Ledger>::builder(Entry::anonymous("def f()\n  rm_rf(\"/tmp/x\")\nend\n"))
        .loader(&NoLoader)
        .frame(&permits, Budget::tree_walker_default())
        .load(&mut host);
    assert!(
        matches!(bad, Err(Error::Framed(_))),
        "{:?}",
        bad.err().map(|e| e.to_string())
    );
    let ok = Program::<Ledger>::builder(Entry::anonymous("def f()\n  ledger_all()\nend\n"))
        .loader(&NoLoader)
        .frame(&permits, Budget::tree_walker_default())
        .load(&mut host);
    assert!(ok.is_ok());
}

#[derive(Debug, tatara_lisp::DeriveTataraDomain)]
#[tatara(keyword = "defcrate")]
struct Crate {
    name: String,
    size: i64,
}

#[derive(Default)]
struct Shelf {
    seen: Vec<String>,
}

#[host(prefix = "shelf_")]
impl Shelf {
    fn label(&mut self, text: &str) -> String {
        self.seen.push(text.to_owned());
        text.to_uppercase()
    }

    fn store(&mut self, c: blue_lang_host::Domain<Crate>) -> i64 {
        self.seen.push(c.0.name);
        c.0.size
    }
}

#[test]
fn a_str_parameter_borrows_and_a_domain_parameter_reads_a_map() {
    let src = "def go()\n  \"#{shelf_label(\"ab\")}:#{shelf_store({name: \"c\", size: 4})}\"\nend\n\ndef bad()\n  shelf_store({name: \"c\", sise: 4})\nend\n";
    let mut host = Shelf::default();
    let mut p = Program::<Shelf>::load_with(Entry::anonymous(src), &NoLoader, &mut host).unwrap();
    assert_eq!(p.call::<String>("go", (), &mut host).unwrap(), "AB:4");
    assert_eq!(host.seen, ["ab", "c"]);
    let err = p.call::<i64>("bad", (), &mut host).unwrap_err().to_string();
    assert!(err.contains("shelf_store") && err.contains("sise"), "{err}");
}

#[test]
fn a_program_that_is_not_canonical_is_refused_unless_the_host_says_as_written() {
    let src = "def f\n  1\nend\n";
    let mut host = ();
    let Err(err) = Program::<()>::load_with(Entry::anonymous(src), &NoLoader, &mut host) else {
        panic!("a non-canonical program loaded");
    };
    assert!(matches!(err, Error::NotCanonical(_)), "{err}");
    assert!(err.to_string().contains("blue fmt --write"), "{err}");
    let mut p = Program::<()>::builder(Entry::anonymous(src))
        .loader(&NoLoader)
        .canonical(Canonical::AsWritten)
        .load(&mut host)
        .unwrap();
    assert_eq!(p.call::<i64>("f", (), &mut host).unwrap(), 1);
}
