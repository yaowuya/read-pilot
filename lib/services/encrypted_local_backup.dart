import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'local_backup.dart';

abstract final class EncryptedLocalBackupCodec {
  static const format = 'read-pilot-local-encrypted';
  static const version = 1;
  static const iterations = 210000;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const macLength = 16;
  static const maxEnvelopeBytes = 16 * 1024 * 1024;
  static const _minPasswordCharacters = 12;
  static const _maxPasswordCharacters = 128;

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);

  static Future<Uint8List> encrypt(Uint8List plain, String password) async {
    _validatePassword(password);
    if (plain.isEmpty || plain.length > LocalBackupCodec.maxBytes) {
      throw const FormatException('本地备份内容无效或超过 10 MiB。');
    }
    final salt = _randomBytes(saltLength);
    final nonce = _randomBytes(nonceLength);
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = await _cipher.encrypt(
      plain,
      secretKey: secretKey,
      nonce: nonce,
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'version': version,
          'kdf': {
            'algorithm': 'PBKDF2-HMAC-SHA256',
            'iterations': iterations,
            'salt': base64Encode(salt),
          },
          'cipher': {
            'algorithm': 'AES-256-GCM',
            'nonce': base64Encode(box.nonce),
            'ciphertext': base64Encode(box.cipherText),
            'mac': base64Encode(box.mac.bytes),
          },
        }),
      ),
    );
    if (bytes.length > maxEnvelopeBytes) {
      throw const FormatException('加密备份超过安全大小限制。');
    }
    return bytes;
  }

  static bool isEncrypted(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxEnvelopeBytes) return false;
    try {
      final root = _map(jsonDecode(utf8.decode(bytes)));
      return root['format'] == format && root['version'] == version;
    } on Object {
      return false;
    }
  }

  static Future<Uint8List> decrypt(Uint8List bytes, String password) async {
    _validatePassword(password);
    try {
      if (bytes.isEmpty || bytes.length > maxEnvelopeBytes) {
        throw const FormatException('加密备份大小无效。');
      }
      final root = _map(jsonDecode(utf8.decode(bytes)));
      _keys(root, const {'format', 'version', 'kdf', 'cipher'});
      if (root['format'] != format || root['version'] != version) {
        throw const FormatException('不是受支持的加密本地备份。');
      }
      final kdf = _map(root['kdf']);
      _keys(kdf, const {'algorithm', 'iterations', 'salt'});
      if (kdf['algorithm'] != 'PBKDF2-HMAC-SHA256' ||
          kdf['iterations'] != iterations) {
        throw const FormatException('加密备份使用了不支持的密钥派生参数。');
      }
      final salt = _base64(kdf['salt']);
      if (salt.length != saltLength) {
        throw const FormatException('加密备份盐值无效。');
      }
      final cipher = _map(root['cipher']);
      _keys(cipher, const {'algorithm', 'nonce', 'ciphertext', 'mac'});
      if (cipher['algorithm'] != 'AES-256-GCM') {
        throw const FormatException('加密备份使用了不支持的加密算法。');
      }
      final nonce = _base64(cipher['nonce']);
      final ciphertext = _base64(cipher['ciphertext']);
      final mac = _base64(cipher['mac']);
      if (nonce.length != nonceLength ||
          mac.length != macLength ||
          ciphertext.isEmpty ||
          ciphertext.length > LocalBackupCodec.maxBytes) {
        throw const FormatException('加密备份密文无效。');
      }
      final secretKey = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final plain = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      if (plain.isEmpty || plain.length > LocalBackupCodec.maxBytes) {
        throw const FormatException('解密后的本地备份大小无效。');
      }
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('密码错误或加密备份已损坏。');
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('密码错误或加密备份已损坏。');
    }
  }

  static void _validatePassword(String value) {
    final length = value.runes.length;
    if (length < _minPasswordCharacters ||
        length > _maxPasswordCharacters ||
        value.contains('\u0000')) {
      throw const FormatException('备份密码需为 12–128 个字符，且不能包含空字符。');
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _base64(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('加密备份字段无效。');
    }
    try {
      return Uint8List.fromList(base64Decode(value));
    } on FormatException {
      throw const FormatException('加密备份字段无效。');
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw const FormatException('加密备份格式无效。');
    return Map<String, dynamic>.from(value);
  }

  static void _keys(Map<String, dynamic> value, Set<String> allowed) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('加密备份包含不支持的字段。');
    }
  }
}
