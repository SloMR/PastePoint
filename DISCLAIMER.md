# PastePoint – Legal Disclaimer

## Introduction

This document explains, for reference, how **PastePoint** works and the limits of what it promises. PastePoint is a peer-to-peer file sharing and messaging platform focused on privacy and speed.

This document is explanatory and is not itself an agreement. Your use of the hosted service is governed by the [Terms of Service](https://pastepoint.com/privacy), which you accept in the app. Where this document and the Terms of Service differ, the Terms of Service govern.

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

## 4. User Responsibility

By using PastePoint, you agree to:

- Use it lawfully and ethically
- Avoid transferring copyrighted, illegal, or harmful material
- Secure your environment (network, browser, and machine)

The developers are not responsible for monitoring or controlling user activity.

## 5. No Data Retention

PastePoint does **not** store:

- Files
- Messages
- Session history or room contents

All file transfers occur directly and are ephemeral.

Our web server keeps standard access logs for security, rate limiting, and abuse handling. Client addresses are truncated before they are written (IPv4 to the /24, IPv6 to the /32), so the logs do not identify individual users, and they are rotated and deleted on a limited schedule. Your own device, browser, or network may log information independently.

The application may send anonymized error reports to a third-party error-tracking service to help maintainers diagnose crashes; see §11 below.

## 6. Encryption & Security

PastePoint uses:

- **WebRTC** for end-to-end encrypted P2P transfers
- **WebSocket** signaling served over TLS via Nginx on the hosted service
- **SSL/TLS**

Security is a shared responsibility between the app and the user. For sensitive usage, use trusted certificates and ensure your host system is secure.

## 7. Open Source Licensing

PastePoint uses and integrates third-party open-source software. Each component is governed by its own license (e.g., MIT, Apache, GPL).

The main project is released under the **GPL-3.0** license. Refer to the [LICENSE](LICENSE) file for more.

## 8. Contributions

By contributing, you agree to:

- License your code under the same license as PastePoint
- Avoid submitting malicious or unauthorized content
- Follow the project’s code quality and community standards

## 9. Production Use Notice

PastePoint is under active development. If you self-host PastePoint, your deployment should:

- Replace self-signed certs with valid CA certificates
- Harden the Nginx config and rate limits
- Regularly audit code and dependencies
- Use isolated network setups if handling sensitive files

## 10. Contact

For security concerns, legal questions, or bug reports:

- GitHub Issues: [https://github.com/SloMR/pastepoint/issues](https://github.com/SloMR/pastepoint/issues)
- Email: [support@pastepoint.com](mailto:support@pastepoint.com)

## 11. Error Diagnostics & Third-Party Processors

PastePoint may send technical error reports to **Sentry** (operated by Functional Software, Inc. d/b/a Sentry). These reports are stored in Sentry's **European Union data region** and contain:

- Crash and exception details (error type, message, stack trace)
- Application version, environment (development / production), and runtime info (OS, browser, language)

The reports do **not** contain:

- File contents or filenames
- Chat messages
- Room or session identifiers
- User accounts, names, or email addresses
- IP addresses or geolocation (the SDK and server-side scrubbing both strip these)

Error reports help us identify and fix bugs. They are retained for a limited time and then deleted automatically. Operators of self-hosted PastePoint instances may disable error reporting entirely by setting `SENTRY_ENABLED=false` in their environment configuration.

PastePoint is a tool. Please use it wisely, lawfully, and responsibly.
