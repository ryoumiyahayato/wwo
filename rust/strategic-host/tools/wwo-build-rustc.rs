use std::{env, ffi::OsString, fs, io, path::PathBuf, process::{Command, ExitCode}};

fn run() -> io::Result<ExitCode> {
    let mut args = env::args_os().skip(1);
    let compiler = args.next().expect("Cargo must provide rustc");
    let args: Vec<OsString> = args.collect();
    let option = |name: &str| {
        args.windows(2).find(|pair| pair[0] == name).and_then(|pair| pair[1].to_str())
    };
    let linked = args.iter().any(|arg| arg.to_str().and_then(|arg| arg.strip_prefix("--emit="))
        .is_some_and(|kinds| kinds.split(',').any(|kind| kind == "link")));
    if linked && option("--crate-name") == Some("wwo_map_lab")
        && !args.iter().any(|arg| arg == "--test")
        && env::var_os("WWO_BUILD_ALLOCATION").as_deref() != Some(std::ffi::OsStr::new("validation"))
    {
        let receipt = PathBuf::from(env::var_os("WWO_BUILD_RECEIPT")
            .ok_or_else(|| io::Error::other("WWO build receipt path missing"))?);
        let number = match fs::read_to_string(&receipt) {
            Ok(number) => number,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let shell = env::var_os("WWO_BUILD_SHELL").ok_or_else(|| io::Error::other("WWO build shell missing"))?;
                let script = env::var_os("WWO_BUILD_ALLOCATOR").ok_or_else(|| io::Error::other("WWO build allocator missing"))?;
                let output = Command::new(shell).args(["-NoProfile", "-NonInteractive", "-File"]).arg(script).output()?;
                if !output.status.success() {
                    return Err(io::Error::other(format!("Build number allocation failed: {}", String::from_utf8_lossy(&output.stderr))));
                }
                let number = String::from_utf8_lossy(&output.stdout).trim().to_owned();
                if !number.parse::<u64>().is_ok_and(|number| number > 0) {
                    return Err(io::Error::other("The allocator returned an invalid WWO build number"));
                }
                fs::write(&receipt, &number)?;
                number
            }
            Err(error) => return Err(error),
        };
        let source = env::var("WWO_BUILD_SOURCE").map_err(io::Error::other)?;
        let out = PathBuf::from(env::var_os("OUT_DIR").ok_or_else(|| io::Error::other("WWO build output directory missing"))?);
        let identity = format!("{number}|{source}");
        let destination = out.join("wwo-build-id.txt");
        if fs::read_to_string(&destination).as_deref().ok() != Some(&identity) {
            fs::write(destination, identity)?;
        }
    }
    let status = Command::new(compiler).args(args).status()?;
    Ok(ExitCode::from(status.code().and_then(|code| u8::try_from(code).ok()).unwrap_or(1)))
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("WWO build identity: {error}");
            ExitCode::FAILURE
        }
    }
}
