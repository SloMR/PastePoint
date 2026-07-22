use actix_http::header::HeaderValue;
use config::{Config, ConfigError, File};
use serde::{Deserialize, Serialize};
use std::env;
use url::Url;

// This function provides a default value for the log level.
fn default_log_level() -> String {
    "debug".to_string()
}

fn default_sentry_sample_rate() -> f32 {
    1.0
}

fn default_sentry_traces_sample_rate() -> f32 {
    0.1
}

#[derive(Clone, Debug, Deserialize)]
pub struct SentryConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub environment: Option<String>,
    #[serde(default = "default_sentry_sample_rate")]
    pub sample_rate: f32,
    #[serde(default = "default_sentry_traces_sample_rate")]
    pub traces_sample_rate: f32,
}

impl Default for SentryConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            environment: None,
            sample_rate: default_sentry_sample_rate(),
            traces_sample_rate: default_sentry_traces_sample_rate(),
        }
    }
}

impl SentryConfig {
    pub fn load() -> Self {
        let environment = env::var("RUN_ENV").unwrap_or_else(|_| "development".to_string());

        let mut cfg: Self = Config::builder()
            .add_source(File::with_name(&format!("config/{environment}")).required(false))
            .build()
            .and_then(|s| s.get::<Self>("sentry"))
            .unwrap_or_default();

        if let Ok(v) = env::var("SENTRY_ENABLED") {
            cfg.enabled = matches!(v.to_ascii_lowercase().as_str(), "true" | "1" | "yes");
        }
        cfg
    }
}

/// Per-platform version policy. Empty `minimum`/`latest` = no policy (fail open).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct PlatformVersion {
    #[serde(default)]
    pub minimum: String,
    #[serde(default)]
    pub latest: String,
    #[serde(default)]
    pub url: String,
}

/// Client update policy served by `GET /version`; each client reads its own key.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct ClientVersionConfig {
    #[serde(default)]
    pub ios: PlatformVersion,
    #[serde(default)]
    pub web: PlatformVersion,
}

impl ClientVersionConfig {
    pub fn load() -> Self {
        let environment = env::var("RUN_ENV").unwrap_or_else(|_| "development".to_string());

        Config::builder()
            .add_source(File::with_name(&format!("config/{environment}")).required(false))
            .build()
            .and_then(|s| s.get::<Self>("client_version"))
            .unwrap_or_default()
    }
}

fn default_turn_ttl() -> u64 {
    1800
}

#[derive(Clone, Debug, Deserialize)]
pub struct TurnConfig {
    #[serde(default)]
    pub secret: String,
    #[serde(default)]
    pub urls: Vec<String>,
    #[serde(default = "default_turn_ttl")]
    pub ttl_seconds: u64,
}

impl Default for TurnConfig {
    fn default() -> Self {
        Self {
            secret: String::new(),
            urls: Vec::new(),
            ttl_seconds: default_turn_ttl(),
        }
    }
}

impl TurnConfig {
    pub fn load() -> Self {
        let environment = env::var("RUN_ENV").unwrap_or_else(|_| "development".to_string());

        let mut cfg: Self = Config::builder()
            .add_source(File::with_name(&format!("config/{environment}")).required(false))
            .build()
            .and_then(|s| s.get::<Self>("turn"))
            .unwrap_or_default();

        if let Ok(secret) = env::var("TURN_SECRET") {
            cfg.secret = secret;
        }
        cfg
    }

    pub fn is_enabled(&self) -> bool {
        !self.secret.is_empty() && !self.urls.is_empty()
    }
}

#[derive(Clone, Debug, Deserialize)]
pub struct ServerConfig {
    pub bind_address: String,
    pub key_file_path: String,
    pub cert_file_path: String,
    pub auto_join: bool,
    pub rate_limit_per_second: u64,
    pub rate_limit_burst_size: u32,
    #[serde(default = "default_log_level")]
    pub log_level: String,
    pub cors_allowed_origins: String,
}

impl ServerConfig {
    pub fn load(auto_join_override: Option<bool>) -> Result<Self, ConfigError> {
        let environment = env::var("RUN_ENV").unwrap_or_else(|_| "development".to_string());
        log::debug!(
            target: "Websocket",
            "Loading configuration for environment: {environment}"
        );

        let mut builder = Config::builder()
            .add_source(File::with_name(&format!("config/{environment}")).required(true));

        if let Some(auto_join) = auto_join_override {
            builder = builder.set_override("server.auto_join", auto_join)?;
        }

        let settings = builder.build()?;
        settings.get::<ServerConfig>("server")
    }

    pub fn is_dev_env() -> bool {
        let environment = env::var("RUN_ENV").unwrap_or_else(|_| "development".to_string());
        log::debug!(
            target: "Websocket",
            "Checking if environment is development: {environment}"
        );
        environment == "development" || environment == "docker-dev"
    }

    pub fn check_origin(&self, origin: &HeaderValue) -> bool {
        fn extract_host(input: &str) -> Option<String> {
            Url::parse(input)
                .or_else(|_| Url::parse(&format!("https://{input}")))
                .ok()
                .and_then(|u| u.host_str().map(|s| s.to_ascii_lowercase()))
        }

        if let Ok(origin_str) = origin.to_str() {
            if let (Some(origin_host), Some(allowed_host)) = (
                extract_host(origin_str),
                extract_host(&self.cors_allowed_origins),
            ) {
                origin_host == allowed_host || origin_host.ends_with(&format!(".{allowed_host}"))
            } else {
                false
            }
        } else {
            false
        }
    }
}
