## 0.1.0

- Initial release.
- `RealtimeKit` facade over `SupabaseClient`.
- `LiveQuery<T>`: realtime list with optimistic merge, pagination, and
  reconnect reconciliation.
- `PresenceTracker` and `BroadcastHub` for presence and ephemeral signals.
- Pluggable `Outbox` (in-memory default) with auto-flush on reconnect and a
  delivery retry cap (poison entries are dead-lettered, not retried forever).
- Pure `LiveListState<T>` merge engine (extracted from `LiveQuery`).
- `Result<T>` error-honest return type.
