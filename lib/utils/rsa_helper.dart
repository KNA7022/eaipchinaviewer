import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
import 'dart:convert';
import 'dart:typed_data';

class RsaHelper {
  static const String publicKeyPEM = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCleaaZ4rYClmsDKlDXxrEZvRXs
WqArQ4j+COOOyNLfJU3vSCrbSc1VcPEm3eOnPvSG3dhA0o9ttR+13g3kfi3gGvMc
Yi9dTQ0ZIbHsXNze4vlI32yOmJjeig1ijlqivcVvJRk8c0HUlaWcmBqTDhMvN/lv
yc7BQ34Ao/JH862rRQIDAQAB
-----END PUBLIC KEY-----''';

  static String encryptPassword(String password) {
    try {
      final parser = RSAKeyParser();
      final RSAPublicKey publicKey = parser.parse(publicKeyPEM);
      
      // 修改: 使用 PKCS1Encoding 而不是 OAEPEncoding
      final cipher = PKCS1Encoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      // 确保使用UTF-8编码
      final dataBytes = utf8.encode(password);
      final encrypted = cipher.process(Uint8List.fromList(dataBytes));
      
      // 直接返回 base64 编码结果，不进行 URI 编码
      final encoded = base64.encode(encrypted);

      
      return encoded;
    } catch (e) {
      return '';
    }
  }
}

class RSAKeyParser {
  RSAPublicKey parse(String key) {
    try {
      final rows = key.split('\n');
      final keyBytes = base64Decode(rows
          .where((row) => row.isNotEmpty && !row.startsWith('-----'))
          .join(''));
      
      final parser = ASN1Parser(keyBytes);
      final topLevelSeq = parser.nextObject() as ASN1Sequence;
      final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
      
      final publicKeyParser = ASN1Parser(publicKeyBitString.contentBytes());
      final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;
      final modulus = publicKeySeq.elements[0] as ASN1Integer;
      final exponent = publicKeySeq.elements[1] as ASN1Integer;
      
      return RSAPublicKey(
        modulus.valueAsBigInteger!,
        exponent.valueAsBigInteger!,
      );
    } catch (e) {
      throw Exception('无效的公钥格式: $e');
    }
  }
}
