import '../quotes/quote_models.dart';

abstract interface class QuoteRepository {
  Future<List<QuoteAggregate>> findAll();
  Future<QuoteAggregate?> findById(String id);
  Future<void> saveAggregate(QuoteAggregate aggregate);
  Future<void> softDelete(String id, DateTime deletedAt);
}
