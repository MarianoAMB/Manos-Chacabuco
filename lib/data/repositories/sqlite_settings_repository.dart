import '../../core/database/app_database.dart';
import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/settings/app_settings.dart';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

final class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<AppSettings> getOrCreateDefaults() async {
    final rows = await _appDatabase.database.query(
      'app_settings',
      where: 'singleton_id = ?',
      whereArgs: const [1],
      limit: 1,
    );
    if (rows.isNotEmpty) return _fromRow(rows.single);

    final defaults = AppSettings.defaults();
    await save(defaults);
    return defaults;
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _appDatabase.database.insert(
      'app_settings',
      _toRow(settings),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _toRow(AppSettings settings) => {
    'singleton_id': 1,
    'business_name': settings.businessName,
    'currency': settings.currency,
    'default_waste_scaled': settings.defaultWastePercentage.scaledValue,
    'default_thread_scaled': settings.defaultThreadPercentage.scaledValue,
    'default_retail_scaled': settings.defaultRetailPercentage?.scaledValue,
    'default_multiplier_scaled': settings.defaultProductMultiplier?.scaledValue,
    'minimum_wholesale_minor': settings.minimumWholesaleAmount?.minorUnits,
    'updated_at': settings.updatedAt.toUtc().toIso8601String(),
  };

  AppSettings _fromRow(Map<String, Object?> row) => AppSettings(
    businessName: row['business_name']! as String,
    currency: row['currency']! as String,
    defaultWastePercentage: DecimalValue.scaled(
      row['default_waste_scaled']! as int,
    ),
    defaultThreadPercentage: DecimalValue.scaled(
      row['default_thread_scaled']! as int,
    ),
    defaultRetailPercentage: switch (row['default_retail_scaled']) {
      final int value => DecimalValue.scaled(value),
      _ => null,
    },
    defaultProductMultiplier: switch (row['default_multiplier_scaled']) {
      final int value => DecimalValue.scaled(value),
      _ => null,
    },
    minimumWholesaleAmount: switch (row['minimum_wholesale_minor']) {
      final int value => Money(
        minorUnits: value,
        currency: row['currency']! as String,
      ),
      _ => null,
    },
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );
}
