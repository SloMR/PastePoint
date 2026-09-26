use server::WsChatServer;
use tokio::sync::mpsc::channel;

#[test]
fn a_client_added_to_a_room_is_a_member() {
    let mut server = WsChatServer::default();
    let (tx, _rx) = channel(8);

    let id = server
        .add_client_to_room("session", "room", None, tx, "alice".to_owned())
        .expect("Failed to add the client");

    assert!(server.rooms["session"]["room"].contains_key(&id));
}
