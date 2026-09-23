use actix_governor::{KeyExtractor, SimpleKeyExtractionError};
use actix_web::dev::ServiceRequest;
use std::net::IpAddr;

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

    /// The client address nginx sets in `X-Forwarded-For` or `X-Real-IP`.
    fn forwarded_ip(req: &ServiceRequest) -> Option<IpAddr> {
        let header = |name| {
            req.headers()
                .get(name)
                .and_then(|value| value.to_str().ok())
        };
        header("X-Forwarded-For")
            .and_then(|value| value.split(',').next())
            .or_else(|| header("X-Real-IP"))
            .and_then(|value| value.trim().parse().ok())
    }
}

impl KeyExtractor for ClientIpKeyExtractor {
    type Key = IpAddr;
    type KeyExtractionError = SimpleKeyExtractionError<&'static str>;

    fn extract(&self, req: &ServiceRequest) -> Result<Self::Key, Self::KeyExtractionError> {
        let ip = self
            .trust_proxy_headers
            .then(|| Self::forwarded_ip(req))
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
