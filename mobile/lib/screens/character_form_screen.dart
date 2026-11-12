import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../i18n.dart';
import '../models.dart';
import '../rust_bridge.dart';
import '../widgets/smooth_avatar.dart';

const _bubbleColors = [
  '#6366F1',
  '#8B5CF6',
  '#EC4899',
  '#F43F5E',
  '#F59E0B',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
];

class CharacterFormScreen extends StatefulWidget {
  final String lang;
  final Character? editing;

  const CharacterFormScreen({
    super.key,
    required this.lang,
    this.editing,
  });

  @override
  State<CharacterFormScreen> createState() => _CharacterFormScreenState();
}

class _CharacterFormScreenState extends State<CharacterFormScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _avatarPath;
  bool _avatarChanged = false;
  String _bubbleColor = _bubbleColors.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _nameCtrl.text = widget.editing!.name;
      _descCtrl.text = widget.editing!.description;
      _avatarPath = widget.editing!.avatarPath;
      _bubbleColor = widget.editing!.bubbleColor;
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      final saved = await RustBridge.importMediaFile(xfile.path);
      if (!mounted) return;
      setState(() {
        _avatarPath = saved;
        _avatarChanged = true;
      });
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError(tr(widget.lang, 'name'));
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    try {
      if (widget.editing != null) {
        await RustBridge.updateCharacter(
          id: widget.editing!.id,
          name: name,
          description: _descCtrl.text.trim(),
          avatarPath: _avatarPath,
          updateAvatar: _avatarChanged,
          bubbleColor: _bubbleColor,
        );
      } else {
        await RustBridge.createCharacter(
          name: name,
          description: _descCtrl.text.trim(),
          avatarPath: _avatarPath,
          bubbleColor: _bubbleColor,
        );
      }
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.editing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(widget.lang, 'deleteCharacter')),
        content: Text(tr(widget.lang, 'confirmDeleteCharacter')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(widget.lang, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(widget.lang, 'delete'),
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await RustBridge.deleteCharacter(widget.editing!.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            tr(widget.lang, isEdit ? 'editCharacter' : 'newCharacter')),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              SmoothAvatar(
                name: _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                avatarPath: _avatarPath,
                colorHex: _bubbleColor,
                radius: 34,
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: _pickImage,
                child: Text(tr(widget.lang, 'pickImage')),
              ),
              if (_avatarPath != null)
                TextButton(
                  onPressed: () => setState(() {
                    _avatarPath = null;
                    _avatarChanged = true;
                  }),
                  child: Text(tr(widget.lang, 'removeImage')),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr(widget.lang, 'name'),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tr(widget.lang, 'description'),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr(widget.lang, 'bubbleColor'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _bubbleColors.map((hex) {
              final selected = hex == _bubbleColor;
              return GestureDetector(
                onTap: () => setState(() => _bubbleColor = hex),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: parseHexColor(hex),
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(tr(widget.lang, isEdit ? 'save' : 'create')),
          ),
        ],
      ),
    );
  }
}
