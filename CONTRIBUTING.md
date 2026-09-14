# Contributing to QuantumGrid OS

QuantumGrid OS is an OpenWrt-based networking operating system developed by **NetCore Technologies**.

The project focuses on high-performance networking, gaming optimization, Wi-Fi intelligence, security, 5G/cellular connectivity, telemetry, hardware acceleration, and a modern management experience.

We welcome contributions that improve QuantumGrid OS, whether they are code changes, packages, hardware support, documentation, testing, UI improvements, or bug fixes.

---

## Getting Started

Before contributing:

1. Fork the QuantumGrid OS repository.
2. Clone your fork locally.
3. Create a dedicated branch for your changes.
4. Make your changes.
5. Test your changes.
6. Commit your work clearly.
7. Push your branch.
8. Open a Pull Request.

Example:

```bash
git clone https://github.com/NetCore-Technologies/QuantumGrid-OS.git
cd QuantumGrid-OS

git checkout -b feature/my-feature
```

---

## What You Can Contribute

### 🧩 OpenWrt Packages

You can contribute new or improved packages for:

* Networking
* Wi-Fi
* Gaming
* Security
* Monitoring
* 5G and cellular
* Hardware acceleration
* System management
* QuantumGrid-specific services

Make sure new packages are properly configured and tested before submitting them.

---

### ⚡ Performance

Performance improvements are an important part of QuantumGrid OS.

Contributions can include:

* Faster packet processing
* Reduced latency
* Improved CPU utilization
* Hardware acceleration
* NSS/EDMA improvements
* SQM and bufferbloat improvements
* Network throughput improvements
* Faster boot times
* Lower memory usage

If possible, include before-and-after benchmarks with your Pull Request.

---

### 📡 Wi-Fi

Wi-Fi contributions can include:

* Driver improvements
* Channel management
* Wireless diagnostics
* Roaming improvements
* Multi-band optimization
* Wi-Fi telemetry
* 5 GHz / 6 GHz improvements
* Signal and interference monitoring

When submitting hardware-specific changes, clearly state the hardware that was tested.

---

### 🎮 Gaming & Network Optimization

QuantumGrid OS includes features designed to improve gaming and latency.

Contributions can include:

* QoS improvements
* SQM improvements
* Bufferbloat reduction
* Latency monitoring
* Traffic prioritization
* Gaming device detection
* Connection monitoring
* WAN optimization

Avoid claiming performance improvements without testing them.

---

### 📱 5G & Cellular

Contributions for cellular networking are welcome.

Examples include:

* Modem support
* QMI/MBIM improvements
* APN management
* Signal monitoring
* Cellular diagnostics
* Automatic failover
* 4G/5G management
* Modem recovery

Include modem model, chipset, firmware version, and relevant configuration when submitting hardware-specific changes.

---

### 🖥️ QuantumGrid UI

QuantumGrid OS aims to provide a modern networking interface.

UI contributions should maintain the QuantumGrid design direction and focus on:

* Clear navigation
* Responsive layouts
* Network telemetry
* Useful diagnostics
* Accessible controls
* Dark/light themes
* Consistent components
* Good performance

For UI Pull Requests, include screenshots when they help demonstrate the change.

---

### 🔐 Security

Security improvements are encouraged.

Examples include:

* Firewall improvements
* Safer defaults
* Authentication improvements
* Security monitoring
* Permission fixes
* Vulnerability fixes
* Secure update mechanisms

Do not include passwords, private keys, tokens, or other sensitive information in commits or Pull Requests.

For security vulnerabilities, follow the repository's security reporting process instead of publicly posting sensitive exploit details.

---

## 🐛 Reporting Bugs

When reporting a bug, provide as much useful information as possible.

Include:

* Device model
* SoC/platform
* QuantumGrid OS version
* OpenWrt version where relevant
* Installed packages
* Configuration
* Steps to reproduce
* Expected behavior
* Actual behavior
* Relevant logs
* Screenshots where useful

