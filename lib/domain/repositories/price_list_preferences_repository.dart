import '../price_lists/price_list_models.dart';

abstract interface class PriceListPreferencesRepository {
  Future<PriceListConfig?> load(PriceListType type);
  Future<void> save(PriceListConfig config, DateTime updatedAt);
}
