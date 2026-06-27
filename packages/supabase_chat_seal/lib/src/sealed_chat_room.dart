import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_seal/src/safety_number.dart';
import 'package:supabase_chat_seal/src/seal_manager.dart';
import 'package:supabase_chat_seal/src/trust_store.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// A [Message] paired with its decrypted [plaintext].
///
/// [plaintext] is `null` when the message carried no encrypted body (e.g. a
/// soft-deleted message) or when decryption failed ([decryptFailed] is `true`).
class DecryptedMessage {
  /// Wraps [message] with its [plaintext].
  const DecryptedMessage(
    this.message, {
    this.plaintext,
    this.decryptFailed = false,
  });

  /// The underlying message row.
  final Message message;

  /// The recovered clear text, if available.
  final String? plaintext;

  /// Whether decryption was attempted and failed.
  final bool decryptFailed;

  /// The message id (or temporary id while pending).
  String get id => message.id;

  /// Whether this message is still awaiting its server echo.
  bool get pending => message.pending;
}

/// Wraps a [ChatRoom] so message bodies are end-to-end encrypted with a static
/// ECDH + AES-GCM sealed box: [send] encrypts per-recipient before the row ever
/// leaves the device, and [messages] decrypts incoming rows on the fly.
///
/// Scope: built for **1:1 / small direct rooms**. Each send produces one
/// ciphertext per *other* recipient, stored in the row's `encrypted` column.
/// Because the pairwise key is static and symmetric, the sender can re-derive
/// it to read their own history — so unlike the Signal variant no local
/// plaintext cache is required for correctness (one is still kept for instant
/// optimistic render).
class SealedChatRoom {
  /// Wraps `room` with sealed-box encryption.
  ///
  /// [recipientUserIds] are the *other* participants; the current user is
  /// excluded.
  SealedChatRoom(
    this._room,
    this._seal, {
    required Iterable<String> recipientUserIds,
  }) : _recipients = {
         ...recipientUserIds.where((id) => id != _room.currentUserId),
       };

  final ChatRoom _room;
  final SealManager _seal;
  final Set<String> _recipients;

  /// Clear-text cache keyed by client id (preferred) or message id, for instant
  /// optimistic render of just-sent messages.
  final Map<String, String> _plaintext = {};

  /// The underlying room (for advanced/raw access).
  ChatRoom get raw => _room;

  /// The local user id.
  String get currentUserId => _room.currentUserId;

  /// The other participants whose messages are encrypted.
  Set<String> get recipients => Set.unmodifiable(_recipients);

  /// Computes the [SafetyNumber] to compare out of band with [userId]
  /// (defaults to the sole recipient in a 1:1 room).
  Future<SafetyNumber> safetyNumber([String? userId]) =>
      _seal.safetyNumber(userId ?? _soleRecipient);

  /// The [TrustLevel] for [userId] (defaults to the 1:1 peer).
  Future<TrustLevel> verificationLevel([String? userId]) =>
      _seal.verificationLevel(userId ?? _soleRecipient);

  /// Whether [userId] (defaults to the 1:1 peer) has been verified.
  Future<bool> isVerified([String? userId]) =>
      _seal.isVerified(userId ?? _soleRecipient);

  /// Marks [userId] (defaults to the 1:1 peer) verified after an out-of-band
  /// safety-number comparison. Required before [send] in strict mode.
  Future<void> markVerified([String? userId]) =>
      _seal.markVerified(userId ?? _soleRecipient);

  /// Accepts a changed key for [userId] (defaults to the 1:1 peer) after
  /// re-verification (e.g. the peer reinstalled).
  Future<void> acceptIdentityChange([String? userId]) =>
      _seal.acceptIdentityChange(userId ?? _soleRecipient);

  String get _soleRecipient {
    if (_recipients.length != 1) {
      throw StateError(
        'pass a userId: this room has ${_recipients.length} recipients',
      );
    }
    return _recipients.first;
  }

  /// Live, decrypted message list (newest-last, same ordering as the room).
  Stream<List<DecryptedMessage>> get messages =>
      _room.messages.asyncMap(_decryptList);

