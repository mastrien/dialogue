import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

typedef _DialogueInvokeNative = Pointer<Utf8> Function(
    Pointer<Utf8> method, Pointer<Utf8> argsJson);
typedef _DialogueInvokeDart = Pointer<Utf8> Function(
    Pointer<Utf8> method, Pointer<Utf8> argsJson);

typedef _DialogueFreeNative = Void Function(Pointer<Utf8> ptr);
typedef _DialogueFreeDart = void Function(Pointer<Utf8> ptr);

DynamicLibrary _openCoreLib(String? overridePath) {
  if (overridePath != null && overridePath.isNotEmpty) {
    return DynamicLibrary.open(overridePath);
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libdialogue_core.so');
  }
  if (Platform.isWindows) {
    for (final candidate in [
      'dialogue_core.dll',
      '../target/debug/dialogue_core.dll',
      '../target/release/dialogue_core.dll',
    ]) {
      if (File(candidate).existsSync()) {
        return DynamicLibrary.open(candidate);
      }
    }
    return DynamicLibrary.open('dialogue_core.dll');
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform');
}

dynamic _invokeSync(String method, Map<String, dynamic> args, String? libPath) {
  final lib = _openCoreLib(libPath);
  final invokeFn = lib
      .lookup<NativeFunction<_DialogueInvokeNative>>('dialogue_invoke')
      .asFunction<_DialogueInvokeDart>();
  final freeFn = lib
      .lookup<NativeFunction<_DialogueFreeNative>>('dialogue_free_string')
      .asFunction<_DialogueFreeDart>();

  final methodPtr = method.toNativeUtf8();
  final argsPtr = jsonEncode(args).toNativeUtf8();
  final resPtr = invokeFn(methodPtr, argsPtr);
  calloc.free(methodPtr);
  calloc.free(argsPtr);

  try {
    final resStr = resPtr.toDartString();
    final decoded = jsonDecode(resStr) as Map<String, dynamic>;
    if (decoded['ok'] == true) {
      return decoded['data'];
    }
    throw Exception(decoded['error'] ?? 'Unknown Rust core error');
  } finally {
    freeFn(resPtr);
  }
}

class RustBridge {
  static String mediaDir = '';
  static String? libraryPathOverride;
  static bool useSyncInTests = false;

  static Future<dynamic> invoke(String method,
      [Map<String, dynamic> args = const {}]) {
    final path = libraryPathOverride;
    if (useSyncInTests) {
      return Future.value(_invokeSync(method, args, path));
    }
    return Isolate.run(() => _invokeSync(method, args, path));
  }

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    await initWithDir(dir.path);
  }

  static Future<void> initWithDir(String dataDir) async {
    await invoke('init', {'data_dir': dataDir});
    mediaDir = (await invoke('get_media_dir')) as String;
  }

  static String? resolveMediaFile(String? filename) {
    if (filename == null || filename.isEmpty || mediaDir.isEmpty) return null;
    return '$mediaDir${Platform.pathSeparator}$filename';
  }

  static Future<AppSettings> getSettings() async {
    final data = await invoke('get_settings');
    return AppSettings.fromJson(data as Map<String, dynamic>);
  }

  static Future<AppSettings> updateSettings({
    String? theme,
    String? language,
    String? deviceName,
  }) async {
    final data = await invoke('update_settings', {
      if (theme != null) 'theme': theme,
      if (language != null) 'language': language,
      if (deviceName != null) 'device_name': deviceName,
    });
    return AppSettings.fromJson(data as Map<String, dynamic>);
  }

  static Future<String> importMediaFile(String path) async {
    return (await invoke('import_media_file', {'path': path})) as String;
  }

  static Future<List<Character>> listCharacters() async {
    final list = (await invoke('list_characters')) as List<dynamic>;
    return list
        .map((e) => Character.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Character> createCharacter({
    required String name,
    required String description,
    String? avatarPath,
    required String bubbleColor,
  }) async {
    final data = await invoke('create_character', {
      'name': name,
      'description': description,
      'avatar_path': avatarPath,
      'bubble_color': bubbleColor,
    });
    return Character.fromJson(data as Map<String, dynamic>);
  }

  static Future<Character> updateCharacter({
    required String id,
    String? name,
    String? description,
    String? avatarPath,
    bool updateAvatar = false,
    String? bubbleColor,
  }) async {
    final data = await invoke('update_character', {
      'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (updateAvatar) 'avatar_path': avatarPath,
      if (bubbleColor != null) 'bubble_color': bubbleColor,
    });
    return Character.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteCharacter(String id) async {
    await invoke('delete_character', {'id': id});
  }

  static Future<List<ConversationSummary>> listConversations() async {
    final list = (await invoke('list_conversations')) as List<dynamic>;
    return list
        .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ConversationSummary> createGroup({
    required String name,
    required String description,
    String? avatarPath,
    required List<String> memberCharacterIds,
  }) async {
    final data = await invoke('create_group', {
      'name': name,
      'description': description,
      'avatar_path': avatarPath,
      'member_character_ids': memberCharacterIds,
    });
    return ConversationSummary.fromJson(data as Map<String, dynamic>);
  }

  static Future<ConversationSummary> updateGroup({
    required String id,
    String? name,
    String? description,
    String? avatarPath,
    bool updateAvatar = false,
    List<String>? memberCharacterIds,
  }) async {
    final data = await invoke('update_group', {
      'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (updateAvatar) 'avatar_path': avatarPath,
      if (memberCharacterIds != null) 'member_character_ids': memberCharacterIds,
    });
    return ConversationSummary.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteGroup(String id) async {
    await invoke('delete_group', {'id': id});
  }

  static Future<List<Message>> listMessages(String conversationId) async {
    final list =
        (await invoke('list_messages', {'id': conversationId})) as List<dynamic>;
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Message> sendMessage({
    required String conversationId,
    required String authorKind,
    String? authorCharacterId,
    required String content,
    String? replyToMessageId,
  }) async {
    final data = await invoke('send_message', {
      'conversation_id': conversationId,
      'author_kind': authorKind,
      'author_character_id': authorCharacterId,
      'content': content,
      'reply_to_message_id': replyToMessageId,
    });
    return Message.fromJson(data as Map<String, dynamic>);
  }

  static Future<Message> editMessage(
      String messageId, String newContent) async {
    final data = await invoke('edit_message', {
      'message_id': messageId,
      'new_content': newContent,
    });
    return Message.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteMessage(String messageId) async {
    await invoke('delete_message', {'id': messageId});
  }

  static Future<PairedDevice> pairWithQrJson(String qrJson) async {
    final payload = jsonDecode(qrJson) as Map<String, dynamic>;
    final data = await invoke('pair_with_qr_payload', payload);
    return PairedDevice.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<PairedDevice>> listPairedDevices() async {
    final list = (await invoke('list_paired_devices')) as List<dynamic>;
    return list
        .map((e) => PairedDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> removePairedDevice(String id) async {
    await invoke('remove_paired_device', {'id': id});
  }

  static Future<List<DiscoveredPeer>> discoverLanPeers() async {
    final list = (await invoke('discover_lan_peers')) as List<dynamic>;
    return list
        .map((e) => DiscoveredPeer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<SyncReport> syncWithPeer(
      String host, int port, String deviceId) async {
    final data = await invoke('sync_with_peer', {
      'host': host,
      'port': port,
      'device_id': deviceId,
    });
    return SyncReport.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> exportBackup(String path) async {
    await invoke('export_backup', {'path': path});
  }

  static Future<SyncReport> importBackup(String path) async {
    final data = await invoke('import_backup', {'path': path});
    return SyncReport.fromJson(data as Map<String, dynamic>);
  }

  static Future<UpdateInfo?> checkForUpdate() async {
    final data = await invoke('check_for_update');
    if (data == null) return null;
    return UpdateInfo.fromJson(data as Map<String, dynamic>);
  }
}
