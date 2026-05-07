use actix_http::header::HeaderValue;
use config::{Config, ConfigError, File};
use serde::Deserialize;
use std::env;
use url::Url;

// This function provides a default value for the log level.
fn default_log_level() -> String {
    "debug".to_string()
}

fn default_sentry_sample_rate() -> f32 {
    1.0
}

#[derive(Clone, Debug, Deserialize)]
pub struct SentryConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub environment: Option<String>,
    #[serde(default = "default_sentry_sample_rate")]
    pub sample_rate: f32,
}

impl Default for SentryConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            environment: None,
            sample_rate: default_sentry_sample_rate(),
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
