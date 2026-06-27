## 0.1.0

- Initial release.
- `RealtimeKit` facade over `SupabaseClient`.
- `LiveQuery<T>`: realtime list with optimistic merge, pagination, and
  reconnect reconciliation.
- `PresenceTracker` and `BroadcastHub` for presence and ephemeral signals.
- Pluggable `Outbox` (in-memory default) with auto-flush on reconnect.
- `Result<T>` error-honest return type.
