//! Named characters only. The host owns world time, population, money, assets,
//! relationships and authority. This crate owns health and learned capability.
//! Save snapshots are privileged backend data; only `PersonView` goes to a UI.
mod action;
mod health;
mod model;
mod system;

pub use action::*;
pub use health::*;
pub use model::*;
pub use system::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub String);
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}
impl std::error::Error for Error {}
pub type Result<T> = std::result::Result<T, Error>;
pub(crate) fn require(ok: bool, message: &str) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(Error(message.into()))
    }
}
pub(crate) fn valid_text(s: &str) -> bool {
    !s.trim().is_empty() && s.len() <= 512 && !s.chars().any(char::is_control)
}
