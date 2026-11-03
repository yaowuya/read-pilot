import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/screens/reader_screen.dart';
import 'ui/theme.dart';

class ReadPilotApp extends StatelessWidget {
  const ReadPilotApp({super.key, required this.controller, this.initialRoute});
  final AppController controller;
  final String? initialRoute;

  String? _bookId(String? route) {
    if (route == null || !route.startsWith('/read/')) return null;
    try {
      final id = Uri.decodeComponent(route.substring('/read/'.length));
      final book = controller.book(id);
      return book != null && book.chapters.isNotEmpty ? id : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final requested =
        initialRoute ??
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    return MaterialApp(
      title: '阅读',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      initialRoute: _bookId(requested) == null ? '/' : requested,
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/'),
          builder: (_) => AppShell(controller: controller),
        ),
        if (_bookId(requested) case final String id)
          MaterialPageRoute<void>(
            settings: RouteSettings(name: requested),
            builder: (_) => ReaderScreen(controller: controller, bookId: id),
          ),
      ],
      routes: {'/': (_) => AppShell(controller: controller)},
      onGenerateRoute: (settings) {
        final id = _bookId(settings.name);
        if (id == null) return null;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ReaderScreen(controller: controller, bookId: id),
        );
      },
    );
  }
}
