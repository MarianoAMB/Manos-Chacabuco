import '../settings/app_settings.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> getOrCreateDefaults();
  Future<void> save(AppSettings settings);
}
