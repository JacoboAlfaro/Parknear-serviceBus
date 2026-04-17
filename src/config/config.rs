use dotenvy::dotenv;
use std::{env, sync::OnceLock};

#[derive(Clone, Debug)]
pub struct ServiceTarget {
    pub name: String,
    pub base_url: String,
}

#[derive(Debug)]
pub struct AppConfig {
    pub database_url: String,
    pub bind_addr: String,
    pub max_db_connections: u32,
    pub request_body_limit: usize,
    pub user_auth: ServiceTarget,
    pub zones_support: ServiceTarget,
    pub reservation_payment: ServiceTarget,
}

static CONFIG: OnceLock<AppConfig> = OnceLock::new();

impl AppConfig {
    pub fn init() -> &'static Self {
        CONFIG.get_or_init(|| {
            let _ = dotenv();

            Self {
                database_url: env::var("DATABASE_URL")
                    .expect("DATABASE_URL es obligatoria"),
                bind_addr: env::var("BIND_ADDR")
                    .unwrap_or_else(|_| "0.0.0.0:3000".to_string()),
                max_db_connections: env::var("MAX_DB_CONNECTIONS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(5),
                request_body_limit: env::var("REQUEST_BODY_LIMIT_BYTES")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(16 * 1024 * 1024),
                user_auth: ServiceTarget {
                    name: env::var("USER_AUTH_SERVICE_NAME")
                        .unwrap_or_else(|_| "user_auth_service".to_string()),
                    base_url: env::var("USER_AUTH_BASE_URL")
                        .expect("USER_AUTH_BASE_URL es obligatoria"),
                },
                zones_support: ServiceTarget {
                    name: env::var("ZONES_SUPPORT_SERVICE_NAME")
                        .unwrap_or_else(|_| "zones_support_service".to_string()),
                    base_url: env::var("ZONES_SUPPORT_BASE_URL")
                        .expect("ZONES_SUPPORT_BASE_URL es obligatoria"),
                },
                reservation_payment: ServiceTarget {
                    name: env::var("RESERVATION_PAYMENT_SERVICE_NAME")
                        .unwrap_or_else(|_| "reservation_payment_service".to_string()),
                    base_url: env::var("RESERVATION_PAYMENT_BASE_URL")
                        .expect("RESERVATION_PAYMENT_BASE_URL es obligatoria"),
                },
            }
        })
    }
}
