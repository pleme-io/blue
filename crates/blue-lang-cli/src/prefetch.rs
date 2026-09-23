//! The real [`Prefetch`]: `nix flake prefetch --json <url>`.
//!
//! The only process `blue lock` starts, and the reason it lives behind
//! `blue_lang_pkg::lock::Prefetch`: every test of the lock supplies canned
//! output instead, so none of them reaches the network. This file therefore
//! has no test of its own that runs nix; its output is read by
//! `blue_lang_pkg::lock::pin_of`, which is tested against the exact bytes this
//! command printed on nix 2.31.5.
//!
//! Direction, stated because it is the point: **blue calls nix, nix never calls
//! blue** — so pinning a source costs no import-from-derivation.

use std::process::{Command, ExitStatus};

use blue_lang_pkg::lock::Prefetch;

/// Pins through the `nix` on `PATH`.
pub struct NixPrefetch;

/// Why the `nix` process gave no usable answer.
#[derive(Debug, thiserror::Error)]
pub enum NixPrefetchError {
    #[error("could not start `nix`: {0}")]
    Spawn(#[source] std::io::Error),
    #[error("`nix flake prefetch --json` exited with {status}: {stderr}")]
    Exit { status: ExitStatus, stderr: String },
    #[error("`nix flake prefetch --json` printed output that is not UTF-8")]
    NotUtf8(#[source] std::string::FromUtf8Error),
}

impl Prefetch for NixPrefetch {
    fn prefetch(&self, url: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // The features named explicitly, so a nix without them enabled in its
        // own config still answers rather than refusing the subcommand.
        let out = Command::new("nix")
            .args([
                "--extra-experimental-features",
                "nix-command flakes",
                "flake",
                "prefetch",
                "--json",
                url,
            ])
            .output()
            .map_err(NixPrefetchError::Spawn)?;
        if !out.status.success() {
            return Err(NixPrefetchError::Exit {
                status: out.status,
                stderr: String::from_utf8_lossy(&out.stderr).trim().to_string(),
            }
            .into());
        }
        Ok(String::from_utf8(out.stdout).map_err(NixPrefetchError::NotUtf8)?)
    }
}
