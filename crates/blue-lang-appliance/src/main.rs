//! `blue-appliance`: the runner a sealed payload is appended to. It takes no
//! flags: every argument is the program's, and the program runs held to the
//! policy sealed with it (`blue_lang_pkg::appliance`).

use std::process::ExitCode;

use blue_lang_pkg::appliance;

fn main() -> ExitCode {
    let payload = match appliance::open_self() {
        Ok(p) => p,
        Err(refusal) => {
            eprintln!("blue-appliance: {refusal}");
            return ExitCode::from(refusal.exit_status());
        }
    };
    blue_lang_runtime::sys::set_program_args(std::env::args().skip(1).collect());
    match appliance::run(&payload) {
        Ok(_) => ExitCode::SUCCESS,
        Err(failure) => {
            eprintln!("{}: {failure}", payload.name);
            ExitCode::from(failure.exit_status())
        }
    }
}