  /// Live typing user ids (passthrough — typing state is not encrypted).
  Stream<List<String>> get typingUserIds => _room.typingUserIds;

  /// Live reactions grouped by message id (passthrough — emoji are not secret).
  Stream<Map<String, List<Reaction>>> get reactionsByMessage =>
      _room.reactionsByMessage;

  /// Live presence list (passthrough).
  Stream<List<JsonMap>> get presentUsers => _room.presentUsers;

  /// Joins the room and ensures sessions exist for all recipients.
  Future<void> join() async {
    await _room.join();
    for (final id in _recipients) {
      await _seal.ensureSession(id);
    }
  }

  /// Encrypts [text] for every recipient and sends it.
  ///
  /// In strict mode this returns an [Err] holding an
  /// [UnverifiedRecipientException] if any recipient is unverified, or an
  /// [IdentityChangedException] if a recipient's key changed — nothing is sent.
  Future<Result<DecryptedMessage>> send(String text) async {
    final Map<String, dynamic> encrypted;
    try {
      encrypted = await _seal.encryptFor(_recipients, text);
    } on Object catch (error, stackTrace) {
      return Err(error, stackTrace);
    }
    final result = await _room.send(extra: {'encrypted': encrypted});
    return result.map((message) {
      final key = message.clientId ?? message.id;
      _plaintext[key] = text;
      return DecryptedMessage(message, plaintext: text);
    });
  }

  /// Adds an emoji [reaction] to a message (not encrypted).
  Future<Result<void>> react(String messageId, String reaction) =>
      _room.react(messageId, reaction);

  /// Removes an emoji [reaction] (not encrypted).
  Future<Result<void>> removeReaction(String messageId, String reaction) =>
      _room.removeReaction(messageId, reaction);

  /// Broadcasts a typing indicator (not encrypted).
  Future<void> setTyping({required bool typing}) =>
      _room.setTyping(typing: typing);

  /// Marks the room (or up to [messageId]) as read.
  Future<Result<void>> markRead([String? messageId]) =>
      _room.markRead(messageId);

  /// Loads an older page of messages.
  Future<void> loadMore() => _room.loadMore();

  /// Leaves the room and releases resources.
  Future<void> leave() => _room.leave();

  Future<List<DecryptedMessage>> _decryptList(List<Message> messages) async {
    final out = <DecryptedMessage>[];
    for (final message in messages) {
      out.add(await _decryptOne(message));
    }
    return out;
  }

  Future<DecryptedMessage> _decryptOne(Message message) async {
    final key = message.clientId ?? message.id;
    final cached = _plaintext[key];
    if (cached != null) return DecryptedMessage(message, plaintext: cached);

    final encrypted = message.extra['encrypted'];
    if (encrypted is! Map) {
      // Not an encrypted message (e.g. legacy/plain or soft-deleted).
      return DecryptedMessage(message, plaintext: message.content);
    }

    try {
      final (envelope, peerUserId) = _envelopeFor(message, encrypted);
      final text = await _seal.decrypt(envelope, peerUserId);
      _plaintext[key] = text;
      return DecryptedMessage(message, plaintext: text);
    } on Object {
      return DecryptedMessage(message, decryptFailed: true);
    }
  }

  /// Selects the envelope to decrypt and the peer whose key unlocks it.
  ///
  /// For our own message we re-derive the key with any recipient it was
  /// addressed to; for an incoming message we use the copy addressed to us and
  /// the sender's key.
  (Map<String, dynamic>, String) _envelopeFor(
    Message message,
    Map<dynamic, dynamic> encrypted,
  ) {
    if (message.senderId == currentUserId) {
      for (final entry in encrypted.entries) {
        final peer = entry.key as String;
        if (peer == currentUserId) continue;
        return (Map<String, dynamic>.from(entry.value as Map), peer);
      }
      throw StateError('no recipient envelope on own message');
    }
    final mine = encrypted[currentUserId];
    if (mine is! Map) throw StateError('no ciphertext addressed to us');
    return (Map<String, dynamic>.from(mine), message.senderId);
  }
}
