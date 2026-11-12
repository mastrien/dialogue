use serde::{Deserialize, Serialize};

use crate::error::{CoreError, CoreResult};

const GITHUB_LATEST_RELEASE_URL: &str =
    "https://api.github.com/repos/mastrien/dialogue/releases/latest";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub release_notes: String,
    pub release_url: String,
    pub download_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    body: Option<String>,
    html_url: String,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
}

pub fn parse_semver(v: &str) -> Option<(u64, u64, u64)> {
    let clean = v.trim().trim_start_matches('v').split('-').next()?;
    let mut parts = clean.split('.');
    let major = parts.next()?.parse::<u64>().ok()?;
    let minor = parts.next().unwrap_or("0").parse::<u64>().ok()?;
    let patch = parts.next().unwrap_or("0").parse::<u64>().ok()?;
    Some((major, minor, patch))
}

pub fn is_newer_version(current: &str, latest: &str) -> bool {
    match (parse_semver(current), parse_semver(latest)) {
        (Some(c), Some(l)) => l > c,
        _ => false,
    }
}

pub async fn check_for_update(platform: &str) -> CoreResult<Option<UpdateInfo>> {
    let current = env!("CARGO_PKG_VERSION").to_string();
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(6))
        .build()
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    let resp = client
        .get(GITHUB_LATEST_RELEASE_URL)
        .header("User-Agent", "dialogue-app")
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    if !resp.status().is_success() {
        return Ok(None);
    }

    let release: GitHubRelease = resp
        .json()
        .await
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    let latest = release.tag_name.trim().trim_start_matches('v').to_string();
    if !is_newer_version(&current, &latest) {
        return Ok(None);
    }

    let download_url = release
        .assets
        .iter()
        .find(|a| match platform {
            "windows" => a.name.ends_with("-setup.exe") || a.name.ends_with(".msi"),
            "android" => a.name.ends_with(".apk"),
            _ => false,
        })
        .map(|a| a.browser_download_url.clone());

    Ok(Some(UpdateInfo {
        current_version: current,
        latest_version: latest,
        release_notes: release.body.unwrap_or_default(),
        release_url: release.html_url,
        download_url,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_semver_comparison() {
        assert!(is_newer_version("0.1.0", "0.1.1"));
        assert!(is_newer_version("0.1.0", "v0.2.0"));
        assert!(is_newer_version("0.1.9", "1.0.0"));
        assert!(!is_newer_version("0.1.0", "0.1.0"));
        assert!(!is_newer_version("0.2.0", "0.1.9"));
    }
}
