import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../i18n.dart';
import '../models.dart';
import '../rust_bridge.dart';
import '../updater.dart';
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
      final update = await AppUpdate.check();
      if (update == null || !mounted) return;
      final lang = widget.settings.language;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _UpdateDialog(lang: lang, update: update),
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

class _UpdateDialog extends StatefulWidget {
  final String lang;
  final AppUpdate update;

  const _UpdateDialog({required this.lang, required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  StreamSubscription<OtaEvent>? _sub;
  bool _downloading = false;
  String? _status;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startInstall() {
    setState(() {
      _downloading = true;
      _status = tr(widget.lang, 'downloading');
    });
    _sub = widget.update.install().listen(
      (event) {
        if (!mounted) return;
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            setState(() {
              _status = '${tr(widget.lang, 'downloading')} ${event.value ?? ''}%';
            });
            break;
          case OtaStatus.INSTALLING:
            setState(() {
              _status = tr(widget.lang, 'installing');
            });
            break;
          case OtaStatus.INSTALLATION_DONE:
            setState(() {
              _downloading = false;
            });
            break;
          case OtaStatus.ALREADY_RUNNING_ERROR:
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          case OtaStatus.INTERNAL_ERROR:
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.CHECKSUM_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
          case OtaStatus.CANCELED:
            setState(() {
              _downloading = false;
              _status =
                  '${tr(widget.lang, 'updateFailed')} ${event.status.name} ${event.value ?? ''}'.trim();
            });
            break;
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _status = '${tr(widget.lang, 'updateFailed')} $e';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    return AlertDialog(
      title: Text(tr(widget.lang, 'updateAvailable')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tr(widget.lang, 'updateDescription')} v${u.version} (v${u.currentVersion})',
            ),
            if (u.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                u.releaseNotes,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: Text(tr(widget.lang, 'later')),
        ),
        FilledButton(
          onPressed: _downloading ? null : _startInstall,
          child: Text(tr(widget.lang, 'updateNow')),
        ),
      ],
    );
  }
}
