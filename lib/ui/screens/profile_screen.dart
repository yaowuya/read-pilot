import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../components/brand_mark.dart';
import '../components/common.dart';
import '../components/reader_preferences.dart';
import '../theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.onNotes,
  });
  final AppController controller;
  final VoidCallback onNotes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: EdgeInsets.all(constraints.maxWidth < 650 ? 20 : 40),
      children: [
        const PageHeading(title: '我的阅读', subtitle: '一间只属于你的安静书房。'),
        const SizedBox(height: 28),
        QuietPanel(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFFEDF0F4),
                child: Icon(
                  Icons.person_outline,
                  color: AppColors.muted,
                  size: 28,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本地读者',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '无需登录，你的阅读只属于你。',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        QuietPanel(
          child: InkWell(
            onTap: onNotes,
            child: Row(
              children: [
                const Icon(Icons.bookmarks_outlined, color: AppColors.ink),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '书签与笔记',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '已留下 ${controller.bookmarks.length} 条阅读记录',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text('阅读偏好', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          '让每一页，都以你喜欢的方式呈现。',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 18),
        QuietPanel(
          child: ReaderPreferences(
            settings: controller.settings,
            onChanged: controller.updateSettings,
          ),
        ),
        const SizedBox(height: 30),
        QuietPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandMark(size: 25),
                  const SizedBox(width: 12),
                  Text('关于阅读', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  const Text(
                    '0.1.0',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '一个离线优先的开源阅读项目。用自己的方式读书，把注意力还给文字。',
                style: TextStyle(height: 1.9, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              const Text(
                '书籍、书源、书签和设置仅保存在当前设备；Web 版保存在当前浏览器。清理应用或站点数据会删除这些记录。首版没有云同步，请保留重要 TXT 原文件。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.9,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: '阅读',
                  applicationVersion: '0.1.0',
                  applicationLegalese:
                      '示例内容为公版原文节选；字体为 Noto Sans SC（SIL OFL）。书封与产品图形为原创。',
                ),
                child: const Text('开源许可与致谢  →'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}
