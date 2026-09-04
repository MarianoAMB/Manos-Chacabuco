import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_price_list_preferences_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_settings_repository.dart';
import 'package:manos_chacabuco/data/storage/local_business_logo_store.dart';
import 'package:manos_chacabuco/domain/price_lists/price_list_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persiste preferencias sin guardar precios', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqlitePriceListPreferencesRepository(database);
    const config = PriceListConfig(
      priceType: PriceListType.retail,
      selectedProductIds: {'p1', 'p2'},
      selectedCategoryIds: {'c1'},
      showPhotos: false,
      footerNote: 'Consultar colores.',
      sort: PriceListSort.priceDescending,
    );

    await repository.save(config, DateTime.utc(2026, 9, 3));
    final restored = await repository.load(PriceListType.retail);
    final raw =
        (await database.database.query('price_list_preferences'))
                .single['config_json']!
            as String;

    expect(restored?.showPhotos, isFalse);
    expect(restored?.selectedProductIds, {'p1', 'p2'});
    expect(restored?.footerNote, 'Consultar colores.');
    expect(restored?.sort, PriceListSort.priceDescending);
    expect(raw.toLowerCase(), isNot(contains('priceminor')));
    expect(raw.toLowerCase(), isNot(contains('cost')));
  });

  test('logo se copia, persiste, recupera y elimina', () async {
    final directory = await Directory.systemTemp.createTemp('business-logo-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(_onePixelPng);
    final targetDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}stored',
    );
    await targetDirectory.create();
    final store = LocalBusinessLogoStore.inDirectory(targetDirectory);
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final settingsRepository = SqliteSettingsRepository(database);
    final defaults = await settingsRepository.getOrCreateDefaults();

    final reference = await store.importFile(source.path);
    await settingsRepository.save(
      defaults.copyWith(
        businessLogoPath: reference,
        updatedAt: DateTime.utc(2026, 9, 3),
      ),
    );
    final restored = await settingsRepository.getOrCreateDefaults();

    expect(restored.businessLogoPath, reference);
    expect(File(store.absolutePath(reference)).existsSync(), isTrue);
    await store.delete(reference);
    await settingsRepository.save(
      restored.copyWith(
        clearBusinessLogoPath: true,
        updatedAt: DateTime.utc(2026, 9, 3, 1),
      ),
    );
    expect(File(store.absolutePath(reference)).existsSync(), isFalse);
    expect(
      (await settingsRepository.getOrCreateDefaults()).businessLogoPath,
      isNull,
    );
  });
}

const _onePixelPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  4,
  0,
  0,
  0,
  181,
  28,
  12,
  2,
  0,
  0,
  0,
  11,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  252,
  255,
  31,
  0,
  3,
  3,
  2,
  0,
  238,
  254,
  191,
  217,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
