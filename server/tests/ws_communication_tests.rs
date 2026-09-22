use crate::common::init_test_server;
use awc::{
    Client,
    ws::{Frame, Message},
};
use futures_util::{SinkExt, StreamExt};
use std::time::Duration;
use tokio::time::timeout;

mod common;

#[actix_rt::test]
async fn test_ws_communication() {
    let srv = init_test_server(false);

    let url = srv.url("/ws");

    let (_resp, mut framed) = Client::new()
        .ws(&url)
        .connect()
        .await
        .expect("Failed to connect");

    framed
        .send(Message::Text("[UserCommand]/name".into()))
        .await
        .unwrap();

    if let Some(Ok(Frame::Text(text))) = framed.next().await {
        let text_str = std::str::from_utf8(&text).unwrap();
        if text_str.contains("[SystemName]") {
            assert!(text_str.contains("[SystemName]"));
        } else {
            panic!("Unexpected response");
        }
    }

    framed.close().await.unwrap();
}

#[actix_rt::test]
async fn test_ws_list_command() {
    let srv = init_test_server(true);

    let url = srv.url("/ws");

    let (_resp, mut framed) = Client::new()
        .ws(&url)
        .connect()
        .await
        .expect("Failed to connect");

    framed
        .send(Message::Text("[UserCommand]/list".into()))
        .await
        .unwrap();

    while let Some(Ok(Frame::Text(text))) = framed.next().await {
        let text_str = std::str::from_utf8(&text).unwrap();
        if text_str.contains("[SystemMembers]") {
            assert!(text_str.contains("[SystemMembers]"));
            break;
        } else {
            continue;
        }
    }

    framed.close().await.unwrap();
}

#[actix_rt::test]
async fn test_ws_join_command() {
    let srv = init_test_server(false);

    let url = srv.url("/ws");

    let (_resp, mut framed) = Client::new()
        .ws(&url)
        .connect()
        .await
        .expect("Failed to connect");

    framed
        .send(Message::Text("[UserCommand]/join test_room".into()))
        .await
        .unwrap();

    let mut joined = false;
    let mut received_members = false;

    let result = timeout(Duration::from_secs(5), async {
        while let Some(Ok(Frame::Text(text))) = framed.next().await {
            let text_str = std::str::from_utf8(&text).unwrap();

            if text_str.contains("[SystemJoin]") && text_str.contains("test_room") {
                joined = true;
            }

            if text_str.contains("[SystemMembers]") {
                received_members = true;
            }

            if joined && received_members {
                break;
            }
        }
    })
    .await;

    if result.is_err() {
        panic!("Test timed out waiting for server responses");
    }

    assert!(joined, "Did not receive join confirmation for test_room");
    assert!(
        received_members,
        "Did not receive members list for test_room"
    );

    framed.close().await.unwrap();
}

#[actix_rt::test]
async fn test_ws_name_arrives_before_room_join() {
    let srv = init_test_server(true);

    let url = srv.url("/ws");

    let (_resp, mut framed) = Client::new()
        .ws(&url)
        .connect()
        .await
        .expect("Failed to connect");

    let first = timeout(Duration::from_secs(5), framed.next())
        .await
        .expect("No frame received");
    match first {
        Some(Ok(Frame::Text(text))) => {
            let text_str = std::str::from_utf8(&text).unwrap();
            assert!(
                text_str.starts_with("[SystemName]"),
                "First frame was: {text_str}"
            );
        }
        other => panic!("Unexpected first frame: {other:?}"),
    }

    framed.close().await.unwrap();
}
