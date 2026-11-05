//! Platform-neutral local usage readers and display rules for Token Yugong.
//!
//! The macOS app remains Swift. Behaviour shared with this crate is specified by
//! `desktop/shared/usage-pace-vectors.json`, derived from `LogicTests.swift`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{env, fs, path::{Path, PathBuf}};

pub const FIVE_HOURS: i64 = 5 * 60 * 60;
pub const WEEK: i64 = 7 * 24 * 60 * 60;

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct Meter {
    pub pct: f64,
    pub resets_at: Option<i64>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct Reading {
    pub five: Option<Meter>,
    pub week: Option<Meter>,
    pub at: i64,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct UsageEvent {
    pub at: i64,
    pub output_tokens: u64,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct ScanSummary {
    pub claude_events: Vec<UsageEvent>,
    pub codex_events: Vec<UsageEvent>,
    pub codex_reading: Option<Reading>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct Snapshot {
    pub known: bool,
    pub headline_pct: Option<f64>,
    pub five: Option<Meter>,
    pub week: Option<Meter>,
    pub daily_fill: Option<f64>,
    pub resting: bool,
    pub state: String,
    pub projected: Option<f64>,
}

fn rolled(meter: &Option<Meter>, now: i64) -> Option<Meter> {
    meter.as_ref().map(|m| {
        if m.resets_at.is_some_and(|reset| reset <= now) {
            Meter { pct: 0.0, resets_at: None }
        } else {
            meter.clone().expect("meter is present")
        }
    })
}

fn projection(meter: &Meter, seconds: i64, now: i64) -> Option<f64> {
    meter.resets_at.filter(|reset| *reset > now).map(|reset| {
        let elapsed = 1.0 - (reset - now) as f64 / seconds as f64;
        meter.pct / elapsed.clamp(0.12, 1.0)
    })
}

/// Evaluates the same five-hour / weekly display rules as `Logic.evaluate`.
pub fn evaluate(reading: Option<&Reading>, now: i64) -> Snapshot {
    let Some(reading) = reading else {
        return Snapshot { known: false, headline_pct: None, five: None, week: None, daily_fill: None, resting: false, state: "lively".into(), projected: None };
    };
    let five = rolled(&reading.five, now);
    let week = rolled(&reading.week, now);
    let resting = [five.as_ref(), week.as_ref()].into_iter().flatten().any(|m| m.pct >= 100.0);
    let daily_fill = if five.is_none() {
        week.as_ref().and_then(|meter| meter.resets_at.map(|reset| {
            let start = reset - WEEK;
            let day = ((now - start).div_euclid(86_400)).clamp(0, 6);
            ((meter.pct - day as f64 * (100.0 / 7.0)) / (100.0 / 7.0)).max(0.0)
        }))
    } else { None };
    let projected = [five.as_ref().and_then(|m| projection(m, FIVE_HOURS, now)), week.as_ref().and_then(|m| projection(m, WEEK, now))]
        .into_iter().flatten().max_by(f64::total_cmp);
    let just_reset = reading.five.as_ref().and_then(|m| m.resets_at).is_some_and(|r| r <= now && now - r < 300)
        || reading.week.as_ref().and_then(|m| m.resets_at).is_some_and(|r| r <= now && now - r < 300)
        || (five.is_none() && week.as_ref().and_then(|m| m.resets_at).is_some_and(|r| {
            let start = r - WEEK;
            let day_start = start + ((now - start).div_euclid(86_400)).clamp(0, 6) * 86_400;
            now >= day_start && now - day_start < 300
        }));
    let top = [five.as_ref(), week.as_ref()].into_iter().flatten().map(|m| m.pct).fold(0.0, f64::max);
    let state = if resting { "resting" } else if just_reset { "morning" } else if let Some(fill) = daily_fill {
        if fill >= 1.0 { "straining" } else if fill >= 0.75 { "steady" } else { "lively" }
    } else if top >= 80.0 || projected.unwrap_or(top) >= 110.0 { "straining" } else if projected.unwrap_or(top) >= 75.0 { "steady" } else { "lively" };
    let headline_pct = five.as_ref().or(week.as_ref()).map(|m| m.pct);
    Snapshot { known: true, headline_pct, five, week, daily_fill, resting, state: state.into(), projected }
}

pub fn pace_rate(events: &[UsageEvent], now: i64) -> f64 {
    events.iter().filter(|event| event.at > now - 180 && event.at <= now).map(|event| event.output_tokens).sum::<u64>() as f64 / 3.0
}

pub fn pace_level(rate: f64) -> &'static str {
    if rate >= 8_000.0 { "veryHigh" } else if rate >= 2_000.0 { "high" } else if rate >= 50.0 { "low" } else { "idle" }
}

fn unix_timestamp(value: &Value) -> Option<i64> {
    value.as_str().and_then(|timestamp| DateTime::parse_from_rfc3339(timestamp).ok()).map(|value| value.with_timezone(&Utc).timestamp())
}

/// Parses one Claude Code assistant JSONL record. API-error records and malformed lines are ignored.
pub fn parse_claude_line(line: &str) -> Option<UsageEvent> {
    let value: Value = serde_json::from_str(line).ok()?;
    if value["type"] != "assistant" || value["isApiErrorMessage"] == true { return None; }
    let output_tokens = value["message"]["usage"]["output_tokens"].as_u64()?;
    Some(UsageEvent { at: unix_timestamp(&value["timestamp"] )?, output_tokens })
}

fn meter(value: &Value, pct_key: &str) -> Option<Meter> {
    let pct = value[pct_key].as_f64()?.clamp(0.0, 100.0);
    if !pct.is_finite() { return None; }
    Some(Meter { pct, resets_at: value["resets_at"].as_i64() })
}

/// Parses Codex `token_count` rollout records and keeps only 300-minute and weekly windows.
pub fn parse_codex_line(line: &str) -> Option<(Option<UsageEvent>, Option<Reading>)> {
    let value: Value = serde_json::from_str(line).ok()?;
    if value["payload"]["type"] != "token_count" { return None; }
    let at = unix_timestamp(&value["timestamp"])?;
    let usage = value["payload"]["info"]["last_token_usage"]["output_tokens"].as_u64().map(|output_tokens| UsageEvent { at, output_tokens });
    let limits = &value["payload"]["rate_limits"];
    let mut five = None;
    let mut week = None;
    for key in ["primary", "secondary"] {
        let window = &limits[key];
        match window["window_minutes"].as_i64() {
            Some(300) => five = meter(window, "used_percent"),
            Some(10_080) => week = meter(window, "used_percent"),
            _ => {}
        }
    }
    let reading = (five.is_some() || week.is_some()).then_some(Reading { five, week, at });
    Some((usage, reading))
}

pub fn local_data_paths() -> (PathBuf, PathBuf) {
    let home = env::var_os("USERPROFILE").or_else(|| env::var_os("HOME")).map(PathBuf::from).unwrap_or_default();
    let codex_home = env::var_os("CODEX_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".codex"));
    (home.join(".claude").join("projects"), codex_home.join("sessions"))
}

fn jsonl_files(root: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(root) else { return; };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() { jsonl_files(&path, files); }
        else if path.extension().is_some_and(|extension| extension == "jsonl") { files.push(path); }
    }
}

/// Reads only local CLI data. No prompts, credentials, or network requests are used.
pub fn scan_local_data() -> ScanSummary {
    let (claude_root, codex_root) = local_data_paths();
    let mut claude_files = Vec::new();
    let mut codex_files = Vec::new();
    jsonl_files(&claude_root, &mut claude_files);
    jsonl_files(&codex_root, &mut codex_files);
    let mut claude_events = Vec::new();
    for file in claude_files { if let Ok(text) = fs::read_to_string(file) { claude_events.extend(text.lines().filter_map(parse_claude_line)); } }
    let mut codex_events = Vec::new();
    let mut codex_reading = None;
    for file in codex_files {
        if let Ok(text) = fs::read_to_string(file) {
            for (event, reading) in text.lines().filter_map(parse_codex_line) {
                if let Some(event) = event { codex_events.push(event); }
                if reading.as_ref().is_some_and(|next| codex_reading.as_ref().is_none_or(|current: &Reading| next.at > current.at)) { codex_reading = reading; }
            }
        }
    }
    claude_events.sort_by_key(|event| event.at);
    codex_events.sort_by_key(|event| event.at);
    ScanSummary { claude_events, codex_events, codex_reading }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)] struct Vectors { logic: Vec<LogicVector>, pace: Vec<PaceVector> }
    #[derive(Deserialize)] struct LogicVector { now: i64, reading: Option<Reading>, expected: Expected }
    #[derive(Deserialize)] struct Expected { state: String, headline_pct: Option<f64>, daily_fill: Option<f64>, resting: bool }
    #[derive(Deserialize)] struct PaceVector { now: i64, events: Vec<UsageEvent>, expected_rate: f64, expected_level: String }

    #[test]
    fn shared_swift_vectors() {
        let vectors: Vectors = serde_json::from_str(include_str!("../../shared/usage-pace-vectors.json")).unwrap();
        for vector in vectors.logic {
            let actual = evaluate(vector.reading.as_ref(), vector.now);
            assert_eq!(actual.state, vector.expected.state);
            assert_eq!(actual.resting, vector.expected.resting);
            assert_eq!(actual.headline_pct, vector.expected.headline_pct);
            match (actual.daily_fill, vector.expected.daily_fill) { (Some(actual), Some(expected)) => assert!((actual - expected).abs() < 0.000_001), (None, None) => {}, _ => panic!("daily-fill mismatch") }
        }
        for vector in vectors.pace {
            let rate = pace_rate(&vector.events, vector.now);
            assert_eq!(rate, vector.expected_rate);
            assert_eq!(pace_level(rate), vector.expected_level);
        }
    }

    #[test]
    fn parsers_ignore_junk_and_read_supported_windows() {
        assert!(parse_claude_line("not json").is_none());
        let claude = r#"{"type":"assistant","timestamp":"2023-11-14T22:13:20Z","message":{"usage":{"output_tokens":200}}}"#;
        assert_eq!(parse_claude_line(claude).unwrap().output_tokens, 200);
        let codex = r#"{"timestamp":"2023-11-14T22:13:20Z","payload":{"type":"token_count","info":{"last_token_usage":{"output_tokens":99}},"rate_limits":{"primary":{"used_percent":42,"window_minutes":300,"resets_at":1700010000},"secondary":{"used_percent":12,"window_minutes":10080,"resets_at":1700604800}}}}"#;
        let (_, reading) = parse_codex_line(codex).unwrap();
        assert_eq!(reading.unwrap().five.unwrap().pct, 42.0);
    }
}
