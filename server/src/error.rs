use crate::CONTENT_TYPE_TEXT_PLAIN;
use actix_web::{HttpResponse, ResponseError};
use derive_more::{Display, From};

#[derive(Debug, Display, From)]
pub enum ServerError {
    #[display("Internal Server Error")]
    InternalServerError,
    #[display("Not Found")]
    NotFound,
    #[display("Bad Request: {}", _0)]
    BadRequest(String),
    #[display("Forbidden")]
    Forbidden,
    #[display("Too Many Requests")]
    TooManyRequests,
    #[display("Service Unavailable")]
    ServiceUnavailable,
}

impl ResponseError for ServerError {
    fn error_response(&self) -> HttpResponse {
        match *self {
            ServerError::InternalServerError => HttpResponse::InternalServerError()
                .content_type(CONTENT_TYPE_TEXT_PLAIN)
                .body("Internal Server Error"),
            ServerError::NotFound => HttpResponse::NotFound()
                .content_type(CONTENT_TYPE_TEXT_PLAIN)
                .body("Not Found"),
            ServerError::BadRequest(ref message) => HttpResponse::BadRequest()
                .content_type(CONTENT_TYPE_TEXT_PLAIN)
                .body(message.clone()),
            ServerError::Forbidden => HttpResponse::Forbidden()
                .content_type(CONTENT_TYPE_TEXT_PLAIN)
                .body("Forbidden"),
            ServerError::TooManyRequests => HttpResponse::TooManyRequests()
                .content_type(CONTENT_TYPE_TEXT_PLAIN)
                .body("Too Many Requests"),
            ServerError::ServiceUnavailable => HttpResponse::ServiceUnavailable()
                .content_type(CONTENT_TYPE_TEXT_PLAIN)
                .body("Service Unavailable"),
        }
    }
}
