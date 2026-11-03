import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/services/source_runtime/script_runtime.dart';

void main() {
  test(
    'sandbox evaluates JSON-safe globals without host capabilities',
    () async {
      final runtime = SandboxedScriptRuntime();
      addTearDown(runtime.close);
      if (!await runtime.isAvailable()) return;

      final value = await runtime.evaluate(
        '''
        JSON.stringify({
          value: result.replace(/广告/g, '').trim(),
          fetchType: typeof fetch,
          javaType: typeof Java,
          packagesType: typeof Packages,
          processType: typeof process,
          requireType: typeof require
        })
      ''',
        globals: const {'result': ' 正文广告 '},
      );

      expect(
        value,
        '{"value":"正文","fetchType":"undefined","javaType":"undefined",'
        '"packagesType":"undefined","processType":"undefined",'
        '"requireType":"undefined"}',
      );
    },
  );

  test('sandbox interrupts an infinite loop within its deadline', () async {
    final runtime = SandboxedScriptRuntime(
      timeout: const Duration(milliseconds: 50),
    );
    addTearDown(runtime.close);
    if (!await runtime.isAvailable()) return;

    await expectLater(
      runtime.evaluate('while (true) {}'),
      throwsA(
        isA<SourceScriptException>().having(
          (error) => error.kind,
          'kind',
          SourceScriptErrorKind.timeout,
        ),
      ),
    );
  });

  test(
    'sandbox never falls back when the native engine is unavailable',
    () async {
      final runtime = SandboxedScriptRuntime();
      addTearDown(runtime.close);
      if (await runtime.isAvailable()) return;

      await expectLater(
        runtime.evaluate('1 + 1'),
        throwsA(
          isA<SourceScriptException>().having(
            (error) => error.kind,
            'kind',
            SourceScriptErrorKind.unsupported,
          ),
        ),
      );
    },
  );
}
