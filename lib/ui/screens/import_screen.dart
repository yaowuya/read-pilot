import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
import '../theme.dart';

/// 导入书籍：本机文件、示例书与在线书源三条入口。
///
/// 设计稿把导入做成独立一页，而不是塞进书架标题行的按钮，这样首次使用的读者
/// 能先看到「支持什么格式、书会存在哪」再决定点哪一个。
class ImportScreen extends StatelessWidget {
  const ImportScreen({
    super.key,
    required this.controller,
    required this.onPickFiles,
    required this.onSources,
  });

  final AppController controller;
  final Future<void> Function() onPickFiles;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '导入书籍',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Center(
            child: Container(
              width: 66,
              height: 66,
              decoration: const BoxDecoration(
                color: AppColors.softBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.file_download_outlined,
                size: 30,
                color: AppColors.blue,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Center(
            child: Text(
              '把你的书，带进来',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '支持 TXT 与 EPUB。\n导入后自动分章，进度与笔记都留在本机。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.9,
              ),
            ),
          ),
          const SizedBox(height: 28),
          _OptionTile(
            key: const Key('import-pick-files'),
            icon: Icons.folder_open_outlined,
            title: '从本机选择文件',
            description: '支持 TXT / EPUB 格式，可一次选择多本',
            onTap: () async {
              await onPickFiles();
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
          const SizedBox(height: 12),
          _OptionTile(
            key: const Key('import-sources'),
            icon: Icons.language_outlined,
            title: '添加在线书源',
            description: '导入书源后即可按书名、作者搜索',
            onTap: onSources,
          ),
          const SizedBox(height: 12),
          _OptionTile(
            key: const Key('import-sample'),
            icon: Icons.auto_stories_outlined,
            title: '先试读一本',
            description: '书架上已有示例书籍，可以直接打开体验',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 24),
          const InfoNote(lines: ['原始文件不会被修改或上传。', '删除书籍只清理本机副本，不动你选中的源文件。']),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.softBlue,
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          child: Icon(icon, size: 21, color: AppColors.blue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.muted,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 19, color: AppColors.muted),
      ],
    ),
  );
}
