# PastePoint – Legal Disclaimer

## Introduction

This document outlines the legal disclaimer for the use of **PastePoint**, a peer-to-peer file sharing and messaging platform focused on privacy, speed, and local connectivity. By using PastePoint, you agree to the terms outlined below. If you do not agree with these terms, please discontinue use.

## 1. No Warranty

PastePoint is provided “as is,” without any warranty of any kind, express or implied. This includes, but is not limited to, warranties of merchantability, fitness for a particular purpose, and non-infringement.

The developers make no guarantees about the reliability, availability, or security of the service.

## 2. Limitation of Liability

Under no circumstances shall the creators, maintainers, or contributors of PastePoint be held liable for any damages or claims resulting from the use or misuse of this software, including but not limited to:

- Loss of data
- Data breaches
- Transmission of malware or illegal content
- Service disruptions or data corruption

Users accept full responsibility for their actions and content shared via PastePoint.

## 3. Intended Use

PastePoint is designed for:

- Secure, **local network** usage
- **Peer-to-peer** file transfers and messaging
- Usage in compliance with all applicable laws

It is **not recommended** for use over public or untrusted networks unless you fully understand and accept the associated risks.

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
- Metadata
- IP logs or session history

All file transfers occur directly and are ephemeral. However, your device, browser, or network may log information independently. The application may send anonymized error reports to a third-party error-tracking service to help maintainers diagnose crashes; see §11 below.

## 6. Encryption & Security

PastePoint uses:

- **WebRTC** for end-to-end encrypted P2P transfers
- **WebSocket** signaling with optional TLS via Nginx
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

PastePoint is under active development and is primarily intended for local or experimental use. Production deployments should:

- Replace self-signed certs with valid CA certificates
- Harden the Nginx config and rate limits
- Regularly audit code and dependencies
- Use isolated network setups if handling sensitive files

## 10. Contact

For security concerns, legal questions, or bug reports:

- GitHub Issues: [https://github.com/SloMR/pastepoint/issues](https://github.com/SloMR/pastepoint/issues)
- Email: [sulaimanromaih@gmail.com](mailto:sulaimanromaih@gmail.com)

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
