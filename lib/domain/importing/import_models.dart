import '../../core/money/money.dart';
import '../materials/material_models.dart';
import '../products/product_models.dart';

enum ImportConfidence { safe, review, unresolved }

extension ImportConfidenceLabel on ImportConfidence {
  String get label => switch (this) {
    ImportConfidence.safe => 'Listo',
    ImportConfidence.review => 'Requiere revisión',
    ImportConfidence.unresolved => 'No resuelto',
  };
}

enum ImportDecision { create, useExisting, review, skip, alreadyImported }

enum ImportRecordType { material, product }

enum ImportIssueKind {
  measurements,
  materials,
  geometry,
  accessories,
  duplicates,
  formulas,
  incomplete,
}

extension ImportIssueKindLabel on ImportIssueKind {
  String get label => switch (this) {
    ImportIssueKind.measurements => 'Medidas',
    ImportIssueKind.materials => 'Materias primas',
    ImportIssueKind.geometry => 'Geometría',
    ImportIssueKind.accessories => 'Avíos',
    ImportIssueKind.duplicates => 'Posibles duplicados',
    ImportIssueKind.formulas => 'Fórmulas',
    ImportIssueKind.incomplete => 'Datos incompletos',
  };
}

final class ImportSourceMetadata {
  const ImportSourceMetadata({
    required this.spreadsheetId,
    required this.sheetName,
    required this.row,
    required this.section,
    required this.recordType,
    required this.originalName,
  });

  final String spreadsheetId;
  final String sheetName;
  final int row;
  final String section;
  final ImportRecordType recordType;
  final String originalName;

  String get stableKey =>
      '$spreadsheetId|$sheetName|$section|${recordType.name}|$row';
}

final class ImportSourceLink {
  const ImportSourceLink({required this.sourceKey, required this.targetId});

  final String sourceKey;
  final String targetId;
}

final class ImportIssue {
  const ImportIssue({
    required this.kind,
    required this.message,
    required this.source,
    this.details,
  });

  final ImportIssueKind kind;
  final String message;
  final ImportSourceMetadata source;
  final String? details;
}

final class SheetPriceComparison {
  const SheetPriceComparison({
    this.sheetCost,
    this.sheetWholesale,
    this.sheetRetail,
    this.appCost,
    this.appWholesale,
    this.appRetail,
  });

  final Money? sheetCost;
  final Money? sheetWholesale;
  final Money? sheetRetail;
  final Money? appCost;
  final Money? appWholesale;
  final Money? appRetail;
}

final class MaterialImportCandidate {
  const MaterialImportCandidate({
    required this.source,
    required this.confidence,
    required this.decision,
    required this.material,
    this.existingTargetId,
    this.issues = const [],
  });

  final ImportSourceMetadata source;
  final ImportConfidence confidence;
  final ImportDecision decision;
  final Material material;
  final String? existingTargetId;
  final List<ImportIssue> issues;

  String get targetId => existingTargetId ?? material.metadata.id;

  MaterialImportCandidate copyWith({ImportDecision? decision}) =>
      MaterialImportCandidate(
        source: source,
        confidence: confidence,
        decision: decision ?? this.decision,
        material: material,
        existingTargetId: decision == ImportDecision.create
            ? null
            : existingTargetId,
        issues: issues,
      );
}

final class ProductImportCandidate {
  const ProductImportCandidate({
    required this.source,
    required this.confidence,
    required this.decision,
    required this.product,
    required this.usages,
    required this.detectedMeasureCount,
    required this.priceComparison,
    this.existingTargetId,
    this.issues = const [],
    this.historicalWeight,
    this.calibrationReady = false,
  });

  final ImportSourceMetadata source;
  final ImportConfidence confidence;
  final ImportDecision decision;
  final Product? product;
  final List<ProductMaterialUsage> usages;
  final String? existingTargetId;
  final List<ImportIssue> issues;
  final double? historicalWeight;
  final int detectedMeasureCount;
  final bool calibrationReady;
  final SheetPriceComparison priceComparison;

  String? get targetId => existingTargetId ?? product?.metadata.id;

  ProductImportCandidate copyWith({ImportDecision? decision}) =>
      ProductImportCandidate(
        source: source,
        confidence: confidence,
        decision: decision ?? this.decision,
        product: product,
        usages: usages,
        existingTargetId: decision == ImportDecision.create
            ? null
            : existingTargetId,
        issues: issues,
        historicalWeight: historicalWeight,
        detectedMeasureCount: detectedMeasureCount,
        calibrationReady: calibrationReady,
        priceComparison: priceComparison,
      );
}

final class ImportPreview {
  const ImportPreview({
    required this.spreadsheetId,
    required this.sheetName,
    required this.analyzedAt,
    required this.materials,
    required this.products,
    required this.omittedRows,
  });

  final String spreadsheetId;
  final String sheetName;
  final DateTime analyzedAt;
  final List<MaterialImportCandidate> materials;
  final List<ProductImportCandidate> products;
  final int omittedRows;

  List<ImportIssue> get issues => [
    for (final item in materials) ...item.issues,
    for (final item in products) ...item.issues,
  ];

  int get primaryRelationshipCount => products
      .expand((item) => item.usages)
      .where((usage) => usage.role == ProductMaterialRole.primary)
      .length;
  int get complementaryRelationshipCount => products
      .expand((item) => item.usages)
      .where((usage) => usage.role == ProductMaterialRole.complementary)
      .length;
  int get productsWithWeight =>
      products.where((item) => item.historicalWeight != null).length;
  int get productsWithMultiplier => products
      .where((item) => item.product?.priceMultiplier.scaledValue != null)
      .length;
  int get productsWithMeasures =>
      products.where((item) => item.detectedMeasureCount > 0).length;
  int get detectedMeasures =>
      products.fold(0, (total, item) => total + item.detectedMeasureCount);
  int get safeGeometryCount =>
      products.where((item) => item.product?.geometryProfile != null).length;
  int get reviewCount =>
      products
          .where((item) => item.confidence != ImportConfidence.safe)
          .length +
      materials
          .where((item) => item.confidence != ImportConfidence.safe)
          .length;
  int get calibrationReadyCount =>
      products.where((item) => item.calibrationReady).length;
  int get newMaterialCount =>
      materials.where((item) => item.decision == ImportDecision.create).length;
  int get newProductCount =>
      products.where((item) => item.decision == ImportDecision.create).length;
}

final class ImportReport {
  const ImportReport({
    required this.id,
    required this.finishedAt,
    required this.importedMaterials,
    required this.importedProducts,
    required this.linkedExisting,
    required this.skipped,
    required this.warnings,
    required this.requiresReview,
    required this.calibrationReady,
    required this.backupPath,
  });

  final String id;
  final DateTime finishedAt;
  final int importedMaterials;
  final int importedProducts;
  final int linkedExisting;
  final int skipped;
  final int warnings;
  final int requiresReview;
  final int calibrationReady;
  final String backupPath;
}

abstract interface class HistoricalImportRepository {
  Future<Map<String, ImportSourceLink>> findSourceLinks(String spreadsheetId);
  Future<String> createBackup();
  Future<ImportReport> importPreview(
    ImportPreview preview, {
    required String backupPath,
  });
  Future<ImportReport?> latestReport();
}
