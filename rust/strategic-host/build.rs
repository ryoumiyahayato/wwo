fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=WWO_BUILD_SOURCE");
    println!("cargo:rerun-if-env-changed=WWO_BUILD_ALLOCATION");
    let output = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let source = std::env::var("WWO_BUILD_SOURCE").unwrap_or_else(|_| "unknown|unknown".into());
    std::fs::write(output.join("wwo-build-id.txt"), format!("0|{source}")).unwrap();
}
