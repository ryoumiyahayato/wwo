use std::sync::OnceLock;

const RAW: &str = include_str!(concat!(env!("OUT_DIR"), "/wwo-build-id.txt"));

pub struct Identity {
    display: String,
    pub commit: &'static str,
    pub state: &'static str,
    pub number: u64,
}

pub fn get() -> &'static Identity {
    static IDENTITY: OnceLock<Identity> = OnceLock::new();
    IDENTITY.get_or_init(|| {
        let mut fields = RAW.split('|');
        let number = fields.next().and_then(|field| field.parse().ok()).unwrap_or(0);
        let commit = fields.next().unwrap_or("unknown");
        let state = fields.next().unwrap_or("unknown");
        let stage = env!("CARGO_PKG_VERSION");
        let short = commit.get(..9).unwrap_or(commit);
        let display = if number == 0 {
            format!("{stage} · {short} · unnumbered")
        } else {
            let dirty = if state == "dirty" { " dirty" } else { "" };
            format!("{stage} · {short}{dirty} · Build {number}")
        };
        Identity { display, commit, state, number }
    })
}

pub fn display() -> &'static str { &get().display }

pub fn window_title() -> String { format!("WWO | {}", display()) }

#[cfg(windows)]
pub fn check() -> std::io::Result<()> {
    let id = get();
    if id.number == 0 || id.commit.len() != 40 || !matches!(id.state, "dirty" | "clean") {
        return Err(std::io::Error::other("This WWO executable lacks a numbered build identity. Use the numbered Windows build or build with wwo-cargo.ps1."));
    }
    Ok(())
}
