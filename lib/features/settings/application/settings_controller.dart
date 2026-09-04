// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../../domain/repositories/business_logo_store.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/settings/app_settings.dart';

final class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required AppSettings initialSettings,
    BusinessLogoStore? logoStore,
  }) : _repository = repository,
       _settings = initialSettings,
       _logoStore = logoStore;

  final SettingsRepository _repository;
  final BusinessLogoStore? _logoStore;
  AppSettings _settings;
  bool _isSaving = false;
  String? _errorMessage;

  AppSettings get settings => _settings;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get logoAbsolutePath {
    final reference = _settings.businessLogoPath;
    if (reference == null || _logoStore == null) return null;
    return _logoStore.absolutePath(reference);
  }

  Future<void> reload() async {
    _settings = await _repository.getOrCreateDefaults();
    notifyListeners();
  }

  Future<void> save(AppSettings settings) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.save(settings);
      _settings = settings;
    } catch (error, stackTrace) {
      debugPrint('Error guardando configuración: $error\n$stackTrace');
      _errorMessage =
          'No pudimos guardar la configuración. Intentá nuevamente.';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> importLogo(String sourcePath) async {
    final store = _logoStore;
    if (store == null) throw StateError('Almacenamiento de logo no disponible');
    final previous = _settings.businessLogoPath;
    final reference = await store.importFile(sourcePath);
    try {
      await save(
        _settings.copyWith(
          businessLogoPath: reference,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (previous != null && previous != reference) {
        await store.delete(previous);
      }
    } catch (_) {
      await store.delete(reference);
      rethrow;
    }
  }

  Future<void> removeLogo() async {
    final store = _logoStore;
    final previous = _settings.businessLogoPath;
    if (store == null || previous == null) return;
    await save(
      _settings.copyWith(
        clearBusinessLogoPath: true,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await store.delete(previous);
  }
}
