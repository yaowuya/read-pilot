import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
import '../design_icons.dart';
import '../theme.dart';

/// 我的：头像与签名、读书统计、以及按稿分组的功能入口。
///
/// 设计稿把「书源管理」「导入书籍」「备份与同步」「通用设置」都收进这一页，
/// 底部导航因此只需要三项；这里只负责入口与统计，不重复实现各页逻辑。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.onNotes,
    required this.onHistory,
    required this.onSources,
    required this.onImport,
    required this.onBackup,
    required this.onSettings,
  });

  final AppController controller;
  final VoidCallback onNotes;
  final VoidCallback onHistory;
  final VoidCallback onSources;
  final VoidCallback onImport;
  final VoidCallback onBackup;
  final VoidCallback onSettings;

  /// 与阅读记录页同一口径：相邻足迹间隔累加，单段最多半小时。
  Duration _totalReadingDuration() {
    const sessionCap = Duration(minutes: 30);
    final activities = [...controller.readingActivities]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    var total = Duration.zero;
    for (var i = 1; i < activities.length; i++) {
      final gap = activities[i].occurredAt.difference(
        activities[i - 1].occurredAt,
      );
      if (gap > Duration.zero && gap <= sessionCap) total += gap;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final books = controller.books;
    final finished = books.where((book) => book.finished).length;
    final markNotes = books.fold<int>(
      0,
      (sum, book) => sum + controller.readerMarks(book.id).length,
    );
    final notes = markNotes > 0 ? markNotes : controller.bookmarks.length;
    final duration = _totalReadingDuration();
    final hours = duration.inMinutes ~/ 60;
    final minutes = duration.inMinutes % 60;
    final enabledSources = controller.sources
        .where((source) => source.enabled)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            12,
            compact ? 16 : 32,
            32,
          ),
          children: [
            _header(context),
            const SizedBox(height: 20),
            InkWell(
              key: const Key('profile-stats'),
              onTap: onHistory,
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: _statsCard(
                context,
                hours: hours,
                minutes: minutes,
                finished: finished,
                notes: notes,
              ),
            ),
            const SizedBox(height: 26),
            RowCard(
              children: [
                ListRow(
                  icon: DesignIcons.notebookPen,
                  title: '读书笔记',
                  trailingText: notes == 0 ? '暂无' : '$notes 条',
                  onTap: onNotes,
                ),
                ListRow(
                  icon: DesignIcons.chart,
                  title: '阅读记录',
                  trailingText: controller.readingActivities.isEmpty
                      ? '暂无'
                      : '${controller.readingActivities.length} 条',
                  onTap: onHistory,
                ),
              ],
            ),
            const SectionLabel('内容与数据'),
            RowCard(
              children: [
                ListRow(
                  icon: DesignIcons.fileUp,
                  title: '导入书籍',
                  trailingText: 'TXT · EPUB',
                  onTap: onImport,
                ),
                ListRow(
                  icon: DesignIcons.layers,
                  title: '书源管理',
                  trailingText: '$enabledSources 个已启用',
                  onTap: onSources,
                ),
                ListRow(
                  icon: DesignIcons.cloud,
                  title: '备份与同步',
                  trailingText: '本机保存',
                  onTap: onBackup,
                ),
              ],
            ),
            const SectionLabel('偏好'),
            RowCard(
              children: [
                ListRow(
                  icon: DesignIcons.settings,
                  title: '通用设置',
                  subtitle: '阅读排版、正文净化与下载偏好',
                  onTap: onSettings,
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Center(
              child: Text(
                '读得慢一点，也没有关系。',
                style: TextStyle(
                  fontSize: 13,
                  height: 2.2,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 0, 0),
    child: Row(
      children: [
        Container(
          width: 57,
          height: 57,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFEDF4FB),
            shape: BoxShape.circle,
          ),
          child: const Text(
            '阅',
            style: TextStyle(fontSize: 23, color: Color(0xFF7E9ABB)),
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '阅读者',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '给生活留一页空白',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('profile-settings'),
          tooltip: '设置',
          onPressed: onSettings,
          icon: const Icon(DesignIcons.settings, size: 21),
          color: AppColors.muted,
        ),
      ],
    ),
  );

  Widget _statsCard(
    BuildContext context, {
    required int hours,
    required int minutes,
    required int finished,
    required int notes,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7FA),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                '与书相伴的日子',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  color: Color(0xFF929BA7),
                ),
              ),
            ),
            Icon(DesignIcons.chevronRight, size: 18, color: Color(0xFFB0B7C1)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _durationStat(hours, minutes),
            _stat('$finished', '本', '读完的书'),
            _stat('$notes', '条', '读书笔记'),
          ],
        ),
      ],
    ),
  );

  Widget _durationStat(int hours, int minutes) => Expanded(
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$hours',
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w500,
                color: Color(0xFF3B4656),
              ),
            ),
            const Text(
              '时',
              style: TextStyle(fontSize: 11, color: Color(0xFF9FA7B2)),
            ),
            const SizedBox(width: 2),
            Text(
              '$minutes',
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w500,
                color: Color(0xFF3B4656),
              ),
            ),
            const Text(
              '分',
              style: TextStyle(fontSize: 11, color: Color(0xFF9FA7B2)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '累计阅读',
          style: TextStyle(fontSize: 10, color: Color(0xFF9DA5B1)),
        ),
      ],
    ),
  );

  Widget _stat(String value, String unit, String label) => Expanded(
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w500,
                color: Color(0xFF3B4656),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              unit,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9FA7B2)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF9DA5B1)),
        ),
      ],
    ),
  );
}
