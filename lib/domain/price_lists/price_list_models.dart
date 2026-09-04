import 'dart:typed_data';

import '../../core/money/money.dart';

enum PriceListType { retail, wholesale }

extension PriceListTypeLabel on PriceListType {
  String get label => switch (this) {
    PriceListType.retail => 'Minorista',
    PriceListType.wholesale => 'Mayorista',
  };

  String get title => 'Lista $label';
}

enum PriceListSort { name, category, priceAscending, priceDescending }

extension PriceListSortLabel on PriceListSort {
  String get label => switch (this) {
    PriceListSort.name => 'Nombre',
    PriceListSort.category => 'Categoría',
    PriceListSort.priceAscending => 'Precio: menor a mayor',
    PriceListSort.priceDescending => 'Precio: mayor a menor',
  };
}

final class PriceListConfig {
  const PriceListConfig({
    required this.priceType,
    this.selectedProductIds = const {},
    this.selectedCategoryIds = const {},
    this.showPhotos = true,
    this.showProductsWithoutPhoto = true,
    this.showDimensions = true,
    this.showMaterial = true,
    this.groupByCategory = true,
    this.showWholesaleMinimum = true,
    this.showUpdatedDate = true,
    this.footerNote,
    this.sort = PriceListSort.name,
  });

  final PriceListType priceType;
  final Set<String> selectedProductIds;
  final Set<String> selectedCategoryIds;
  final bool showPhotos;
  final bool showProductsWithoutPhoto;
  final bool showDimensions;
  final bool showMaterial;
  final bool groupByCategory;
  final bool showWholesaleMinimum;
  final bool showUpdatedDate;
  final String? footerNote;
  final PriceListSort sort;

  PriceListConfig copyWith({
    PriceListType? priceType,
    Set<String>? selectedProductIds,
    Set<String>? selectedCategoryIds,
    bool? showPhotos,
    bool? showProductsWithoutPhoto,
    bool? showDimensions,
    bool? showMaterial,
    bool? groupByCategory,
    bool? showWholesaleMinimum,
    bool? showUpdatedDate,
    String? footerNote,
    bool clearFooterNote = false,
    PriceListSort? sort,
  }) => PriceListConfig(
    priceType: priceType ?? this.priceType,
    selectedProductIds: selectedProductIds ?? this.selectedProductIds,
    selectedCategoryIds: selectedCategoryIds ?? this.selectedCategoryIds,
    showPhotos: showPhotos ?? this.showPhotos,
    showProductsWithoutPhoto:
        showProductsWithoutPhoto ?? this.showProductsWithoutPhoto,
    showDimensions: showDimensions ?? this.showDimensions,
    showMaterial: showMaterial ?? this.showMaterial,
    groupByCategory: groupByCategory ?? this.groupByCategory,
    showWholesaleMinimum: showWholesaleMinimum ?? this.showWholesaleMinimum,
    showUpdatedDate: showUpdatedDate ?? this.showUpdatedDate,
    footerNote: clearFooterNote ? null : footerNote ?? this.footerNote,
    sort: sort ?? this.sort,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'priceType': priceType.name,
    'selectedProductIds': selectedProductIds.toList()..sort(),
    'selectedCategoryIds': selectedCategoryIds.toList()..sort(),
    'showPhotos': showPhotos,
    'showProductsWithoutPhoto': showProductsWithoutPhoto,
    'showDimensions': showDimensions,
    'showMaterial': showMaterial,
    'groupByCategory': groupByCategory,
    'showWholesaleMinimum': showWholesaleMinimum,
    'showUpdatedDate': showUpdatedDate,
    'footerNote': footerNote,
    'sort': sort.name,
  };

