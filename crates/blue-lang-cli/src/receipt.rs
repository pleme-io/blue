//! `blue run --receipts DIR` and `blue receipt verify FILE`.
//!
//! The run hands the runtime an [`Account`] that tallies host calls and knows
//! how to name a definition (`blue_lang_mondou::def_hash::identify`); each
//! held process writes its own receipt when an incarnation ends, and the run
//! writes one when it ends (`blue_lang_runtime::receipt`).

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_runtime::pipeline::{Run, RunError};
use blue_lang_runtime::{Account, Hold};

#[derive(clap::Subcommand)]
pub enum ReceiptCmd {
    /// Recompute a receipt's name from its bytes and check its form; any
    /// edit fails.
    Verify { file: PathBuf },
}

/// `blue receipt …`.
pub fn run(cmd: ReceiptCmd) -> ExitCode {
    match cmd {
        ReceiptCmd::Verify { file } => match blue_lang_runtime::receipt::verify(&file) {
            Ok(hash) => {
                println!("verified {hash}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("blue: {e}");
                ExitCode::FAILURE
            }
        },
    }
}

/// The account every `blue run` gives of itself: crash traces name their
/// definition's `def_hash`, and with `receipts` each held process writes a
/// receipt there.
pub fn account(receipts: Option<PathBuf>) -> Account {
    Account {
        identify: Some(blue_lang_mondou::def_hash::identify),
        receipts,
        ..Account::default()
    }
}

/// The hold a run with receipts runs under: its own, or the top, so every
/// host call goes through a counting shim.
pub fn hold_for(hold: Option<Hold>, receipts: Option<&Path>) -> Option<Hold> {
    match (hold, receipts) {
        (None, Some(_)) => Some(Hold::from(blue_lang_waku::Waku::top())),
        (hold, _) => hold,
    }
}

/// Write the run's receipt into `dir`. A receipt that cannot be written is
/// said and costs the run nothing.
pub fn write_run(
    dir: &Path,
    hold: Option<&Hold>,
    account: &Account,
    outcome: &Result<Run, RunError>,
) {
    let Some(hold) = hold else { return };
    let receipt = blue_lang_runtime::receipt::of_run(
        hold,
        account,
        blue_lang_runtime::receipt::exit_of(outcome),
    );
    if let Err(e) = blue_lang_runtime::receipt::write(dir, &receipt) {
        eprintln!(
            "blue: the run's receipt could not be written to {}: {e}",
            dir.display()
        );
    }
}
