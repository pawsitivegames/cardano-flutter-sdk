# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: security@cardano-flutter-sdk.dev

Include in your report:

- Description of the vulnerability
- Affected versions
- Steps to reproduce (if applicable)
- Proposed fix (if you have one)

**Response:** We will acknowledge within 48 hours and coordinate a fix.

## Supported Versions

- Latest minor version (v1.x.y) receives security fixes
- Previous minor versions: best-effort support
- v0.x: best-effort support; consider upgrading to v1.0+

## Security Practices

- Regular security audits (quarterly)
- Dependency scanning (dependabot enabled)
- No hardcoded secrets in the repository
- All Rust code passes `cargo clippy --all-targets -- -D warnings`
- All Dart code passes `flutter analyze` with no warnings

## Disclosure Timeline

Once a security fix is ready:

1. We will prepare a patch release
2. Notify security@cardano-flutter-sdk.dev (or your report contact) with details
3. Publish the fix to pub.dev and crates.io
4. Post a security advisory on GitHub
5. Announce the fix on community channels

We appreciate your responsible disclosure and will credit you appropriately (unless you prefer anonymity).
