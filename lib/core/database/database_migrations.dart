import 'package:sqflite/sqflite.dart' show Database;

abstract final class DatabaseMigrations {
  static const currentVersion = 6;

  static Future<void> migrate(
    Database database,
    int fromVersion,
    int toVersion,
  ) async {
    if (fromVersion < 1 && toVersion >= 1) {
      await _createVersion1(database);
    }
    if (fromVersion < 2 && toVersion >= 2) {
      await _upgradeToVersion2(database);
    }
    if (fromVersion < 3 && toVersion >= 3) {
      await _upgradeToVersion3(database);
    }
    if (fromVersion < 4 && toVersion >= 4) {
      await _upgradeToVersion4(database);
    }
    if (fromVersion < 5 && toVersion >= 5) {
      await _upgradeToVersion5(database);
    }
    if (fromVersion < 6 && toVersion >= 6) {
      await _upgradeToVersion6(database);
    }
  }

  static Future<void> _createVersion1(Database database) async {
    final batch = database.batch();

    batch.execute('''
      CREATE TABLE app_settings (
        singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
        business_name TEXT NOT NULL,
        currency TEXT NOT NULL,
        default_waste_scaled INTEGER NOT NULL,
        default_thread_scaled INTEGER NOT NULL,
        default_retail_scaled INTEGER,
        default_multiplier_scaled INTEGER,
        minimum_wholesale_minor INTEGER,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE measurement_units (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        dimension TEXT NOT NULL,
        base_unit_factor_scaled INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE material_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE materials (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES material_categories(id),
        name TEXT NOT NULL,
        description TEXT,
        purchase_quantity_scaled INTEGER NOT NULL,
        purchase_unit_id TEXT NOT NULL REFERENCES measurement_units(id),
        purchase_price_minor INTEGER NOT NULL,
        currency TEXT NOT NULL,
        consumption_unit_id TEXT NOT NULL REFERENCES measurement_units(id),
        brand_or_supplier TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE material_variants (
        id TEXT PRIMARY KEY,
        material_id TEXT NOT NULL REFERENCES materials(id),
        name TEXT NOT NULL,
        purchase_quantity_scaled INTEGER,
        purchase_unit_id TEXT REFERENCES measurement_units(id),
        purchase_price_minor INTEGER,
        currency TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE product_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES product_categories(id),
        name TEXT NOT NULL,
        description TEXT,
        photo_path TEXT,
        shape_code TEXT,
        dimensions_json TEXT,
        waste_override_scaled INTEGER,
        retail_override_scaled INTEGER,
        price_multiplier_scaled INTEGER NOT NULL,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE product_material_usages (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id),
        material_id TEXT NOT NULL REFERENCES materials(id),
        material_variant_id TEXT REFERENCES material_variants(id),
        amount_scaled INTEGER NOT NULL,
        unit_id TEXT NOT NULL REFERENCES measurement_units(id),
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE quotes (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        quote_date TEXT NOT NULL,
        valid_until TEXT NOT NULL,
        waste_override_scaled INTEGER,
        retail_override_scaled INTEGER,
        multiplier_override_scaled INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE quote_items (
        id TEXT PRIMARY KEY,
        quote_id TEXT NOT NULL REFERENCES quotes(id),
        source_product_id TEXT REFERENCES products(id),
        description TEXT NOT NULL,
        quantity_scaled INTEGER NOT NULL,
        unit_price_minor INTEGER NOT NULL,
        currency TEXT NOT NULL,
        customization_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE quote_adjustments (
        id TEXT PRIMARY KEY,
        quote_id TEXT NOT NULL REFERENCES quotes(id),
        description TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        currency TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE sync_outbox (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        acknowledged_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_materials_active ON materials(is_active, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_variants_material ON material_variants(material_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_products_active ON products(is_active, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_product_usages_product ON product_material_usages(product_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_quote_items_quote ON quote_items(quote_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_outbox_pending ON sync_outbox(acknowledged_at, occurred_at)',
    );

    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeToVersion2(Database database) async {
    final batch = database.batch();
    batch.execute('ALTER TABLE material_variants ADD COLUMN notes TEXT');
    batch.execute(
      'CREATE INDEX idx_materials_category ON materials(category_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_materials_supplier ON materials(brand_or_supplier)',
    );
    batch.execute(
      'CREATE INDEX idx_variants_name ON material_variants(name COLLATE NOCASE)',
    );
    batch.execute('''
      CREATE UNIQUE INDEX idx_material_categories_unique_name
      ON material_categories(name COLLATE NOCASE)
      WHERE deleted_at IS NULL
    ''');

    final now = DateTime.now().toUtc().toIso8601String();
    const units = [
      (
        'd8a885bb-55c2-4fb3-b430-933781c3f8c0',
        'gram',
        'Gramos',
        'g',
        'weight',
        1000000,
      ),
      (
        '696f7d11-937d-47cc-9e4c-8e46f5caa706',
        'kilogram',
        'Kilogramos',
        'kg',
        'weight',
        1000000000,
      ),
      (
        'e2a6fd75-1f02-41ea-bd51-14e8535ddad5',
        'meter',
        'Metros',
        'm',
        'length',
        1000000,
      ),
      (
        'b59af36e-bb0c-4533-a4a8-48ec2cead406',
        'centimeter',
        'Centímetros',
        'cm',
        'length',
        10000,
      ),
      (
        '35258dd4-0b31-45dd-b06e-1992d96757d9',
        'square_meter',
        'Metros cuadrados',
        'm²',
        'area',
        1000000,
      ),
      (
        '44df27a1-a71f-447c-b6ee-02e75b6d6238',
        'square_centimeter',
        'Centímetros cuadrados',
        'cm²',
        'area',
        100,
      ),
      (
        '2bf70ea7-4bb8-4249-b009-f57f55aa1a85',
        'item',
        'Unidades',
        'u',
        'count',
        1000000,
      ),
    ];
    for (final unit in units) {
      batch.rawInsert(
        '''
          INSERT OR IGNORE INTO measurement_units
            (id, code, name, symbol, dimension, base_unit_factor_scaled,
             created_at, updated_at, deleted_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
        ''',
        [unit.$1, unit.$2, unit.$3, unit.$4, unit.$5, unit.$6, now, now],
      );
    }

    const categories = [
      ('16a028b4-23e3-46f4-9aa0-956cfa5f1392', 'Cordones'),
      ('1e7a99d0-0fea-411f-a4e6-15f26c53e45e', 'Cueros y cuerinas'),
      ('490386f4-1afe-4b6c-9876-19dd33a72aa9', 'Cierres'),
      ('502cbd3c-4aa5-4f82-b811-a95f97485d3b', 'Mosquetones'),
      ('0608546f-b7a4-46bf-b027-33a7997944cf', 'Herrajes y avíos'),
      ('b4f04da4-ae96-44f8-884a-d129983fd086', 'Cintas'),
      ('fd65e750-06ae-4f4d-8c6a-b0e6104649df', 'Hilos'),
      ('d00325ab-e7cc-4c2c-a153-4605ba0dcc54', 'Otros'),
    ];
    for (final category in categories) {
      batch.rawInsert(
        '''
          INSERT OR IGNORE INTO material_categories
            (id, name, is_active, created_at, updated_at, deleted_at)
          VALUES (?, ?, 1, ?, ?, NULL)
        ''',
        [category.$1, category.$2, now, now],
      );
    }

    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeToVersion3(Database database) async {
    final batch = database.batch();
    batch.execute(
      'ALTER TABLE products ADD COLUMN thread_override_scaled INTEGER',
    );
    batch.execute(
      "ALTER TABLE product_material_usages ADD COLUMN role TEXT NOT NULL DEFAULT 'primary'",
    );
    batch.execute(
      'CREATE INDEX idx_products_category ON products(category_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_products_name ON products(name COLLATE NOCASE)',
    );
    batch.execute(
      'CREATE INDEX idx_product_usages_material ON product_material_usages(material_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_product_usages_variant ON product_material_usages(material_variant_id, deleted_at)',
    );
    batch.execute('''
      CREATE UNIQUE INDEX idx_product_categories_unique_name
      ON product_categories(name COLLATE NOCASE)
      WHERE deleted_at IS NULL
    ''');

    final now = DateTime.now().toUtc().toIso8601String();
    const categories = [
      ('a27c29b7-5d11-4cae-9c26-57fc7a441001', 'Deco'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441002', 'Cestos'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441003', 'Maceteros'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441004', 'Bandejas'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441005', 'Cajas y contenedores'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441006', 'Bolsos y accesorios'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441007', 'Cocina y mesa'),
      ('a27c29b7-5d11-4cae-9c26-57fc7a441008', 'Otros'),
    ];
    for (final category in categories) {
      batch.rawInsert(
        '''
          INSERT OR IGNORE INTO product_categories
            (id, name, is_active, created_at, updated_at, deleted_at)
          VALUES (?, ?, 1, ?, ?, NULL)
        ''',
        [category.$1, category.$2, now, now],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeToVersion4(Database database) async {
    final batch = database.batch();
    batch.execute(
      'ALTER TABLE quotes ADD COLUMN validity_days INTEGER NOT NULL DEFAULT 15',
    );
    batch.execute(
      "ALTER TABLE quotes ADD COLUMN price_type TEXT NOT NULL DEFAULT 'retail'",
    );
    batch.execute(
      "ALTER TABLE quotes ADD COLUMN currency TEXT NOT NULL DEFAULT 'ARS'",
    );
    batch.execute(
      'ALTER TABLE quotes ADD COLUMN total_minor INTEGER NOT NULL DEFAULT 0',
    );
    batch.execute('ALTER TABLE quote_items ADD COLUMN category_id TEXT');
    batch.execute(
      'ALTER TABLE quote_items ADD COLUMN personalization_description TEXT',
    );
    batch.execute('ALTER TABLE quote_items ADD COLUMN dimensions_json TEXT');
    batch.execute(
      'ALTER TABLE quote_items ADD COLUMN waste_override_scaled INTEGER',
    );
    batch.execute(
      'ALTER TABLE quote_items ADD COLUMN thread_override_scaled INTEGER',
    );
    batch.execute(
      'ALTER TABLE quote_items ADD COLUMN retail_override_scaled INTEGER',
    );
    batch.execute(
      'ALTER TABLE quote_items ADD COLUMN price_multiplier_scaled INTEGER NOT NULL DEFAULT 1000000',
    );
    batch.execute('ALTER TABLE quote_items ADD COLUMN snapshot_json TEXT');
    batch.execute(
      'ALTER TABLE quote_adjustments ADD COLUMN quote_item_id TEXT',
    );
    batch.execute('''
      UPDATE quotes
      SET validity_days = MAX(
        0,
        CAST(julianday(valid_until) - julianday(quote_date) AS INTEGER)
      )
    ''');
    batch.execute('''
      UPDATE quotes
      SET total_minor = COALESCE((
        SELECT SUM(
          CAST(qi.quantity_scaled / 1000000 AS INTEGER) * qi.unit_price_minor
        )
        FROM quote_items qi
        WHERE qi.quote_id = quotes.id AND qi.deleted_at IS NULL
      ), 0) + COALESCE((
        SELECT SUM(qa.amount_minor)
        FROM quote_adjustments qa
        WHERE qa.quote_id = quotes.id AND qa.deleted_at IS NULL
      ), 0)
    ''');
    batch.execute(
      'CREATE INDEX idx_quotes_date ON quotes(quote_date DESC, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_quote_items_source ON quote_items(source_product_id)',
    );
    batch.execute(
      'CREATE INDEX idx_quote_adjustments_quote ON quote_adjustments(quote_id, deleted_at)',
    );
    batch.execute(
      'CREATE INDEX idx_quote_adjustments_item ON quote_adjustments(quote_item_id, deleted_at)',
    );
    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeToVersion5(Database database) async {
    final batch = database.batch();
    batch.execute('ALTER TABLE products ADD COLUMN geometry_profile_json TEXT');
    batch.execute(
      "ALTER TABLE product_material_usages ADD COLUMN consumption_source TEXT NOT NULL DEFAULT 'manual'",
    );
    batch.execute(
      'ALTER TABLE quote_items ADD COLUMN geometry_profile_json TEXT',
    );
    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeToVersion6(Database database) async {
    final batch = database.batch();
    batch.execute(
      'ALTER TABLE product_material_usages ADD COLUMN calibration_eligible INTEGER NOT NULL DEFAULT 1',
    );
    batch.execute('''
      CREATE TABLE import_records (
        id TEXT PRIMARY KEY,
        source_key TEXT NOT NULL UNIQUE,
        spreadsheet_id TEXT NOT NULL,
        sheet_name TEXT NOT NULL,
        source_row INTEGER NOT NULL,
        section TEXT NOT NULL,
        record_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        original_name TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE import_reports (
        id TEXT PRIMARY KEY,
        spreadsheet_id TEXT NOT NULL,
        sheet_name TEXT NOT NULL,
        finished_at TEXT NOT NULL,
        imported_materials INTEGER NOT NULL,
        imported_products INTEGER NOT NULL,
        linked_existing INTEGER NOT NULL,
        skipped INTEGER NOT NULL,
        warnings INTEGER NOT NULL,
        requires_review INTEGER NOT NULL,
        calibration_ready INTEGER NOT NULL,
        backup_path TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_import_records_source ON import_records(spreadsheet_id, sheet_name, record_type)',
    );
    batch.execute(
      'CREATE INDEX idx_import_reports_date ON import_reports(finished_at DESC)',
    );
    await batch.commit(noResult: true);
  }
}
