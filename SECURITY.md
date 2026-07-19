# Security Policy

## Supported versions

Security fixes are developed for the latest `0.1.x` revision on the `main` branch. Older commits and unmerged development branches are not maintained as separate release lines.

## Reporting a vulnerability

Potential vulnerabilities should be reported privately whenever possible. Use the repository’s GitHub Security Advisory reporting flow if it is enabled. If private reporting is unavailable, open a minimal issue requesting a private contact channel; do not include credentials, IP addresses, private keys, access tokens, exploit payloads, or identifying VPS data in a public issue.

Reports should include:

- affected command and version;
- supported operating system and architecture;
- expected and observed behavior;
- minimal reproduction steps with secrets removed;
- potential impact and any known mitigation.

## Security-sensitive areas

Changes involving the following areas require explicit confirmation, input validation, failure recovery, and focused tests:

- installer, upgrade and uninstall path ownership;
- SSH configuration and service restart;
- UFW and exposed ports;
- backup manifests and restore targets;
- commands executed with root privileges;
- Docker cleanup and lifecycle operations;
- downloaded repository keys and package sources.

Server Toolkit does not collect telemetry or transmit VPS configuration to the project maintainers. Network requests are limited to user-invoked connectivity checks, TLS inspection, package repositories, and source installation or upgrade.
