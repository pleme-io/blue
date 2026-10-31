use std::num::NonZeroUsize;

pub const ENV: &str = "BLUE_TEST_STACK";

pub const DEFAULT_MIB: NonZeroUsize = NonZeroUsize::new(64).unwrap();

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stack {
    Inherit,
    Mib(NonZeroUsize),
}

impl Stack {
    pub fn from_setting(setting: Option<&str>) -> Result<Self, String> {
        match setting.map(str::trim) {
            None | Some("") => Ok(Self::Mib(DEFAULT_MIB)),
            Some("inherit") => Ok(Self::Inherit),
            Some(v) => v.parse::<NonZeroUsize>().map(Self::Mib).map_err(|_| {
                format!("{ENV} is {v:?}; it takes inherit, or a whole number of MiB above 0")
            }),
        }
    }

    pub fn configured() -> Self {
        let setting = match std::env::var(ENV) {
            Ok(v) => Some(v),
            Err(std::env::VarError::NotPresent) => None,
            Err(std::env::VarError::NotUnicode(v)) => {
                panic!("{ENV} is {v:?}; it takes inherit, or a whole number of MiB above 0")
            }
        };
        Self::from_setting(setting.as_deref()).unwrap_or_else(|why| panic!("{why}"))
    }
}

pub fn run<T: Send>(body: impl FnOnce() -> T + Send) -> T {
    run_on(Stack::configured(), body)
}

pub fn run_on<T: Send>(stack: Stack, body: impl FnOnce() -> T + Send) -> T {
    let Stack::Mib(mib) = stack else {
        return body();
    };
    let name = std::thread::current()
        .name()
        .unwrap_or("blue-test-stack")
        .to_string();
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name(name)
            .stack_size(mib.get() << 20)
            .spawn_scoped(scope, body)
            .unwrap_or_else(|e| panic!("could not start a thread with a {mib} MiB stack: {e}"))
            .join()
            .unwrap_or_else(|payload| std::panic::resume_unwind(payload))
    })
}

#[cfg(test)]
mod tests {
    use super::{run_on, Stack, DEFAULT_MIB};
    use std::num::NonZeroUsize;

    #[test]
    fn the_setting_is_the_default_inherit_or_a_size_and_nothing_else() {
        assert_eq!(Stack::from_setting(None), Ok(Stack::Mib(DEFAULT_MIB)));
        assert_eq!(Stack::from_setting(Some("")), Ok(Stack::Mib(DEFAULT_MIB)));
        assert_eq!(Stack::from_setting(Some("inherit")), Ok(Stack::Inherit));
        assert_eq!(
            Stack::from_setting(Some("16")),
            Ok(Stack::Mib(NonZeroUsize::new(16).unwrap()))
        );
        for bad in ["0", "-1", "off", "16MiB", "1.5"] {
            let why = Stack::from_setting(Some(bad)).expect_err(bad);
            assert!(
                why.contains("BLUE_TEST_STACK") && why.contains("inherit"),
                "{why}"
            );
        }
    }

    #[test]
    fn a_sized_stack_runs_the_body_on_its_own_thread_named_for_the_caller() {
        let caller = std::thread::current().id();
        let caller_name = std::thread::current().name().map(str::to_string);
        let (id, name) = run_on(Stack::Mib(NonZeroUsize::new(4).unwrap()), || {
            (
                std::thread::current().id(),
                std::thread::current().name().map(str::to_string),
            )
        });
        assert_ne!(id, caller);
        assert_eq!(name, caller_name);
    }

    #[test]
    fn inherit_runs_the_body_on_the_calling_thread() {
        let caller = std::thread::current().id();
        assert_eq!(
            run_on(Stack::Inherit, || std::thread::current().id()),
            caller
        );
    }

    #[test]
    fn a_panic_in_the_body_reaches_the_caller_with_its_message() {
        let caught = std::panic::catch_unwind(|| {
            run_on(Stack::Mib(DEFAULT_MIB), || panic!("the body's own words"))
        })
        .expect_err("the panic must propagate");
        let text = caught
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| caught.downcast_ref::<String>().cloned());
        assert_eq!(text.as_deref(), Some("the body's own words"));
    }

    #[test]
    fn a_body_deeper_than_the_harness_stack_completes_on_the_default_stack() {
        fn depth(n: u64) -> u64 {
            let pad = std::hint::black_box([n; 64]);
            if n == 0 {
                0
            } else {
                pad[0].min(1) + depth(n - 1)
            }
        }
        assert_eq!(
            run_on(Stack::Mib(DEFAULT_MIB), || depth(std::hint::black_box(
                20_000
            ))),
            20_000
        );
    }
}
