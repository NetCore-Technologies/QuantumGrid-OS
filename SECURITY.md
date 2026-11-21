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
Every administrator POST action also checks the uHTTPd TLS environment server-side
and returns a forbidden response when the request did not arrive over HTTPS. The redirect
is therefore not the only protection for password setup or configuration-changing APIs.
This TLS requirement does not replace LuCI authentication, same-origin validation or
trusted-network firewall policy.



The stable AW1000 image includes uHTTPd, the mbedTLS ustream runtime and the OpenSSL
key-generation utility. On first boot, QuantumGrid sets uHTTPd's `redirect_https`
option so requests arriving on the default HTTP listeners are redirected to HTTPS.
The Security Center reports configured HTTPS listener entries, TLS runtime availability,
non-empty certificate/key files and HTTP redirect configuration. This is a configuration-
level check; it does not probe live sockets or external reachability.

The optional RJ11 FXS packages are sourced from the third-party
`Perz3us/openwrt-aw1000-phone` repository. QuantumGrid pins the `v0.9.0` feed to
commit `fe85222e57d1c3e191ffb976b37667bbf221a020`; the upstream commit is unsigned, so this pin enforces exact source
identity but does not cryptographically authenticate the upstream author's identity.
The FXS service remains disabled by default and still requires the separate Skyworks
SLIC patch and physical telephony validation.

The default device certificate is self-signed. HTTPS encrypts the management session,
but it does not provide a publicly trusted device identity. Administrators should verify
the certificate fingerprint over a trusted channel and keep the management interface
restricted to trusted management networks. Do not expose the router's administration
service to the public Internet.

## Development Status

QuantumGrid OS is experimental software during development.

NSS, EDMA, PPE, cellular, authentication, and other platform components may change significantly before production releases. Development builds should not be considered secure or production-ready unless explicitly marked as such.
