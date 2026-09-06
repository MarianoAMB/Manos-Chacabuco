// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../../core/sync/sync_contracts.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../domain/sync/sync_models.dart';

final class SyncController extends ChangeNotifier with WidgetsBindingObserver {
  SyncController({
    required LocalSyncStore localStore,
    required SyncAccountStore accountStore,
    required SyncAuthenticator authenticator,
    Connectivity? connectivity,
    Future<void> Function()? onDataApplied,
  }) : _localStore = localStore,
       _accountStore = accountStore,
       _authenticator = authenticator,
       _connectivity = connectivity ?? Connectivity(),
       _onDataApplied = onDataApplied;

  final LocalSyncStore _localStore;
  final SyncAccountStore _accountStore;
  final SyncAuthenticator _authenticator;
  final Connectivity _connectivity;
  final Future<void> Function()? _onDataApplied;

  SyncAccountState _account = const SyncAccountState.disconnected();
  SyncConnectionStatus _status = SyncConnectionStatus.disconnected;
  SyncAuthenticatedSession? _session;
  List<SyncConflict> _conflicts = const [];
  List<SyncDeviceSnapshot> _devices = const [];
  int _pendingCount = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;
  Timer? _debounce;
  Timer? _retryTimer;
  bool _initialized = false;
  bool _online = true;
  int _consecutiveFailures = 0;

  SyncAccountState get account => _account;
  SyncConnectionStatus get status => _status;
  List<SyncConflict> get conflicts => _conflicts;
  List<SyncDeviceSnapshot> get devices => _devices;
  int get pendingCount => _pendingCount;
  bool get isConfigured => _authenticator.isConfigured;
  bool get canConfigure => _authenticator is ConfigurableSyncAuthenticator;
  String? get configurationMessage => _authenticator.configurationMessage;
  bool get isBusy => _status == SyncConnectionStatus.syncing;

