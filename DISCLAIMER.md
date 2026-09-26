# PastePoint – Legal Disclaimer

## Introduction

This document explains, for reference, how **PastePoint** works and the limits of what it promises. PastePoint is a peer-to-peer file sharing and messaging platform focused on privacy and speed.

This document is explanatory and is not itself an agreement. Your use of the hosted service, the web app at pastepoint.com and the iOS app, is governed by the Terms of Service on the [Privacy & Terms page](https://pastepoint.com/privacy). The iOS app asks you to accept them before it connects. Where this document and the Terms of Service differ, the Terms of Service govern.

## 1. No Warranty

PastePoint is provided “as is,” without any warranty of any kind, express or implied. This includes, but is not limited to, warranties of merchantability, fitness for a particular purpose, and non-infringement.

The developers make no guarantees about the reliability, availability, or security of the service.

## 2. Limitation of Liability

To the maximum extent permitted by applicable law, the creators, maintainers, and contributors of PastePoint shall not be liable for any damages or claims resulting from the use or misuse of this software, including but not limited to:

- Loss of data
- Data breaches
- Transmission of malware or illegal content
- Service disruptions or data corruption

Nothing in this document excludes or limits liability that cannot be excluded or limited under applicable law, such as liability for death or personal injury caused by negligence, or for fraud.

Users accept full responsibility for their actions and content shared via PastePoint.

## 3. Intended Use

PastePoint is designed for:

- **Peer-to-peer** file transfers and messaging, over a local network or the internet
- Usage in compliance with all applicable laws

Transfers are encrypted end-to-end between the participating devices. As with any tool, you are responsible for what you choose to send and to whom.

PastePoint has no accounts. The server gives each connection a new random name.

The public room, shown as “On this Wi-Fi”, holds every device that shares your public IP address. On a shared network, such as an office, a campus or some mobile networks, that can include people you don't know. An invite-only session admits only the devices that have its code.

## 4. User Responsibility

When using PastePoint, you are expected to:

- Use it lawfully and ethically
- Avoid transferring copyrighted, illegal, or harmful material
- Secure your environment (network, browser, and machine)

The developers are not responsible for monitoring or controlling user activity.

You can block another user from the menu on any of their messages. Blocking removes their messages from your device and closes the connection to them. A block lasts until your device reconnects to the server, because names are not kept between connections. **Report and Block** also opens an email to [support@pastepoint.com](mailto:support@pastepoint.com), so you can report the abuse.

## 5. No Data Retention

Our servers do **not** store:

- Files
- Messages
- Session history or room contents

Files and messages travel between the devices, directly or through our TURN relay, and are ephemeral.

The signaling server uses connection data, such as IP addresses, in memory to set up connections, to place devices in rooms, and for rate limiting and abuse prevention.

Our web server keeps standard access logs for security, rate limiting, and abuse handling. Client addresses are truncated before they are written (IPv4 to the /24, IPv6 to the /32), and session codes are removed from logged request paths, so the logs do not identify individual users. They are rotated and deleted on a limited schedule. Your own device, browser, or network may log information independently.

The apps and the server may send error reports to a third-party error-tracking service to help maintainers diagnose crashes, and the web app sends aggregate usage statistics to a third-party analytics service; see §11 below.

## 6. Encryption & Security

PastePoint uses:

- **WebRTC** data channels, encrypted end-to-end with DTLS, for messages and file transfers
- **WebSocket** signaling served over TLS via Nginx on the hosted service. The signaling server assigns names, keeps track of rooms and relays the messages that set up each connection. Messages and files never pass through it.
- A **TURN relay** when two devices can't connect directly. It forwards their encrypted traffic without being able to read it.
- **SSL/TLS**

Security is a shared responsibility between the app and the user. For sensitive usage, use trusted certificates and ensure your host system is secure.

## 7. Open Source Licensing

PastePoint uses and integrates third-party open-source software. Each component is governed by its own license (for example MIT, ISC, Apache-2.0, or BSD). The web app lists them at [pastepoint.com/acknowledgements](https://pastepoint.com/acknowledgements), and the iOS app lists them in the Settings app under PastePoint.

The main project is released under the **GPL-3.0** license. Refer to the [LICENSE](LICENSE) file for more.

## 8. Contributions

If you contribute, you are expected to:

- License your code under the same license as PastePoint
- Avoid submitting malicious or unauthorized content
- Follow the project’s code quality and community standards, described in [CONTRIBUTING.md](CONTRIBUTING.md)

## 9. Production Use Notice

PastePoint is under active development. If you self-host PastePoint, your deployment should:

- Replace self-signed certs with valid CA certificates
- Harden the Nginx config and rate limits
- Regularly audit code and dependencies
- Use isolated network setups if handling sensitive files
- Turn off error reporting or point it at your own Sentry project (see §11)

## 10. Contact

- Security problems, bug reports and feature requests: [GitHub Issues](https://github.com/SloMR/PastePoint/issues), or email [support@pastepoint.com](mailto:support@pastepoint.com)
- Legal questions and abuse reports: [support@pastepoint.com](mailto:support@pastepoint.com)

## 11. Error Diagnostics & Third-Party Processors

The web app, the iOS app and the signaling server send crash reports, exception details and anonymized performance measurements to **Sentry** (operated by Functional Software, Inc. d/b/a Sentry). These reports are stored in Sentry's **European Union data region** and contain:

- Crash and exception details (error type, message, stack trace)
- Application version, environment (development / production), and basic runtime info (OS version, browser or device model)
- Timings and counts, such as how long a connection or a transfer took and its size
- The random names PastePoint assigns to your device and to the devices you connect with (a new name is generated for every connection)

The reports do **not** contain:

- File contents or filenames
- Chat messages
- Room or session identifiers
- Email addresses
- IP addresses or geolocation (the SDK and server-side scrubbing both strip these)

Error reports help us identify and fix bugs. They are retained for a limited time and then deleted automatically.

The web app at pastepoint.com also sends cookieless, aggregate usage statistics to **Umami Cloud**, which is hosted in the European Union. Session codes are removed from page addresses and referrers before anything is sent. Umami does not receive file contents or messages and does not set cookies. It runs only on pastepoint.com: self-hosted copies and the iOS app do not send usage statistics.

Operators of self-hosted PastePoint instances may disable error reporting entirely by setting `enabled = false` (or leaving the `dsn` empty) under `[sentry]` in the server configuration, and `sentry.enabled` to `false` in the web client's environment files. The committed production configuration (`server/config/production.toml` and `client/web/src/environments/environment.prod.ts`) turns error reporting on and sends reports to the PastePoint project, so change it before deploying your own copy.

PastePoint is a tool. Please use it wisely, lawfully, and responsibly.
