const invoke = window.__TAURI__.core.invoke;

const status = document.querySelector("#status"); const details = document.querySelector("#details"); const percent = document.querySelector("#percent"); const pace = document.querySelector("#pace"); const showPace = document.querySelector("#show-pace");
async function refresh() {
  status.textContent = "Reading local Claude Code and Codex data…";
  try {
    const data = await invoke("dashboard");
    percent.textContent = data.snapshot.headline_pct === null ? "—%" : `${Math.round(data.snapshot.headline_pct)}%`;
    status.textContent = data.snapshot.known ? `Codex usage is ${data.snapshot.state}.` : "No current local limit window found yet.";
    details.textContent = `${data.claude_events} Claude Code events · ${data.codex_events} Codex events`;
    pace.textContent = `${Math.round(data.pace)} output tokens/min · ${data.pace_level.replace("_", " ")}`;
  } catch (error) { status.textContent = "Could not read local usage data."; details.textContent = String(error); }
}
async function loadSettings() { const settings = await invoke("get_settings"); showPace.checked = settings.show_pace; pace.hidden = !settings.show_pace; }
showPace.addEventListener("change", async () => { const settings = await invoke("update_settings", { settings: { showPace: showPace.checked, compactWindow: false } }); pace.hidden = !settings.show_pace; showPace.checked = settings.show_pace; });
document.querySelector("#refresh").addEventListener("click", refresh);
await loadSettings(); await refresh();
