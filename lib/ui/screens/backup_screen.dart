import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
import '../components/local_backup_panel.dart';
import '../theme.dart';

/// 备份与同步：按设计稿是一个居中主视觉 + 若干备份条目。
///
/// 设计稿里还有 WebDAV 同步与自动备份，但本版本没有远程存储和定时任务，
/// 所以这里如实标注「本版本暂未提供」，而不是放一个点了没反应的开关。
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '备份与同步',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          const _BackupHero(),
          _BackupTile(
            title: '本机备份',
            lines: const ['包含书架、进度、笔记、书源和阅读设置。'],
            child: LocalBackupPanel(controller: controller),
          ),
          const _BackupTile(
            title: 'WebDAV 同步',
            lines: ['连接你自己的存储空间，用于跨设备备份。', '书籍文件可以单独管理。'],
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: PillTag('本版本暂未提供', tone: PillTone.neutral),
            ),
          ),
          const _BackupRow(
            title: '自动备份',
            description: '本版本由你手动备份；按同步策略自动运行尚未接入。',
          ),
          const SizedBox(height: 12),
          const InfoNote(
            lines: [
              '书架数据和书籍文件是两回事。',
              '备份只包含本地书籍、进度、笔记、分组与阅读设置。',
              '跨设备阅读时，还需要原始书籍文件。',
            ],
          ),
          const SizedBox(height: 18),
          const _SourceNote('备份文件写在你选择的位置，不会上传到任何服务器。'),
        ],
      ),
    );
  }
}

class _BackupHero extends StatelessWidget {
  const _BackupHero();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 28, bottom: 26),
    child: Column(
      children: [
        Icon(Icons.cloud_done_outlined, size: 48, color: Color(0xFF7F9EC7)),
        SizedBox(height: 20),
        Text(
          '让阅读有迹可循',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 9),
        Text(
          '书架、进度和笔记，都值得好好保存',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFA5AFBB), height: 1.8),
        ),
      ],
    ),
  );
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.title,
    required this.lines,
    required this.child,
  });

  final String title;
  final List<String> lines;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(19, 17, 19, 14),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE7ECF3)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFA2ADBC),
                height: 1.8,
              ),
            ),
          ),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 15),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 5),
        Text(
          description,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF9AA2AF),
            height: 1.7,
          ),
        ),
      ],
    ),
  );
}

class _SourceNote extends StatelessWidget {
  const _SourceNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.info_outline, size: 13, color: Color(0xFFA7ADB7)),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFFA7ADB7),
            height: 1.7,
          ),
        ),
      ),
    ],
  );
}
