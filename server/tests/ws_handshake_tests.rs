use actix_web::{App, http::StatusCode, test, web};
use server::{ServerConfig, SessionStore, chat_ws, private_chat_ws};

/// Loads the development config.
fn load_config() -> ServerConfig {
    ServerConfig::load(Some(false)).expect("Failed to load server configuration")
}

/// A WebSocket upgrade request from a local client.
fn upgrade_request(uri: &str) -> test::TestRequest {
    test::TestRequest::get()
        .uri(uri)
        .insert_header(("Upgrade", "websocket"))
        .insert_header(("Connection", "Upgrade"))
        .insert_header(("Sec-WebSocket-Version", "13"))
        .insert_header(("Sec-WebSocket-Key", "test_key"))
        .peer_addr("127.0.0.1:12345".parse().unwrap())
}

#[actix_rt::test]
async fn public_socket_upgrades() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(SessionStore::default()))
            .app_data(web::Data::new(load_config()))
            .service(chat_ws),
    )
    .await;

    let resp = test::call_service(&app, upgrade_request("/ws").to_request()).await;

    assert_eq!(resp.status(), StatusCode::SWITCHING_PROTOCOLS);
}

#[actix_rt::test]
async fn private_socket_upgrades_with_a_known_code() {
    let store = SessionStore::default();
    let code = store
        .create_private_session("127.0.0.1")
        .expect("private session");
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(store))
            .app_data(web::Data::new(load_config()))
            .service(private_chat_ws),
    )
    .await;

    let req = upgrade_request(&format!("/ws/{code}")).to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), StatusCode::SWITCHING_PROTOCOLS);
}

#[actix_rt::test]
async fn private_socket_refuses_an_unknown_code() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(SessionStore::default()))
            .app_data(web::Data::new(load_config()))
            .service(private_chat_ws),
    )
    .await;

    let resp = test::call_service(&app, upgrade_request("/ws/unknown_code").to_request()).await;

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[actix_rt::test]
async fn private_socket_refuses_a_public_session_key() {
    let store = SessionStore::default();
    store
        .get_or_create_session_uuid("127.0.0.1", false, false)
        .expect("public session");
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(store))
            .app_data(web::Data::new(load_config()))
            .service(private_chat_ws),
    )
    .await;

    let resp = test::call_service(&app, upgrade_request("/ws/127.0.0.1").to_request()).await;

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[actix_rt::test]
async fn socket_refuses_a_cross_site_origin() {
    let mut config = load_config();
    config.cors_allowed_origins = "https://pastepoint.com".to_owned();
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(SessionStore::default()))
            .app_data(web::Data::new(config))
            .service(chat_ws),
    )
    .await;

    let req = upgrade_request("/ws")
        .insert_header(("Origin", "https://evil.example"))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    let req = upgrade_request("/ws")
        .insert_header(("Origin", "https://pastepoint.com"))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::SWITCHING_PROTOCOLS);
}
