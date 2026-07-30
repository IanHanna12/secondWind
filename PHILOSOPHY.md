# Second Wind philosophy

Second Wind is intentionally conservative.

It exists to help people understand and make deliberate storage changes on
their own Mac—not to invent problems, create urgency, or promise magic.

## Understand before acting

Second Wind acts only on locations and categories it explicitly understands.
Unknown, ambiguous, or sensitive data is left untouched rather than guessed
at. A small, explainable scope is more valuable than a broad, opaque one.

## Review before changing

A scan is observation, not action. Every change is shown in a plan and must be
explicitly confirmed. Choosing a destination is part of that final review.
Opening a review sheet never moves a file.

## Prefer recovery over destruction

Second Wind moves reviewed items to Finder Trash or local Recovery storage.
Recovery items remain on the Mac and are never deleted automatically. Permanent
deletion is a separate, deliberate action.

## Make honest claims

Second Wind does not claim to clean RAM, speed up a Mac, repair permissions, or
calculate invented system-health scores. It reports the local information it
can support and states the limits of that information.

## Use the least privilege needed

The standard app works without elevated privilege. The optional helper exists
only for tightly defined operations that macOS requires it for. It accepts
typed, validated requests—not arbitrary commands, shell text, or filesystem
paths—and verifies that its caller is the signed Second Wind app.

## Keep data local and visible

Second Wind has no account, remote telemetry, analytics, cloud sync, remote rule
downloads, or update checks. Its decisions come from bundled rules, its
activity is stored locally, and its behavior should be traceable in the code.

## Grow through explicit policy

New cleanup capability should be added only when its boundaries, recovery
story, review flow, and tests are clear. Convenience is not a reason to make a
destructive action less understandable.
