import '../../core/formatting/argentine_number_formatter.dart';
import '../materials/material_models.dart';
import '../products/product_models.dart';

final class ProductCommercialFormatter {
  const ProductCommercialFormatter();

  String? dimensions(
    ProductDimensions? dimensions,
    List<MeasurementUnit> units,
  ) {
    if (dimensions == null || dimensions.values.isEmpty) return null;
    final unitById = {for (final unit in units) unit.id: unit};
    final entries = dimensions.values.entries
        .where((entry) => unitById.containsKey(entry.value.unitId))
        .toList(growable: false);
    if (entries.isEmpty) return null;
    final symbols = entries
        .map((entry) => unitById[entry.value.unitId]!.symbol)
        .toSet();
    if (symbols.length == 1) {
      final symbol = symbols.single;
      final diameterIndex = entries.indexWhere(
        (entry) => _normalized(entry.key).contains('diametro'),
      );
      final ordered = diameterIndex <= 0
          ? entries
          : [
              entries[diameterIndex],
              ...entries.where((e) => e != entries[diameterIndex]),
            ];
      final values = ordered
          .map((entry) => ArgentineNumberFormatter.decimal(entry.value.amount))
          .join(' × ');
      return '${diameterIndex >= 0 ? 'Ø ' : ''}$values $symbol';
    }
    return entries
        .map((entry) {
          final unit = unitById[entry.value.unitId]!;
          final value = ArgentineNumberFormatter.decimal(entry.value.amount);
          return '$value ${unit.symbol} ${entry.key.toLowerCase()}';
        })
        .join(' · ');
  }

  String? primaryMaterials({
    required List<ProductMaterialUsage> usages,
    required List<Material> materials,
    required List<MaterialVariant> variants,
  }) {
    final materialById = {
      for (final material in materials) material.metadata.id: material,
    };
    final variantById = {
      for (final variant in variants) variant.metadata.id: variant,
    };
    final labels = <String>[];
    for (final usage in usages.where(
      (usage) => usage.role == ProductMaterialRole.primary,
    )) {
      final material = materialById[usage.materialId];
      if (material == null) continue;
      final variant = usage.materialVariantId == null
          ? null
          : variantById[usage.materialVariantId];
      final label = variant == null
          ? material.name
          : '${material.name} · ${variant.name}';
      if (!labels.contains(label)) labels.add(label);
    }
    if (labels.isEmpty) return null;
    if (labels.length <= 2) return labels.join(' + ');
    return '${labels.first} + ${labels.length - 1} materiales';
  }

  String _normalized(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
}
