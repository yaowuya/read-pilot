import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'application/app_controller.dart';
import 'data/app_repository.dart';
import 'data/database.dart';
import 'services/source_engine.dart';
import 'ui/components/brand_mark.dart';
import 'ui/theme.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.ensureSemantics();
  final initialRoute = binding.platformDispatcher.defaultRouteName;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans SC',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  await _launch(initialRoute);
}

Future<AppController> _createController() async {
  final database = await openAppDatabase();
  final controller = AppController(AppRepository(database), SourceEngine());
  try {
    await controller.initialize();
    return controller;
  } catch (_) {
    controller.dispose();
    await database.close();
    rethrow;
  }
}

Future<void> _launch(String initialRoute) async {
  try {
    final controller = await _createController();
    runApp(ReadPilotApp(controller: controller, initialRoute: initialRoute));
  } catch (_) {
    runApp(_StartupError(onRetry: () => _launch(initialRoute)));
  }
}

class _StartupError extends StatefulWidget {
  const _StartupError({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  State<_StartupError> createState() => _StartupErrorState();
}

class _StartupErrorState extends State<_StartupError> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    builder: (context, _) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 48),
              const SizedBox(height: 24),
              const Text(
                '阅读',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '暂时无法打开本地书库。请检查存储空间，\n或确认浏览器允许此站点存储数据。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.8),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        setState(() => _busy = true);
                        await widget.onRetry();
                        if (mounted) setState(() => _busy = false);
                      },
                child: Text(_busy ? '正在重试…' : '重试'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
