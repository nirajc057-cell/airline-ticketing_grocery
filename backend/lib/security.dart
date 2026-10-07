import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

String randomSecret([int bytes = 32]) {
  final random = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

// New credentials use a salted, deliberately expensive hash. Existing
// credentials remain verifiable without forcing the old owner to reset them.
String hashPassword(String password, {String? salt}) {
  final actualSalt = salt ?? randomSecret(18);
  const rounds = 160000;
  final key = _pbkdf2(password, actualSalt, rounds);
  return 'pbkdf2-sha256\$$rounds\$$actualSalt\$${base64Url.encode(key)}';
}

bool verifyPassword(String password, String stored, String scheme) {
  if (scheme == 'sha256') {
    return _sameBytes(utf8.encode(sha256Hex(password)), utf8.encode(stored));
  }
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
  final rounds = int.tryParse(parts[1]);
  if (rounds == null || rounds < 100000 || rounds > 1000000) return false;
  final expected = base64Url.decode(base64Url.normalize(parts[3]));
  return _sameBytes(_pbkdf2(password, parts[2], rounds), expected);
}

List<int> _pbkdf2(String password, String salt, int rounds) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final saltBytes = utf8.encode(salt);
  var block = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var i = 1; i < rounds; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return result;
}

bool _sameBytes(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < min(a.length, b.length); i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
