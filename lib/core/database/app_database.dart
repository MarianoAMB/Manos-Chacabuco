import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as desktop;

import 'database_migrations.dart';

final class AppDatabase {
  AppDatabase._(this.database);

  final mobile.Database database;

  static Future<AppDatabase> openDefault() async {
    final supportDirectory = await getApplicationSupportDirectory();
    await supportDirectory.create(recursive: true);
    final databasePath = paths.join(
      supportDirectory.path,
      'manos_chacabuco.db',
    );

    if (Platform.isWindows) {
      desktop.sqfliteFfiInit();
      return open(factory: desktop.databaseFactoryFfi, path: databasePath);
    }
    if (Platform.isAndroid) {
      return open(factory: mobile.databaseFactory, path: databasePath);
    }
    throw UnsupportedError('Plataforma no configurada para persistencia local');
  }

  static Future<AppDatabase> open({
    required mobile.DatabaseFactory factory,
    required String path,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: mobile.OpenDatabaseOptions(
        version: DatabaseMigrations.currentVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) =>
            DatabaseMigrations.migrate(database, 0, version),
        onUpgrade: DatabaseMigrations.migrate,
      ),
    );
    return AppDatabase._(database);
  }

  Future<void> close() => database.close();
}