  factory PriceListConfig.fromJson(Map<String, Object?> json) =>
      PriceListConfig(
        priceType: PriceListType.values.byName(json['priceType']! as String),
        selectedProductIds: Set<String>.from(
          (json['selectedProductIds'] as List<Object?>?) ?? const [],
        ),
        selectedCategoryIds: Set<String>.from(
          (json['selectedCategoryIds'] as List<Object?>?) ?? const [],
        ),
        showPhotos: (json['showPhotos'] as bool?) ?? true,
        showProductsWithoutPhoto:
            (json['showProductsWithoutPhoto'] as bool?) ?? true,
        showDimensions: (json['showDimensions'] as bool?) ?? true,
        showMaterial: (json['showMaterial'] as bool?) ?? true,
        groupByCategory: (json['groupByCategory'] as bool?) ?? true,
        showWholesaleMinimum: (json['showWholesaleMinimum'] as bool?) ?? true,
        showUpdatedDate: (json['showUpdatedDate'] as bool?) ?? true,
        footerNote: json['footerNote'] as String?,
        sort: PriceListSort.values.byName(
          (json['sort'] as String?) ?? PriceListSort.name.name,
        ),
      );
}

/// Entrada comercial ya calculada por los motores existentes.
/// No expone costos, porcentajes ni multiplicadores al documento final.
final class PriceListSourceProduct {
  const PriceListSourceProduct({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.isActive,
    this.photoPath,
    this.dimensionsText,
    this.materialText,
    this.wholesalePrice,
    this.retailPrice,
  });

  final String productId;
  final String name;
  final String categoryId;
  final String categoryName;
  final bool isActive;
  final String? photoPath;
  final String? dimensionsText;
  final String? materialText;
  final Money? wholesalePrice;
  final Money? retailPrice;

  Money? priceFor(PriceListType type) => switch (type) {
    PriceListType.retail => retailPrice,
    PriceListType.wholesale => wholesalePrice,
  };

  bool isEligibleFor(PriceListType type) {
    final price = priceFor(type);
    return isActive && price != null && price.minorUnits > 0;
  }
}

final class PriceListItem {
  const PriceListItem({
    required this.productId,
    required this.name,
    required this.categoryName,
    required this.price,
    this.photoPath,
    this.dimensionsText,
    this.materialText,
  });

  final String productId;
  final String name;
  final String categoryName;
  final Money price;
  final String? photoPath;
  final String? dimensionsText;
  final String? materialText;

  Map<String, Object?> toClientJson() => {
    'productId': productId,
    'name': name,
    'category': categoryName,
    'priceMinorUnits': price.minorUnits,
    'currency': price.currency,
    if (photoPath != null) 'photoPath': photoPath,
    if (dimensionsText != null) 'dimensions': dimensionsText,
    if (materialText != null) 'material': materialText,
  };
}

final class PriceListGroup {
  const PriceListGroup({required this.name, required this.items});

  final String? name;
  final List<PriceListItem> items;
}

final class PriceListDocument {
  const PriceListDocument({
    required this.businessName,
    required this.generatedAt,
    required this.type,
    required this.groups,
    required this.showPhotos,
    required this.showUpdatedDate,
    this.logoPath,
    this.wholesaleMinimum,
    this.footerNote,
  });

  final String businessName;
  final String? logoPath;
  final DateTime generatedAt;
  final PriceListType type;
  final List<PriceListGroup> groups;
  final bool showPhotos;
  final bool showUpdatedDate;
  final Money? wholesaleMinimum;
  final String? footerNote;

  List<PriceListItem> get items => [for (final group in groups) ...group.items];

  Map<String, Object?> toClientJson() => {
    'businessName': businessName,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'type': type.name,
    'showPhotos': showPhotos,
    if (wholesaleMinimum != null)
      'wholesaleMinimumMinorUnits': wholesaleMinimum!.minorUnits,
    if (footerNote != null) 'footerNote': footerNote,
    'groups': [
      for (final group in groups)
        {
          if (group.name != null) 'name': group.name,
          'items': [for (final item in group.items) item.toClientJson()],
        },
    ],
  };
}

enum PriceListRenderTarget { pdf, image }

final class PriceListPage {
  const PriceListPage({
    required this.number,
    required this.groups,
    this.editorialColumns = const [],
  });

  final int number;
  final List<PriceListGroup> groups;
  final List<PriceListColumn> editorialColumns;

  List<PriceListItem> get items => [for (final group in groups) ...group.items];
}

final class PriceListColumn {
  const PriceListColumn({required this.groups});

  final List<PriceListGroup> groups;

  List<PriceListItem> get items => [for (final group in groups) ...group.items];
}

final class GeneratedPriceListFile {
  const GeneratedPriceListFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.pageCount,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final int pageCount;
}
