import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_e2ee/src/e2ee_manager.dart';
import 'package:supabase_chat_e2ee/src/safety_number.dart';
import 'package:supabase_chat_e2ee/src/trust_store.dart';
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

/// Wraps a [ChatRoom] so message bodies are end-to-end encrypted with the
/// Signal Protocol: [send] encrypts per-recipient before the row ever leaves
/// the device, and [messages] decrypts incoming rows on the fly.
///
/// Scope: built for **1:1 / small direct rooms**. Each send produces one
/// ciphertext per *other* recipient, stored in the row's `encrypted` column;
/// the sender's own copy is kept in a local plaintext cache (Signal can't
/// encrypt-to-self on a single device). The server only ever sees ciphertext.
/// Large group rooms should use Signal's SenderKey fan-out instead — not yet
/// implemented here.
class EncryptedChatRoom {
  /// Wraps `room` with end-to-end encryption.
  ///
  /// [recipientUserIds] are the *other* participants. The current user is
  /// excluded (self-readback comes from the local plaintext cache).
  EncryptedChatRoom(
    this._room,
    this._e2ee, {
    required Iterable<String> recipientUserIds,
  }) : _recipients = {
         ...recipientUserIds.where((id) => id != _room.currentUserId),
       };

  final ChatRoom _room;
  final E2eeManager _e2ee;
  final Set<String> _recipients;

  /// Clear-text cache keyed by client id (preferred) or message id, so a
  /// ciphertext is only ever decrypted once (the Signal ratchet is one-shot).
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
      _e2ee.safetyNumber(userId ?? _soleRecipient);

  /// The [TrustLevel] for [userId] (defaults to the 1:1 peer).
  Future<TrustLevel> verificationLevel([String? userId]) =>
      _e2ee.verificationLevel(userId ?? _soleRecipient);

  /// Whether [userId] (defaults to the 1:1 peer) has been verified.
  Future<bool> isVerified([String? userId]) =>
      _e2ee.isVerified(userId ?? _soleRecipient);

  /// Marks [userId] (defaults to the 1:1 peer) verified after an out-of-band
  /// safety-number comparison. Required before [send] in strict mode.
  Future<void> markVerified([String? userId]) =>
      _e2ee.markVerified(userId ?? _soleRecipient);

  /// Accepts a changed identity for [userId] (defaults to the 1:1 peer) after
  /// re-verification (e.g. the peer reinstalled).
  Future<void> acceptIdentityChange([String? userId]) =>
      _e2ee.acceptIdentityChange(userId ?? _soleRecipient);

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
      if (id == currentUserId) continue;
      await _e2ee.ensureSession(id);
    }
  }

  /// Encrypts [text] for every recipient and sends it. The plaintext is cached
  /// locally so the optimistic message and its server echo render immediately
  /// without attempting to decrypt our own (one-shot) ciphertext.
  ///
  /// In strict mode this returns an [Err] holding an
  /// [UnverifiedRecipientException] if any recipient is unverified, or an
  /// [IdentityChangedException] if a recipient's key changed — nothing is sent.
  Future<Result<DecryptedMessage>> send(String text) async {
    final Map<String, dynamic> encrypted;
    try {
      encrypted = await _e2ee.encryptFor(_recipients, text);
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

    final mine = encrypted[currentUserId];
    if (mine is! Map) {
      // No ciphertext addressed to us.
      return DecryptedMessage(message, decryptFailed: true);
    }

    try {
      final text = await _e2ee.decrypt(
        Map<String, dynamic>.from(mine),
        message.senderId,
      );
      _plaintext[key] = text;
      return DecryptedMessage(message, plaintext: text);
    } on Object {
      return DecryptedMessage(message, decryptFailed: true);
    }
  }
}
