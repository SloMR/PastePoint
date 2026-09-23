use actix_governor::{Governor, GovernorConfigBuilder};
use actix_web::{App, HttpResponse, http::StatusCode, test, web};
use server::ClientIpKeyExtractor;

/// Status codes for requests that all arrive from the same proxy, one per client address.
async fn statuses(trust_proxy_headers: bool, clients: &[&str]) -> Vec<StatusCode> {
    let config = GovernorConfigBuilder::default()
        .seconds_per_request(60)
        .burst_size(1)
        .key_extractor(ClientIpKeyExtractor::new(trust_proxy_headers))
        .finish()
        .expect("rate limit config");
    let app = test::init_service(
        App::new()
            .wrap(Governor::new(&config))
            .route("/", web::get().to(HttpResponse::Ok)),
    )
    .await;

    let mut statuses = Vec::new();
    for client in clients {
        let req = test::TestRequest::get()
            .uri("/")
            .peer_addr("172.19.0.4:443".parse().unwrap())
            .insert_header(("X-Forwarded-For", *client))
            .to_request();
        statuses.push(test::call_service(&app, req).await.status());
    }
    statuses
}

#[actix_rt::test]
async fn clients_behind_the_proxy_have_their_own_limits() {
    let statuses = statuses(true, &["203.0.113.1", "203.0.113.2", "203.0.113.1"]).await;

    assert_eq!(
        statuses,
        [
            StatusCode::OK,
            StatusCode::OK,
            StatusCode::TOO_MANY_REQUESTS
        ]
    );
}

#[actix_rt::test]
async fn forwarding_headers_are_ignored_without_the_proxy() {
    let statuses = statuses(false, &["203.0.113.1", "203.0.113.2"]).await;

    assert_eq!(statuses, [StatusCode::OK, StatusCode::TOO_MANY_REQUESTS]);
}
