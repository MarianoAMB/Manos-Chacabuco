import 'package:manos_chacabuco/domain/importing/spreadsheet_models.dart';

SpreadsheetWorkbook historicalImportFixture() => SpreadsheetWorkbook(
  sheets: [
    SpreadsheetSheet(
      name: 'Hoja 1',
      rows: [
        _row(1, {
          'A': 'Materia prima',
          'B': 'Precios',
          'C': 'Peso / cm / unid',
          'E': 'Deco',
          'F': 'Peso',
          'G': 'Mat. Prima',
          'H': 'Hilos',
          'I': 'Cueros y avíos',
          'J': 'Desperdicio',
          'K': 'Total costo',
          'L': 'Beneficio',
          'M': 'Total Mayor',
          'N': 'Total menor',
        }),
        _material(6, 'Cordón X', 21000, 2100),
        _material(7, 'Cueros marca', 80, 1),
        _material(8, 'Cierre', 1200, 100),
        _material(9, 'Deslizador', 660, 1),
        _material(11, 'Cintas símil gamuza 30mm', 880, 100),
        _material(12, 'Prend imán 15mm', 450, 1),
        _material(13, 'Mosquetones 15 mm', 363, 1),
        _material(15, 'Medias lunas 15 mm', 92.4, 1),
        _material(16, 'Medias lunas 30 mm', 440, 1),
        _material(17, 'Remaches tapados 12x12', 81.4, 1),
        _material(18, 'Mosquetón grueso', 1860, 1),
        _material(19, 'Mosquetón argolla', 422.84, 1),
        _material(20, 'Cuerina cálculo por cm2', 0.785708, 1),
        _material(22, 'Cuero correa 20 mm', 49.792, 1),
        _product(
          30,
          'Macetero 20x20',
          400,
          primaryFormula: '=(F30*B6)/C6',
          complementaryFormula: '=B7',
          multiplier: 2.4,
        ),
        _product(
          31,
          'Macetero 18x18',
          350,
          primaryFormula: '=(F31*B6)/C6',
          complementaryFormula: '=B7',
          multiplier: 2.4,
        ),
        _product(
          32,
          'Macetero 18x14',
          280,
          primaryFormula: '=(F32*B6)/C6',
          complementaryFormula: '=B7',
          multiplier: 2.4,
        ),
        _product(
          40,
          'Bandeja 37x13',
          160,
          primaryFormula: '=(F40*B6)/C6',
          complementaryFormula: '=B7',
          multiplier: 2.4,
        ),
        _product(
          44,
          'Canasto infantil 33x25',
          620,
          primaryFormula: '=(F44*B6)/C6',
          complementaryFormula: '=B7*3',
          multiplier: 2.5,
        ),
        _row(45, {
          'E': 'Accesorios',
          'F': 'Peso',
          'G': 'Mat. Prima',
          'H': 'Hilos',
          'I': 'Cueros',
          'J': 'Desperdicio',
          'K': 'Correderas / avíos',
          'L': 'Cierres / cueros',
          'M': 'Total costo',
          'N': 'Beneficio',
          'O': 'Total Mayor',
          'P': 'Total menor',
        }),
        _row(46, {
          'E': 'Bolso Pirámide',
          'F': 550,
          'G': _formula('=(F46*B6)/C6', 5500),
          'I': _formula('=B7', 80),
          'K': _formula('=B9', 660),
          'L': _formula('=(100*B8)/C8', 1200),
          'M': 7440,
          'N': 3,
          'O': 22320,
          'P': 29016,
        }),
        _row(53, {
          'E': 'Bandolera Isa',
          'F': 450,
          'G': _formula('=(F53*B6)/C6', 4500),
          'I': _formula('=B7', 80),
          'K': _formula('=((B18*1)+(B19*2)+(B16*5))', 4905.68),
          'L': _formula('=(B11*174)/C11', 1531.2),
          'M': 11016.88,
          'N': 2.5,
          'O': 27542.2,
          'P': 35804.86,
        }),
      ],
    ),
  ],
);

SpreadsheetRow _material(int row, String name, num price, num quantity) =>
    _row(row, {'A': name, 'B': price, 'C': quantity});

SpreadsheetRow _product(
  int row,
  String name,
  num weight, {
  required String primaryFormula,
  required String complementaryFormula,
  required num multiplier,
}) => _row(row, {
  'E': name,
  'F': weight,
  'G': _formula(primaryFormula, weight * 10),
  'I': _formula(complementaryFormula, 80),
  'K': weight * 10 + 80,
  'L': multiplier,
  'M': (weight * 10 + 80) * multiplier,
  'N': (weight * 10 + 80) * multiplier * 1.1,
});

SpreadsheetRow _row(int index, Map<String, Object?> values) => SpreadsheetRow(
  index: index,
  cells: {
    for (final entry in values.entries)
      entry.key: switch (entry.value) {
        final SpreadsheetCell cell => cell,
        final Object value => SpreadsheetCell(value: value),
        null => const SpreadsheetCell(),
      },
  },
);

SpreadsheetCell _formula(String formula, num value) =>
    SpreadsheetCell(value: value, formula: formula);
