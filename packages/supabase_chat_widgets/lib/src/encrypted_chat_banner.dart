import 'package:flutter/material.dart';

/// A header banner showing the end-to-end-encryption verification state.
///
/// When [verified] is false it shows the [safetyNumber] (to compare out of
/// band) and a "Verify" button; once verified it collapses to a slim
/// "verified" indicator. Purely presentational — it carries **no** crypto
/// dependency, so it works above any E2EE flavor (`supabase_chat_seal` (MIT) or
/// `supabase_chat_e2ee` (GPL)): just feed it the room's verification state.
class EncryptedChatBanner extends StatelessWidget {
  /// Creates a verification banner.
  const EncryptedChatBanner({
    required this.verified,
    required this.onVerify,
    super.key,
    this.loading = false,
    this.safetyNumber,
    this.peerLabel,
  });

  /// Whether the peer's identity has been verified.
  final bool verified;

  /// Whether trust state is still loading (renders a slim placeholder).
  final bool loading;

  /// The formatted safety number to compare out of band, when unverified.
  final String? safetyNumber;

  /// A human label for the peer.
  final String? peerLabel;

  /// Called when the user taps "Verify".
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (loading) {
      return const SizedBox(height: 2, child: LinearProgressIndicator());
    }

    if (verified) {
      return Container(
        width: double.infinity,
        color: scheme.secondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_rounded,
              size: 16,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 6),
            Text(
              'End-to-end encrypted · verified',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final peer = peerLabel ?? 'this contact';
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify $peer',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.tonal(
                onPressed: onVerify,
                child: const Text('Verify'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Compare this security code on both devices, then tap Verify.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (safetyNumber != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              safetyNumber!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
