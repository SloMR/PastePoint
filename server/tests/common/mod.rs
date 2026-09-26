use actix_codec::Framed;
use actix_test::{TestServer, start};
use actix_web::{App, web};
use awc::{
    BoxedSocket, Client,
    ws::{Codec, Frame, Message},
};
use futures_util::{SinkExt, StreamExt};
use server::{ServerConfig, SessionStore, chat_ws};
use std::time::Duration;
use tokio::time::timeout;

pub type Socket = Framed<BoxedSocket, Codec>;

/// Starts an in-process server with the public `/ws` route.
pub fn init_test_server(auto_join: bool) -> TestServer {
    let config = ServerConfig::load(Some(auto_join)).expect("Failed to load server configuration");
    let session_manager = web::Data::new(SessionStore::default());
    let config_data = web::Data::new(config);

    start(move || {
        App::new()
            .app_data(session_manager.clone())
            .app_data(config_data.clone())
            .service(chat_ws)
    })
}

/// Opens a WebSocket to `/ws`.
pub async fn connect(srv: &TestServer) -> Socket {
    let (_response, socket) = Client::new()
        .ws(srv.url("/ws"))
        .connect()
        .await
        .expect("Failed to connect");
    socket
}

/// Sends a text frame.
pub async fn send_text(socket: &mut Socket, text: &str) {
    socket
        .send(Message::Text(text.to_owned().into()))
        .await
        .expect("Failed to send");
}

/// Returns the next text frame, skipping pings.
pub async fn next_text(socket: &mut Socket) -> String {
    loop {
        let frame = timeout(Duration::from_secs(5), socket.next())
            .await
            .expect("Timed out waiting for the server")
            .expect("The server closed the connection")
            .expect("Failed to read a frame");

        if let Frame::Text(text) = frame {
            return String::from_utf8(text.to_vec()).unwrap();
        }
    }
}

/// Skips text frames until one contains `expected`, and returns it.
pub async fn wait_for(socket: &mut Socket, expected: &str) -> String {
    loop {
        let text = next_text(socket).await;
        if text.contains(expected) {
            return text;
        }
    }
}

/// Reads the name the server sends first on every connection.
pub async fn read_name(socket: &mut Socket) -> String {
    let text = next_text(socket).await;
    text.strip_prefix("[SystemName] ")
        .expect("The first frame was not the name")
        .to_owned()
}
