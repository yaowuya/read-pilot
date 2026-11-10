import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
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

  @override
  Widget build(BuildContext context) {
    final books = controller.books;
    final reading = books.where((book) => book.hasStarted).length;
    final finished = books.where((book) => book.finished).length;
    final notes = controller.bookmarks.length;
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
            _statsCard(
              context,
              reading: reading,
              finished: finished,
              notes: notes,
            ),
            const SizedBox(height: 26),
            RowCard(
              children: [
                ListRow(
                  icon: Icons.bookmarks_outlined,
                  title: '读书笔记',
                  trailingText: notes == 0 ? '暂无' : '$notes 条',
                  onTap: onNotes,
                ),
                ListRow(
                  icon: Icons.history_outlined,
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
                  icon: Icons.file_download_outlined,
                  title: '导入书籍',
                  trailingText: 'TXT · EPUB',
                  onTap: onImport,
                ),
                ListRow(
                  icon: Icons.language_outlined,
                  title: '书源管理',
                  trailingText: '$enabledSources 个已启用',
                  onTap: onSources,
                ),
                ListRow(
                  icon: Icons.cloud_upload_outlined,
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
                  icon: Icons.tune,
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
          icon: const Icon(Icons.settings_outlined, size: 21),
          color: AppColors.muted,
        ),
      ],
    ),
  );

  Widget _statsCard(
    BuildContext context, {
    required int reading,
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
        const Text(
          '与书相伴的日子',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1,
            color: Color(0xFF929BA7),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _stat('$reading', '本', '累计阅读'),
            _stat('$finished', '本', '读完的书'),
            _stat('$notes', '条', '读书笔记'),
          ],
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
