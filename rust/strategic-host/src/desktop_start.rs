use std::{env, fs::{self, File, OpenOptions}, io, os::windows::process::CommandExt,
    path::{Path, PathBuf}, process::{Child, Command}, thread, time::{Duration, Instant, SystemTime, UNIX_EPOCH}};
use crate::{formal_ui::Session, state::Request};
use wwo_map_lab::formal_clock::TimeControl;

pub(crate) const TICK_INTERVAL: Duration = Duration::from_millis(250);

pub(crate) fn runtime_directory() -> io::Result<PathBuf> {
    let local = env::var_os("LOCALAPPDATA").ok_or_else(|| io::Error::other("找不到 Windows 用户数据目录。"))?;
    Ok(PathBuf::from(local).join("WWO-Rust-Candidate"))
}

pub(crate) fn configured_data() -> io::Result<Option<PathBuf>> {
    #[derive(serde::Deserialize)]
    struct RuntimeConfig { data_directory: PathBuf, program_directory: Option<PathBuf> }

    let path = runtime_directory()?.join("runtime.json");
    let file = match File::open(&path) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(io::Error::other(format!("{} · {error}", path.display()))),
    };
    let config: RuntimeConfig = serde_json::from_reader(file)
        .map_err(|error| io::Error::other(format!("{} · {error}", path.display())))?;
    if !config.data_directory.is_absolute() {
        return Err(io::Error::other(format!("{} · data_directory 需要使用绝对路径。", path.display())));
    }
    if let Some(directory)=config.program_directory {
        if !directory.is_absolute() {
            return Err(io::Error::other(format!("{} · program_directory 需要使用绝对路径。",path.display())));
        }
        if env::args_os().nth(1).is_none() {
            let expected=directory.join("wwo-map-lab.exe").canonicalize().map_err(|error|
                io::Error::other(format!("无法打开正式程序目录 {} · {error}",directory.display())))?;
            if env::current_exe()?.canonicalize()?!=expected {
                return Err(io::Error::other(format!("请从正式程序路径启动 · {}",expected.display())));
            }
        }
    }
    Ok(Some(config.data_directory))
}

pub(crate) fn write_runtime_log(text: &str) {
    let Ok(dir) = runtime_directory() else { return; };
    if fs::create_dir_all(&dir).is_err() { return; }
    let mut end = text.len().min(32 * 1024);
    while !text.is_char_boundary(end) { end -= 1; }
    let _ = fs::write(dir.join("startup.log"), &text[..end]);
}

pub(crate) fn notify_program_update(message: &str) {
    static NOTIFIED: std::sync::OnceLock<()> = std::sync::OnceLock::new();
    NOTIFIED.get_or_init(|| {
        if let Some(path) = env::var_os("WWO_UPDATE_READY_FILE") {
            let _ = fs::write(path, message);
        }
    });
}

pub(crate) fn attach_parent_console() {
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn AttachConsole(process: u32) -> i32;
        fn GetStdHandle(kind: u32) -> *mut core::ffi::c_void;
    }
    unsafe {
        let output = GetStdHandle(-11i32 as u32);
        if output.is_null() || output as isize == -1 {
            AttachConsole(u32::MAX);
        }
    }
}

pub(crate) fn require_writable_directory(path: &Path) -> io::Result<()> {
    use std::os::windows::fs::OpenOptionsExt;
    // FILE_ADD_FILE | FILE_DELETE_CHILD and FILE_FLAG_BACKUP_SEMANTICS.
    OpenOptions::new().access_mode(0x42).custom_flags(0x0200_0000).open(path)
        .map(drop).map_err(|error| io::Error::other(format!("目录无法写入或替换文件 · {} · {error}", path.display())))
}

pub(crate) fn lock_profile() -> io::Result<(PathBuf, File)> {
    let profile = env::var("WWO_RUST_PROFILE").unwrap_or_else(|_| "Default".into());
    if profile.is_empty() || profile.len() > 40 || !profile.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-')) {
        return Err(io::Error::other("WWO_RUST_PROFILE 无效。"));
    }
    let profile = runtime_directory()?.join("profiles").join(profile);
    fs::create_dir_all(profile.join("WWO_R68_Candidate"))
        .map_err(|e| io::Error::other(format!("无法创建档案目录 {} · {e}", profile.display())))?;
    let path = profile.join("session.lock");
    let lock = OpenOptions::new().create(true).truncate(false).read(true).write(true).open(&path)
        .map_err(|e| io::Error::other(format!("无法打开会话锁 {} · {e}", path.display())))?;
    lock.try_lock().map_err(|e| io::Error::other(format!("档案正在使用，或无法锁定 {} · {e}", path.display())))?;
    Ok((profile, lock))
}

pub struct DesktopSession {
    pub state: PathBuf,
    pub requests: PathBuf,
    pub preferences: PathBuf,
    control: PathBuf,
    child: Child,
    _slot_lock: File,
    clock_world: String,
    tick_serial: u64,
    awaiting_tick: bool,
    next_tick: Instant,
}

