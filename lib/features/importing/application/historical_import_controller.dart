// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/importing/import_models.dart';
import '../../../domain/importing/spreadsheet_models.dart';
import '../../../domain/services/historical_sheet_analyzer.dart';
import '../../materials/application/materials_controller.dart';
import '../../products/application/products_controller.dart';
import '../../settings/application/settings_controller.dart';

final class HistoricalImportController extends ChangeNotifier {
  HistoricalImportController({
    required HistoricalImportRepository repository,
    required XlsxWorkbookLoader workbookLoader,
    required MaterialsController materialsController,
    required ProductsController productsController,
    required SettingsController settingsController,
    HistoricalSheetAnalyzer analyzer = const HistoricalSheetAnalyzer(),
    Uuid uuid = const Uuid(),
  }) : _repository = repository,
       _workbookLoader = workbookLoader,
       _materialsController = materialsController,
       _productsController = productsController,
       _settingsController = settingsController,
       _analyzer = analyzer,
       _uuid = uuid;

  static const spreadsheetId = '1xByYNR5_7jVRI4H6yGWOVubsAOn6n15YmghdT-D_mH8';
  static const sheetName = 'Hoja 1';

  final HistoricalImportRepository _repository;
  final XlsxWorkbookLoader _workbookLoader;
  final MaterialsController _materialsController;
  final ProductsController _productsController;
  final SettingsController _settingsController;
  final HistoricalSheetAnalyzer _analyzer;
  final Uuid _uuid;

  ImportPreview? _preview;
  ImportReport? _latestReport;
  bool _isAnalyzing = false;
  bool _isImporting = false;
  String? _errorMessage;
  String? _selectedFilePath;

  ImportPreview? get preview => _preview;
  ImportReport? get latestReport => _latestReport;
  bool get isAnalyzing => _isAnalyzing;
  bool get isImporting => _isImporting;
  String? get errorMessage => _errorMessage;
  String? get selectedFilePath => _selectedFilePath;

  Future<void> load() async {
    _latestReport = await _repository.latestReport();
    notifyListeners();
  }

  Future<void> analyzeFile(String path) async {
    _isAnalyzing = true;
    _errorMessage = null;
    _preview = null;
    _selectedFilePath = path;
    notifyListeners();
    try {
      final bytes = await File(path).readAsBytes();
      final workbook = _workbookLoader.read(bytes);
      final links = await _repository.findSourceLinks(spreadsheetId);
      _preview = _analyzer.analyze(
        workbook: workbook,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        units: _materialsController.units,
        materialCategories: _materialsController.categories,
        productCategories: _productsController.categories,
        existingMaterials: [
          for (final bundle in _materialsController.materials) bundle.material,
        ],
        existingProducts: [
          for (final bundle in _productsController.products) bundle.product,
        ],
        sourceLinks: links,
        settings: _settingsController.settings,
        idFactory: _uuid.v4,
      );
    } on FormatException catch (error) {
      _errorMessage = error.message.toString();
    } catch (error, stackTrace) {
      debugPrint('Error analizando importación: $error\n$stackTrace');
      _errorMessage =
          'No pudimos leer esa planilla. Verificá que sea el XLSX correcto.';
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  void resolveProductConflict(String sourceKey, ImportDecision decision) {
    final current = _preview;
    if (current == null) return;
    _preview = ImportPreview(
      spreadsheetId: current.spreadsheetId,
      sheetName: current.sheetName,
      analyzedAt: current.analyzedAt,
      materials: current.materials,
      products: [
        for (final item in current.products)
          item.source.stableKey == sourceKey
              ? item.copyWith(decision: decision)
              : item,
      ],
      omittedRows: current.omittedRows,
    );
    notifyListeners();
  }

  void resolveMaterialConflict(String sourceKey, ImportDecision decision) {
    final current = _preview;
    if (current == null) return;
    _preview = ImportPreview(
      spreadsheetId: current.spreadsheetId,
      sheetName: current.sheetName,
      analyzedAt: current.analyzedAt,
      materials: [
        for (final item in current.materials)
          item.source.stableKey == sourceKey
              ? item.copyWith(decision: decision)
              : item,
      ],
      products: current.products,
      omittedRows: current.omittedRows,
    );
    notifyListeners();
  }

  Future<ImportReport> importSafeData() async {
    final current = _preview;
    if (current == null) throw StateError('Primero analizá una planilla.');
    _isImporting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final backupPath = await _repository.createBackup();
      final report = await _repository.importPreview(
        current,
        backupPath: backupPath,
      );
      _latestReport = report;
      await _materialsController.load();
      await _productsController.load();
      final path = _selectedFilePath;
      if (path != null) await analyzeFile(path);
      return report;
    } catch (error, stackTrace) {
      debugPrint('Error importando planilla: $error\n$stackTrace');
      _errorMessage =
          'La importación no se completó. No se guardaron datos parciales.';
      rethrow;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }
}
