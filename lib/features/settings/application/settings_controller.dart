// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/settings/app_settings.dart';

final class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required AppSettings initialSettings,
  }) : _repository = repository,
       _settings = initialSettings;

  final SettingsRepository _repository;
  AppSettings _settings;
  bool _isSaving = false;
  String? _errorMessage;

  AppSettings get settings => _settings;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

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
}
