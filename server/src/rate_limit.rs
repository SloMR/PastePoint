use actix_governor::{KeyExtractor, SimpleKeyExtractionError};
use actix_web::{dev::ServiceRequest, http::header::HeaderMap};
use std::net::IpAddr;

/// The client address nginx sets in `X-Forwarded-For` or `X-Real-IP`. The last value is
/// nginx's own, because it comes after anything a client could slip into the request.
pub(crate) fn forwarded_ip(headers: &HeaderMap) -> Option<IpAddr> {
    let last = |name: &str| {
        headers
            .get_all(name)
            .last()
            .and_then(|value| value.to_str().ok())
    };
    last("X-Forwarded-For")
        .and_then(|value| value.rsplit(',').next())
        .or_else(|| last("X-Real-IP"))
        .and_then(|value| value.trim().parse().ok())
}

/// Rate-limit key for the client behind nginx, instead of nginx's own address.
///
/// The forwarding headers are only trusted when `trust_proxy_headers` is set, because
/// without nginx in front any client could write them.
#[derive(Clone, Copy, Debug)]
pub struct ClientIpKeyExtractor {
    trust_proxy_headers: bool,
}

impl ClientIpKeyExtractor {
    pub fn new(trust_proxy_headers: bool) -> Self {
        Self {
            trust_proxy_headers,
        }
    }
}

impl KeyExtractor for ClientIpKeyExtractor {
    type Key = IpAddr;
    type KeyExtractionError = SimpleKeyExtractionError<&'static str>;

    fn extract(&self, req: &ServiceRequest) -> Result<Self::Key, Self::KeyExtractionError> {
        let ip = self
            .trust_proxy_headers
            .then(|| forwarded_ip(req.headers()))
            .flatten()
            .or_else(|| req.peer_addr().map(|addr| addr.ip()))
            .ok_or_else(|| SimpleKeyExtractionError::new("Could not extract client IP address"))?;

        // An IPv6 user usually holds a whole /56, so limit per prefix like the default extractor.
        Ok(match ip {
            IpAddr::V6(ipv6) => {
                let mut octets = ipv6.octets();
                octets[7..].fill(0);
                IpAddr::V6(octets.into())
            }
            v4 => v4,
        })
    }
}
