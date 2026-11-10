import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
import '../components/reader_preferences.dart';
import '../design_icons.dart';

/// 通用设置：把散落在别处的低频入口收在一起，按设计稿分组呈现。
class AppSettingsScreen extends StatefulWidget {
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
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _cleanText = true;
  bool _assistant = true;
  bool _wifiOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '设置',
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final enabled = widget.controller.sources
              .where((source) => source.enabled)
              .length;
          final cached = widget.controller.books.fold<int>(
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
                      icon: DesignIcons.type,
                      title: '阅读排版',
                      trailingText: '字体 · 主题',
                      onTap: () => _openReaderPreferences(context),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(DesignIcons.eraser),
                      title: const Text('正文净化'),
                      subtitle: const Text('清理影响阅读的重复文字'),
                      trailing: SwitchDot(
                        key: const Key('settings-clean-text'),
                        value: _cleanText,
                        semanticLabel: '正文净化',
                        onChanged: (value) =>
                            setState(() => _cleanText = value),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(DesignIcons.sparkles),
                      title: const Text('阅读助手'),
                      subtitle: const Text('在需要时解释与回顾'),
                      trailing: SwitchDot(
                        key: const Key('settings-assistant'),
                        value: _assistant,
                        semanticLabel: '阅读助手',
                        onChanged: (value) =>
                            setState(() => _assistant = value),
                      ),
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
                      icon: DesignIcons.layers,
                      title: '书源管理',
                      trailingText: '$enabled 个已启用',
                      onTap: widget.onSources,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(DesignIcons.wifi),
                      title: const Text('仅在 Wi-Fi 下下载'),
                      subtitle: const Text('避免使用移动数据'),
                      trailing: SwitchDot(
                        key: const Key('settings-wifi-only'),
                        value: _wifiOnly,
                        semanticLabel: '仅在 Wi-Fi 下下载',
                        onChanged: (value) => setState(() => _wifiOnly = value),
                      ),
                    ),
                    ListRow(
                      icon: DesignIcons.hardDrive,
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
                      icon: DesignIcons.cloud,
                      title: '备份与同步',
                      trailingText: '本机保存',
                      onTap: widget.onBackup,
                    ),
                    ListRow(
                      icon: DesignIcons.info,
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
                lines: ['正文净化与下载偏好仅作用于本机界面。', '阅读助手始终使用本地回顾，不连接模型。'],
              ),
            ],
          );
        },
      ),
    );
  }

  void _openReaderPreferences(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: ReaderPreferences(
              settings: widget.controller.settings,
              onChanged: widget.controller.updateSettings,
              stylePresets: widget.controller.readerStylePresets,
              onSaveStylePreset: (name, settings) async {
                await widget.controller.saveReaderStylePreset(name, settings);
              },
              onDeleteStylePreset: widget.controller.deleteReaderStylePreset,
            ),
          ),
        ),
      ),
    );
  }
}
