import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../i18n.dart';
import '../models.dart';
import '../rust_bridge.dart';
import '../widgets/smooth_avatar.dart';

class GroupFormScreen extends StatefulWidget {
  final String lang;
  final List<Character> characters;
  final ConversationSummary? editing;

  const GroupFormScreen({
    super.key,
    required this.lang,
    required this.characters,
    this.editing,
  });

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _avatarPath;
  bool _avatarChanged = false;
  final Set<String> _memberIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _nameCtrl.text = widget.editing!.conversation.name;
      _descCtrl.text = widget.editing!.conversation.description;
      _avatarPath = widget.editing!.conversation.avatarPath;
      _memberIds.addAll(widget.editing!.memberIds);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final saved = await RustBridge.importMediaFile(xfile.path);
    setState(() {
      _avatarPath = saved;
      _avatarChanged = true;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    if (widget.editing != null) {
      await RustBridge.updateGroup(
        id: widget.editing!.conversation.id,
        name: name,
        description: _descCtrl.text.trim(),
        avatarPath: _avatarPath,
        updateAvatar: _avatarChanged,
        memberCharacterIds: _memberIds.toList(),
      );
    } else {
      await RustBridge.createGroup(
        name: name,
        description: _descCtrl.text.trim(),
        avatarPath: _avatarPath,
        memberCharacterIds: _memberIds.toList(),
      );
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _delete() async {
    if (widget.editing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(widget.lang, 'deleteGroup')),
        content: Text(tr(widget.lang, 'confirmDeleteGroup')),
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
      await RustBridge.deleteGroup(widget.editing!.conversation.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(widget.lang, isEdit ? 'editGroup' : 'newGroup')),
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
                name: _nameCtrl.text.isEmpty ? 'G' : _nameCtrl.text,
                avatarPath: _avatarPath,
                colorHex: '#10B981',
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
            maxLines: 2,
            decoration: InputDecoration(
              labelText: tr(widget.lang, 'description'),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr(widget.lang, 'members'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ...widget.characters.map((ch) => CheckboxListTile(
                value: _memberIds.contains(ch.id),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _memberIds.add(ch.id);
                    } else {
                      _memberIds.remove(ch.id);
                    }
                  });
                },
                secondary: SmoothAvatar(
                  name: ch.name,
                  avatarPath: ch.avatarPath,
                  colorHex: ch.bubbleColor,
                  radius: 18,
                ),
                title: Text(ch.name),
              )),
          const SizedBox(height: 24),
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
