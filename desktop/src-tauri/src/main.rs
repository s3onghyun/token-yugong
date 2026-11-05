use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf, sync::Mutex, time::{Duration, SystemTime, UNIX_EPOCH}};
use tauri::{image::Image, menu::{Menu, MenuItem}, tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent}, AppHandle, Manager, State};
use yugong_core::{evaluate, pace_level, pace_rate, scan_local_data, Snapshot};

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
struct Settings { show_pace: bool, compact_window: bool }

struct AppState { settings: Mutex<Settings>, settings_path: PathBuf }

#[derive(Serialize)]
struct Dashboard { snapshot: Snapshot, pace: f64, pace_level: String, claude_events: usize, codex_events: usize }

fn show_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") { let _ = window.show(); let _ = window.set_focus(); }
}

fn pixel_yugong(frame: u8, pct: u8) -> Image<'static> {
    // Compact panel rendering; the full existing animation is copied unchanged from docs/hero.gif at build time.
    let mut rgba = vec![0; 16 * 16 * 4];
    let mut put = |x: usize, y: usize, color: [u8; 4]| { let index = (y * 16 + x) * 4; rgba[index..index + 4].copy_from_slice(&color); };
    let skin = [239, 187, 137, 255]; let blue = [47, 94, 143, 255]; let dark = [55, 46, 39, 255]; let earth = [150, 97, 58, 255];
    for y in 3..7 { for x in 6..10 { put(x, y, skin); } }
    for y in 7..13 { for x in 5..11 { put(x, y, blue); } }
    for x in 4..12 { put(x, 2, dark); }
    put(if frame % 2 == 0 { 4 } else { 3 }, 11, skin); put(if frame % 2 == 0 { 11 } else { 12 }, 11, skin);
    for x in 2..6 { put(x, 13, earth); }
    for x in 0..(pct as usize * 16 / 100).min(16) { put(x, 15, [96, 181, 107, 255]); }
    Image::new_owned(rgba, 16, 16)
}

fn save_settings(path: &PathBuf, settings: &Settings) -> Result<(), String> {
    if let Some(parent) = path.parent() { fs::create_dir_all(parent).map_err(|error| error.to_string())?; }
    fs::write(path, serde_json::to_vec_pretty(settings).map_err(|error| error.to_string())?).map_err(|error| error.to_string())
}

#[tauri::command]
fn dashboard() -> Dashboard {
    let summary = scan_local_data(); let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() as i64;
    let events = summary.claude_events.iter().chain(summary.codex_events.iter()).cloned().collect::<Vec<_>>(); let pace = pace_rate(&events, now);
    Dashboard { snapshot: evaluate(summary.codex_reading.as_ref(), now), pace, pace_level: pace_level(pace).to_owned(), claude_events: summary.claude_events.len(), codex_events: summary.codex_events.len() }
}

#[tauri::command]
fn get_settings(state: State<'_, AppState>) -> Settings { state.settings.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).clone() }

#[tauri::command]
fn update_settings(settings: Settings, state: State<'_, AppState>) -> Result<Settings, String> {
    save_settings(&state.settings_path, &settings)?; *state.settings.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = settings.clone(); Ok(settings)
}

fn main() {
    tauri::Builder::default().setup(|app| {
        let settings_path = app.path().app_config_dir()?.join("settings.json");
        let settings = fs::read(&settings_path).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default();
        app.manage(AppState { settings: Mutex::new(settings), settings_path });
        let open = MenuItem::with_id(app, "open", "Open Token Yugong", true, None::<&str>)?;
        let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
        let menu = Menu::with_items(app, &[&open, &quit])?;
        let tray = TrayIconBuilder::with_id("yugong").menu(&menu).title("—%").tooltip("Token Yugong — local usage only").icon(pixel_yugong(0, 0)).show_menu_on_left_click(true)
            .on_menu_event(|app, event| match event.id().as_ref() { "open" => show_window(app), "quit" => app.exit(0), _ => {} })
            .on_tray_icon_event(|tray, event| { if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event { show_window(&tray.app_handle()); } }).build(app)?;
        std::thread::spawn(move || {
            let mut frame = 0_u8;
            let mut ticks = 40_u8;
            let mut pct = 0_u8;
            loop {
                // Reading session files can be expensive, so the icon keeps animating at 4 fps
                // while usage is refreshed only every ten seconds.
                if ticks >= 40 {
                    let summary = scan_local_data();
                    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() as i64;
                    pct = evaluate(summary.codex_reading.as_ref(), now).headline_pct.unwrap_or(0.0).round().clamp(0.0, 100.0) as u8;
                    let label = format!("{pct}%");
                    let _ = tray.set_title(Some(label.as_str())); // StatusNotifierItem label on Linux.
                    let _ = tray.set_tooltip(Some(format!("Token Yugong — {label}"))); // Windows notification-area text.
                    ticks = 0;
                }
                let _ = tray.set_icon(Some(pixel_yugong(frame, pct)));
                frame = frame.wrapping_add(1);
                ticks = ticks.saturating_add(1);
                std::thread::sleep(Duration::from_millis(250));
            }
        });
        Ok(())
    }).invoke_handler(tauri::generate_handler![dashboard, get_settings, update_settings]).run(tauri::generate_context!()).expect("Token Yugong desktop shell failed");
}
