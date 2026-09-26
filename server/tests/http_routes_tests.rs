use actix_cors::Cors;
use actix_web::{App, http::StatusCode, test, web};
use bytes::Bytes;
use server::{ServerConfig, SessionStore, create_session, health, index};

#[actix_rt::test]
async fn index_redirects_to_health() {
    let app = test::init_service(App::new().service(index)).await;
    let req = test::TestRequest::get().uri("/").to_request();
    let resp = test::call_service(&app, req).await;

    assert_eq!(resp.status(), StatusCode::FOUND);
}

#[actix_rt::test]
async fn health_reports_that_the_server_runs() {
    let app = test::init_service(App::new().service(health)).await;
    let req = test::TestRequest::get().uri("/health").to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::OK);

    let body = test::read_body(resp).await;
    assert_eq!(body, Bytes::from_static(b"PastePoint Server is running!"));
}

#[actix_rt::test]
async fn cors_allows_only_the_configured_origin() {
    let mut config = ServerConfig::load(Some(false)).expect("Failed to load server configuration");
    config.cors_allowed_origins = "https://pastepoint.com".to_owned();
    let cors = Cors::default().allowed_origin_fn(move |origin, _| config.check_origin(origin));
    let app = test::init_service(App::new().wrap(cors).service(index)).await;

    let req = test::TestRequest::get()
        .uri("/")
        .insert_header(("Origin", "https://pastepoint.com"))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(
        resp.headers().get("Access-Control-Allow-Origin").unwrap(),
        "https://pastepoint.com"
    );

    for origin in ["https://www.pastepoint.com", "https://malicious-site.com"] {
        let req = test::TestRequest::get()
            .uri("/")
            .insert_header(("Origin", origin))
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert!(
            resp.headers().get("Access-Control-Allow-Origin").is_none(),
            "{origin}"
        );
    }

    let req = test::TestRequest::get().uri("/").to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.headers().get("Access-Control-Allow-Origin").is_none());
}

#[actix_rt::test]
async fn create_session_refuses_cross_site_requests() {
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(SessionStore::default()))
            .service(create_session),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/create-session")
        .insert_header(("Sec-Fetch-Site", "cross-site"))
        .peer_addr("127.0.0.1:12345".parse().unwrap())
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    let req = test::TestRequest::get()
        .uri("/create-session")
        .insert_header(("Sec-Fetch-Site", "same-origin"))
        .peer_addr("127.0.0.1:12345".parse().unwrap())
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::OK);
}
