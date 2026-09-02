import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../common/sync_metadata.dart';
import '../importing/import_models.dart';
import '../importing/spreadsheet_models.dart';
import '../materials/material_models.dart';
import '../pricing/pricing_models.dart';
import '../products/product_models.dart';
import '../settings/app_settings.dart';
import 'cost_engine.dart';
import 'import_name_normalizer.dart';
import 'product_measure_extractor.dart';
import 'sheet_formula_parser.dart';

final class HistoricalSheetAnalyzer {
  const HistoricalSheetAnalyzer({
    this.formulaParser = const SheetFormulaParser(),
    this.nameNormalizer = const ImportNameNormalizer(),
    this.measureExtractor = const ProductMeasureExtractor(),
  });

  final SheetFormulaParser formulaParser;
  final ImportNameNormalizer nameNormalizer;
  final ProductMeasureExtractor measureExtractor;

  ImportPreview analyze({
    required SpreadsheetWorkbook workbook,
    required String spreadsheetId,
    required String sheetName,
    required List<MeasurementUnit> units,
    required List<MaterialCategory> materialCategories,
    required List<ProductCategory> productCategories,
    required List<Material> existingMaterials,
    required List<Product> existingProducts,
    required Map<String, ImportSourceLink> sourceLinks,
    required AppSettings settings,
    required String Function() idFactory,
    DateTime? analyzedAt,
  }) {
    final sheet = workbook.sheetNamed(sheetName);
    if (sheet == null) {
      throw FormatException('El archivo no contiene la hoja “$sheetName”.');
    }
    final now = (analyzedAt ?? DateTime.now()).toUtc();
    final materialCandidates = _materials(
      sheet: sheet,
      spreadsheetId: spreadsheetId,
      units: units,
      categories: materialCategories,
      existing: existingMaterials,
      sourceLinks: sourceLinks,
      idFactory: idFactory,
      now: now,
    );
    final materialByRow = {
      for (final candidate in materialCandidates)
        candidate.source.row: _resolvedMaterial(candidate, existingMaterials),
    }..removeWhere((_, value) => value == null);
    final sections = _detectSections(sheet);
    final result = <ProductImportCandidate>[];
    var omittedRows = 0;
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      final endRow = sectionIndex + 1 < sections.length
          ? sections[sectionIndex + 1].headerRow - 1
          : sheet.rows.map((row) => row.index).fold(0, (a, b) => a > b ? a : b);
      for (final row in sheet.rows.where(
        (row) => row.index > section.headerRow && row.index <= endRow,
      )) {
        final rawName = row.cell(section.productColumn).text;
        if (!_validProductName(rawName)) {
          if (row.cells.values.any((cell) => !cell.isEmpty)) omittedRows++;
          continue;
        }
        result.add(
          _product(
            row: row,
            rawName: rawName!,
            section: section,
            sheetName: sheet.name,
            spreadsheetId: spreadsheetId,
            units: units,
            categories: productCategories,
            existing: existingProducts,
            sourceLinks: sourceLinks,
            materialByRow: Map<int, Material>.from(materialByRow),
            settings: settings,
            idFactory: idFactory,
            now: now,
          ),
        );
      }
    }
    return ImportPreview(
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      analyzedAt: now,
      materials: materialCandidates,
      products: result,
      omittedRows: omittedRows,
    );
  }

  List<MaterialImportCandidate> _materials({
    required SpreadsheetSheet sheet,
    required String spreadsheetId,
    required List<MeasurementUnit> units,
    required List<MaterialCategory> categories,
    required List<Material> existing,
    required Map<String, ImportSourceLink> sourceLinks,
    required String Function() idFactory,
    required DateTime now,
  }) {
    final result = <MaterialImportCandidate>[];
    for (final row in sheet.rows) {
      final originalName = row.cell('A').text;
      final price = row.cell('B').number;
      final quantity = row.cell('C').number;
      if (originalName == null ||
          originalName.toLowerCase().contains('materia prima')) {
        continue;
      }
      if (price == null || quantity == null || price <= 0 || quantity <= 0) {
        continue;
      }
      final source = ImportSourceMetadata(
        spreadsheetId: spreadsheetId,
        sheetName: sheet.name,
        row: row.index,
        section: 'Materias primas',
        recordType: ImportRecordType.material,
        originalName: originalName,
      );
      final inference = _inferMaterial(originalName, units, categories);
      final material = Material(
        metadata: SyncMetadata(id: idFactory(), createdAt: now, updatedAt: now),
        name: nameNormalizer.displayName(originalName),
        categoryId: inference.categoryId,
        purchase: PurchasePresentation(
          quantity: MeasuredQuantity(
            amount: _decimal(quantity),
            unitId: inference.unit.id,
          ),
          price: Money(minorUnits: (price * 100).round(), currency: 'ARS'),
        ),
        consumptionUnitId: inference.unit.id,
        notes: 'Importado de Precio Manos Chacabuco · fila ${row.index}.',
      );
      final importedLink = sourceLinks[source.stableKey];
      final exact = existing
          .where(
            (item) =>
                nameNormalizer.matchingKey(item.name) ==
                nameNormalizer.matchingKey(originalName),
          )
          .firstOrNull;
      final sameUnit = exact?.consumptionUnitId == material.consumptionUnitId;
      final sameCategory = exact?.categoryId == material.categoryId;
      final issues = <ImportIssue>[];
      late final ImportDecision decision;
      String? existingTargetId;
      if (importedLink != null) {
        decision = ImportDecision.alreadyImported;
        existingTargetId = importedLink.targetId;
      } else if (exact != null && sameUnit && sameCategory) {
        decision = ImportDecision.useExisting;
        existingTargetId = exact.metadata.id;
      } else if (exact != null) {
        decision = ImportDecision.review;
        existingTargetId = exact.metadata.id;
        issues.add(
          ImportIssue(
            kind: ImportIssueKind.duplicates,
            message: 'Existe una materia prima con el mismo nombre y otra unidad o categoría.',
            source: source,
          ),
        );
      } else if (inference.safe) {
        decision = ImportDecision.create;
      } else {
        decision = ImportDecision.review;
      }
      if (!inference.safe) {
        issues.add(
          ImportIssue(
            kind: ImportIssueKind.materials,
            message: 'La unidad o categoría necesita revisión.',
            source: source,
          ),
        );
      }
      result.add(
        MaterialImportCandidate(
          source: source,
          confidence: issues.isEmpty
              ? ImportConfidence.safe
              : ImportConfidence.review,
          decision: decision,
          material: material,
          existingTargetId: existingTargetId,
          issues: issues,
        ),
      );
    }
    return result;
  }

  ProductImportCandidate _product({
    required SpreadsheetRow row,
    required String rawName,
    required _SheetSection section,
    required String sheetName,
    required String spreadsheetId,
    required List<MeasurementUnit> units,
    required List<ProductCategory> categories,
    required List<Product> existing,
    required Map<String, ImportSourceLink> sourceLinks,
    required Map<int, Material> materialByRow,
    required AppSettings settings,
    required String Function() idFactory,
    required DateTime now,
  }) {
    final source = ImportSourceMetadata(
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      row: row.index,
      section: section.name,
      recordType: ImportRecordType.product,
      originalName: rawName,
    );
    final issues = <ImportIssue>[];
    final multiplierNumber = row.cell(section.multiplierColumn).number;
    final weight = row.cell(section.weightColumn).number;
    final measures = measureExtractor.extract(rawName);
    if (measures.values.isNotEmpty && !measures.semanticIsSafe) {
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.measurements,
          message: 'Se detectaron medidas, pero no su significado exacto.',
          source: source,
        ),
      );
    }
    if (measures.values.isNotEmpty && measures.geometryProfile == null) {
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.geometry,
          message: 'Las medidas no alcanzan para asignar una forma segura.',
          source: source,
        ),
      );
    }

    final productId = idFactory();
    Product? product;
    if (multiplierNumber == null || multiplierNumber <= 0) {
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.incomplete,
          message: 'Falta el multiplicador del producto.',
          source: source,
        ),
      );
    } else {
      final centimeter = _unitByCode(units, 'centimeter');
      product = Product(
        metadata: SyncMetadata(id: productId, createdAt: now, updatedAt: now),
        name: nameNormalizer.displayName(rawName),
        categoryId: _productCategoryId(rawName, section.name, categories),
        dimensions: measures.values.isEmpty
            ? null
            : ProductDimensions(
                shapeCode: measures.geometryProfile?.shapeCode ?? 'custom',
                values: {
                  for (final entry in measures.values.entries)
                    entry.key: MeasuredQuantity(
                      amount: entry.value,
                      unitId: centimeter.id,
                    ),
                },
              ),
        geometryProfile: measures.geometryProfile,
        priceMultiplier: _decimal(multiplierNumber),
        pricingOverrides: const PricingOverrides(),
        notes:
            'Importado de Precio Manos Chacabuco · ${section.name}, fila ${row.index}.',
      );
    }

    final usages = <ProductMaterialUsage>[];
    final primary = formulaParser.parsePrimary(
      row.cell(section.primaryMaterialColumn).formula,
      row.index,
    );
    final mixedMaterial = _mentionsUnsplitMix(rawName);
    if (primary == null) {
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.formulas,
          message: 'No se pudo identificar la materia prima principal.',
          source: source,
          details: row.cell(section.primaryMaterialColumn).formula,
        ),
      );
    } else if (weight == null || weight <= 0) {
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.incomplete,
          message: 'Falta el peso o consumo histórico.',
          source: source,
        ),
      );
    } else {
      final material = materialByRow[primary.materialRow];
      if (material == null) {
        issues.add(
          ImportIssue(
            kind: ImportIssueKind.materials,
            message: 'La fórmula apunta a una materia prima no disponible.',
            source: source,
          ),
        );
      } else if (product != null) {
        usages.add(
          ProductMaterialUsage(
            metadata: SyncMetadata(
              id: idFactory(),
              createdAt: now,
              updatedAt: now,
            ),
            productId: productId,
            materialId: material.metadata.id,
            consumption: MeasuredQuantity(
              amount: _decimal(weight),
              unitId: material.consumptionUnitId,
            ),
            role: ProductMaterialRole.primary,
            consumptionSource: ConsumptionSource.confirmed,
            calibrationEligible:
                !mixedMaterial && measures.geometryProfile != null,
            notes: mixedMaterial
                ? 'Peso total histórico; distribución entre materiales pendiente.'
                : 'Consumo histórico confirmado desde la planilla.',
          ),
        );
      }
    }
    if (mixedMaterial) {
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.materials,
          message: 'El nombre indica varios materiales, pero la planilla no distribuye el peso.',
          source: source,
        ),
      );
    }

    for (final column in section.complementaryColumns) {
      final cell = row.cell(column);
      final terms = formulaParser.parseComplementary(cell.formula);
      if (terms == null && cell.formula != null) {
        issues.add(
          ImportIssue(
            kind: ImportIssueKind.formulas,
            message: 'Hay una fórmula de avío que no pudo interpretarse.',
            source: source,
            details: cell.formula,
          ),
        );
      } else if (terms != null && product != null) {
        for (final term in terms) {
          final material = materialByRow[term.materialRow];
          if (material == null) {
            issues.add(
              ImportIssue(
                kind: ImportIssueKind.materials,
                message: 'Un avío apunta a una materia prima no disponible.',
                source: source,
              ),
            );
            continue;
          }
          usages.add(
            ProductMaterialUsage(
              metadata: SyncMetadata(
                id: idFactory(),
                createdAt: now,
                updatedAt: now,
              ),
              productId: productId,
              materialId: material.metadata.id,
              consumption: MeasuredQuantity(
                amount: _decimal(term.quantity),
                unitId: material.consumptionUnitId,
              ),
              role: ProductMaterialRole.complementary,
              consumptionSource: ConsumptionSource.confirmed,
              calibrationEligible: false,
              notes: 'Cantidad reconstruida desde fórmula histórica.',
            ),
          );
        }
      }
      if (cell.formula == null && (cell.number ?? 0) > 0) {
        issues.add(
          ImportIssue(
            kind: ImportIssueKind.accessories,
            message: 'Complementario histórico sin identificar.',
            source: source,
            details: 'Costo histórico: ${cell.number}',
          ),
        );
      }
    }

    final importedLink = sourceLinks[source.stableKey];
    final exact = existing
        .where(
          (item) =>
              nameNormalizer.matchingKey(item.name) ==
              nameNormalizer.matchingKey(rawName),
        )
        .firstOrNull;
    late final ImportDecision decision;
    String? existingTargetId;
    if (importedLink != null) {
      decision = ImportDecision.alreadyImported;
      existingTargetId = importedLink.targetId;
    } else if (exact != null) {
      decision = ImportDecision.review;
      existingTargetId = exact.metadata.id;
      issues.add(
        ImportIssue(
          kind: ImportIssueKind.duplicates,
          message: 'Ya existe un producto con el mismo nombre.',
          source: source,
        ),
      );
    } else if (product == null) {
      decision = ImportDecision.review;
    } else {
      decision = ImportDecision.create;
    }
    final comparison = _priceComparison(
      product: product,
      usages: usages,
      materialByRow: materialByRow,
      units: units,
      settings: settings,
      sheetCost: _money(row.cell(section.totalCostColumn).number),
      sheetWholesale: _money(row.cell(section.wholesaleColumn).number),
      sheetRetail: _money(row.cell(section.retailColumn).number),
    );
    return ProductImportCandidate(
      source: source,
      confidence: issues.isEmpty
          ? ImportConfidence.safe
          : product == null
          ? ImportConfidence.unresolved
          : ImportConfidence.review,
      decision: decision,
      product: product,
      usages: usages,
      existingTargetId: existingTargetId,
      issues: issues,
      historicalWeight: weight != null && weight > 0 ? weight : null,
      detectedMeasureCount: measures.values.length,
      calibrationReady: usages.any(
        (usage) =>
            usage.role == ProductMaterialRole.primary &&
            usage.calibrationEligible,
      ),
      priceComparison: comparison,
    );
  }

  SheetPriceComparison _priceComparison({
    required Product? product,
    required List<ProductMaterialUsage> usages,
    required Map<int, Material> materialByRow,
    required List<MeasurementUnit> units,
    required AppSettings settings,
    required Money? sheetCost,
    required Money? sheetWholesale,
    required Money? sheetRetail,
  }) {
    if (product == null || usages.isEmpty) {
      return SheetPriceComparison(
        sheetCost: sheetCost,
        sheetWholesale: sheetWholesale,
        sheetRetail: sheetRetail,
      );
    }
    try {
      final materialById = {
        for (final material in materialByRow.values)
          material.metadata.id: material,
      };
      final unitById = {for (final unit in units) unit.id: unit};
      const engine = CostEngine();
      final lines = [
        for (final usage in usages)
          engine
              .resolveLine(
                usage: usage,
                material: materialById[usage.materialId]!,
                variant: null,
                usageUnit: unitById[usage.consumption.unitId]!,
                purchaseUnit:
                    unitById[materialById[usage.materialId]!
                        .purchase
                        .quantity
                        .unitId]!,
                materialConsumptionUnit:
                    unitById[materialById[usage.materialId]!
                        .consumptionUnitId]!,
              )
              .line,
      ];
      final cost = engine.calculate(
        lines: lines,
        threadPercentage: settings.defaultThreadPercentage,
        wastePercentage: settings.defaultWastePercentage,
      );
      final wholesale = cost.totalCost.multiply(product.priceMultiplier);
      final retail = settings.defaultRetailPercentage == null
          ? null
          : wholesale.multiply(
              DecimalValue.one + settings.defaultRetailPercentage!,
            );
      return SheetPriceComparison(
        sheetCost: sheetCost,
        sheetWholesale: sheetWholesale,
        sheetRetail: sheetRetail,
        appCost: cost.totalCost,
        appWholesale: wholesale,
        appRetail: retail,
      );
    } catch (_) {
      return SheetPriceComparison(
        sheetCost: sheetCost,
        sheetWholesale: sheetWholesale,
        sheetRetail: sheetRetail,
      );
    }
  }

  List<_SheetSection> _detectSections(SpreadsheetSheet sheet) {
    final sections = <_SheetSection>[];
    for (final row in sheet.rows) {
      final first = nameNormalizer.matchingKey(row.cell('E').text ?? '');
      if (first != 'deco' && first != 'accesorios') continue;
      final labels = {
        for (final entry in row.cells.entries)
          nameNormalizer.matchingKey(entry.value.text ?? ''): entry.key,
      };
      String column(bool Function(String label) matches) => labels.entries
          .where((entry) => matches(entry.key))
          .map((entry) => entry.value)
          .first;
      final complementary = <String>[];
      for (final entry in labels.entries) {
        if (entry.value == 'E' || entry.value == 'G') continue;
        if (entry.key.contains('cuero') ||
            entry.key.contains('avio') ||
            entry.key.contains('corredera') ||
            entry.key.contains('cierre')) {
          complementary.add(entry.value);
        }
      }
      sections.add(
        _SheetSection(
          name: first == 'deco' ? 'Deco' : 'Accesorios',
          headerRow: row.index,
          productColumn: 'E',
          weightColumn: column((label) => label == 'peso'),
          primaryMaterialColumn: column((label) => label.contains('mat prima')),
          complementaryColumns: complementary,
          totalCostColumn: column((label) => label == 'total costo'),
          multiplierColumn: column((label) => label == 'beneficio'),
          wholesaleColumn: column((label) => label == 'total mayor'),
          retailColumn: column((label) => label == 'total menor'),
        ),
      );
    }
    if (sections.isEmpty) {
      throw const FormatException(
        'No se encontraron los bloques Deco y Accesorios.',
      );
    }
    return sections;
  }

  _MaterialInference _inferMaterial(
    String name,
    List<MeasurementUnit> units,
    List<MaterialCategory> categories,
  ) {
    final key = nameNormalizer.matchingKey(name);
    late final String unitCode;
    late final String categoryName;
    var safe = true;
    if (key.contains('cord')) {
      unitCode = 'gram';
      categoryName = 'Cordones';
    } else if (key.contains('cuerina')) {
      unitCode = 'square_centimeter';
      categoryName = 'Cueros y cuerinas';
    } else if (key.contains('cierre')) {
      unitCode = 'centimeter';
      categoryName = 'Cierres';
    } else if (key.contains('cinta')) {
      unitCode = 'centimeter';
      categoryName = 'Cintas';
    } else if (key.contains('correa')) {
      unitCode = 'centimeter';
      categoryName = 'Cueros y cuerinas';
    } else if (key.contains('mosquet')) {
      unitCode = 'item';
      categoryName = 'Mosquetones';
    } else if (key.contains('deslizador') ||
        key.contains('remache') ||
        key.contains('media luna') ||
        key.contains('medias lunas') ||
        key.contains('iman')) {
      unitCode = 'item';
      categoryName = 'Herrajes y avíos';
    } else if (key.contains('cuero')) {
      unitCode = 'item';
      categoryName = 'Cueros y cuerinas';
    } else {
      unitCode = 'item';
      categoryName = 'Otros';
      safe = false;
    }
    return _MaterialInference(
      unit: _unitByCode(units, unitCode),
      categoryId: _categoryId(categories, categoryName),
      safe: safe,
    );
  }

  String _productCategoryId(
    String name,
    String section,
    List<ProductCategory> categories,
  ) {
    final key = nameNormalizer.matchingKey(name);
    final category = key.contains('macetero')
        ? 'Maceteros'
        : key.contains('cesto') || key.contains('canasto')
        ? 'Cestos'
        : key.contains('bandeja')
        ? 'Bandejas'
        : key.contains('caja') || key.contains('contenedor')
        ? 'Cajas y contenedores'
        : section == 'Accesorios'
        ? 'Bolsos y accesorios'
        : key.contains('panera') ||
              key.contains('plato') ||
              key.contains('mesa') ||
              key.contains('cubierto') ||
              key.contains('fuente')
        ? 'Cocina y mesa'
        : 'Deco';
    return _categoryId(categories, category);
  }

  bool _mentionsUnsplitMix(String name) {
    final key = nameNormalizer.matchingKey(name);
    return key.contains('algodon') &&
        (key.contains('ppp') || key.contains('polipropileno'));
  }

  bool _validProductName(String? name) {
    if (name == null) return false;
    final key = nameNormalizer.matchingKey(name);
    return key.isNotEmpty &&
        key != 'producto' &&
        key != 'deco' &&
        key != 'accesorios';
  }

  Material? _resolvedMaterial(
    MaterialImportCandidate candidate,
    List<Material> existing,
  ) {
    if (candidate.decision == ImportDecision.review ||
        candidate.decision == ImportDecision.skip) {
      return null;
    }
    if (candidate.existingTargetId != null) {
      return existing
          .where((item) => item.metadata.id == candidate.existingTargetId)
          .firstOrNull;
    }
    return candidate.material;
  }

  MeasurementUnit _unitByCode(List<MeasurementUnit> units, String code) =>
      units.where((unit) => unit.code == code).first;

  String _categoryId(List<Object> categories, String name) {
    for (final category in categories) {
      final categoryName = switch (category) {
        MaterialCategory item => item.name,
        ProductCategory item => item.name,
        _ => '',
      };
      if (nameNormalizer.matchingKey(categoryName) ==
          nameNormalizer.matchingKey(name)) {
        return switch (category) {
          MaterialCategory item => item.metadata.id,
          ProductCategory item => item.metadata.id,
          _ => throw StateError('Categoría inválida'),
        };
      }
    }
    throw StateError('No existe la categoría $name.');
  }

  DecimalValue _decimal(double value) {
    final fixed = value.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
    final normalized = fixed.endsWith('.')
        ? fixed.substring(0, fixed.length - 1)
        : fixed;
    return DecimalValue.parse(normalized);
  }

  Money? _money(double? value) => value == null || !value.isFinite
      ? null
      : Money(minorUnits: (value * 100).round(), currency: 'ARS');
}

final class _SheetSection {
  const _SheetSection({
    required this.name,
    required this.headerRow,
    required this.productColumn,
    required this.weightColumn,
    required this.primaryMaterialColumn,
    required this.complementaryColumns,
    required this.totalCostColumn,
    required this.multiplierColumn,
    required this.wholesaleColumn,
    required this.retailColumn,
  });

  final String name;
  final int headerRow;
  final String productColumn;
  final String weightColumn;
  final String primaryMaterialColumn;
  final List<String> complementaryColumns;
  final String totalCostColumn;
  final String multiplierColumn;
  final String wholesaleColumn;
  final String retailColumn;
}

final class _MaterialInference {
  const _MaterialInference({
    required this.unit,
    required this.categoryId,
    required this.safe,
  });

  final MeasurementUnit unit;
  final String categoryId;
  final bool safe;
}
