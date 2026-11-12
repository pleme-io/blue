use std::path::Path;

use blue_lang_runtime::door::{Door, Ran};
use blue_lang_runtime::pipeline::Executor;

pub(crate) const ENV: &str = "BLUE_DOOR";

#[derive(Clone, Copy, Debug, PartialEq, Eq, clap::ValueEnum)]
pub(crate) enum DoorFlag {
    Auto,
    Walker,
    Vm,
}

impl DoorFlag {
    fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "" | "auto" => Some(DoorFlag::Auto),
            "walker" | "off" => Some(DoorFlag::Walker),
            "vm" => Some(DoorFlag::Vm),
            _ => None,
        }
    }
}

pub(crate) fn executor(
    vm: bool,
    flag: Option<DoorFlag>,
    env: Option<&str>,
) -> Result<Executor, String> {
    let chosen = match (vm, flag, env) {
        (true, Some(DoorFlag::Walker), _) => {
            return Err("`--vm` and `--door walker` name two doors; pass one".into())
        }
        (true, _, _) => DoorFlag::Vm,
        (false, Some(f), _) => f,
        (false, None, Some(v)) => DoorFlag::parse(v).ok_or_else(|| {
            format!("{ENV}=\"{v}\" names no door; it is auto, walker (or off) or vm")
        })?,
        (false, None, None) => DoorFlag::Auto,
    };
    Ok(match chosen {
        DoorFlag::Auto => Executor::Auto,
        DoorFlag::Walker => Executor::Walker,
        DoorFlag::Vm => Executor::Vm,
    })
}

pub(crate) struct Held {
    pub memo: bool,
    pub steps: bool,
    pub taped: bool,
    pub watched: bool,
}

impl Held {
    fn reason(&self) -> Option<&'static str> {
        if self.memo {
            Some("the memo is on, and it answers calls on the walker only")
        } else if self.steps {
            Some("--receipt-steps counts the walker's steps")
        } else if self.taped {
            Some("a recorded or replayed run is taped on the walker")
        } else if self.watched {
            Some("a watched run observes the walker's calls")
        } else {
            None
        }
    }
}

pub(crate) fn settle(
    executor: Executor,
    held: &Held,
    account: &blue_lang_runtime::Account,
) -> Executor {
    match (executor, held.reason()) {
        (Executor::Auto, Some(why)) => {
            if let Ok(mut slot) = account.door.lock() {
                *slot = Some(Door::chosen(Ran::Walker, why));
            }
            Executor::Walker
        }
        (e, _) => e,
    }
}

pub(crate) fn write(file: &Path, door: &Door) {
    let text = blue_lang_proc::receipt::canonical(&door.to_json());
    let written = file
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| std::fs::write(file, text));
    if let Err(e) = written {
        eprintln!(
            "blue: the run's door could not be written to {}: {e}",
            file.display()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_flag_beats_the_environment_and_auto_is_the_default() {
        assert_eq!(executor(false, None, None), Ok(Executor::Auto));
        assert_eq!(executor(false, None, Some("walker")), Ok(Executor::Walker));
        assert_eq!(executor(false, None, Some("off")), Ok(Executor::Walker));
        assert_eq!(
            executor(false, Some(DoorFlag::Vm), Some("walker")),
            Ok(Executor::Vm)
        );
        assert_eq!(executor(true, None, Some("walker")), Ok(Executor::Vm));
        assert!(executor(true, Some(DoorFlag::Walker), None).is_err());
        assert!(executor(false, None, Some("fast")).is_err());
    }

    #[test]
    fn a_held_run_stays_on_the_walker_and_names_why() {
        let account = blue_lang_runtime::Account::default();
        let held = Held {
            memo: true,
            steps: false,
            taped: false,
            watched: false,
        };
        assert_eq!(settle(Executor::Auto, &held, &account), Executor::Walker);
        let door = account.door.lock().unwrap().clone().unwrap();
        assert_eq!(door.ran, Ran::Walker);
        assert!(door.why.contains("memo"));
        let free = Held {
            memo: false,
            steps: false,
            taped: false,
            watched: false,
        };
        assert_eq!(
            settle(
                Executor::Auto,
                &free,
                &blue_lang_runtime::Account::default()
            ),
            Executor::Auto
        );
        assert_eq!(
            settle(Executor::Vm, &held, &blue_lang_runtime::Account::default()),
            Executor::Vm
        );
    }
}
