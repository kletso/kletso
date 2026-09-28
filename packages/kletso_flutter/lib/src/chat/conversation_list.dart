import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../listenable_adapter.dart';
import '../theme/kletso_theme.dart';

/// List of the end user's conversations with a "new conversation" row.
final class KletsoConversationList extends StatefulWidget {
  /// Creates the list for [client].
  const KletsoConversationList({
    required this.client,
    super.key,
    this.onSelected,
  });

  /// The client.
  final KletsoClient client;

  /// Called after a conversation was switched to or created.
  final VoidCallback? onSelected;

  @override
  State<KletsoConversationList> createState() => _KletsoConversationListState();
}

final class _KletsoConversationListState extends State<KletsoConversationList> {
  late final KletsoListenable<List<KletsoConversation>> _list = widget
      .client
      .conversations
      .asFlutter();
  late final KletsoListenable<KletsoConversation?> _active = widget
      .client
      .activeConversation
      .asFlutter();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.client.listConversations().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    }).ignore();
  }

  @override
  void dispose() {
    _list.dispose();
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_list, _active]),
      builder: (context, _) {
        final items = _list.value;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.add_comment_outlined, color: t.primary),
              title: Text(
                'New conversation',
                style: t.subtitle.copyWith(color: t.primary),
              ),
              onTap: () async {
                await widget.client.startConversation();
                widget.onSelected?.call();
              },
            ),
            if (_loading && items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(color: t.primary),
                ),
              ),
            for (final c in items)
              ListTile(
                selected: c.id == _active.value?.id,
                selectedTileColor: t.primarySoft,
                shape: RoundedRectangleBorder(borderRadius: t.borderRadiusMd),
                leading: Icon(switch (c.status) {
                  KletsoConversationStatus.handoff => Icons.support_agent,
                  KletsoConversationStatus.closed => Icons.check_circle_outline,
                  _ => Icons.chat_bubble_outline,
                }, color: t.textMuted),
                title: Text(
                  c.title ?? 'Conversation',
                  style: t.subtitle,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _when(c.updatedAt ?? c.createdAt),
                  style: t.caption,
                ),
                onTap: () async {
                  await widget.client.switchConversation(c.id);
                  widget.onSelected?.call();
                },
              ),
          ],
        );
      },
    );
  }

  static String _when(DateTime? d) {
    if (d == null) return '';
    final local = d.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    String two(int n) => n.toString().padLeft(2, '0');
    return sameDay
        ? '${two(local.hour)}:${two(local.minute)}'
        : '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
