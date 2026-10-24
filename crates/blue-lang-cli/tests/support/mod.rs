use std::process::{Command, Output};

pub fn run_fresh_script(command: impl Fn() -> Command) -> Output {
    (0..50)
        .find_map(|_| match command().output() {
            Err(e) if e.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                std::thread::sleep(std::time::Duration::from_millis(20));
                None
            }
            r => Some(r),
        })
        .expect("the script stayed busy for a second")
        .expect("the OS runs the script")
}