A good bug report should allow another developer to reproduce the problem.

---

## 🔧 Hardware Contributions

When adding support for new hardware, provide:

```text
Device:
SoC:
RAM:
Flash:
Ethernet:
Wi-Fi:
Modem:
OpenWrt Target:
OpenWrt Subtarget:
QuantumGrid Configuration:
Testing Performed:
```

Do not mark hardware as fully supported unless it has actually been tested.

---

## 🧪 Testing

Always test changes before opening a Pull Request.

At minimum, check:

```bash
git diff --check
git status
```

For build changes, build the affected target or package.

For networking changes, test the relevant networking functionality.

For UI changes, test the affected pages and responsive layouts.

For hardware changes, test on the actual target hardware whenever possible.

---

## 🌿 Branches

Use descriptive branch names.

Examples:

```text
feature/wifi-telemetry
feature/5g-failover
feature/gaming-qos
fix/wifi-crash
fix/modem-detection
perf/nss-networking
ui/dashboard-telemetry
docs/build-guide
```

Avoid working directly on the main branch.

---

## 📝 Commit Messages

Use clear commit messages that explain what changed.

Preferred formats:

```text
feat: add 5G signal monitoring
fix: correct modem detection
perf: improve packet processing
wifi: improve channel scanning
security: harden firewall defaults
ui: improve network dashboard
docs: update build instructions
build: update firmware workflow
test: add Wi-Fi regression tests
refactor: simplify telemetry service
```

Keep commits focused on one logical change whenever possible.

---

## 🔀 Pull Requests

Before opening a Pull Request:

* Make sure your branch is up to date.
* Test your changes.
* Check for unintended modifications.
* Run `git diff --check`.
* Write a clear Pull Request description.
* Include screenshots or benchmarks where useful.

A Pull Request should explain:

### What changed?

Describe the implementation.

### Why?

Explain the problem being solved.

### Testing

Explain what hardware, firmware, targets, or environments were tested.

### Additional Notes

Mention compatibility issues, limitations, dependencies, or anything maintainers should know.

---

## 📚 Documentation

Documentation improvements are always welcome.

You can contribute:

* Build guides
* Installation instructions
* Hardware documentation
* Troubleshooting guides
* Package documentation
* Configuration examples
* Developer documentation
* API documentation

Keep documentation accurate and avoid documenting features that have not been tested.

---

## 📦 Dependencies

When adding dependencies:

* Prefer existing OpenWrt packages.
* Avoid unnecessary dependencies.
* Consider firmware size.
* Consider RAM and CPU requirements.
* Check upstream maintenance status.
* Verify licensing compatibility.

---

## 🚫 Do Not Commit

Never commit:

```text
.env
private keys
passwords
API tokens
SSH keys
personal configuration
private certificates
user data
large generated build artifacts
```

Check your changes before pushing:

```bash
git status
git diff
```

---

## 📜 Licensing

All contributions must comply with the licenses used by QuantumGrid OS and its dependencies.

Do not submit code, images, documentation, or other assets that you do not have permission to redistribute.

---

## 💬 Contribution Process

For larger changes, discuss the idea before spending significant development time on it.

A typical contribution process is:

```text
Idea
 ↓
Issue / Discussion
 ↓
Fork
 ↓
Feature Branch
 ↓
Development
 ↓
Testing
 ↓
Pull Request
 ↓
Review
 ↓
Changes / Approval
 ↓
Merge
```

Keep Pull Requests focused and make changes requested during review before asking for approval again.

---

## 🤝 Code of Conduct

Contributors are expected to communicate respectfully and constructively.

Technical disagreements are welcome, but discussions should remain focused on the project, implementation, and technical evidence.

Harassment, personal attacks, spam, and deliberately disruptive behavior are not acceptable.

---

## Final Note

We appreciate all **feedback, bug reports, testing, ideas, documentation, and code contributions** that help improve QuantumGrid OS.

Every contribution helps make QuantumGrid OS better.
