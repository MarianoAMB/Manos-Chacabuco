import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/database/database_migrations.dart';
import 'package:manos_chacabuco/core/sync/sync_contracts.dart';
import 'package:manos_chacabuco/core/sync/sync_engine.dart';
import 'package:manos_chacabuco/data/sync/fake_remote_sync_store.dart';
import 'package:manos_chacabuco/data/sync/sqlite_sync_store.dart';
import 'package:manos_chacabuco/domain/sync/sync_models.dart';
import 'package:manos_chacabuco/features/sync/application/sync_controller.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'crear y editar offline guarda primero y deja outbox pendiente',
    () async {
      final device = await _Device.open('offline');
      addTearDown(device.close);
      await _insertProduct(device, 'p-offline', 'Producto offline');

      final row = (await device.database.database.query(
        'products',
        where: 'id = ?',
        whereArgs: const ['p-offline'],
      )).single;
      final pending = await device.store.pending();

      expect(row['name'], 'Producto offline');
      expect(
        pending.any((change) => change.envelope.entityId == 'p-offline'),
        isTrue,
      );

      await _renameProduct(device, 'p-offline', 'Producto editado offline');
      expect(await device.store.pendingCount(), greaterThan(0));
    },
  );

  test(
    'primer dispositivo puebla remoto y segundo vacío conserva el ID',
    () async {
      final remote = FakeRemoteSyncStore();
      final a = await _Device.open('simple-a');
      final b = await _Device.open('simple-b');
      addTearDown(a.close);
      addTearDown(b.close);
      await _insertProduct(a, 'same-stable-id', 'Macetero desde Windows');

      await _sync(a, remote);
      await _sync(b, remote);

      final received = (await b.database.database.query(
        'products',
        where: 'id = ?',
        whereArgs: const ['same-stable-id'],
      )).single;
      expect(received['name'], 'Macetero desde Windows');
      expect(received['id'], 'same-stable-id');
      expect(await b.store.conflicts(), isEmpty);
    },
  );

  test('entidades diferentes se combinan aunque ambos tengan datos', () async {
    final remote = FakeRemoteSyncStore();
    final a = await _Device.open('merge-a');
    final b = await _Device.open('merge-b');
    addTearDown(a.close);
    addTearDown(b.close);
    await _insertProduct(a, 'product-a', 'Producto A');
    await _insertProduct(b, 'product-b', 'Producto B');

    await _sync(a, remote);
    await _sync(b, remote);
    await _sync(a, remote);

    expect(
      await a.database.database.query('products', where: 'deleted_at IS NULL'),
      hasLength(2),
    );
    expect(
      await b.database.database.query('products', where: 'deleted_at IS NULL'),
      hasLength(2),
    );
  });

  test(
    'misma entidad crea conflicto y ambas resoluciones preservan datos',
    () async {
      final remote = FakeRemoteSyncStore();
      final a = await _Device.open('conflict-a');
      final b = await _Device.open('conflict-b');
      addTearDown(a.close);
      addTearDown(b.close);
      await _insertProduct(a, 'conflicted', 'Versión inicial');
      await _sync(a, remote);
      await _sync(b, remote);

      await _renameProduct(a, 'conflicted', 'Versión Windows');
      await _renameProduct(b, 'conflicted', 'Versión Android');
      await _sync(a, remote);
      await _sync(b, remote);

      var conflicts = await b.store.conflicts();
      expect(conflicts, hasLength(1));
      expect(
        conflicts.single.localPayload.toString(),
        contains('Versión Android'),
      );
      expect(
        conflicts.single.remoteEnvelope.payload.toString(),
        contains('Versión Windows'),
      );

      await b.store.resolveConflict(
        conflicts.single.id,
        SyncConflictResolution.useLocal,
      );
      await _sync(b, remote);
      await _sync(a, remote);
      expect(await _productName(a, 'conflicted'), 'Versión Android');

      await _renameProduct(a, 'conflicted', 'Otra edición Windows');
      await _renameProduct(b, 'conflicted', 'Otra edición Android');
      await _sync(a, remote);
      await _sync(b, remote);
      conflicts = await b.store.conflicts();
      expect(conflicts, hasLength(1));
      await b.store.resolveConflict(
        conflicts.single.id,
        SyncConflictResolution.useRemote,
      );
      expect(await _productName(b, 'conflicted'), 'Otra edición Windows');
    },
  );

  test('tres dispositivos agrupan candidatos y publican una resolución convergente', () async {
    final remote = FakeRemoteSyncStore();
    final a = await _Device.open('three-way-a');
    final b = await _Device.open('three-way-b');
    final c = await _Device.open('three-way-c');
    addTearDown(a.close);
    addTearDown(b.close);
    addTearDown(c.close);

    await _insertProduct(a, 'three-way', 'Versión inicial');
    await _sync(a, remote);
    await _sync(b, remote);
    await _sync(c, remote);

    await _renameProduct(a, 'three-way', 'Versión PC A');
    await _renameProduct(b, 'three-way', 'Versión Android B');
    await _renameProduct(c, 'three-way', 'Versión PC C');
    final branchA = (await a.store.pending()).singleWhere(
      (pending) => pending.envelope.entityId == 'three-way',
    );
    final branchC = (await c.store.pending()).singleWhere(
      (pending) => pending.envelope.entityId == 'three-way',
    );
    await remote.push(branchA.envelope);
    await remote.push(branchC.envelope);

    await _sync(b, remote);
    final conflict = (await b.store.conflicts()).single;
    expect(conflict.remoteEnvelopes, hasLength(2));
    expect(
      conflict.remoteEnvelopes.map((envelope) => envelope.payload.toString()),
      containsAll([contains('Versión PC A'), contains('Versión PC C')]),
    );

    await b.store.resolveConflict(
      conflict.id,
      SyncConflictResolution.useRemote,
      remoteRevision: branchC.envelope.revision,
    );
    final resolution = (await b.store.pending()).singleWhere(
      (pending) => pending.envelope.entityId == 'three-way',
    );
    expect(resolution.envelope.baseRevision, branchC.envelope.revision);
    expect(
      resolution.envelope.resolvedRevisions,
      contains(branchA.envelope.revision),
    );
    await _sync(b, remote);
    await _sync(a, remote);
    await _sync(c, remote);
    await _sync(a, remote);
    await _sync(b, remote);
    await _sync(c, remote);

    expect(await _productName(a, 'three-way'), 'Versión PC C');
    expect(await _productName(b, 'three-way'), 'Versión PC C');
    expect(await _productName(c, 'three-way'), 'Versión PC C');
    expect(await a.store.conflicts(), isEmpty);
    expect(await b.store.conflicts(), isEmpty);
    expect(await c.store.conflicts(), isEmpty);
  });

  test('una resolución se integra después de todas las ramas que declara resueltas', () async {
    final remote = FakeRemoteSyncStore();
    final seed = await _Device.open('resolved-order-seed');
    final target = await _Device.open('resolved-order-target');
    addTearDown(seed.close);
    addTearDown(target.close);

    await _insertProduct(seed, 'resolved-order', 'Versión inicial');
    await _sync(seed, remote);
    await _sync(target, remote);
    final initial = remote.allChanges.singleWhere(
      (change) => change.entityId == 'resolved-order',
    );
    Map<String, Object?> payload(String name) => {
      'root': {
        ...Map<String, Object?>.from(initial.payload['root']! as Map),
        'name': name,
      },
      'usages': const <Object?>[],
    };
    final branchA = SyncEnvelope.create(
      changeId: 'z-branch-a',
      deviceId: 'device-a',
      entityType: 'product',
      entityId: 'resolved-order',
      operation: SyncOperation.upsert,
      payload: payload('Versión A'),
      occurredAt: DateTime.utc(2026, 9, 5, 10),
      baseRevision: initial.revision,
      assets: const [],
    );
    final branchC = SyncEnvelope.create(
      changeId: 'y-branch-c',
      deviceId: 'device-c',
      entityType: 'product',
      entityId: 'resolved-order',
      operation: SyncOperation.upsert,
      payload: payload('Versión C'),
      occurredAt: DateTime.utc(2026, 9, 5, 11),
      baseRevision: initial.revision,
      assets: const [],
    );
    final resolution = SyncEnvelope.create(
      changeId: 'a-resolution',
      deviceId: 'device-b',
      entityType: 'product',
      entityId: 'resolved-order',
      operation: SyncOperation.upsert,
      payload: payload('Versión elegida'),
      occurredAt: DateTime.utc(2026, 9, 5, 12),
      baseRevision: initial.revision,
      resolvedRevisions: [branchA.revision, branchC.revision],
      assets: const [],
    );
    await remote.push(resolution);
    await remote.push(branchA);
    await remote.push(branchC);

    await _sync(target, remote);

    expect(await _productName(target, 'resolved-order'), 'Versión elegida');
    expect(await target.store.conflicts(), isEmpty);
  });

  test(
    'un candidato más nuevo reemplaza su versión anterior en el conflicto',
    () async {
      final remote = FakeRemoteSyncStore();
      final seed = await _Device.open('head-seed');
      final target = await _Device.open('head-target');
      addTearDown(seed.close);
      addTearDown(target.close);

      await _insertProduct(seed, 'head-product', 'Versión inicial');
      await _sync(seed, remote);
      await _sync(target, remote);
      await _renameProduct(target, 'head-product', 'Cambio local');
      final initial = remote.allChanges.singleWhere(
        (change) => change.entityId == 'head-product',
      );
      Map<String, Object?> payload(String name) => {
        'root': {
          ...Map<String, Object?>.from(initial.payload['root']! as Map),
          'name': name,
        },
        'usages': const <Object?>[],
      };
      final firstRemote = SyncEnvelope.create(
        changeId: 'remote-first',
        deviceId: 'remote-device',
        entityType: 'product',
        entityId: 'head-product',
        operation: SyncOperation.upsert,
        payload: payload('Cambio remoto 1'),
        occurredAt: DateTime.utc(2026, 9, 5, 10),
        baseRevision: initial.revision,
        assets: const [],
      );
      final newestRemote = SyncEnvelope.create(
        changeId: 'remote-newest',
        deviceId: 'remote-device',
        entityType: 'product',
        entityId: 'head-product',
        operation: SyncOperation.upsert,
        payload: payload('Cambio remoto 2'),
        occurredAt: DateTime.utc(2026, 9, 5, 11),
        baseRevision: firstRemote.revision,
        assets: const [],
      );
      await remote.push(firstRemote);
      await remote.push(newestRemote);

      await _sync(target, remote);

      final conflict = (await target.store.conflicts()).single;
      expect(conflict.remoteEnvelopes, hasLength(1));
      expect(
        conflict.remoteEnvelope.payload.toString(),
        contains('Cambio remoto 2'),
      );
      await target.store.resolveConflict(
        conflict.id,
        SyncConflictResolution.useLocal,
      );
      final resolution = (await target.store.pending()).singleWhere(
        (change) => change.envelope.entityId == 'head-product',
      );
      expect(
        resolution.envelope.resolvedRevisions,
        containsAll([firstRemote.revision, newestRemote.revision]),
      );
      await _sync(target, remote);
      await _sync(seed, remote);
      expect(await _productName(seed, 'head-product'), 'Cambio local');
      expect(await seed.store.conflicts(), isEmpty);
    },
  );

  test(
    'editar antes de subir una resolución conserva todas las ramas resueltas',
    () async {
      final remote = FakeRemoteSyncStore();
      final a = await _Device.open('edit-resolution-a');
      final b = await _Device.open('edit-resolution-b');
      addTearDown(a.close);
      addTearDown(b.close);

      await _insertProduct(a, 'edit-resolution', 'Versión inicial');
      await _sync(a, remote);
      await _sync(b, remote);
      await _renameProduct(a, 'edit-resolution', 'Cambio A');
      await _renameProduct(b, 'edit-resolution', 'Cambio B');
      await _sync(a, remote);
      await _sync(b, remote);
      final conflict = (await b.store.conflicts()).single;

      await b.store.resolveConflict(
        conflict.id,
        SyncConflictResolution.useLocal,
      );
      await _renameProduct(b, 'edit-resolution', 'Cambio B posterior');
      final pending = (await b.store.pending()).singleWhere(
        (change) => change.envelope.entityId == 'edit-resolution',
      );
      expect(
        pending.envelope.resolvedRevisions,
        contains(conflict.remoteEnvelope.revision),
      );

      await _sync(b, remote);
      await _sync(a, remote);
      expect(await _productName(a, 'edit-resolution'), 'Cambio B posterior');
      expect(await a.store.conflicts(), isEmpty);
    },
  );

  test('tombstone elimina en el otro dispositivo y no resucita', () async {
    final remote = FakeRemoteSyncStore();
    final a = await _Device.open('delete-a');
    final b = await _Device.open('delete-b');
    addTearDown(a.close);
    addTearDown(b.close);
    await _insertProduct(a, 'deleted-product', 'Producto a eliminar');
    await _sync(a, remote);
    await _sync(b, remote);

    final deletedAt = DateTime.utc(2026, 9, 4, 15);
    await a.database.database.update(
      'products',
      {
        'deleted_at': deletedAt.toIso8601String(),
        'updated_at': deletedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: const ['deleted-product'],
    );
    await _sync(a, remote);
    await _sync(b, remote);
    await _sync(b, remote);

    final row = (await b.database.database.query(
      'products',
      where: 'id = ?',
      whereArgs: const ['deleted-product'],
    )).single;
    expect(row['deleted_at'], deletedAt.toIso8601String());
    expect(
      remote.allChanges
          .where((change) => change.entityId == 'deleted-product')
          .last
          .operation,
      SyncOperation.delete,
    );
  });

  test('quitar un consumo elimina el hijo remoto del agregado', () async {
    final remote = FakeRemoteSyncStore();
    final a = await _Device.open('children-a');
    final b = await _Device.open('children-b');
    addTearDown(a.close);
    addTearDown(b.close);
    await _insertProductWithUsage(a);

    await _sync(a, remote);
    await _sync(b, remote);
    expect(
      await b.database.database.query(
        'product_material_usages',
        where: 'product_id = ?',
        whereArgs: const ['product-with-usage'],
      ),
      hasLength(1),
    );

    await a.database.database.delete(
      'product_material_usages',
      where: 'id = ?',
      whereArgs: const ['usage-to-remove'],
    );
    await _sync(a, remote);
    await _sync(b, remote);

    expect(
      await b.database.database.query(
        'product_material_usages',
        where: 'product_id = ?',
        whereArgs: const ['product-with-usage'],
      ),
      isEmpty,
    );
  });

  test('foto, logo y snapshot viajan separados y sin recalcularse', () async {
    final remote = FakeRemoteSyncStore();
    final a = await _Device.open('assets-a');
    final b = await _Device.open('assets-b');
    addTearDown(a.close);
    addTearDown(b.close);
    final photoBytes = utf8.encode('foto-binaria-estable');
    final logoBytes = utf8.encode('logo-binario-estable');
    await File(paths.join(a.photos.path, 'photo-a.jpg'))
        .writeAsBytes(photoBytes);
    await File(paths.join(a.logos.path, 'logo-a.png')).writeAsBytes(logoBytes);
    await _insertProduct(
      a,
      'with-photo',
      'Producto con foto',
      photoPath: 'photo-a.jpg',
    );
    await _insertSettings(a, logoPath: 'logo-a.png');
    const snapshot = '{"precio":2500000, "material":"Cordón N°7"}';
    await _insertQuote(a, snapshot);

    await _sync(a, remote);
    await _sync(b, remote);

    expect(
      await File(paths.join(b.photos.path, 'photo-a.jpg')).readAsBytes(),
      photoBytes,
    );
    expect(
      await File(paths.join(b.logos.path, 'logo-a.png')).readAsBytes(),
      logoBytes,
    );
    final item = (await b.database.database.query(
      'quote_items',
      where: 'id = ?',
      whereArgs: const ['quote-item'],
    )).single;
    expect(item['snapshot_json'], snapshot);
    expect(remote.uploadedAssetCount, 2);
  });

  test('fallo remoto conserva outbox y el retry es idempotente', () async {
    final remote = FakeRemoteSyncStore();
    final device = await _Device.open('retry');
    addTearDown(device.close);
    await _insertProduct(device, 'retry-product', 'Producto retry');
    final before = await device.store.pendingCount();
    remote.failNextRequest = true;

    await expectLater(
      _sync(device, remote),
      throwsA(isA<RemoteSyncException>()),
    );
    expect(await device.store.pendingCount(), before);

    await _sync(device, remote);
    final uploads = remote.uploadedChangeCount;
    await _sync(device, remote);
    await _sync(device, remote);
    expect(remote.uploadedChangeCount, uploads);
    expect(await device.store.pendingCount(), 0);
  });

  test(
    'desconectar conserva datos y pendientes; reconectar los sincroniza',
    () async {
      final remote = FakeRemoteSyncStore();
      final a = await _Device.open('reconnect-a');
      final b = await _Device.open('reconnect-b');
      addTearDown(a.close);
      addTearDown(b.close);

      await a.store.save(
        const SyncAccountState(connected: true, email: 'taller@example.com'),
      );
      await a.store.save(const SyncAccountState.disconnected());
      await _insertProduct(a, 'offline-disconnected', 'Guardado sin Google');

      expect(
        (await a.database.database.query(
          'products',
          where: 'id = ?',
          whereArgs: const ['offline-disconnected'],
        )).single['name'],
        'Guardado sin Google',
      );
      expect(await a.store.pendingCount(), greaterThan(0));

      await a.store.save(
        const SyncAccountState(connected: true, email: 'taller@example.com'),
      );
      await _sync(a, remote);
      await _sync(b, remote);

      expect(
        await _productName(b, 'offline-disconnected'),
        'Guardado sin Google',
      );
      expect((await a.store.load()).email, 'taller@example.com');
    },
  );

  test(
    'cambiar de cuenta copia todos los datos sin pedir un segundo ingreso',
    () async {
      final device = await _Device.open('different-account');
      addTearDown(device.close);
      final firstRemote = FakeRemoteSyncStore();
      final secondRemote = FakeRemoteSyncStore();
      final authenticator = _FakeAuthenticator(
        email: 'primera@example.com',
        remote: firstRemote,
      );
      final controller = SyncController(
        localStore: device.store,
        accountStore: device.store,
        authenticator: authenticator,
      );
      addTearDown(controller.dispose);

      await _insertProduct(device, 'account-migration', 'Producto conservado');
      await controller.connect();
      expect(controller.account.email, 'primera@example.com');
      expect(await device.store.pendingCount(), 0);
      await device.database.database.insert('sync_outbox', {
        'id': 'old-account-marker',
        'entity_type': 'product',
        'entity_id': 'account-migration',
        'operation': 'upsert',
        'payload_json':
            '{"baseRevision":"old-base","resolvedRevisions":["old-head"]}',
        'occurred_at': DateTime.utc(2026, 9, 5, 12).toIso8601String(),
        'acknowledged_at': null,
      });
      authenticator.email = 'otra@example.com';
      authenticator.remote = secondRemote;

      await controller.connect();
      expect(controller.account.connected, isTrue);
      expect(controller.account.email, 'otra@example.com');
      expect(authenticator.connectCount, 2);
      expect(
        secondRemote.allChanges.any(
          (change) => change.entityId == 'account-migration',
        ),
        isTrue,
      );
      final migratedProduct = secondRemote.allChanges.singleWhere(
        (change) => change.entityId == 'account-migration',
      );
      expect(migratedProduct.baseRevision, isNull);
      expect(migratedProduct.resolvedRevisions, isEmpty);

      final restored = await _Device.open('different-account-restored');
      addTearDown(restored.close);
      await _sync(restored, secondRemote);
      expect(
        await _productName(restored, 'account-migration'),
        'Producto conservado',
      );
    },
  );

  test(
    'cache de dispositivos conserva una base v8 y sus 186 cambios pendientes',
    () async {
      final root = await Directory.systemTemp.createTemp('manos-v8-cache-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final photos = Directory(paths.join(root.path, 'product_photos'));
      final logos = Directory(paths.join(root.path, 'business_assets'));
      await photos.create(recursive: true);
      await logos.create(recursive: true);
      final databasePath = paths.join(root.path, 'app.db');
      var database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      var store = SqliteSyncStore(
        database: database,
        photoDirectory: photos,
        logoDirectory: logos,
      );
      await _insertProduct(
        _Device(database, store, root, photos, logos),
        'retained-v8',
        'Producto conservado',
      );
      final stableDeviceId = await store.deviceId();
      await store.save(
        const SyncAccountState(
          connected: true,
          email: 'manoschacabuco@gmail.com',
        ),
      );
      await database.database.delete('sync_outbox');
      final batch = database.database.batch();
      for (var index = 0; index < 186; index++) {
        batch.insert('sync_outbox', {
          'id': 'retained-change-$index',
          'entity_type': 'product',
          'entity_id': 'retained-v8',
          'operation': 'upsert',
          'payload_json': '{}',
          'occurred_at': DateTime.utc(
            2026,
            9,
            5,
            12,
          ).add(Duration(milliseconds: index)).toIso8601String(),
          'acknowledged_at': null,
        });
      }
      await batch.commit(noResult: true);
      final snapshot = await store.buildCurrentDeviceSnapshot(
        recentChanges: const [],
      );
      await store.saveDeviceSnapshots([snapshot]);
      await store.renameCurrentDevice('PC del taller');
      await database.close();

      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      store = SqliteSyncStore(
        database: database,
        photoDirectory: photos,
        logoDirectory: logos,
      );
      addTearDown(database.close);

      expect(await database.database.getVersion(), 8);
      expect(DatabaseMigrations.currentVersion, 8);
      expect(await store.deviceId(), stableDeviceId);
      expect(await store.pendingCount(), 186);
      expect(
        (await database.database.query(
          'products',
          where: 'id = ?',
          whereArgs: const ['retained-v8'],
        )).single['name'],
        'Producto conservado',
      );
      expect((await store.load()).email, 'manoschacabuco@gmail.com');
      final restoredDevices = await store.loadDeviceSnapshots();
      expect(restoredDevices, hasLength(1));
      expect(restoredDevices.single.deviceId, stableDeviceId);
      expect(restoredDevices.single.isCurrent, isTrue);
      expect(restoredDevices.single.name, 'PC del taller');
      expect(restoredDevices.single.summary.products, 1);
    },
  );
}

Future<void> _sync(_Device device, FakeRemoteSyncStore remote) =>
    SyncEngine(local: device.store, remote: remote).synchronize();

Future<void> _insertProduct(
  _Device device,
  String id,
  String name, {
  String? photoPath,
}) async {
  final now = DateTime.utc(2026, 9, 4, 10).toIso8601String();
  await device.database.database.insert('products', {
    'id': id,
    'category_id': 'a27c29b7-5d11-4cae-9c26-57fc7a441003',
    'name': name,
    'description': null,
    'photo_path': photoPath,
    'shape_code': null,
    'dimensions_json': null,
    'waste_override_scaled': null,
    'retail_override_scaled': null,
    'price_multiplier_scaled': 2000000,
    'notes': null,
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
    'thread_override_scaled': null,
    'geometry_profile_json': null,
  });
}

Future<void> _renameProduct(_Device device, String id, String name) async {
  await device.database.database.update(
    'products',
    {'name': name, 'updated_at': DateTime.now().toUtc().toIso8601String()},
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<void> _insertProductWithUsage(_Device device) async {
  final database = device.database.database;
  final category = (await database.query('material_categories')).first;
  final gram = (await database.query(
    'measurement_units',
    where: 'code = ?',
    whereArgs: const ['gram'],
  )).single;
  final now = DateTime.utc(2026, 9, 4, 10).toIso8601String();
  await database.insert('materials', {
    'id': 'material-for-usage',
    'category_id': category['id'],
    'name': 'Material sincronizable',
    'purchase_quantity_scaled': 1000000000,
    'purchase_unit_id': gram['id'],
    'purchase_price_minor': 100000,
    'currency': 'ARS',
    'consumption_unit_id': gram['id'],
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
  });
  await _insertProduct(device, 'product-with-usage', 'Producto con consumo');
  await database.insert('product_material_usages', {
    'id': 'usage-to-remove',
    'product_id': 'product-with-usage',
    'material_id': 'material-for-usage',
    'amount_scaled': 250000000,
    'unit_id': gram['id'],
    'role': 'primary',
    'consumption_source': 'confirmed',
    'calibration_eligible': 1,
    'created_at': now,
    'updated_at': now,
  });
}

Future<String> _productName(_Device device, String id) async =>
    (await device.database.database.query(
          'products',
          columns: const ['name'],
          where: 'id = ?',
          whereArgs: [id],
        )).single['name']!
        as String;

Future<void> _insertSettings(_Device device, {required String logoPath}) async {
  await device.database.database.insert('app_settings', {
    'singleton_id': 1,
    'business_name': 'Manos Chacabuco',
    'currency': 'ARS',
    'default_waste_scaled': 15000,
    'default_thread_scaled': 60000,
    'default_retail_scaled': 300000,
    'default_multiplier_scaled': 2000000,
    'minimum_wholesale_minor': null,
    'updated_at': DateTime.utc(2026, 9, 4).toIso8601String(),
    'business_logo_path': logoPath,
  });
}

Future<void> _insertQuote(_Device device, String snapshot) async {
  final now = DateTime.utc(2026, 9, 4).toIso8601String();
  await device.database.database.transaction((transaction) async {
    await transaction.insert('quotes', {
      'id': 'quote',
      'customer_name': 'Cliente',
      'quote_date': now,
      'valid_until': DateTime.utc(2026, 9, 19).toIso8601String(),
      'waste_override_scaled': null,
      'retail_override_scaled': null,
      'multiplier_override_scaled': null,
      'notes': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'validity_days': 15,
      'price_type': 'retail',
      'currency': 'ARS',
      'total_minor': 2500000,
    });
    await transaction.insert('quote_items', {
      'id': 'quote-item',
      'quote_id': 'quote',
      'source_product_id': null,
      'description': 'Pieza especial',
      'quantity_scaled': 1000000,
      'unit_price_minor': 2500000,
      'currency': 'ARS',
      'customization_json': '{"description":null,"usages":[]}',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'category_id': null,
      'personalization_description': null,
      'dimensions_json': null,
      'waste_override_scaled': null,
      'thread_override_scaled': null,
      'retail_override_scaled': null,
      'price_multiplier_scaled': 2000000,
      'snapshot_json': snapshot,
      'geometry_profile_json': null,
    });
  });
}

final class _Device {
  const _Device(this.database, this.store, this.root, this.photos, this.logos);

  final AppDatabase database;
  final SqliteSyncStore store;
  final Directory root;
  final Directory photos;
  final Directory logos;

  static Future<_Device> open(String name) async {
    final root = await Directory.systemTemp.createTemp('manos-sync-$name-');
    final photos = Directory(paths.join(root.path, 'product_photos'));
    final logos = Directory(paths.join(root.path, 'business_assets'));
    await photos.create(recursive: true);
    await logos.create(recursive: true);
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: paths.join(root.path, 'app.db'),
    );
    final store = SqliteSyncStore(
      database: database,
      photoDirectory: photos,
      logoDirectory: logos,
    );
    return _Device(database, store, root, photos, logos);
  }

  Future<void> close() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final class _FakeAuthenticator implements SyncAuthenticator {
  _FakeAuthenticator({required this.email, required this.remote});

  String email;
  FakeRemoteSyncStore remote;
  int disconnectCount = 0;
  int connectCount = 0;

  @override
  String? get configurationMessage => null;

  @override
  bool get isConfigured => true;

  @override
  Future<SyncAuthenticatedSession> connect() async {
    connectCount++;
    return _FakeSession(email, remote);
  }

  @override
  Future<void> disconnect() async => disconnectCount++;

  @override
  Future<SyncAuthenticatedSession?> restore() async => null;
}

final class _FakeSession implements SyncAuthenticatedSession {
  const _FakeSession(this.email, this.remoteStore);

  @override
  final String email;

  @override
  final RemoteSyncStore remoteStore;

  @override
  Future<void> close() async {}
}
