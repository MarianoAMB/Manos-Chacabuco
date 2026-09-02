import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/domain/importing/import_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/services/historical_sheet_analyzer.dart';
import 'package:manos_chacabuco/domain/services/product_measure_extractor.dart';
import 'package:manos_chacabuco/domain/services/sheet_formula_parser.dart';
import 'package:manos_chacabuco/domain/settings/app_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/historical_import_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('parser limitado de fórmulas históricas', () {
    const parser = SheetFormulaParser();

    test('reconoce la relación principal por peso y fila de material', () {
      final term = parser.parsePrimary('=(F30*B6)/C6', 30);

      expect(term?.materialRow, 6);
      expect(term?.usesProductWeight, isTrue);
    });

    test('reconoce un avío por unidades', () {
      final terms = parser.parseComplementary('=B7*2');

      expect(terms, hasLength(1));
      expect(terms!.single.materialRow, 7);
      expect(terms.single.quantity, 2);
    });

    test('reconoce varios avíos y también una suma explícita', () {
      final terms = parser.parseComplementary('=SUM((B18*1)+(B19*2)+(B16*5))');

      expect(terms!.map((term) => (term.materialRow, term.quantity)), [
        (18, 1),
        (19, 2),
        (16, 5),
      ]);
    });

    test('reconoce una longitud proporcional', () {
      final terms = parser.parseComplementary('=(B11*174)/C11');

      expect(terms, hasLength(1));
      expect(terms!.single.materialRow, 11);
      expect(terms.single.quantity, 174);
    });

    test('una expresión desconocida no se evalúa', () {
      expect(parser.parseComplementary('=INDIRECTO(B7)'), isNull);
    });
  });

  group('medidas y geometría prudentes', () {
    const extractor = ProductMeasureExtractor();

    test('Macetero 20x20 propone diámetro, alto y cilindro', () {
      final result = extractor.extract('Macetero 20x20');

      expect(result.values['Diámetro'], DecimalValue.parse('20'));
      expect(result.values['Alto'], DecimalValue.parse('20'));
      expect(result.geometryProfile?.shapeCode, 'cylinder');
      expect(result.semanticIsSafe, isTrue);
    });

    test('oval argentino extrae tres medidas y perfil oval', () {
      final result = extractor.extract('Contenedor oval 27,5x18x12 alto');

      expect(result.values['Largo'], DecimalValue.parse('27.5'));
      expect(result.values['Ancho'], DecimalValue.parse('18'));
      expect(result.values['Alto'], DecimalValue.parse('12'));
      expect(result.geometryProfile?.shapeCode, 'oval');
    });

    test('Bandeja 37x13 conserva medidas sin inventar geometría', () {
      final result = extractor.extract('Bandeja 37x13');

      expect(result.values['Largo'], DecimalValue.parse('37'));
      expect(result.values['Ancho'], DecimalValue.parse('13'));
      expect(result.geometryProfile, isNull);
      expect(result.semanticIsSafe, isTrue);
    });

    test('familia ambigua conserva números sin asignar forma', () {
      final result = extractor.extract('Canasto infantil 33x25');

      expect(result.values.values, hasLength(2));
      expect(result.geometryProfile, isNull);
      expect(result.semanticIsSafe, isFalse);
    });
  });

  test('analiza materiales, secciones, peso, multiplicador y avíos', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final materials = SqliteMaterialCatalogRepository(database);
    final settings = AppSettings.defaults(now: DateTime.utc(2026, 9, 2));
    var nextId = 0;

    final preview = const HistoricalSheetAnalyzer().analyze(
      workbook: historicalImportFixture(),
      spreadsheetId: 'sheet-id',
      sheetName: 'Hoja 1',
      units: await materials.findUnits(),
      materialCategories: await materials.findCategories(),
      productCategories: await SqliteProductCatalogRepository(database)
          .findCategories(),
      existingMaterials: const [],
      existingProducts: const [],
      sourceLinks: const <String, ImportSourceLink>{},
      settings: settings,
      idFactory: () => 'fixture-${nextId++}',
      analyzedAt: DateTime.utc(2026, 9, 2),
    );

    final cord = preview.materials.firstWhere(
      (item) => item.source.originalName == 'Cordón X',
    );
    expect(cord.material.purchase.price.minorUnits, 2100000);
    expect(cord.material.purchase.quantity.amount, DecimalValue.parse('2100'));
    final macetero = preview.products.firstWhere(
      (item) => item.source.originalName == 'Macetero 20x20',
    );
    expect(macetero.source.section, 'Deco');
    expect(macetero.product?.priceMultiplier, DecimalValue.parse('2.4'));
    expect(macetero.historicalWeight, 400);
    expect(macetero.product?.pricingOverrides.wastePercentage, isNull);
    expect(macetero.product?.pricingOverrides.retailPercentage, isNull);
    final primary = macetero.usages.singleWhere(
      (usage) => usage.role == ProductMaterialRole.primary,
    );
    expect(primary.consumption.amount, DecimalValue.parse('400'));
    expect(primary.consumptionSource, ConsumptionSource.confirmed);
    expect(primary.calibrationEligible, isTrue);
    final bandolera = preview.products.firstWhere(
      (item) => item.source.originalName == 'Bandolera Isa',
    );
    expect(bandolera.source.section, 'Accesorios');
    expect(
      bandolera.usages.where(
        (usage) => usage.role == ProductMaterialRole.complementary,
      ),
      hasLength(5),
    );
    expect(settings.defaultWastePercentage, DecimalValue.percent('1.5'));
    expect(settings.defaultThreadPercentage, DecimalValue.percent('6'));
  });
}
