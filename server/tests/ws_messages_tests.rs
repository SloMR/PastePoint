use crate::common::{connect, init_test_server, next_text, read_name, send_text, wait_for};
use awc::ws::Message;
use futures_util::SinkExt;
use serde_json::{Value, json};

mod common;

#[actix_rt::test]
async fn name_arrives_before_the_room_join() {
    let srv = init_test_server(true);
    let mut socket = connect(&srv).await;

    let first = next_text(&mut socket).await;

    assert!(first.starts_with("[SystemName]"), "First frame: {first}");
}

#[actix_rt::test]
async fn name_command_replies_with_the_name() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;
    let name = read_name(&mut socket).await;

    send_text(&mut socket, "[UserCommand]/name").await;

    assert_eq!(next_text(&mut socket).await, format!("[SystemName] {name}"));
}

#[actix_rt::test]
async fn list_command_replies_with_the_rooms() {
    let srv = init_test_server(true);
    let mut socket = connect(&srv).await;
    // The auto-join also sends a room list, so let it finish first.
    wait_for(&mut socket, "[SystemMembers]").await;

    send_text(&mut socket, "[UserCommand]/list").await;

    assert_eq!(next_text(&mut socket).await, "[SystemRooms] main");
}

#[actix_rt::test]
async fn join_command_announces_the_join_and_the_members() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;

    send_text(&mut socket, "[UserCommand]/join test_room").await;

    wait_for(&mut socket, "[SystemJoin] test_room").await;
    wait_for(&mut socket, "[SystemMembers]").await;
}

#[actix_rt::test]
async fn rejoining_a_room_announces_the_join() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;

    for room in ["test_room", "main", "test_room"] {
        send_text(&mut socket, &format!("[UserCommand]/join {room}")).await;
        wait_for(&mut socket, &format!("[SystemJoin] {room}")).await;
    }
}

#[actix_rt::test]
async fn every_client_in_a_room_gets_the_member_list() {
    let srv = init_test_server(false);
    let mut first = connect(&srv).await;
    let mut second = connect(&srv).await;

    send_text(&mut first, "[UserCommand]/join test_room").await;
    send_text(&mut second, "[UserCommand]/join test_room").await;

    wait_for(&mut first, "[SystemMembers]").await;
    wait_for(&mut second, "[SystemMembers]").await;
}

#[actix_rt::test]
async fn relayed_signals_carry_the_senders_name() {
    let srv = init_test_server(true);
    let mut alice = connect(&srv).await;
    let alice_name = read_name(&mut alice).await;
    let mut bob = connect(&srv).await;
    let bob_name = read_name(&mut bob).await;

    let forged = json!({
        "type": "offer",
        "from": "Someone Else",
        "to": bob_name,
        "data": { "type": "offer", "sdp": "v=0" },
        "sequence": 7,
    });
    send_text(&mut alice, &format!("[SignalMessage] {forged}")).await;

    let text = wait_for(&mut bob, "[SignalMessage]").await;
    let json = text.strip_prefix("[SignalMessage] ").unwrap();
    let relayed: Value = serde_json::from_str(json).unwrap();

    assert_eq!(relayed["from"], alice_name);
    assert_eq!(relayed["to"], bob_name);
    assert_eq!(relayed["sequence"], 7);
    assert_eq!(relayed["data"]["sdp"], "v=0");
}

#[actix_rt::test]
async fn an_unknown_command_gets_a_system_error() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;

    send_text(&mut socket, "[UserCommand]/unknown").await;

    wait_for(&mut socket, "[SystemError]").await;
}

#[actix_rt::test]
async fn text_without_a_prefix_gets_a_system_error() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;

    send_text(&mut socket, "Hello, World!").await;

    wait_for(&mut socket, "[SystemError]").await;
}

#[actix_rt::test]
async fn a_signal_without_a_recipient_gets_a_system_error() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;

    let signal = r#"[SignalMessage] {"from": "user1", "data": "test"}"#;
    send_text(&mut socket, signal).await;

    wait_for(&mut socket, "[SystemError]").await;
}

#[actix_rt::test]
async fn a_binary_frame_does_not_break_the_connection() {
    let srv = init_test_server(false);
    let mut socket = connect(&srv).await;
    let name = read_name(&mut socket).await;

    let binary = Message::Binary(vec![0, 1, 2, 3].into());
    socket.send(binary).await.expect("Failed to send");
    send_text(&mut socket, "[UserCommand]/name").await;

    assert_eq!(next_text(&mut socket).await, format!("[SystemName] {name}"));
}
