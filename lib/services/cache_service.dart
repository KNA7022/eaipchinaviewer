import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CacheService {
  static Future<void> clearCache() async {
    final cacheDir = await getTemporaryDirectory();
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
      await cacheDir.create();
    }
  }
}
