use blue_lang_host::{host, CallError, Entry, Error, Host, NoLoader, Program};

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
    assert_eq!(names, ["ledger_add", "ledger_all", "repeat"]);
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
