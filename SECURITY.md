# Security Policy

## Supported Versions

QuantumGrid OS is currently under active development. Security support will follow the latest stable release and development branch.

| Version               | Supported          |
| --------------------- | ------------------ |
| Latest stable release | :white_check_mark: |
| Development (`main`)  | :white_check_mark: |
| Older releases        | :x:                |

Security support for development builds may depend on the severity of the issue and whether the affected component is already considered production-ready.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

For vulnerabilities affecting QuantumGrid OS, please use GitHub's private security reporting mechanism:

**GitHub → Security → Advisories → Report a vulnerability**

When reporting an issue, please include:

* A clear description of the vulnerability
* The affected QuantumGrid OS version or commit
* The affected component or package
* Steps required to reproduce the issue
* Any relevant logs, configuration, screenshots, or proof-of-concept information
* The potential security impact
* A suggested mitigation, if known

Please provide enough information for the issue to be reproduced and investigated.

## Response Process

We will make a reasonable effort to:

1. Acknowledge a vulnerability report.
2. Investigate and reproduce the issue.
3. Determine its severity and affected versions.
4. Develop and test a fix where practical.
5. Release or document the appropriate mitigation.
6. Publish a security advisory when disclosure is appropriate.

Response and remediation times may vary depending on the severity, complexity, affected hardware, and whether the issue involves QuantumGrid code or an upstream dependency.

## Scope

Security reports may include vulnerabilities in:

* QuantumGrid OS services
* QuantumGrid web interface
* QuantumGrid APIs
* Authentication and session handling
* SSH and management controls
* Management ACLs
* Network security components
* QuantumGrid packages
* Firmware/build integration
* Wi-Fi configuration and management
* Cellular/5G management
* System update mechanisms

QuantumGrid incorporates upstream software such as OpenWrt and other open-source components. Vulnerabilities that originate entirely in an upstream project should also be reported to the appropriate upstream security team where applicable.

## Responsible Disclosure

Please allow reasonable time for investigation and remediation before publicly disclosing a vulnerability.

We appreciate responsible security research and will make a good-faith effort to work with researchers to understand and resolve reported issues.

## Automated Security Checks

The repository runs GitHub CodeQL analysis for Python and JavaScript/TypeScript. The control-centre
CI also runs npm audit against the committed lockfile and fails when high- or critical-severity
dependency advisories are present. A successful CodeQL analysis job means the analysis completed;
it does not by itself prove that the repository has zero open alerts. Dependency advisories and
CodeQL findings must be reviewed and remediated independently.

## Security Updates

Security fixes will be included in supported releases whenever practical.

Release notes and security advisories will identify affected versions and recommended upgrade or mitigation steps when appropriate.

## Administrator web transport
On first login, the API reports whether the root password hash is configured. The
control centre sets the chosen password before opening the dashboard when rpcd has
created a bootstrap session for an empty root password. Do not attach an unconfigured
router to an untrusted network; the first administrator on the trusted LAN can claim
the initial account.


The stable AW1000 image includes uHTTPd, the mbedTLS ustream runtime and the OpenSSL
key-generation utility. On first boot, QuantumGrid removes the default plaintext HTTP
listener and enables `redirect_https` as defence in depth. The Security Center reports
configured HTTPS listener entries, TLS runtime availability, non-empty certificate/key
files and the redirect setting. This is a configuration-level check; it does not probe
live sockets or external reachability.

Every administrator POST action independently checks the uHTTPd TLS environment and
returns a forbidden response unless the request arrived over HTTPS. This does not replace
LuCI authentication, same-origin validation or trusted-network firewall policy.

Dropbear SSH is explicitly bound to the logical `lan` interface on TCP port 22. It is
not configured to listen on WAN or all interfaces. The Security Center additionally maps every
enabled Dropbear interface against actual firewall-zone network membership. Only a unique,
recognised internal zone is accepted as trusted; standard WAN/WWAN zones require review, and
custom, missing or ambiguous mappings are left unknown. This is a configuration correlation, not
a packet-path reachability test. Keep SSH port-forwarding and separate WAN firewall exposure disabled.

