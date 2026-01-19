import 'dart:convert';
import 'package:crypto/crypto.dart';

class Md5Helper {
  static String hash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Generate Last.fm API signature
  /// Parameters should be sorted alphabetically and concatenated
  /// Format: param1value1param2value2...secret
  static String generateLastfmSignature(
    Map<String, String> params,
    String secret,
  ) {
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer();

    for (final key in sortedKeys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(secret);

    return hash(buffer.toString());
  }
}
