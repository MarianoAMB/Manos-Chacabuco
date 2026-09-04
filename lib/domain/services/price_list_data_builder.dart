import '../price_lists/price_list_models.dart';
import '../../core/money/money.dart';

final class PriceListDataBuilder {
  const PriceListDataBuilder();

  PriceListDocument build({
    required List<PriceListSourceProduct> products,
    required PriceListConfig config,
    required String businessName,
    required DateTime generatedAt,
    String? logoPath,
    Money? minimumWholesaleAmount,
  }) {
    final selected = products
        .where((source) {
          if (!source.isEligibleFor(config.priceType)) return false;
          if (!config.selectedProductIds.contains(source.productId)) {
            return false;
          }
          if (!config.showProductsWithoutPhoto && source.photoPath == null) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final sorted = [...selected]
      ..sort(_comparator(config.sort, config.priceType));

    final groups = config.groupByCategory
        ? _grouped(sorted, config)
        : [
            PriceListGroup(
              name: null,
              items: [for (final source in sorted) _item(source, config)],
            ),
          ];

    final note = config.footerNote?.trim();
    return PriceListDocument(
      businessName: businessName.trim().isEmpty
          ? 'Manos Chacabuco'
          : businessName.trim(),
      logoPath: logoPath,
      generatedAt: generatedAt,
      type: config.priceType,
      groups: groups.where((group) => group.items.isNotEmpty).toList(),
      showPhotos: config.showPhotos,
      showUpdatedDate: config.showUpdatedDate,
      wholesaleMinimum:
          config.priceType == PriceListType.wholesale &&
              config.showWholesaleMinimum
          ? minimumWholesaleAmount
          : null,
      footerNote: note == null || note.isEmpty ? null : note,
    );
  }

  List<PriceListGroup> _grouped(
    List<PriceListSourceProduct> sources,
    PriceListConfig config,
  ) {
    final byCategory = <String, List<PriceListSourceProduct>>{};
    for (final source in sources) {
      byCategory.putIfAbsent(source.categoryName, () => []).add(source);
    }
    final names = byCategory.keys.toList()
      ..sort((left, right) => _text(left).compareTo(_text(right)));
    return [
      for (final name in names)
        PriceListGroup(
          name: name,
          items: [
            for (final source in byCategory[name]!) _item(source, config),
          ],
        ),
    ];
  }

  PriceListItem _item(PriceListSourceProduct source, PriceListConfig config) {
    final price = source.priceFor(config.priceType);
    if (price == null || price.minorUnits <= 0) {
      throw StateError('El producto no tiene un precio comercial válido.');
    }
    return PriceListItem(
      productId: source.productId,
      name: source.name,
      categoryName: source.categoryName,
      price: price,
      photoPath: config.showPhotos ? source.photoPath : null,
      dimensionsText: config.showDimensions ? source.dimensionsText : null,
      materialText: config.showMaterial ? source.materialText : null,
    );
  }

  Comparator<PriceListSourceProduct> _comparator(
    PriceListSort sort,
    PriceListType type,
  ) => (left, right) {
    final comparison = switch (sort) {
      PriceListSort.name => _text(left.name).compareTo(_text(right.name)),
      PriceListSort.category => _compareMany([
        _text(left.categoryName).compareTo(_text(right.categoryName)),
        _text(left.name).compareTo(_text(right.name)),
      ]),
      PriceListSort.priceAscending =>
        left
            .priceFor(type)!
            .minorUnits
            .compareTo(right.priceFor(type)!.minorUnits),
      PriceListSort.priceDescending =>
        right
            .priceFor(type)!
            .minorUnits
            .compareTo(left.priceFor(type)!.minorUnits),
    };
    if (comparison != 0) return comparison;
    final byName = _text(left.name).compareTo(_text(right.name));
    return byName != 0 ? byName : left.productId.compareTo(right.productId);
  };

  int _compareMany(List<int> values) =>
      values.firstWhere((value) => value != 0, orElse: () => 0);

  String _text(String value) => value.trim().toLowerCase();
}
