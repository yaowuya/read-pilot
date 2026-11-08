import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/reading_activity.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../theme.dart';

/// 阅读记录：按设计稿顶部是本周/上周的时长、七天柱状图与三项统计，
/// 下面接最近在读和可筛选的阅读足迹时间线。
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
  bool _lastWeek = false;

  /// 同一次阅读里两次记录之间最多算半小时，避免把整夜的空档当成长阅读。
  static const _sessionCap = Duration(minutes: 30);

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

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

  DateTime get _weekStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime get _rangeStart =>
      _lastWeek ? _weekStart.subtract(const Duration(days: 7)) : _weekStart;

  DateTime get _rangeEnd =>
      _lastWeek ? _weekStart : _weekStart.add(const Duration(days: 7));

  List<ReadingActivity> _inRange(List<ReadingActivity> activities) => [
    for (final activity in activities)
      if (!activity.occurredAt.toLocal().isBefore(_rangeStart) &&
          activity.occurredAt.toLocal().isBefore(_rangeEnd))
        activity,
  ];

  /// 阅读时长按相邻两条记录之间的间隔累加，单段超过 [_sessionCap] 就不计入。
  Duration _sessionDuration(List<ReadingActivity> activities) {
    if (activities.length < 2) return Duration.zero;
    final times = [for (final a in activities) a.occurredAt.toLocal()]..sort();
    var total = Duration.zero;
    for (var i = 1; i < times.length; i++) {
      final gap = times[i].difference(times[i - 1]);
      if (gap > Duration.zero && gap <= _sessionCap) total += gap;
    }
    return total;
  }

  /// 七天柱状图：每天按同样的间隔口径估算的分钟数。
  List<int> _dailyMinutes(List<ReadingActivity> activities) {
    final values = List<int>.filled(7, 0);
    for (var day = 0; day < 7; day++) {
      final start = _rangeStart.add(Duration(days: day));
      final end = start.add(const Duration(days: 1));
      final dayActivities = [
        for (final a in activities)
          if (!a.occurredAt.toLocal().isBefore(start) &&
              a.occurredAt.toLocal().isBefore(end))
            a,
      ];
      values[day] = _sessionDuration(dayActivities).inMinutes;
    }
    return values;
  }

  int _dayCount(List<ReadingActivity> activities) => {
    for (final a in activities)
      '${a.occurredAt.toLocal().year}-${a.occurredAt.toLocal().month}-${a.occurredAt.toLocal().day}',
  }.length;

  int _bookCount(List<ReadingActivity> activities) => {
    for (final a in activities)
      if (a.bookId.isNotEmpty) a.bookId,
  }.length;

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
    appBar: AppTopBar(
      onBack: () => Navigator.of(context).maybePop(),
      title: '阅读记录',
      actions: [
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => CircleIconButton(
            key: const Key('reading-history-clear'),
            tooltip: '清空阅读足迹',
            icon: Icons.delete_sweep_outlined,
            selected: false,
            onPressed: widget.controller.readingActivities.isEmpty
                ? () {}
                : () => _clear(context),
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
        final inRange = _inRange(activities);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                _weekSwitch(),
                _statHero(inRange),
                _barChart(_dailyMinutes(inRange)),
                _statsGrid(inRange),
                _goal(),
                _recentSection(),
                const SectionLabel('阅读足迹'),
                _filterRow(books),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: EmptyState(
                      title: '没有匹配的阅读足迹',
                      description: '试试切换事件或书籍筛选条件。',
                    ),
                  )
                else
                  for (var index = 0; index < filtered.length; index++)
                    _activityRow(filtered[index], index),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _weekSwitch() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5F8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _weekTab('本周', !_lastWeek, const Key('history-week-this')),
            _weekTab('上周', _lastWeek, const Key('history-week-last')),
          ],
        ),
      ),
    ),
  );

  Widget _weekTab(String label, bool active, Key key) => Expanded(
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _lastWeek = label == '上周'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: active ? const Color(0xFF414E61) : const Color(0xFF89919D),
          ),
        ),
      ),
    ),
  );

  Widget _statHero(List<ReadingActivity> inRange) {
    final duration = _sessionDuration(inRange);
    final hours = duration.inMinutes ~/ 60;
    final minutes = duration.inMinutes % 60;
    return Column(
      children: [
        Text(
          _lastWeek ? '上周阅读时长' : '本周阅读时长',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        Text.rich(
          key: const Key('history-stat-duration'),
          TextSpan(
            children: [
              TextSpan(
                text: '$hours',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const TextSpan(
                text: '小时',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              TextSpan(
                text: '$minutes',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const TextSpan(
                text: '分钟',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          '慢慢读，也在慢慢积累',
          style: TextStyle(fontSize: 11, color: Color(0xFFA0A7B1)),
        ),
      ],
    );
  }

  Widget _barChart(List<int> values) {
    final peak = values.fold<int>(
      0,
      (best, value) => value > best ? value : best,
    );
    return Container(
      key: const Key('history-chart'),
      height: 168,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.bottomCenter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < 7; index++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${values[index]}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFFA5ADB8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      key: Key('history-bar-$index'),
                      height: peak == 0 ? 4 : 8 + 96 * values[index] / peak,
                      decoration: BoxDecoration(
                        color: index == 6
                            ? const Color(0xFF6C96D4)
                            : const Color(0xFFDCE3EC),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _weekdays[index],
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFA5ADB8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsGrid(List<ReadingActivity> inRange) {
    final notes = widget.controller.bookmarks
        .where(
          (note) =>
              !note.createdAt.toLocal().isBefore(_rangeStart) &&
              note.createdAt.toLocal().isBefore(_rangeEnd),
        )
        .length;
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          _statCell(
            '${_dayCount(inRange)}',
            '天',
            '有书相伴',
            const Key('history-stat-days'),
          ),
          _statCell(
            '${_bookCount(inRange)}',
            '本',
            '阅读书籍',
            const Key('history-stat-books'),
          ),
          _statCell('$notes', '条', '留下笔记', const Key('history-stat-notes')),
        ],
      ),
    );
  }

  Widget _statCell(String value, String unit, String label, Key key) =>
      Expanded(
        child: Column(
          key: key,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  TextSpan(
                    text: unit,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF929AA5)),
            ),
          ],
        ),
      );

  Widget _goal() => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Row(
      children: [
        const Icon(Icons.eco_outlined, size: 18, color: AppColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '不着急，一页也是进步',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                '让阅读成为生活里自然的一部分',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _recentSection() {
    final recent =
        [
          for (final book in widget.controller.books)
            if (book.hasStarted) book,
        ]..sort((a, b) {
          final left = a.lastOpenedAt ?? DateTime(1970);
          final right = b.lastOpenedAt ?? DateTime(1970);
          return right.compareTo(left);
        });
    if (recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('最近在读'),
        for (final book in recent.take(2)) _recentRow(book),
      ],
    );
  }

  // 最近在读只作展示：这一页负责回看记录，打开书走下面的足迹行。
  Widget _recentRow(Book book) => Padding(
    key: Key('history-recent-book-${book.id}'),
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: BookCover(
            book: book,
            imageLoader: widget.controller.loadBookCover,
            width: 42,
            height: 58,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${book.progressLabel} · 阅读中',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filterRow(Map<String, String> books) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
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
          onSelected: (bookId) =>
              setState(() => _bookId = bookId.isEmpty ? null : bookId),
          itemBuilder: (_) => [
            const PopupMenuItem<String>(value: '', child: Text('全部书籍')),
            for (final entry in books.entries)
              PopupMenuItem<String>(
                key: Key('history-book-option-${entry.key}'),
                value: entry.key,
                child: Text(entry.value),
              ),
          ],
          child: Chip(
            avatar: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text(_bookId == null ? '全部书籍' : books[_bookId] ?? '已移除书籍'),
          ),
        ),
      ],
    ),
  );

  Widget _activityRow(ReadingActivity activity, int index) => InkWell(
    key: Key('reading-history-item-$index'),
    borderRadius: BorderRadius.circular(12),
    onTap: () => widget.onOpen(activity),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Icon(
            switch (activity.kind) {
              ReadingActivityKind.opened => Icons.menu_book_outlined,
              ReadingActivityKind.chapter => Icons.auto_stories_outlined,
              ReadingActivityKind.finished => Icons.emoji_events_outlined,
            },
            color: AppColors.blue,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.bookTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${activity.chapterTitle} · ${_kindLabel(activity.kind)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _timeLabel(activity.occurredAt),
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
