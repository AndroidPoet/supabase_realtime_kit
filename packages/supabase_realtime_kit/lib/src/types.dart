/// Shared primitive types used across the kit.
library;

/// A JSON object as returned by Supabase.
typedef JsonMap = Map<String, dynamic>;

/// Builds a `T` from a database row.
typedef FromJson<T> = T Function(JsonMap json);

/// Extracts the stable server identity (primary key) of an item.
typedef IdSelector<T> = Object Function(T item);

/// Extracts the optimistic-reconciliation key of an item, or `null` if it has
/// none. For chat this is the client-generated `client_id`: an optimistic row
/// and its eventual server echo share the same key, so the echo replaces the
/// placeholder instead of duplicating it.
typedef PendingKeySelector<T> = Object? Function(T item);
