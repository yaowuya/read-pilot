import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/design.dart';
import '../components/local_backup_panel.dart';
import '../theme.dart';

/// 备份与同步：本机备份、恢复与说明，按设计稿聚成一页。
///
/// WebDAV 同步在设计稿里有入口，但本版本没有远程存储实现，所以这里如实标注
/// 「本版本暂未提供」，而不是放一个点了没反应的按钮。
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          const Text(
            '让阅读有迹可循',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '书架、进度和笔记，都值得好好保存。',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.8),
          ),
          const SizedBox(height: 22),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本机备份',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  '包含书架、进度、笔记、书源和阅读设置。',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 10),
                LocalBackupPanel(controller: controller),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SurfaceCard(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WebDAV 同步',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  '连接你自己的存储空间，用于跨设备备份。',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    height: 1.8,
                  ),
                ),
                SizedBox(height: 10),
                PillTag('本版本暂未提供', tone: PillTone.neutral),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const InfoNote(
            lines: [
              '备份文件是一个加密或明文的 JSON 包，可以放回本机任意位置。',
              '恢复会先预览内容，再决定是否覆盖当前数据。',
              '书籍正文可能需要重新下载，进度与笔记会一并恢复。',
            ],
          ),
        ],
      ),
    );
  }
}
