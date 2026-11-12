import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../i18n.dart';
import '../models.dart';
import '../rust_bridge.dart';
import '../widgets/smooth_avatar.dart';
import 'character_form_screen.dart';
import 'chat_screen.dart';
import 'group_form_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Character> _characters = [];
  List<ConversationSummary> _conversations = [];
  String _search = '';
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) => _autoSync());
    if (!RustBridge.useSyncInTests) {
      _checkUpdate();
    }
  }

  Future<void> _checkUpdate() async {
    try {
      final info = await RustBridge.checkForUpdate();
      if (info == null || !mounted) return;
      final lang = widget.settings.language;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(lang, 'updateAvailable')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tr(lang, 'updateDescription')} v${info.latestVersion} (v${info.currentVersion})',
                ),
                if (info.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    info.releaseNotes,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(lang, 'later')),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(info.downloadUrl ?? info.releaseUrl);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Text(tr(lang, 'updateNow')),
            ),
          ],
        ),
      );
    } catch (_) {
      // Ignore network errors on offline startup
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final chars = await RustBridge.listCharacters();
    final convs = await RustBridge.listConversations();
    if (!mounted) return;
    setState(() {
      _characters = chars;
      _conversations = convs;
    });
  }

  Future<void> _autoSync() async {
    try {
      final paired = await RustBridge.listPairedDevices();
      if (paired.isEmpty) return;
      final peers = await RustBridge.discoverLanPeers();
      bool changed = false;
      for (final p in peers.where((e) => e.isPaired)) {
        final report = await RustBridge.syncWithPeer(p.host, p.port, p.deviceId);
        if (report.charactersMerged > 0 ||
            report.conversationsMerged > 0 ||
            report.messagesMerged > 0 ||
            report.membersMerged > 0) {
          changed = true;
        }
      }
      if (changed) await _refresh();
    } catch (_) {
      // Ignore background LAN sync errors silently
    }
  }

  String _formatTime(int? ms) {
    if (ms == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.language;
    final filtered = _conversations.where((c) {
      final title = c.conversation.kind == 'direct'
          ? (c.character?.name ?? '')
          : c.conversation.name;
      return title.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(lang, 'appTitle'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: tr(lang, 'newCharacter'),
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CharacterFormScreen(lang: lang),
                ),
              );
              await _refresh();
            },
          ),
          IconButton(
            tooltip: tr(lang, 'newGroup'),
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      GroupFormScreen(lang: lang, characters: _characters),
                ),
              );
              await _refresh();
            },
          ),
          IconButton(
            tooltip: tr(lang, 'settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    settings: widget.settings,
                    onSettingsChanged: widget.onSettingsChanged,
                    onDataChanged: _refresh,
                  ),
                ),
              );
              await _refresh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: tr(lang, 'searchPlaceholder'),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        tr(lang, 'noConversations'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final item = filtered[idx];
                        final isDirect = item.conversation.kind == 'direct';
                        final title = isDirect
                            ? (item.character?.name ?? '?')
                            : item.conversation.name;
                        final avatar = isDirect
                            ? item.character?.avatarPath
                            : item.conversation.avatarPath;
                        final color = isDirect
                            ? (item.character?.bubbleColor ?? '#6366F1')
                            : '#10B981';

                        return ListTile(
                          leading: SmoothAvatar(
                            name: title,
                            avatarPath: avatar,
                            colorHex: color,
                          ),
                          title: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            item.lastMessage?.content ??
                                tr(lang, 'noMessagesYet'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatTime(item.lastMessage?.createdAt),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  lang: lang,
                                  summary: item,
                                  characters: _characters,
                                ),
                              ),
                            );
                            await _refresh();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
