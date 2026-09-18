import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/features/sync/application/sync_diagnostic.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('explica una restricción SQLite sin copiar valores privados', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT UNIQUE)',
    );
    await database.insert('categories', {'id': 'a', 'name': 'Nombre privado'});

    Object? failure;
    try {
      await database.insert('categories', {
        'id': 'b',
        'name': 'Nombre privado',
      });
    } on Object catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    final report = SyncDiagnostic.describe(
      'Procesando una categoría de producto',
      failure!,
    );
    expect(report, contains('BASE_LOCAL_DUPLICADO'));
    expect(report, contains('categories.name'));
    expect(report, isNot(contains('Nombre privado')));
    expect(report, isNot(contains('args')));
  });
}
