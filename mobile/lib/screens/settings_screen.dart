import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../i18n.dart';
import '../models.dart';
import '../rust_bridge.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Future<void> Function() onDataChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.onDataChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  final _deviceNameCtrl = TextEditingController();
  List<PairedDevice> _paired = [];
  List<DiscoveredPeer> _peers = [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _deviceNameCtrl.text = _settings.deviceName;
    _loadPaired();
  }

  Future<void> _loadPaired() async {
    final list = await RustBridge.listPairedDevices();
    if (mounted) setState(() => _paired = list);
  }

  Future<void> _scanQr() async {
    final qrJson = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (qrJson == null) return;
    await _pairFromQrString(qrJson);
  }

  Future<void> _pairFromQrString(String qrJson) async {
    try {
      final qrMap = jsonDecode(qrJson) as Map<String, dynamic>;
      final paired = await RustBridge.pairWithQrJson(qrJson);
      await _loadPaired();
      // Sync directly using the QR's host:port so initial sync works even if mDNS is blocked
      final host = qrMap['host'] as String;
      final port = qrMap['port'] as int;
      final report = await RustBridge.syncWithPeer(host, port, paired.deviceId);
      await widget.onDataChanged();
      if (mounted) {
        setState(() => _status =
            'Paired with ${paired.deviceName}! (+${report.charactersMerged} chars, +${report.messagesMerged} msgs)');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Pair/Sync error: $e');
    }
  }

  Future<void> _scanLan() async {
    setState(() => _status = '...');
    final peers = await RustBridge.discoverLanPeers();
    if (mounted) {
      setState(() {
        _peers = peers;
        _status = null;
      });
    }
  }

  Future<void> _exportBackup() async {
    final tmp = await getTemporaryDirectory();
    final path = '${tmp.path}/dialogue-backup.zip';
    await RustBridge.exportBackup(path);
    await Share.shareXFiles([XFile(path)]);
  }

  Future<void> _importBackup() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    final report = await RustBridge.importBackup(path);
    await widget.onDataChanged();
    if (mounted) {
      setState(() => _status =
          'Imported: ${report.charactersMerged} chars, ${report.messagesMerged} msgs');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = _settings.language;
    return Scaffold(
      appBar: AppBar(title: Text(tr(lang, 'settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr(lang, 'theme'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'dark', label: Text(tr(lang, 'dark'))),
              ButtonSegment(value: 'light', label: Text(tr(lang, 'light'))),
            ],
            selected: {_settings.theme},
            onSelectionChanged: (s) async {
              final updated = await RustBridge.updateSettings(theme: s.first);
              setState(() => _settings = updated);
              widget.onSettingsChanged(updated);
            },
          ),
          const SizedBox(height: 16),
          Text(tr(lang, 'language'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'pt', label: Text('Português')),
            ],
            selected: {_settings.language},
            onSelectionChanged: (s) async {
              final updated =
                  await RustBridge.updateSettings(language: s.first);
              setState(() => _settings = updated);
              widget.onSettingsChanged(updated);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deviceNameCtrl,
                  decoration: InputDecoration(
                    labelText: tr(lang, 'deviceName'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final updated = await RustBridge.updateSettings(
                      deviceName: _deviceNameCtrl.text.trim());
                  setState(() => _settings = updated);
                  widget.onSettingsChanged(updated);
                },
                child: Text(tr(lang, 'save')),
              ),
            ],
          ),
          const Divider(height: 32),
          Text(tr(lang, 'lanSync'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(tr(lang, 'scanQr')),
              ),
              OutlinedButton.icon(
                onPressed: _scanLan,
                icon: const Icon(Icons.wifi_find),
                label: Text(tr(lang, 'discoverPeers')),
              ),
            ],
          ),
          if (_peers.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._peers.map((p) => ListTile(
                  title: Text(p.deviceName),
                  subtitle: Text('${p.host}:${p.port}'),
                  trailing: p.isPaired
                      ? TextButton(
                          onPressed: () async {
                            final r = await RustBridge.syncWithPeer(
                                p.host, p.port, p.deviceId);
                            await widget.onDataChanged();
                            setState(() => _status =
                                '+${r.messagesMerged} msgs, +${r.charactersMerged} chars');
                          },
                          child: Text(tr(lang, 'syncNow')),
                        )
                      : null,
                )),
          ],
          const SizedBox(height: 14),
          Text(tr(lang, 'pairedDevices'),
              style: Theme.of(context).textTheme.labelLarge),
          if (_paired.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr(lang, 'noPairedDevices'),
                  style: const TextStyle(color: Colors.grey)),
            )
          else
            ..._paired.map((d) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.deviceName),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    onPressed: () async {
                      await RustBridge.removePairedDevice(d.deviceId);
                      await _loadPaired();
                    },
                  ),
                )),
          const Divider(height: 32),
          Text(tr(lang, 'backup'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _exportBackup,
                icon: const Icon(Icons.download),
                label: Text(tr(lang, 'exportBackup')),
              ),
              OutlinedButton.icon(
                onPressed: _importBackup,
                icon: const Icon(Icons.upload),
                label: Text(tr(lang, 'importBackup')),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _popped = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: MobileScanner(
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    '${error.errorCode.name}: ${error.errorDetails?.message ?? ''}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
        onDetect: (capture) {
          if (_popped) return;
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (raw != null && raw.isNotEmpty) {
            _popped = true;
            Navigator.pop(context, raw);
          }
        },
      ),
    );
  }
}
