//! The workspace's one TLS seam: rustls with the Mozilla root set.
//!
//! Every client that speaks TLS (`http_request` over `https://`, the RESP
//! client's `tls:` target) wraps its `TcpStream` here, so the provider, the
//! root store and the name verification live in one audited place. Server
//! certificates are verified — there is no `dangerous` configuration() to
//! reach.
//!
//! The wasm targets are a typed absence: `ring`'s C core carries no wasm
//! build (clang rejects its sources for wasm32 in the component toolchain —
//! a world-fact, not ours to dissolve), so there the `Tls` variant does not
//! exist and `Conn::tls` refuses by name rather than linking what cannot
//! build. Plain connections are unchanged.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

#[derive(Debug)]
pub enum Conn {
    Plain(TcpStream),
    #[cfg(not(target_arch = "wasm32"))]
    Tls(rustls::StreamOwned<rustls::ClientConnection, TcpStream>),
}

impl Conn {
    pub fn plain(stream: TcpStream) -> Self {
        Conn::Plain(stream)
    }

    pub fn tls(stream: TcpStream, host: &str) -> Result<Self, String> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            let conn = rustls::ClientConnection::new(config(), server_name(host)?)
                .map_err(|e| format!("{host}: {e}"))?;
            Ok(Conn::Tls(rustls::StreamOwned::new(conn, stream)))
        }
        #[cfg(target_arch = "wasm32")]
        {
            let _ = (stream, host);
            Err(format!(
                "{host}: tls is absent on this target (ring's C carries no wasm build)"
            ))
        }
    }

    /// The socket under the wire, for timeouts and peer facts.
    pub fn sock(&self) -> &TcpStream {
        match self {
            Conn::Plain(s) => s,
            #[cfg(not(target_arch = "wasm32"))]
            Conn::Tls(s) => &s.sock,
        }
    }
}

impl Write for Conn {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Conn::Plain(s) => s.write(buf),
            #[cfg(not(target_arch = "wasm32"))]
            Conn::Tls(s) => s.write(buf),
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Conn::Plain(s) => s.flush(),
            #[cfg(not(target_arch = "wasm32"))]
            Conn::Tls(s) => s.flush(),
        }
    }
}

impl Read for Conn {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Conn::Plain(s) => s.read(buf),
            #[cfg(not(target_arch = "wasm32"))]
            Conn::Tls(s) => s.read(buf),
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn config() -> Arc<rustls::ClientConfig> {
    static CONFIG: std::sync::OnceLock<Arc<rustls::ClientConfig>> = std::sync::OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let roots = rustls::RootCertStore {
                roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
            };
            Arc::new(
                rustls::ClientConfig::builder()
                    .with_root_certificates(roots)
                    .with_no_client_auth(),
            )
        })
        .clone()
}

#[cfg(not(target_arch = "wasm32"))]
fn server_name(host: &str) -> Result<rustls::pki_types::ServerName<'static>, String> {
    if let Ok(ip) = host.parse::<std::net::IpAddr>() {
        Ok(rustls::pki_types::ServerName::IpAddress(ip.into()))
    } else {
        rustls::pki_types::DnsName::try_from(host.to_string())
            .map(rustls::pki_types::ServerName::DnsName)
            .map_err(|e| format!("{host} is not a name TLS can verify: {e}"))
    }
}
