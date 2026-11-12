class Character {
  final String id;
  final String name;
  final String description;
  final String? avatarPath;
  final String bubbleColor;
  final int createdAt;
  final int updatedAt;

  Character({
    required this.id,
    required this.name,
    required this.description,
    this.avatarPath,
    required this.bubbleColor,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Character.fromJson(Map<String, dynamic> j) => Character(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['description'] as String?) ?? '',
        avatarPath: j['avatar_path'] as String?,
        bubbleColor: (j['bubble_color'] as String?) ?? '#6366F1',
        createdAt: j['created_at'] as int,
        updatedAt: j['updated_at'] as int,
      );
}

class Conversation {
  final String id;
  final String kind; // 'direct' | 'group'
  final String? directCharacterId;
  final String name;
  final String description;
  final String? avatarPath;
  final int createdAt;
  final int updatedAt;

  Conversation({
    required this.id,
    required this.kind,
    this.directCharacterId,
    required this.name,
    required this.description,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        kind: j['kind'] as String,
        directCharacterId: j['direct_character_id'] as String?,
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        avatarPath: j['avatar_path'] as String?,
        createdAt: j['created_at'] as int,
        updatedAt: j['updated_at'] as int,
      );
}

class Message {
  final String id;
  final String conversationId;
  final String authorKind; // 'user' | 'character'
  final String? authorCharacterId;
  final String authorNameSnapshot;
  final String content;
  final String? replyToMessageId;
  final int createdAt;
  final int updatedAt;
  final int? editedAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.authorKind,
    this.authorCharacterId,
    required this.authorNameSnapshot,
    required this.content,
    this.replyToMessageId,
    required this.createdAt,
    required this.updatedAt,
    this.editedAt,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        authorKind: j['author_kind'] as String,
        authorCharacterId: j['author_character_id'] as String?,
        authorNameSnapshot: (j['author_name_snapshot'] as String?) ?? '',
        content: j['content'] as String,
        replyToMessageId: j['reply_to_message_id'] as String?,
        createdAt: j['created_at'] as int,
        updatedAt: j['updated_at'] as int,
        editedAt: j['edited_at'] as int?,
      );
}

class ConversationSummary {
  final Conversation conversation;
  final Character? character;
  final List<String> memberIds;
  final Message? lastMessage;

  ConversationSummary({
    required this.conversation,
    this.character,
    required this.memberIds,
    this.lastMessage,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) =>
      ConversationSummary(
        conversation:
            Conversation.fromJson(j['conversation'] as Map<String, dynamic>),
        character: j['character'] != null
            ? Character.fromJson(j['character'] as Map<String, dynamic>)
            : null,
        memberIds: ((j['member_ids'] as List<dynamic>?) ?? [])
            .map((e) => e as String)
            .toList(),
        lastMessage: j['last_message'] != null
            ? Message.fromJson(j['last_message'] as Map<String, dynamic>)
            : null,
      );
}

class AppSettings {
  final String theme; // 'dark' | 'light'
  final String language; // 'en' | 'pt'
  final String deviceId;
  final String deviceName;

  AppSettings({
    required this.theme,
    required this.language,
    required this.deviceId,
    required this.deviceName,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        theme: (j['theme'] as String?) ?? 'dark',
        language: (j['language'] as String?) ?? 'en',
        deviceId: j['device_id'] as String,
        deviceName: j['device_name'] as String,
      );
}

class PairedDevice {
  final String deviceId;
  final String deviceName;
  final int lastSyncAt;
  final int pairedAt;

  PairedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.lastSyncAt,
    required this.pairedAt,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        deviceId: j['device_id'] as String,
        deviceName: j['device_name'] as String,
        lastSyncAt: j['last_sync_at'] as int,
        pairedAt: j['paired_at'] as int,
      );
}

class DiscoveredPeer {
  final String deviceId;
  final String deviceName;
  final String host;
  final int port;
  final bool isPaired;

  DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.host,
    required this.port,
    required this.isPaired,
  });

  factory DiscoveredPeer.fromJson(Map<String, dynamic> j) => DiscoveredPeer(
        deviceId: j['device_id'] as String,
        deviceName: j['device_name'] as String,
        host: j['host'] as String,
        port: j['port'] as int,
        isPaired: j['is_paired'] as bool,
      );
}

class SyncReport {
  final int charactersMerged;
  final int conversationsMerged;
  final int membersMerged;
  final int messagesMerged;
  final int mediaDownloaded;

  SyncReport({
    required this.charactersMerged,
    required this.conversationsMerged,
    required this.membersMerged,
    required this.messagesMerged,
    required this.mediaDownloaded,
  });

  factory SyncReport.fromJson(Map<String, dynamic> j) => SyncReport(
        charactersMerged: j['characters_merged'] as int,
        conversationsMerged: j['conversations_merged'] as int,
        membersMerged: j['members_merged'] as int,
        messagesMerged: j['messages_merged'] as int,
        mediaDownloaded: j['media_downloaded'] as int,
      );
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;
  final String? downloadUrl;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUrl,
    this.downloadUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        currentVersion: j['current_version'] as String,
        latestVersion: j['latest_version'] as String,
        releaseNotes: (j['release_notes'] as String?) ?? '',
        releaseUrl: j['release_url'] as String,
        downloadUrl: j['download_url'] as String?,
      );
}
