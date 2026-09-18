import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/sync/sync_contracts.dart';
import 'package:manos_chacabuco/domain/sync/sync_models.dart';
import 'package:manos_chacabuco/features/settings/presentation/settings_screen.dart';
import 'package:manos_chacabuco/features/sync/application/sync_controller.dart';
import 'package:manos_chacabuco/features/sync/application/sync_diagnostic.dart';
import 'package:googleapis/drive/v3.dart' show DetailedApiRequestError;

import '../support/test_app_harness.dart';

void main() {
  testWidgets('sin credenciales muestra un botón y un asistente claro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    final store = _EmptySyncStore();
    final syncController = SyncController(
      localStore: store,
      accountStore: store,
      authenticator: _ConfigurableAuthenticator(),
    );
    addTearDown(syncController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            controller: harness.settingsController,
            syncController: syncController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final connect = find.byKey(const Key('connect-google-drive'));
    expect(connect, findsOneWidget);
    expect(find.text('Conectar con Google'), findsOneWidget);
    expect(find.byKey(const Key('open-sync-privacy')), findsOneWidget);
    expect(find.textContaining('credencial OAuth'), findsNothing);

    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();

    expect(find.text('Activar Google Drive'), findsOneWidget);
    expect(find.text('Abrir Google Cloud'), findsOneWidget);
    expect(find.text('Elegir archivo JSON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'primer fallo muestra un detalle seguro y el reintento lo limpia',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = (await tester.runAsync(createTestAppHarness))!;
      addTearDown(harness.close);
      final store = _EmptySyncStore();
      final remote = _FirstPullFailingRemoteStore();
      final controller = SyncController(
        localStore: store,
        accountStore: store,
        authenticator: _ConnectedAuthenticator(remote),
      );
      addTearDown(controller.dispose);

      await controller.connect();
      expect(controller.status, SyncConnectionStatus.error);
      expect(controller.account.lastSyncAt, isNull);
      expect(controller.lastFailureDetails, contains('Leyendo los archivos'));
      expect(controller.lastFailureDetails, isNot(contains('dato privado')));
      await controller.refreshPending();
      expect(controller.status, SyncConnectionStatus.error);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              controller: harness.settingsController,
              syncController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final showDetails = find.byKey(const Key('show-sync-failure-details'));
      await tester.ensureVisible(showDetails);
      await tester.tap(showDetails);
      await tester.pumpAndSettle();
      expect(find.text('Detalle del problema'), findsOneWidget);
      expect(find.textContaining('FORMATO_DATOS'), findsOneWidget);
      expect(find.textContaining('dato privado'), findsNothing);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      remote.fail = false;
      await controller.syncNow();
      await tester.pumpAndSettle();
      expect(controller.status, SyncConnectionStatus.synchronized);
      expect(controller.account.lastSyncAt, isNotNull);
      expect(controller.lastFailureDetails, isNull);
      expect(showDetails, findsNothing);
    },
  );

  test('el detalle de Google no expone el cuerpo de la respuesta', () {
    final result = SyncDiagnostic.describe(
      'Leyendo los archivos de Google Drive',
      DetailedApiRequestError(403, 'token privado de ejemplo'),
    );
    expect(result, contains('HTTP 403'));
    expect(result, isNot(contains('token privado')));
  });

  test('un JSON inválido identifica el archivo sin mostrar su contenido', () {
    final result = SyncDiagnostic.describe(
      'Leyendo los archivos de Google Drive',
      const SyncFileFormatException(
        'mc-change-archivo123.json',
        FormatException('contenido privado'),
      ),
    );
    expect(result, contains('mc-change-archivo123.json'));
    expect(result, isNot(contains('contenido privado')));
  });
}

final class _ConnectedAuthenticator implements SyncAuthenticator {
  const _ConnectedAuthenticator(this.remote);

  final RemoteSyncStore remote;

  @override
  String? get configurationMessage => null;

  @override
  bool get isConfigured => true;

  @override
  Future<SyncAuthenticatedSession> connect() async => _ConnectedSession(remote);

  @override
  Future<void> disconnect() async {}

  @override
  Future<SyncAuthenticatedSession?> restore() async => null;
}

final class _ConnectedSession implements SyncAuthenticatedSession {
  const _ConnectedSession(this.remoteStore);

  @override
  String get email => 'manoschacabuco@gmail.com';

  @override
  final RemoteSyncStore remoteStore;

  @override
  Future<void> close() async {}
}

final class _FirstPullFailingRemoteStore implements RemoteSyncStore {
  bool fail = true;

  @override
  Future<List<SyncEnvelope>> pull({required Set<String> knownChangeIds}) async {
    if (fail) throw const FormatException('dato privado');
    return const [];
  }

  @override
  Future<void> push(SyncEnvelope envelope) async {}

  @override
  Future<bool> hasAsset(String hash) async => false;

  @override
  Future<void> uploadAsset(SyncAssetReference asset, Uint8List bytes) async {}

  @override
  Future<Uint8List?> downloadAsset(SyncAssetReference asset) async => null;
}

final class _ConfigurableAuthenticator
    implements ConfigurableSyncAuthenticator {
  bool configured = false;

  @override
  String? get configurationMessage => configured
      ? null
      : 'Google Drive necesita una configuración inicial de esta app.';

  @override
  bool get isConfigured => configured;

  @override
  Future<void> configure(String setupInput) async => configured = true;

  @override
  Future<SyncAuthenticatedSession> connect() => throw UnimplementedError();

  @override
  Future<void> disconnect() async {}

  @override
  Future<SyncAuthenticatedSession?> restore() async => null;
}

final class _EmptySyncStore implements LocalSyncStore, SyncAccountStore {
  SyncAccountState account = const SyncAccountState.disconnected();

  @override
  Future<List<SyncConflict>> conflicts() async => const [];

  @override
  Future<String> deviceId() async => 'test-device';

  @override
  Future<RemoteIntegrationResult> integrateRemote(
    SyncEnvelope envelope, {
    required Future<Uint8List?> Function(SyncAssetReference asset)
    downloadAsset,
  }) async => RemoteIntegrationResult.ignored;

  @override
  Future<void> markPushed(PendingSyncEnvelope pending) async {}

  @override
  Future<Set<String>> processedChangeIds() async => const {};

  @override
  Future<List<PendingSyncEnvelope>> pending({int limit = 100}) async =>
      const [];

  @override
  Future<void> prepareFullUploadForNewAccount() async {}

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<Uint8List?> readAsset(SyncAssetReference asset) async => null;

  @override
  Future<void> resolveConflict(
    String conflictId,
    SyncConflictResolution resolution, {
    String? remoteRevision,
  }) async {}

  @override
  Future<SyncAccountState> load() async => account;

  @override
  Future<void> save(SyncAccountState state) async => account = state;
}
