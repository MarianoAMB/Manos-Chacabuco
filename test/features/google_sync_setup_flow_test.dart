import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/sync/sync_contracts.dart';
import 'package:manos_chacabuco/domain/sync/sync_models.dart';
import 'package:manos_chacabuco/features/settings/presentation/settings_screen.dart';
import 'package:manos_chacabuco/features/sync/application/sync_controller.dart';

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
