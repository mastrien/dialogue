import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dialogue_mobile/i18n.dart';
import 'package:dialogue_mobile/models.dart';
import 'package:dialogue_mobile/rust_bridge.dart';
import 'package:dialogue_mobile/screens/character_form_screen.dart';
import 'package:dialogue_mobile/screens/chat_screen.dart';
import 'package:dialogue_mobile/screens/group_form_screen.dart';
import 'package:dialogue_mobile/screens/home_screen.dart';
import 'package:dialogue_mobile/screens/settings_screen.dart';
import 'package:dialogue_mobile/updater.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    RustBridge.useSyncInTests = true;
    tempDir = Directory.systemTemp.createTempSync('dialogue_flutter_test_');
    await RustBridge.initWithDir(tempDir.path);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('i18n returns English and Portuguese strings', () {
    expect(tr('en', 'you'), 'You');
    expect(tr('pt', 'you'), 'Você');
    expect(tr('en', 'unknown_key'), 'unknown_key');
  });

  test('models deserialize from Rust core JSON', () {
    final ch = Character.fromJson({
      'id': 'c1',
      'name': 'Alice',
      'description': 'Bio',
      'avatar_path': null,
      'bubble_color': '#EC4899',
      'created_at': 1000,
      'updated_at': 1000,
    });
    expect(ch.name, 'Alice');
    expect(ch.bubbleColor, '#EC4899');

    final peer = DiscoveredPeer.fromJson({
      'device_id': 'd1',
      'device_name': 'Desktop',
      'host': '192.168.1.10',
      'port': 5000,
      'is_paired': true,
    });
    expect(peer.isPaired, isTrue);

    final report = SyncReport.fromJson({
      'characters_merged': 1,
      'conversations_merged': 2,
      'members_merged': 3,
      'messages_merged': 4,
      'media_downloaded': 0,
    });
    expect(report.messagesMerged, 4);
  });

  test('RustBridge FFI full CRUD, groups, messages, and backup', () async {
    final settings = await RustBridge.getSettings();
    expect(settings.theme, 'dark');
    expect(settings.language, 'en');

    final updated = await RustBridge.updateSettings(deviceName: 'Test Phone');
    expect(updated.deviceName, 'Test Phone');

    final ch = await RustBridge.createCharacter(
      name: 'FFI Alice',
      description: 'Test bio',
      bubbleColor: '#EC4899',
    );
    expect(ch.name, 'FFI Alice');

    final editedCh = await RustBridge.updateCharacter(
      id: ch.id,
      name: 'FFI Alice 2',
      description: 'Updated bio',
      bubbleColor: '#6366F1',
    );
    expect(editedCh.name, 'FFI Alice 2');

    final convs = await RustBridge.listConversations();
    final direct = convs.firstWhere((c) => c.character?.id == ch.id);

    final m1 = await RustBridge.sendMessage(
      conversationId: direct.conversation.id,
      authorKind: 'user',
      content: 'Hello',
    );
    final m2 = await RustBridge.sendMessage(
      conversationId: direct.conversation.id,
      authorKind: 'character',
      authorCharacterId: ch.id,
      content: 'Hi there, how are you doing today?',
      replyToMessageId: m1.id,
    );
    expect(m2.replyToMessageId, m1.id);

    final editedMsg = await RustBridge.editMessage(m1.id, 'Hello edited');
    expect(editedMsg.editedAt, isNotNull);

    await RustBridge.deleteMessage(m1.id);
    final msgs = await RustBridge.listMessages(direct.conversation.id);
    expect(msgs.length, 1);

    final grp = await RustBridge.createGroup(
      name: 'FFI Group',
      description: 'Group desc',
      memberCharacterIds: [ch.id],
    );
    expect(grp.memberIds, [ch.id]);

    final updatedGrp = await RustBridge.updateGroup(
      id: grp.conversation.id,
      name: 'FFI Group 2',
      memberCharacterIds: [],
    );
    expect(updatedGrp.conversation.name, 'FFI Group 2');

    final backupPath = '${tempDir.path}${Platform.pathSeparator}test_backup.zip';
    await RustBridge.exportBackup(backupPath);
    expect(File(backupPath).existsSync(), isTrue);
    final impReport = await RustBridge.importBackup(backupPath);
    expect(impReport.charactersMerged, 0); // already up-to-date

    await RustBridge.deleteGroup(grp.conversation.id);
    await RustBridge.deleteCharacter(ch.id);
  });

  testWidgets('HomeScreen creates character via CharacterFormScreen and opens ChatScreen',
      (tester) async {
    final settings = await RustBridge.getSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          settings: settings,
          onSettingsChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open New Character
    await tester.tap(find.byIcon(Icons.person_add_outlined));
    await tester.pumpAndSettle();

    // Empty name shows validation SnackBar
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CharacterFormScreen)))
        .clearSnackBars();
    await tester.pumpAndSettle();

    // Fill name and create
    await tester.enterText(find.byType(TextField).first, 'Widget Bob');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Appears in HomeScreen list
    expect(find.text('Widget Bob'), findsOneWidget);

    // Tap to open ChatScreen
    await tester.tap(find.text('Widget Bob'));
    await tester.pumpAndSettle();

    // Send a short message as You
    await tester.enterText(find.byType(TextField), 'Oi!');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('Oi!'), findsOneWidget);

    // Toggle to character and send a longer message
    await tester.tap(find.text('Widget Bob').last);
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      'This is a much longer message from Widget Bob to test stacked timestamp.',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'This is a much longer message from Widget Bob to test stacked timestamp.'),
      findsOneWidget,
    );

    // Long press first message -> Edit
    await tester.longPress(find.text('Oi!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Oi editado');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(find.text('Oi editado'), findsOneWidget);

    // Cleanup character
    final chars = await RustBridge.listCharacters();
    for (final c in chars) {
      await RustBridge.deleteCharacter(c.id);
    }
  });

  testWidgets('ChatScreen groups consecutive group messages and colors only author name',
      (tester) async {
    final alice = Character(
      id: 'c1',
      name: 'Alice',
      description: '',
      bubbleColor: '#EC4899',
      createdAt: 1,
      updatedAt: 1,
    );
    final summary = ConversationSummary(
      conversation: Conversation(
        id: 'g1',
        kind: 'group',
        name: 'Team',
        description: '',
        createdAt: 1,
        updatedAt: 1,
      ),
      memberIds: ['c1'],
    );
    final messages = [
      Message(
        id: 'm1',
        conversationId: 'g1',
        authorKind: 'character',
        authorCharacterId: 'c1',
        authorNameSnapshot: 'Alice',
        content: 'Short 1',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
      Message(
        id: 'm2',
        conversationId: 'g1',
        authorKind: 'character',
        authorCharacterId: 'c1',
        authorNameSnapshot: 'Alice',
        content: 'Short 2',
        createdAt: 1700000060000,
        updatedAt: 1700000060000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          lang: 'en',
          summary: summary,
          characters: [alice],
          initialMessages: messages,
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Alice'),
      ),
      findsOneWidget,
    );
    expect(find.text('Short 1'), findsOneWidget);
    expect(find.text('Short 2'), findsOneWidget);

    // Swipe right on "Short 1" to mark as reply
    await tester.drag(find.text('Short 1'), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Replying to:'), findsOneWidget);
  });

  test('isNewerVersion compares semver correctly', () {
    expect(isNewerVersion('0.1.3', '0.1.2'), isTrue);
    expect(isNewerVersion('0.2.0', '0.1.9'), isTrue);
    expect(isNewerVersion('0.1.2', '0.1.2'), isFalse);
    expect(isNewerVersion('0.1.1', '0.1.2'), isFalse);
  });

  testWidgets('GroupFormScreen & SettingsScreen render and update settings',
      (tester) async {
    var settings = await RustBridge.getSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: settings,
          onSettingsChanged: (s) => settings = s,
          onDataChanged: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(settings.theme, 'light');

    await tester.tap(find.text('Português'));
    await tester.pumpAndSettle();
    expect(settings.language, 'pt');

    // Reset back to defaults
    await RustBridge.updateSettings(theme: 'dark', language: 'en');

    // Test GroupFormScreen render
    await tester.pumpWidget(
      const MaterialApp(
        home: GroupFormScreen(lang: 'en', characters: []),
      ),
    );
    expect(find.text('New Group'), findsOneWidget);
  });
}
