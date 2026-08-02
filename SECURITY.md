# Security Policy

Second Wind makes local filesystem changes, so reports about path validation,
Recovery containment, helper authentication, persistence integrity, diagnostic
redaction, or observability exposure are especially important.

Please report a suspected vulnerability privately through GitHub's
**Security → Report a vulnerability** flow. Do not include private filesystem
paths, user names, Recovery references, or diagnostic exports in a public issue.

The current v1.x line receives best-effort security fixes. Older previews are
not supported. This project does not provide guaranteed response times.

The standard release is ad-hoc signed and not Apple-notarized. This is a known
distribution limitation, not a claim that Gatekeeper has verified the publisher.
