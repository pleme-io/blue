use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let Some(file) = args.next().map(PathBuf::from) else {
        eprintln!("blue-component: name the program to run (argv[1])");
        return ExitCode::from(64);
    };
    blue_lang_runtime::sys::set_program_args(args.collect());
    if let Some(dir) = file.parent().filter(|d| *d != Path::new("")) {
        if let Err(e) = std::env::set_current_dir(dir) {
            eprintln!("blue-component: {}: {e}", dir.display());
            return ExitCode::from(66);
        }
    }
    let text = match std::fs::read_to_string(&file) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("blue-component: {}: {e}", file.display());
            return ExitCode::from(66);
        }
    };
    let loader = blue_lang_pkg::load_path::LoadPath::for_entry(&file);
    match blue_lang_runtime::pipeline::run_framed(
        blue_lang_runtime::uses::Entry {
            path: Some(&file),
            text: &text,
        },
        blue_lang_runtime::inputs::Inputs::new(),
        &loader,
        None,
        None,
    ) {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("blue-component: {e}");
            ExitCode::FAILURE
        }
    }
}
