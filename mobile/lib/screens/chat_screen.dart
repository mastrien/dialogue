import 'package:flutter/material.dart';
import '../i18n.dart';
import '../models.dart';
import '../rust_bridge.dart';
import '../widgets/smooth_avatar.dart';
import 'character_form_screen.dart';
import 'group_form_screen.dart';

class ChatScreen extends StatefulWidget {
  final String lang;
  final ConversationSummary summary;
  final List<Character> characters;
  final List<Message>? initialMessages;

  const ChatScreen({
    super.key,
    required this.lang,
    required this.summary,
    required this.characters,
    this.initialMessages,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late ConversationSummary _summary;
  late List<Character> _characters;
  List<Message> _messages = [];

  String _authorKind = 'user';
  String? _selectedGroupCharId;
  Message? _replyTo;
  Message? _editingMsg;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
    _characters = widget.characters;
    _selectedGroupCharId = _summary.memberIds.isNotEmpty ? _summary.memberIds.first : null;
    if (widget.initialMessages != null) {
      _messages = widget.initialMessages!;
    } else {
      _loadMessages();
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await RustBridge.listMessages(_summary.conversation.id);
    final chars = await RustBridge.listCharacters();
    final convs = await RustBridge.listConversations();
    final updated = convs.where((c) => c.conversation.id == _summary.conversation.id).firstOrNull;
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _characters = chars;
      if (updated != null) _summary = updated;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_editingMsg != null) {
      await RustBridge.editMessage(_editingMsg!.id, text);
      setState(() {
        _editingMsg = null;
        _controller.clear();
      });
      await _loadMessages();
      return;
    }

    final isDirect = _summary.conversation.kind == 'direct';
    final charId = isDirect
        ? _summary.character?.id
        : (_authorKind == 'character' ? _selectedGroupCharId : null);

    await RustBridge.sendMessage(
      conversationId: _summary.conversation.id,
      authorKind: _authorKind,
      authorCharacterId: charId,
      content: text,
      replyToMessageId: _replyTo?.id,
    );
    setState(() {
      _replyTo = null;
      _controller.clear();
    });
    await _loadMessages();
  }

  void _showMessageActions(Message msg) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(tr(widget.lang, 'reply')),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _editingMsg = null;
                  _replyTo = msg;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(tr(widget.lang, 'edit')),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyTo = null;
                  _editingMsg = msg;
                  _controller.text = msg.content;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(tr(widget.lang, 'delete'),
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                await RustBridge.deleteMessage(msg.id);
                await _loadMessages();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDirect = _summary.conversation.kind == 'direct';
    final charMap = {for (final c in _characters) c.id: c};
    final groupMembers = _summary.memberIds
        .map((id) => charMap[id])
        .whereType<Character>()
        .toList();

    final title =
        isDirect ? (_summary.character?.name ?? '?') : _summary.conversation.name;
    final avatar =
        isDirect ? _summary.character?.avatarPath : _summary.conversation.avatarPath;
    final colorHex =
        isDirect ? (_summary.character?.bubbleColor ?? '#6366F1') : '#10B981';

    final msgMap = {for (final m in _messages) m.id: m};

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            SmoothAvatar(
              name: title,
              avatarPath: avatar,
              colorHex: colorHex,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (!isDirect)
                    Text(
                      '${groupMembers.length} ${tr(widget.lang, 'membersCount')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () async {
              if (isDirect && _summary.character != null) {
                final deleted = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterFormScreen(
                      lang: widget.lang,
                      editing: _summary.character,
                    ),
                  ),
                );
                if (deleted == true) {
                  if (mounted) Navigator.pop(context);
                  return;
                }
              } else {
                final deleted = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupFormScreen(
                      lang: widget.lang,
                      characters: _characters,
                      editing: _summary,
                    ),
                  ),
                );
                if (deleted == true) {
                  if (mounted) Navigator.pop(context);
                  return;
                }
              }
              await _loadMessages();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, idx) {
                final msg = _messages[idx];
                final isUser = msg.authorKind == 'user';
                bool sameAuthor(Message? other) =>
                    other != null &&
                    other.authorKind == msg.authorKind &&
                    other.authorCharacterId == msg.authorCharacterId &&
                    other.authorNameSnapshot == msg.authorNameSnapshot;

                final isFirstInGroup =
                    idx == 0 || !sameAuthor(_messages[idx - 1]);
                final isLastInGroup = idx == _messages.length - 1 ||
                    !sameAuthor(_messages[idx + 1]);

                final authorChar = msg.authorCharacterId != null
                    ? charMap[msg.authorCharacterId!]
                    : null;
                final authorName = isUser
                    ? tr(widget.lang, 'you')
                    : (authorChar?.name ??
                        (msg.authorNameSnapshot.isNotEmpty
                            ? msg.authorNameSnapshot
                            : tr(widget.lang, 'removedCharacter')));
                final nameColor =
                    parseHexColor(authorChar?.bubbleColor ?? '#A1A1AA');

                final isDark = Theme.of(context).brightness == Brightness.dark;
                final bubbleColor = isUser
                    ? const Color(0xFF4F46E5)
                    : (isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFE4E4E7));
                final textColor = isUser
                    ? Colors.white
                    : (isDark ? Colors.white : const Color(0xFF18181B));
                final metaColor = isUser
                    ? Colors.white70
                    : (isDark ? Colors.white60 : Colors.black54);

                final quoted = msg.replyToMessageId != null
                    ? msgMap[msg.replyToMessageId!]
                    : null;
                final isShortInline = quoted == null &&
                    msg.content.length <= 28 &&
                    !msg.content.contains('\n');

                final dt = DateTime.fromMillisecondsSinceEpoch(msg.createdAt);
                final timeStr =
                    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                final borderRadius = BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft:
                      Radius.circular(!isUser && isLastInGroup ? 4 : 18),
                  bottomRight:
                      Radius.circular(isUser && isLastInGroup ? 4 : 18),
                );

                return Padding(
                  padding: EdgeInsets.only(
                    top: isFirstInGroup ? (idx == 0 ? 0 : 12) : 3,
                  ),
                  child: Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      onLongPress: () => _showMessageActions(msg),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        child: Column(
                          crossAxisAlignment: isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (!isDirect && !isUser && isFirstInGroup)
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 38, bottom: 3),
                                child: Text(
                                  authorName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: nameColor,
                                  ),
                                ),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!isDirect && !isUser) ...[
                                  if (isLastInGroup)
                                    SmoothAvatar(
                                      name: authorName,
                                      avatarPath: authorChar?.avatarPath,
                                      colorHex:
                                          authorChar?.bubbleColor ?? '#6366F1',
                                      radius: 14,
                                    )
                                  else
                                    const SizedBox(width: 28),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: borderRadius,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (quoted != null)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(bottom: 6),
                                            padding:
                                                const EdgeInsets.only(left: 8),
                                            decoration: BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: isUser
                                                      ? Colors.white54
                                                      : const Color(0xFF6366F1),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              quoted.content,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: metaColor,
                                                  fontSize: 12),
                                            ),
                                          ),
                                        if (isShortInline)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  msg.content,
                                                  style: TextStyle(
                                                      color: textColor,
                                                      fontSize: 15),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (msg.editedAt != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 4),
                                                  child: Text(
                                                    tr(widget.lang, 'edited'),
                                                    style: TextStyle(
                                                        color: metaColor,
                                                        fontSize: 10),
                                                  ),
                                                ),
                                              Text(
                                                timeStr,
                                                style: TextStyle(
                                                    color: metaColor,
                                                    fontSize: 10),
                                              ),
                                            ],
                                          )
                                        else ...[
                                          Text(
                                            msg.content,
                                            style: TextStyle(
                                                color: textColor, fontSize: 15),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (msg.editedAt != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 6),
                                                  child: Text(
                                                    tr(widget.lang, 'edited'),
                                                    style: TextStyle(
                                                        color: metaColor,
                                                        fontSize: 10),
                                                  ),
                                                ),
                                              Text(
                                                timeStr,
                                                style: TextStyle(
                                                    color: metaColor,
                                                    fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Reply / Edit Banner
          if (_replyTo != null || _editingMsg != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_editingMsg != null ? tr(widget.lang, 'editingMessage') : tr(widget.lang, 'replyingTo')}: ${(_editingMsg ?? _replyTo)!.content}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _replyTo = null;
                        if (_editingMsg != null) {
                          _editingMsg = null;
                          _controller.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),

          // Author Toggle (1-1) or Selector (Group)
          if (_editingMsg == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: isDirect
                  ? SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'user',
                          label: Text(tr(widget.lang, 'you')),
                        ),
                        ButtonSegment(
                          value: 'character',
                          label: Text(_summary.character?.name ?? '?'),
                        ),
                      ],
                      selected: {_authorKind},
                      onSelectionChanged: (s) =>
                          setState(() => _authorKind = s.first),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(tr(widget.lang, 'you')),
                            selected: _authorKind == 'user',
                            onSelected: (_) =>
                                setState(() => _authorKind = 'user'),
                          ),
                          const SizedBox(width: 6),
                          ...groupMembers.map((m) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(m.name),
                                  selected: _authorKind == 'character' &&
                                      _selectedGroupCharId == m.id,
                                  onSelected: (_) => setState(() {
                                    _authorKind = 'character';
                                    _selectedGroupCharId = m.id;
                                  }),
                                ),
                              )),
                        ],
                      ),
                    ),
            ),

          // Input bar
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: tr(widget.lang, 'typeMessage'),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: Icon(_editingMsg != null ? Icons.check : Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
