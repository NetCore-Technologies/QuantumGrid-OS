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

## Security Updates

Security fixes will be included in supported releases whenever practical.

Release notes and security advisories will identify affected versions and recommended upgrade or mitigation steps when appropriate.

## Development Status

QuantumGrid OS is experimental software during development.

NSS, EDMA, PPE, cellular, authentication, and other platform components may change significantly before production releases. Development builds should not be considered secure or production-ready unless explicitly marked as such.
