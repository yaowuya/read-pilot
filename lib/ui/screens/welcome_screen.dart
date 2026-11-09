import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../components/brand_mark.dart';
import '../theme.dart';

/// 设计稿首次打开页。产品名用「阅读」，本地 flag 只显示一次。
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  static const _flagName = 'welcome_seen_v1';

  static Future<bool> shouldShow() async {
    if (kIsWeb) {
      // Web 没有稳定本地文件语义时，默认跳过，避免每次刷新都打断。
      return false;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      return !File('${dir.path}/$_flagName').existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/$_flagName').writeAsString('1');
    } catch (_) {
      // 写失败也不拦进入主页。
    }
  }

  Future<void> _continue() async {
    await markSeen();
    onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(size: 72),
              const SizedBox(height: 28),
              const Text(
                '阅读',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '给生活留一页空白',
                style: TextStyle(fontSize: 15, color: AppColors.muted),
              ),
              const SizedBox(height: 36),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: const [
                  _FeatureChip(icon: Icons.menu_book_outlined, label: '打开就能读'),
                  _FeatureChip(icon: Icons.tune, label: '设置按需出现'),
                  _FeatureChip(
                    icon: Icons.auto_awesome_outlined,
                    label: '助手围绕书',
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('welcome-start'),
                  onPressed: _continue,
                  child: const Text('开始阅读'),
                ),
              ),
              TextButton(
                key: const Key('welcome-skip'),
                onPressed: _continue,
                child: const Text('先体验'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.blue),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
