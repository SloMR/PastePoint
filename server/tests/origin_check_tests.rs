use actix_http::header::HeaderValue;
use server::ServerConfig;

#[test]
fn allows_the_configured_origin() {
    let mut config_https = ServerConfig::load(Some(false)).expect("load config");
    config_https.cors_allowed_origins = "https://pastepoint.com".to_string();
    let origin_https = HeaderValue::from_str("https://pastepoint.com").unwrap();
    assert!(config_https.check_origin(&origin_https));

    let mut config_http = ServerConfig::load(Some(false)).expect("load config");
    config_http.cors_allowed_origins = "http://pastepoint.com".to_string();
    let origin_http = HeaderValue::from_str("http://pastepoint.com").unwrap();
    assert!(config_http.check_origin(&origin_http));
}

#[test]
fn allows_a_configured_www_origin() {
    let mut config_https = ServerConfig::load(Some(false)).expect("load config");
    config_https.cors_allowed_origins = "https://www.pastepoint.com".to_string();
    let origin_https = HeaderValue::from_str("https://www.pastepoint.com").unwrap();
    assert!(config_https.check_origin(&origin_https));

    let mut config_http = ServerConfig::load(Some(false)).expect("load config");
    config_http.cors_allowed_origins = "http://www.pastepoint.com".to_string();
    let origin_http = HeaderValue::from_str("http://www.pastepoint.com").unwrap();
    assert!(config_http.check_origin(&origin_http));
}

#[test]
fn refuses_a_subdomain() {
    let mut config_https = ServerConfig::load(Some(false)).expect("load config");
    config_https.cors_allowed_origins = "https://pastepoint.com".to_string();
    let origin_https = HeaderValue::from_str("https://sub.pastepoint.com").unwrap();
    assert!(!config_https.check_origin(&origin_https));

    let mut config_http = ServerConfig::load(Some(false)).expect("load config");
    config_http.cors_allowed_origins = "http://pastepoint.com".to_string();
    let origin_http = HeaderValue::from_str("http://sub.pastepoint.com").unwrap();
    assert!(!config_http.check_origin(&origin_http));
}

#[test]
fn requires_the_same_scheme_and_port() {
    let mut config = ServerConfig::load(Some(false)).expect("load config");
    config.cors_allowed_origins = "https://pastepoint.com".to_string();

    for (origin, allowed) in [
        ("https://pastepoint.com:443", true),
        ("https://PastePoint.com", true),
        ("http://pastepoint.com", false),
        ("https://pastepoint.com:8443", false),
        ("null", false),
    ] {
        let origin_value = HeaderValue::from_str(origin).unwrap();
        assert_eq!(
            config.check_origin(&origin_value),
            allowed,
            "origin {origin}"
        );
    }
}

#[test]
fn refuses_an_origin_that_only_starts_like_the_allowed_one() {
    let mut config_https = ServerConfig::load(Some(false)).expect("load config");
    config_https.cors_allowed_origins = "https://pastepoint.com".to_string();
    let origin_https = HeaderValue::from_str("https://pastepoint.com.evil.com").unwrap();
    assert!(!config_https.check_origin(&origin_https));

    let mut config_http = ServerConfig::load(Some(false)).expect("load config");
    config_http.cors_allowed_origins = "http://pastepoint.com".to_string();
    let origin_http = HeaderValue::from_str("http://pastepoint.com.evil.com").unwrap();
    assert!(!config_http.check_origin(&origin_http));
}