The optional central syslog sender has three distinct transports. UDP and TCP are plaintext and
must remain on a trusted management VLAN or VPN. TLS uses the managed stunnel client bound only
to loopback, requires the installed public CA bundle, certificate-chain verification, TLS 1.2,
an exact DNS hostname/SNI, IPv4 subject-alternative-name or IPv6 subject-alternative-name match,
and non-root stunnel user/group identities. IPv6 literals are bracketed for the stunnel endpoint
and canonicalized before certificate-identity comparison; only global-unicast and unique-local
addresses are accepted (not unspecified, loopback, link-local, multicast, documentation or
transition ranges). Alternate stunnel config files and unmanaged directives in the QuantumGrid
service section fail closed. Runtime readiness checks the PID file, process name and exact stunnel
executable/configuration arguments; the update waits briefly for that posture and rolls both
UCI configurations back if it cannot be established. These are configuration and local-process
checks only: TLS mode does not support private CA import, client-certificate mutual authentication,
multiple collectors or collector receipt testing. A successful local service restart does not
prove that the remote collector received a message.

Configuration backups are generated by the native `sysupgrade -b` utility and encrypted in the
browser before download. The `.qgbak` container uses PBKDF2-HMAC-SHA-256 (600,000 iterations),
a random salt, AES-256-GCM, a fresh nonce and authenticated metadata. The passphrase is never sent
to the router. Use a unique high-entropy passphrase stored separately from the backup; it cannot
be recovered. Both encrypted backups and the decrypted gzip archive contain sensitive settings.

Restore is an authenticated same-origin HTTPS operation. The browser decrypts locally and streams
the gzip archive to the router without sending the passphrase. Backup snapshot creation and restore
share an atomic lock. Before the native `sysupgrade -r` extractor is invoked, QuantumGrid verifies
the gzip/tar structure, bounded compressed and expanded size, exact verbose-listing metadata layout,
member count, allowed `etc/` and `root/` paths, unique names, file/directory types and mode characters,
parent/child path consistency, and absence of whitespace-ambiguous paths, symlinks, hardlinks,
special files, set-ID and sticky modes. It requires the device inventory ID, exact AW1000 profile
and OpenWrt target/architecture to match. Free `/tmp` space must cover the uploaded archive, a
maximum-sized 64 MiB rollback archive and an 8 MiB reserve. A separately generated native rollback
archive is validated before the uploaded archive can be applied. Failed restoration triggers a rollback attempt; if
rollback cannot be confirmed, its validated archive is preserved under `/tmp` and its path is reported
for out-of-band retrieval before temporary storage is cleared. A reboot is scheduled after successful
restore or successful rollback.

The stable device ID is public inventory metadata, not a secret, cryptographic hardware attestation
or publisher signature. It is an accidental cross-device guard only. AES-GCM authenticates the
encrypted container to its passphrase; it does not prove the origin of the configuration data.
Keep an independent backup and an out-of-band recovery route. These checks have not been validated
against every archive variant or on physical AW1000 recovery hardware; production rollout must test
the exact firmware/archive pair and preserve console or equivalent recovery access.

The default device certificate is self-signed. HTTPS encrypts the management session,
but it does not provide a publicly trusted device identity. The Security Center now reports
the certificate's SHA-256 fingerprint, which administrators must compare with a fingerprint
obtained through a separate trusted channel before trusting a device. This is a presentation
of the digest, not automatic certificate-chain, hostname, expiry or peer validation.
The same panel audits the HTTPS private-key file's type, root ownership and group/other
permission bits using symlink-aware filesystem metadata; a symlink is not accepted as a regular
key file. The key contents are never returned. Restrict management to trusted networks.
Do not expose the router's administration service to the public Internet.

QuantumGrid also provisions a random 128-bit device inventory ID in the writable
`/etc/quantumgrid/device-id` path. This ID is intentionally public and is only a stable
inventory key. It is not a secret, authenticator, TLS certificate, proof of board identity
or fleet-enrollment credential. A central management plane must establish trust using
separately provisioned per-device keys or certificates and an authenticated enrollment flow.

The optional RJ11 FXS packages are sourced from the third-party
`Perz3us/openwrt-aw1000-phone` repository. QuantumGrid pins the `v0.9.0` feed to
commit `fe85222e57d1c3e191ffb976b37667bbf221a020`; the upstream commit is unsigned, so
the pin enforces exact source identity but does not cryptographically authenticate
the author's identity. The FXS service remains disabled by default and needs the separate
Skyworks SLIC patch and physical telephony validation.

## Development Status

QuantumGrid OS is experimental software during development.

NSS, EDMA, PPE, cellular, authentication, and other platform components may change significantly before production releases. Development builds should not be considered secure or production-ready unless explicitly marked as such.
