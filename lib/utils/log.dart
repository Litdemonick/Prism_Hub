import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:prismhub/utils/PrismHub_directory.dart';
import 'package:prismhub/utils/PrismHub_storage.dart';
import 'package:path/path.dart' as path;

final logger = Logger('Miru');

class MiruLog {
  static final logFilePath = path.join(PrismHubDirectory.getDirectory, 'PrismHub.log');

  static void ensureInitialized() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      final log =
          '${record.loggerName} ${record.level.name} ${record.time}: ${record.message} ${record.error ?? ''} ${record.stackTrace ?? ''}';
      // 如果是开发环境则打印到控制台
      if (kReleaseMode) {
        writeLogToFile(log);
        return;
      }

      debugPrint(log);
    });
  }

  // 写入日志到文件
  static void writeLogToFile(String log) {
    if (!PrismHubStorage.getSetting(SettingKey.saveLog)) {
      return;
    }
    final file = File(logFilePath);
    file.writeAsStringSync('$log\n', mode: FileMode.append);
    if (file.lengthSync() > 1024 * 1024 * 10) {
      file.deleteSync();
    }
  }
}
