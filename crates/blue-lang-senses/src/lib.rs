#![deny(unsafe_code)]

pub mod audio;
pub mod canvas;
pub mod display;
mod font;
#[cfg(unix)]
mod seam;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refusal {
    Unsupported(String),
    NotFound(String),
    Denied(String),
    Refused(String),
    Timeout(String),
}

impl Refusal {
    #[must_use]
    pub fn kind(&self) -> &'static str {
        match self {
            Refusal::Unsupported(_) => "unsupported",
            Refusal::NotFound(_) => "not_found",
            Refusal::Denied(_) => "permission_denied",
            Refusal::Refused(_) => "refused",
            Refusal::Timeout(_) => "timeout",
        }
    }

    #[must_use]
    pub fn message(&self) -> &str {
        match self {
            Refusal::Unsupported(m)
            | Refusal::NotFound(m)
            | Refusal::Denied(m)
            | Refusal::Refused(m)
            | Refusal::Timeout(m) => m,
        }
    }
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.kind(), self.message())
    }
}

impl std::error::Error for Refusal {}
