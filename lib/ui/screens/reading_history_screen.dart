import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/reading_activity.dart';
import '../components/common.dart';
import '../theme.dart';

class ReadingHistoryScreen extends StatefulWidget {
  const ReadingHistoryScreen({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final AppController controller;
  final ValueChanged<ReadingActivity> onOpen;

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  ReadingActivityKind? _kind;
  String? _bookId;

  String _kindLabel(ReadingActivityKind kind) => switch (kind) {
    ReadingActivityKind.opened => '开始阅读',
    ReadingActivityKind.chapter => '阅读章节',
    ReadingActivityKind.finished => '读完本书',
  };

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _clear(BuildContext context) async {
    if (!await confirmRemoval(
      context,
      '清空阅读足迹？',
      '只删除当前设备的阅读足迹，书籍、进度和笔记仍会保留。',
    )) {
      return;
    }
    if (context.mounted) {
      try {
        await widget.controller.clearReadingActivities();
      } catch (error) {
        if (context.mounted) showMessage(context, errorMessage(error));
      }
    }
  }

  List<ReadingActivity> _filtered(List<ReadingActivity> activities) => [
    for (final activity in activities)
      if ((_kind == null || activity.kind == _kind) &&
          (_bookId == null || activity.bookId == _bookId))
        activity,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('阅读足迹', style: TextStyle(fontSize: 18)),
      actions: [
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => IconButton(
            key: const Key('reading-history-clear'),
            tooltip: '清空阅读足迹',
            onPressed: widget.controller.readingActivities.isEmpty
                ? null
                : () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final activities = widget.controller.readingActivities;
        if (activities.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState(
              title: '每一次翻页，都在这里',
              description: '打开章节、切换章节或读完一本书后，会在当前设备留下最近的阅读足迹。',
            ),
          );
        }
        final books = <String, String>{
          for (final activity in activities)
            if (activity.bookId.isNotEmpty) activity.bookId: activity.bookTitle,
        };
        final filtered = _filtered(activities);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        key: const Key('history-kind-all'),
                        label: const Text('全部事件'),
                        selected: _kind == null,
                        onSelected: (_) => setState(() => _kind = null),
                      ),
                      for (final kind in ReadingActivityKind.values)
                        FilterChip(
                          key: Key('history-kind-${kind.name}'),
                          label: Text(_kindLabel(kind)),
                          selected: _kind == kind,
                          onSelected: (_) => setState(() => _kind = kind),
                        ),
                      PopupMenuButton<String>(
                        key: const Key('history-book-filter'),
                        tooltip: '筛选书籍',
                        onSelected: (bookId) => setState(
                          () => _bookId = bookId.isEmpty ? null : bookId,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem<String>(
                            value: '',
                            child: Text('全部书籍'),
                          ),
                          for (final entry in books.entries)
                            PopupMenuItem<String>(
                              key: Key('history-book-option-${entry.key}'),
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        child: Chip(
                          avatar: const Icon(
                            Icons.menu_book_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _bookId == null
                                ? '全部书籍'
                                : books[_bookId] ?? '已移除书籍',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: EmptyState(
                            title: '没有匹配的阅读足迹',
                            description: '试试切换事件或书籍筛选条件。',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final activity = filtered[index];
                            return QuietPanel(
                              padding: EdgeInsets.zero,
                              child: InkWell(
                                key: Key('reading-history-item-$index'),
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => widget.onOpen(activity),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(switch (activity.kind) {
                                        ReadingActivityKind.opened =>
                                          Icons.menu_book_outlined,
                                        ReadingActivityKind.chapter =>
                                          Icons.auto_stories_outlined,
                                        ReadingActivityKind.finished =>
                                          Icons.emoji_events_outlined,
                                      }, color: AppColors.blue),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              activity.bookTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${activity.chapterTitle} · ${_kindLabel(activity.kind)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: AppColors.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _timeLabel(activity.occurredAt),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
