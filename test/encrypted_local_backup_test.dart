import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/services/encrypted_local_backup.dart';

void main() {
  test(
    'encrypted local backup round-trips and rejects wrong passwords',
    () async {
      final plain = Uint8List.fromList(
        utf8.encode('{"format":"read-pilot-local"}'),
      );
      final first = await EncryptedLocalBackupCodec.encrypt(
        plain,
        'correct horse battery staple',
      );
      final second = await EncryptedLocalBackupCodec.encrypt(
        plain,
        'correct horse battery staple',
      );

      expect(first, isNot(plain));
      expect(first, isNot(second));
      expect(EncryptedLocalBackupCodec.isEncrypted(first), isTrue);
      expect(
        await EncryptedLocalBackupCodec.decrypt(
          first,
          'correct horse battery staple',
        ),
        plain,
      );
      await expectLater(
        EncryptedLocalBackupCodec.decrypt(first, 'different password'),
        throwsFormatException,
      );
    },
  );

  test(
    'encrypted local backup rejects tampering without exposing crypto errors',
    () async {
      final encrypted = await EncryptedLocalBackupCodec.encrypt(
        Uint8List.fromList(utf8.encode('{"format":"read-pilot-local"}')),
        'correct horse battery staple',
      );
      final root = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final cipher = root['cipher'] as Map<String, dynamic>;
      final bytes = base64Decode(cipher['ciphertext'] as String);
      bytes[0] ^= 0x01;
      cipher['ciphertext'] = base64Encode(bytes);
      final tampered = Uint8List.fromList(utf8.encode(jsonEncode(root)));

      await expectLater(
        EncryptedLocalBackupCodec.decrypt(
          tampered,
          'correct horse battery staple',
        ),
        throwsFormatException,
      );
    },
  );
}