impl DesktopSession {
    pub fn start(home: &Path) -> io::Result<Self> {
        let project = env::var_os("WWO_R68_PROJECT").map(PathBuf::from)
            .or_else(|| home.ancestors().map(|folder| folder.join("wwo-r68-candidate"))
                .find(|folder| folder.join("project.godot").is_file()))
            .ok_or_else(|| io::Error::other("找不到 R68 项目。请设置 WWO_R68_PROJECT 指向 R68 源码目录。"))?;
        if !project.join("project.godot").is_file() {
            return Err(io::Error::other(format!("该目录没有 R68 项目文件\n{}", project.display())));
        }
        let godot = env::var_os("WWO_GODOT_EXE").map(PathBuf::from)
            .or_else(|| [home.join("Godot_v4.6.3-stable_win64_console.exe"),
                PathBuf::from("D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64_console.exe")]
                .into_iter().find(|file| file.is_file()))
            .ok_or_else(|| io::Error::other("找不到 Godot 4.6.3。请设置 WWO_GODOT_EXE 指向 Godot 程序。"))?;
        let script = home.join("tools/formal_host_bridge.gd");
        if !script.is_file() { return Err(io::Error::other(format!("缺少会话文件\n{}", script.display()))); }

        let (profile, lock) = lock_profile()?;

        let time = SystemTime::now().duration_since(UNIX_EPOCH).map_err(io::Error::other)?.as_nanos();
        let dir = env::temp_dir().join(format!("WWO-V-desktop-{}-{time}", std::process::id()));
        fs::create_dir(&dir)?;
        let control = dir.join("godot-control.json");
        let child = Command::new(godot).current_dir(&project).arg("--path").arg(&project)
            .arg("--script").arg(script).arg("--log-file").arg(dir.join("godot.log"))
            .args(["--", "--dev-preview", "--dev-background", "--rust-menu", "--rust-clock"])
            .arg(format!("--observe-file={}", control.display())).arg(format!("--formal-bridge={}", dir.display()))
            .env("APPDATA", &profile).env("LOCALAPPDATA", &profile).env("WWO_DEV_USER_ROOT", &profile)
            .env("WWO_FORMAL_CHARACTER_BRIDGE", &dir)
            .env_remove("WWO_DEV_RESUME").creation_flags(0x0800_0000).spawn()?;
        Ok(Self { state: dir.join("world.json"), requests: dir.join("requests.ndjson"),
            preferences: profile.join("WWO_R68_Candidate/interface_settings.cfg"), control, child,
            _slot_lock: lock, clock_world: String::new(), tick_serial: 0, awaiting_tick: false,
            next_tick: Instant::now() + TICK_INTERVAL })
    }

    pub fn poll(&mut self) {
        if let Some(folder) = self.state.parent() {
            let _ = wwo_map_lab::formal_character::poll(folder);
        }
        if let Ok(Some(status)) = self.child.try_wait() {
            let marker = self.state.with_file_name("bridge-exited");
            if !marker.exists() { let _ = fs::write(marker, status.to_string()); }
        }
    }

    pub fn tick_clock(&mut self, session: Option<&Session>, now: Instant) -> io::Result<()> {
        let Some((session, clock)) = session.and_then(|s| s.rust_clock.as_ref().map(|clock| (s, clock))) else {
            self.clock_world.clear();
            self.awaiting_tick = false;
            return Ok(());
        };
        if self.clock_world != clock.world {
            self.clock_world.clone_from(&clock.world);
            self.awaiting_tick = false;
            self.next_tick = now + TICK_INTERVAL;
        }
        if clock.tick_ack == self.tick_serial {
            self.awaiting_tick = false;
        }
        if session.paused {
            self.next_tick = now + TICK_INTERVAL;
            return Ok(());
        }
        if self.awaiting_tick || now < self.next_tick {
            return Ok(());
        }

        let control = TimeControl { paused: session.paused, speed: i64::from(session.speed) };
        if let Some(minutes) = control.tick() {
            let serial = self.tick_serial + 1;
            self.next_tick = now + TICK_INTERVAL;
            Request::ClockTick {
                world: &clock.world, serial, expected_minute: session.total_minutes,
                speed: session.speed, minutes,
            }.output(Some(&self.requests))?;
            self.tick_serial = serial;
            self.awaiting_tick = true;
        }
        Ok(())
    }
}

impl Drop for DesktopSession {
    fn drop(&mut self) {
        if matches!(self.child.try_wait(), Ok(Some(_))) { return; }
        let temporary = self.control.with_extension("tmp");
        if fs::write(&temporary, r#"{"id":"desktop-quit","action":"quit"}"#).is_ok() {
            let _ = fs::rename(temporary, &self.control);
        }
        let until = Instant::now() + Duration::from_secs(5);
        while Instant::now() < until && matches!(self.child.try_wait(), Ok(None)) {
            thread::sleep(Duration::from_millis(50));
        }
    }
}

pub fn show_error(message: &str) {
    #[link(name = "user32")]
    unsafe extern "system" {
        fn MessageBoxW(window: *mut core::ffi::c_void, text: *const u16, caption: *const u16, flags: u32) -> i32;
    }
    let text: Vec<_> = message.encode_utf16().chain([0]).collect();
    let title: Vec<_> = "WWO 启动失败".encode_utf16().chain([0]).collect();
    unsafe { MessageBoxW(std::ptr::null_mut(), text.as_ptr(), title.as_ptr(), 0x10); }
}

/// After moving our window off screen, release focus without reactivating it.
/// A permanently hidden Vulkan surface receives no redraws on this Windows path.
pub fn debug_release_focus(window:&winit::window::Window) {
    use winit::raw_window_handle::{HasWindowHandle,RawWindowHandle};
    if let Ok(handle)=window.window_handle() {
        if let RawWindowHandle::Win32(handle)=handle.as_raw() {
            #[link(name="user32")]
            unsafe extern "system" {fn ShowWindow(window:*mut core::ffi::c_void,command:i32)->i32;}
            // SW_HIDE then SW_SHOWNOACTIVATE, at the existing off-screen position.
            unsafe {
                ShowWindow(handle.hwnd.get() as *mut core::ffi::c_void,0);
                ShowWindow(handle.hwnd.get() as *mut core::ffi::c_void,4);
            }
        }
    }
}
