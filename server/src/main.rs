use actix_cors::Cors;
use actix_governor::{Governor, GovernorConfigBuilder};
use actix_http::KeepAlive;
use actix_web::{
    App, HttpServer,
    middleware::{Condition, Logger},
    web::Data,
};
use openssl::ssl::{SslAcceptor, SslFiletype, SslMethod};
use server::{
    CORS_MAX_AGE, ClientVersionConfig, KEEP_ALIVE_INTERVAL, SentryConfig, ServerConfig,
    SessionStore, chat_ws, create_session, health, index, private_chat_ws,
    version as version_route,
};
use std::borrow::Cow;
use std::io::Result;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::Arc;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const NAME: &str = env!("CARGO_PKG_NAME");
const AUTHORS: &str = env!("CARGO_PKG_AUTHORS");

fn init_sentry(cfg: &SentryConfig) -> Option<sentry::ClientInitGuard> {
    if !cfg.enabled {
        return None;
    }
    let dsn = std::env::var("SENTRY_DSN").ok().filter(|s| !s.is_empty())?;

    let global_traces_rate = cfg.traces_sample_rate;
    let options = sentry::ClientOptions {
        release: sentry::release_name!(),
        environment: cfg.environment.clone().map(Cow::Owned),
        sample_rate: cfg.sample_rate,
        traces_sample_rate: cfg.traces_sample_rate,
        enable_logs: true,
        server_name: Some(Cow::Borrowed("pastepoint-server")),
        traces_sampler: Some(Arc::new(move |ctx| match ctx.name() {
            "signaling.relay" => 0.01,
            name if name.starts_with("GET /ws") => 0.0,
            _ => global_traces_rate,
        })),
        send_default_pii: false,
        attach_stacktrace: true,
        max_breadcrumbs: 50,
        before_send: Some(Arc::new(|mut event| {
            // Strip anything that could carry user-identifying data before the
            // event leaves the process.
            event.user = Some(sentry::protocol::User {
                ip_address: Some(sentry::protocol::IpAddress::Exact(IpAddr::V4(
                    Ipv4Addr::LOCALHOST,
                ))),
                ..Default::default()
            });
            event.server_name = None;
            if let Some(req) = event.request.as_mut() {
                req.cookies = None;
                req.headers.clear();
                req.data = None;
                req.query_string = None;
            }
            Some(event)
        })),
        ..Default::default()
    };

    let guard = sentry::init((dsn, options));
    sentry::configure_scope(|scope| {
        scope.set_user(Some(sentry::protocol::User {
            ip_address: Some(sentry::protocol::IpAddress::Exact(IpAddr::V4(
                Ipv4Addr::LOCALHOST,
            ))),
            ..Default::default()
        }));
    });

    Some(guard)
}

#[actix_web::main]
async fn main() -> Result<()> {
    let sentry_cfg = SentryConfig::load();
    let _sentry_guard = init_sentry(&sentry_cfg);

    let config = ServerConfig::load(None).expect("Failed to load server configuration");

    let log_filter = format!(
        "{lvl},reqwest=warn,hyper=warn,hyper_util=warn,h2=warn,rustls=warn,tokio_util=warn",
        lvl = config.log_level
    );

    let env_logger_logger =
        env_logger::Builder::from_env(env_logger::Env::new().default_filter_or(log_filter)).build();
    let max_level = env_logger_logger.filter();
    let sentry_logger = sentry::integrations::log::SentryLogger::with_dest(env_logger_logger)
        .filter(|md| match md.level() {
            log::Level::Error => sentry::integrations::log::LogFilter::Exception,
            log::Level::Warn => {
                sentry::integrations::log::LogFilter::Log
                    | sentry::integrations::log::LogFilter::Breadcrumb
            }
            log::Level::Info => sentry::integrations::log::LogFilter::Breadcrumb,
            log::Level::Debug | log::Level::Trace => sentry::integrations::log::LogFilter::Ignore,
        });
    log::set_boxed_logger(Box::new(sentry_logger)).expect("Failed to set logger");
    log::set_max_level(max_level);

    if _sentry_guard.is_some() {
        log::info!(target: "Websocket", "Sentry error reporting enabled");
    } else {
        log::debug!(target: "Websocket", "Sentry error reporting disabled");
    }
    let governor_conf = GovernorConfigBuilder::default()
        .requests_per_second(config.rate_limit_per_second)
        .burst_size(config.rate_limit_burst_size)
        .use_headers()
        .finish()
        .expect("Invalid rate limit configuration");

    log::debug!(target: "Websocket", "Rate limiting configured: {governor_conf:?}");

    log::info!(
        target: "Websocket",
        "Starting HTTPS server at https://{} - PastePoint({}) - {} - {}",
        config.bind_address,
        NAME,
        VERSION,
        AUTHORS
    );

    let mut builder = SslAcceptor::mozilla_intermediate(SslMethod::tls())?;
    builder
        .set_private_key_file(&config.key_file_path, SslFiletype::PEM)
        .map_err(|e| log::error!(target: "Websocket","Failed to load private key: {e}"))
        .expect("Cannot find private key file");
    builder
        .set_certificate_chain_file(&config.cert_file_path)
        .map_err(|e| log::error!(target: "Websocket","Failed to load certificate chain file: {e}"))
        .expect("Cannot find certificate chain file");

    log::debug!(target: "Websocket","Using key file: {}", &config.key_file_path);
    log::debug!(target: "Websocket","Using cert file: {}", &config.cert_file_path);

    let session_manager = Data::new(SessionStore::default());
    session_manager.spawn_cleanup_task();

    let server_config = Data::new(config.clone());
    let client_version = Data::new(ClientVersionConfig::load());
    let sentry_enabled = _sentry_guard.is_some();

    HttpServer::new(move || {
        let server_config = server_config.clone();
        let server_config_for_app = server_config.clone();
        let client_version = client_version.clone();
        let cors = Cors::default()
            .allowed_origin_fn(move |origin, _req_head| server_config.check_origin(origin))
            .allowed_methods(vec!["GET", "OPTIONS"])
            .supports_credentials()
            .max_age(CORS_MAX_AGE);

        App::new()
            .wrap(Governor::new(&governor_conf))
            .wrap(Logger::default())
            .wrap(cors)
            .wrap(Condition::new(
                sentry_enabled,
                sentry_actix::Sentry::with_transaction(),
            ))
            .app_data(session_manager.clone())
            .app_data(server_config_for_app)
            .app_data(client_version)
            .service(index)
            .service(health)
            .service(version_route)
            .service(create_session)
            .service(chat_ws)
            .service(private_chat_ws)
    })
    .keep_alive(KeepAlive::Timeout(KEEP_ALIVE_INTERVAL))
    .bind_openssl(&config.bind_address, builder)?
    .run()
    .await
}
