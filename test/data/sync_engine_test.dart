import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
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

      final restored = await _Device.open('different-account-restored');
      addTearDown(restored.close);
      await _sync(restored, secondRemote);
      expect(
        await _productName(restored, 'account-migration'),
        'Producto conservado',
      );
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
