import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
import '../components/reader_preferences.dart';

/// 通用设置：把散落在别处的低频入口收在一起，按设计稿分组呈现。
///
/// 部分开关（阅读助手、仅在 Wi-Fi 下下载、自动备份）在本版本没有对应的持久化
/// 字段，这里如实显示为不可用状态，而不是假装保存成功。
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({
    super.key,
    required this.controller,
    required this.onSources,
    required this.onBackup,
  });

  final AppController controller;
  final VoidCallback onSources;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '设置',
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final enabled = controller.sources
              .where((source) => source.enabled)
              .length;
          final cached = controller.books.fold<int>(
            0,
            (sum, book) => sum + book.cachedChapters,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              const SectionLabel('阅读'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    ListRow(
                      icon: Icons.format_size,
                      title: '阅读排版',
                      trailingText: '字体 · 主题',
                      onTap: () => _openReaderPreferences(context),
                    ),
                    const ListRow(
                      icon: Icons.auto_fix_high,
                      title: '正文净化',
                      subtitle: '清理影响阅读的重复文字',
                      trailingText: '阅读时调整',
                    ),
                    const ListRow(
                      icon: Icons.psychology_outlined,
                      title: '阅读助手',
                      subtitle: '在需要时解释与回顾',
                      trailingText: '随阅读打开',
                    ),
                  ],
                ),
              ),
              const SectionLabel('内容与下载'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    ListRow(
                      key: const Key('settings-sources'),
                      icon: Icons.language_outlined,
                      title: '书源管理',
                      trailingText: '$enabled 个已启用',
                      onTap: onSources,
                    ),
                    const ListRow(
                      icon: Icons.wifi_outlined,
                      title: '仅在 Wi-Fi 下下载',
                      subtitle: '避免使用移动数据',
                      trailingText: '跟随系统',
                    ),
                    ListRow(
                      icon: Icons.download_done_outlined,
                      title: '离线内容',
                      trailingText: '$cached 章已缓存',
                    ),
                  ],
                ),
              ),
              const SectionLabel('数据与应用'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    ListRow(
                      key: const Key('settings-backup'),
                      icon: Icons.cloud_outlined,
                      title: '备份与同步',
                      trailingText: '本机保存',
                      onTap: onBackup,
                    ),
                    ListRow(
                      icon: Icons.info_outline,
                      title: '关于阅读',
                      trailingText: '0.1.0',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: '阅读',
                        applicationVersion: '0.1.0',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const InfoNote(
                lines: ['所有书籍、进度与笔记都留在本机。', '卸载应用会一并删除，重要内容请先备份。'],
              ),
            ],
          );
        },
      ),
    );
  }

  void _openReaderPreferences(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: ReaderPreferences(
                  settings: controller.settings,
                  onChanged: controller.updateSettings,
                  stylePresets: controller.readerStylePresets,
                  onSaveStylePreset: controller.saveReaderStylePreset,
                  onDeleteStylePreset: controller.deleteReaderStylePreset,
                ),
              ),
            ),
          ),
        ),
      );
}
