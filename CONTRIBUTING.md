# Contributing

Bug reports and focused feature proposals are welcome. Before opening an issue,
check the existing issues and the [v1 stability contract](Docs/STABILITY.md).

For code changes:

1. Keep Core independent of UI, persistence, services, and macOS adapters.
2. Preserve one canonical Storage Inventory and the reviewed cleanup workflow.
3. Keep unknown data protected and observability read-only and redacted.
4. Add focused tests for changed behavior.
5. Run:

   ```bash
   swift test --disable-sandbox
   (cd observability && swift test --disable-sandbox)
   ```

Do not attach local data, full paths, Recovery manifests, or diagnostic exports
to public issues. Maintenance and support are provided on a best-effort basis.
