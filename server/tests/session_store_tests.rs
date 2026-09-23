use server::SessionStore;
use std::{thread, time::Duration};

#[test]
fn public_key_cannot_join_through_the_private_route() {
    let store = SessionStore::default();
    let public = store
        .get_or_create_session_uuid("backend_ws:203.0.113.7", false, false)
        .expect("public session");

    assert_eq!(
        store.get_or_create_session_uuid("backend_ws:203.0.113.7", true, true),
        None
    );
    assert_eq!(
        store.get_or_create_session_uuid("backend_ws:203.0.113.7", true, false),
        Some(public)
    );
}

#[test]
fn private_code_cannot_join_through_the_public_route() {
    let store = SessionStore::default();
    let code = store.create_private_session().expect("private session");

    assert_eq!(store.get_or_create_session_uuid(&code, false, false), None);
}

#[test]
fn unjoined_private_code_expires() {
    let store = SessionStore::with_expiration(Duration::from_millis(20));
    let code = store.create_private_session().expect("private session");
    thread::sleep(Duration::from_millis(60));

    assert_eq!(store.get_or_create_session_uuid(&code, true, true), None);
}

#[test]
fn rejoining_within_the_grace_period_keeps_the_code() {
    let store = SessionStore::with_expiration(Duration::from_millis(50));
    let code = store.create_private_session().expect("private session");
    let uuid = store
        .get_or_create_session_uuid(&code, true, true)
        .expect("join");

    store.remove_client(&uuid);
    assert_eq!(
        store.get_or_create_session_uuid(&code, true, true),
        Some(uuid)
    );
    thread::sleep(Duration::from_millis(150));

    assert_eq!(
        store.get_or_create_session_uuid(&code, true, true),
        Some(uuid)
    );
}

#[test]
fn private_code_expires_after_the_last_client_leaves() {
    let store = SessionStore::with_expiration(Duration::from_millis(50));
    let code = store.create_private_session().expect("private session");
    let uuid = store
        .get_or_create_session_uuid(&code, true, true)
        .expect("join");

    store.remove_client(&uuid);
    thread::sleep(Duration::from_millis(150));

    assert_eq!(store.get_or_create_session_uuid(&code, true, true), None);
}

#[test]
fn concurrent_joins_and_leaves_keep_counts_consistent() {
    let store = SessionStore::default();
    let workers: Vec<_> = (0..8)
        .map(|worker| {
            let store = store.clone();
            thread::spawn(move || {
                let key = format!("backend_ws:198.51.100.{}", worker % 2);
                for _ in 0..500 {
                    let uuid = store
                        .get_or_create_session_uuid(&key, false, false)
                        .expect("session");
                    store.remove_client(&uuid);
                }
            })
        })
        .collect();
    for worker in workers {
        worker.join().expect("worker");
    }

    for key in ["backend_ws:198.51.100.0", "backend_ws:198.51.100.1"] {
        assert_eq!(
            store.get_or_create_session_uuid(key, true, false),
            None,
            "{key} should have been removed with its last client"
        );
    }
}
