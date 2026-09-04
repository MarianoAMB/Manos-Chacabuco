import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../domain/price_lists/price_list_models.dart';
import '../../domain/repositories/price_list_preferences_repository.dart';

final class SqlitePriceListPreferencesRepository
    implements PriceListPreferencesRepository {
  const SqlitePriceListPreferencesRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<PriceListConfig?> load(PriceListType type) async {
    final rows = await _appDatabase.database.query(
      'price_list_preferences',
      columns: const ['config_json'],
      where: 'price_type = ?',
      whereArgs: [type.name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PriceListConfig.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['config_json']! as String) as Map,
      ),
    );
  }

  @override
  Future<void> save(PriceListConfig config, DateTime updatedAt) async {
    await _appDatabase.database.insert('price_list_preferences', {
      'price_type': config.priceType.name,
      'config_json': jsonEncode(config.toJson()),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
