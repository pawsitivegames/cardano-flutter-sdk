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

This project is currently pre-1.0 and the current package version is `0.12.0`.

- `0.12.x` and the current `main` branch receive security fixes when practical
- Older `0.x` versions receive best-effort support; upgrade to the current
  release before reporting a problem that may already be fixed
- No `1.x` support commitment is made until a `1.0.0` release exists

## Security Practices

- Security reviews are recorded in `docs/security-review-phase7.md`; this
  policy does not claim a recurring audit cadence
- Dependency alerts and Dependabot status: verify in GitHub repository settings
- No hardcoded secrets in the repository
- All Rust code passes `cargo clippy --all-targets -- -D warnings`
- The Dart package passes `flutter analyze` with no issues. The example app is
  analyzed with errors blocking and warnings visible; its known warnings are
  limited to explicitly experimental hardware-wallet and scoped web APIs.

Dependency-alert and Dependabot status are controlled by GitHub repository
settings and are not asserted by this file. The repository currently has no
committed `.github/dependabot.yml`; maintainers must verify those settings
directly before treating automated dependency monitoring as enabled.

## Disclosure Timeline

Once a security fix is ready:

1. We will prepare a patch release
2. Notify security@cardano-flutter-sdk.dev (or your report contact) with details
3. Publish the affected package release through its supported distribution
   channel
4. Post a security advisory on GitHub when appropriate
5. Announce the fix on community channels when appropriate

We appreciate your responsible disclosure and will credit you appropriately (unless you prefer anonymity).