  String get statusLabel => switch (_status) {
    SyncConnectionStatus.notConfigured => 'Falta configurar Google',
    SyncConnectionStatus.disconnected => 'Sin cuenta conectada',
    SyncConnectionStatus.offline => 'Sin conexión',
    SyncConnectionStatus.syncing => 'Sincronizando…',
    SyncConnectionStatus.pending => '$_pendingCount cambios pendientes',
    SyncConnectionStatus.synchronized => 'Todo actualizado',
    SyncConnectionStatus.conflict =>
      '${_conflicts.length} ${_conflicts.length == 1 ? 'cambio necesita' : 'cambios necesitan'} revisión',
    SyncConnectionStatus.error =>
      _account.lastError ?? 'No se pudo sincronizar',
  };

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _account = await _accountStore.load();
    await _refreshLocalState();
    final connectivity = await _connectivity.checkConnectivity();
    _online = !connectivity.contains(ConnectivityResult.none);
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _connectivityChanged,
    );
    _periodicTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_account.connected && _session != null && _online) _scheduleSync();
    });
    if (!_authenticator.isConfigured) {
      _status = SyncConnectionStatus.notConfigured;
      notifyListeners();
      return;
    }
    if (!_account.connected) {
      _status = SyncConnectionStatus.disconnected;
      notifyListeners();
      return;
    }
    try {
      _session = await _authenticator.restore();
      if (_session == null) {
        _account = _account.copyWith(
          connected: false,
          lastError: 'Volvé a conectar tu cuenta de Google.',
        );
        await _accountStore.save(_account);
        _status = SyncConnectionStatus.disconnected;
      } else if (_online) {
        await syncNow();
      } else {
        _status = SyncConnectionStatus.offline;
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo restaurar Google Drive: $error\n$stackTrace');
      _status = SyncConnectionStatus.error;
      _account = _account.copyWith(lastError: _friendlyError(error));
      await _accountStore.save(_account);
    }
    notifyListeners();
  }

  Future<void> connect() async {
    if (!_authenticator.isConfigured || isBusy) return;
    _status = SyncConnectionStatus.syncing;
    notifyListeners();
    try {
      final session = await _authenticator.connect();
      final previousEmail = _account.email;
      final accountChanged =
          previousEmail != null &&
          previousEmail.toLowerCase() != session.email.toLowerCase();
      if (accountChanged) {
        await _localStore.prepareFullUploadForNewAccount();
      }
      await _session?.close();
      _session = session;
      _account = SyncAccountState(
        connected: true,
        email: session.email,
        lastSyncAt: _account.lastSyncAt,
      );
      await _accountStore.save(_account);
      await syncNow(force: true);
    } catch (error, stackTrace) {
      debugPrint('No se pudo conectar Google Drive: $error\n$stackTrace');
      _account = _account.copyWith(lastError: _friendlyError(error));
      await _accountStore.save(_account);
      _status = SyncConnectionStatus.error;
    }
    notifyListeners();
  }

  Future<void> configure(String setupInput) async {
    if (isBusy) return;
    final authenticator = _authenticator;
    if (authenticator is! ConfigurableSyncAuthenticator) {
      throw StateError('Esta versión no permite configurar Google Drive.');
    }
    await authenticator.configure(setupInput);
    await _session?.close();
    _session = null;
    _account = _account.copyWith(connected: false, clearError: true);
    await _accountStore.save(_account);
    _status = SyncConnectionStatus.disconnected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (isBusy) return;
    try {
      await _authenticator.disconnect();
    } finally {
      await _session?.close();
      _session = null;
      _account = _account.copyWith(connected: false, clearError: true);
      await _accountStore.save(_account);
      await _refreshLocalState();
      _status = SyncConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> syncNow({bool force = false}) async {
    final session = _session;
    if (session == null || (isBusy && !force)) return;
    if (!_online) {
      await _refreshLocalState();
      _status = SyncConnectionStatus.offline;
      notifyListeners();
      return;
    }
    _status = SyncConnectionStatus.syncing;
    _retryTimer?.cancel();
    _retryTimer = null;
    notifyListeners();
    try {
      final result = await SyncEngine(
        local: _localStore,
        remote: session.remoteStore,
      ).synchronize();
      await _refreshLocalState();
      if (result.downloaded > 0 && _onDataApplied != null) {
        await _onDataApplied();
      }
      _account = _account.copyWith(
        connected: true,
        email: session.email,
        lastSyncAt: DateTime.now().toUtc(),
        clearError: true,
      );
      await _accountStore.save(_account);
      _consecutiveFailures = 0;
      _status = _conflicts.isNotEmpty
          ? SyncConnectionStatus.conflict
          : _pendingCount > 0
          ? SyncConnectionStatus.pending
          : SyncConnectionStatus.synchronized;
    } catch (error, stackTrace) {
      debugPrint('Error sincronizando Google Drive: $error\n$stackTrace');
      await _refreshLocalState();
      _account = _account.copyWith(lastError: _friendlyError(error));
      await _accountStore.save(_account);
      _status = _online
          ? SyncConnectionStatus.error
          : SyncConnectionStatus.offline;
      if (_online && _isTransient(error)) _scheduleRetry();
    }
    notifyListeners();
  }

  Future<void> resolveConflict(
    SyncConflict conflict,
    SyncConflictResolution resolution, {
    String? remoteRevision,
  }) async {
    await _localStore.resolveConflict(
      conflict.id,
      resolution,
      remoteRevision: remoteRevision,
    );
    await _refreshLocalState();
    if (_onDataApplied != null) await _onDataApplied();
    _status = _conflicts.isNotEmpty
        ? SyncConnectionStatus.conflict
        : SyncConnectionStatus.pending;
    notifyListeners();
    _scheduleSync();
  }

  Future<void> refreshPending() async {
    await _refreshLocalState();
    if (_account.connected && !isBusy) {
      _status = _conflicts.isNotEmpty
          ? SyncConnectionStatus.conflict
          : _pendingCount > 0
          ? SyncConnectionStatus.pending
          : SyncConnectionStatus.synchronized;
    }
    notifyListeners();
  }

  void localDataChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      await refreshPending();
      if (_account.connected && _session != null && _online) {
        await syncNow();
      }
    });
  }

  Future<void> _refreshLocalState() async {
    _pendingCount = await _localStore.pendingCount();
    _conflicts = await _localStore.conflicts();
    if (_localStore case final DeviceSyncLocalStore deviceStore) {
      final devices = [...await deviceStore.loadDeviceSnapshots()];
      devices.sort((left, right) {
        if (left.isCurrent != right.isCurrent) return left.isCurrent ? -1 : 1;
        final leftDate = left.lastSyncedAt;
        final rightDate = right.lastSyncedAt;
        if (leftDate == null) return rightDate == null ? 0 : 1;
        if (rightDate == null) return -1;
        return rightDate.compareTo(leftDate);
      });
      _devices = List.unmodifiable(devices);
    } else {
      _devices = const [];
    }
  }

  SyncDeviceSnapshot? deviceById(String deviceId) {
    for (final device in _devices) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }

  Future<void> renameCurrentDevice(String name) async {
    if (_localStore case final DeviceSyncLocalStore deviceStore) {
      await deviceStore.renameCurrentDevice(name);
      await _refreshLocalState();
      notifyListeners();
      if (_account.connected && _session != null && _online) {
        await syncNow();
      }
    }
  }

  void _connectivityChanged(List<ConnectivityResult> results) {
    final wasOnline = _online;
    _online = !results.contains(ConnectivityResult.none);
    if (!_online && _account.connected) {
      _status = SyncConnectionStatus.offline;
      notifyListeners();
    } else if (!wasOnline && _online && _account.connected) {
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(syncNow()));
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _consecutiveFailures++;
    final seconds = 15 * (1 << (_consecutiveFailures - 1).clamp(0, 4));
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (_account.connected && _session != null && _online) {
        unawaited(syncNow());
      }
    });
  }

  bool _isTransient(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('network') ||
        text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('temporar') ||
        text.contains('quota') ||
        text.contains('429') ||
        text.contains('500') ||
        text.contains('502') ||
        text.contains('503') ||
        text.contains('504');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _account.connected) {
      _scheduleSync();
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('cancel') ||
        text.contains('rechaz') ||
        text.contains('autoriz')) {
      return 'No se completó el acceso a Google. Podés intentarlo de nuevo.';
    }
    if (text.contains('clientconfigurationerror') ||
        text.contains('oauth') ||
        text.contains('client_id')) {
      return 'Google rechazó la identificación de esta app. Revisá la configuración inicial.';
    }
    if (text.contains('quota')) {
      return 'Google Drive alcanzó temporalmente su límite. Intentaremos después.';
    }
    if (text.contains('token') || text.contains('sesión')) {
      return 'La sesión de Google venció. Volvé a conectar la cuenta.';
    }
    if (text.contains('network') || text.contains('socket')) {
      return 'No hay conexión. Tus cambios quedaron guardados para después.';
    }
    return 'Google Drive no está disponible ahora. Tus datos locales están seguros.';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _periodicTimer?.cancel();
    _debounce?.cancel();
    _retryTimer?.cancel();
    unawaited(_session?.close());
    super.dispose();
  }
}
