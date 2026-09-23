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

/// Reads frames until the server announces this connection's name.
async fn read_name<S>(framed: &mut S) -> String
where
    S: futures_util::Stream<Item = Result<Frame, awc::error::WsProtocolError>> + Unpin,
{
    loop {
        let frame = timeout(Duration::from_secs(5), framed.next())
            .await
            .expect("No frame received");
        if let Some(Ok(Frame::Text(text))) = frame {
            let text_str = std::str::from_utf8(&text).unwrap();
            if let Some(name) = text_str.strip_prefix("[SystemName] ") {
                return name.to_owned();
            }
        }
    }
}

#[actix_rt::test]
async fn test_ws_signal_sender_is_the_connection_owner() {
    let srv = init_test_server(true);
    let url = srv.url("/ws");

    let (_resp, mut alice) = Client::new().ws(&url).connect().await.expect("connect");
    let alice_name = read_name(&mut alice).await;
    let (_resp, mut bob) = Client::new().ws(&url).connect().await.expect("connect");
    let bob_name = read_name(&mut bob).await;

    let forged = serde_json::json!({
        "type": "offer",
        "from": "Someone Else",
        "to": bob_name,
        "data": { "type": "offer", "sdp": "v=0" },
        "sequence": 7,
    });
    alice
        .send(Message::Text(format!("[SignalMessage] {forged}").into()))
        .await
        .unwrap();

    let relayed = timeout(Duration::from_secs(5), async {
        while let Some(Ok(frame)) = bob.next().await {
            if let Frame::Text(text) = frame {
                let text_str = std::str::from_utf8(&text).unwrap();
                if let Some(json) = text_str.strip_prefix("[SignalMessage] ") {
                    return serde_json::from_str::<serde_json::Value>(json).unwrap();
                }
            }
        }
        panic!("Connection closed before the signal arrived");
    })
    .await
    .expect("Signal was not relayed");

    assert_eq!(relayed["from"], alice_name.as_str());
    assert_eq!(relayed["to"], bob_name.as_str());
    assert_eq!(relayed["sequence"], 7);
    assert_eq!(relayed["data"]["sdp"], "v=0");

    alice.close().await.unwrap();
    bob.close().await.unwrap();
}
