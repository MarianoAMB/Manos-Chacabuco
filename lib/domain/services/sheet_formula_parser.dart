final class FormulaMaterialTerm {
  const FormulaMaterialTerm({
    required this.materialRow,
    required this.quantity,
    this.usesProductWeight = false,
  });

  final int materialRow;
  final double quantity;
  final bool usesProductWeight;
}

final class SheetFormulaParser {
  const SheetFormulaParser();

  FormulaMaterialTerm? parsePrimary(String? formula, int productRow) {
    if (formula == null) return null;
    final compact = _unwrapSum(_compact(formula));
    final patterns = [
      RegExp('^\\(?F$productRow\\*B(\\d+)\\)?/C\\1\$', caseSensitive: false),
      RegExp('^\\(?B(\\d+)\\*F$productRow\\)?/C\\1\$', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(compact);
      if (match != null) {
        return FormulaMaterialTerm(
          materialRow: int.parse(match.group(1)!),
          quantity: 1,
          usesProductWeight: true,
        );
      }
    }
    return null;
  }

  List<FormulaMaterialTerm>? parseComplementary(String? formula) {
    if (formula == null) return null;
    final compact = _compact(formula);
    if (compact.isEmpty || compact == '0') return const [];

    final divided = RegExp(
      r'\(?([0-9]+(?:[.,][0-9]+)?)\*B(\d+)\)?/C\2',
      caseSensitive: false,
    ).allMatches(compact).toList();
    final dividedReverse = RegExp(
      r'\(?B(\d+)\*([0-9]+(?:[.,][0-9]+)?)\)?/C\1',
      caseSensitive: false,
    ).allMatches(compact).toList();
    if (divided.isNotEmpty || dividedReverse.isNotEmpty) {
      final covered = <FormulaMaterialTerm>[
        for (final match in divided)
          FormulaMaterialTerm(
            materialRow: int.parse(match.group(2)!),
            quantity: _number(match.group(1)!),
          ),
        for (final match in dividedReverse)
          FormulaMaterialTerm(
            materialRow: int.parse(match.group(1)!),
            quantity: _number(match.group(2)!),
          ),
      ];
      return covered;
    }

    final multiplied = RegExp(
      r'B(\d+)\*([0-9]+(?:[.,][0-9]+)?)',
      caseSensitive: false,
    ).allMatches(compact).toList();
    final multipliedReverse = RegExp(
      r'([0-9]+(?:[.,][0-9]+)?)\*B(\d+)',
      caseSensitive: false,
    ).allMatches(compact).toList();
    if (multiplied.isNotEmpty || multipliedReverse.isNotEmpty) {
      return [
        for (final match in multiplied)
          FormulaMaterialTerm(
            materialRow: int.parse(match.group(1)!),
            quantity: _number(match.group(2)!),
          ),
        for (final match in multipliedReverse)
          FormulaMaterialTerm(
            materialRow: int.parse(match.group(2)!),
            quantity: _number(match.group(1)!),
          ),
      ];
    }

    final direct = RegExp(
      r'^\(*B(\d+)\)*$',
      caseSensitive: false,
    ).firstMatch(compact);
    if (direct != null) {
      return [
        FormulaMaterialTerm(
          materialRow: int.parse(direct.group(1)!),
          quantity: 1,
        ),
      ];
    }
    return null;
  }

  String _compact(String formula) => formula
      .trim()
      .replaceFirst(RegExp(r'^='), '')
      .replaceAll(r'$', '')
      .replaceAll(RegExp(r'\s+'), '');

  String _unwrapSum(String formula) {
    final match = RegExp(
      r'^SUM\((.*)\)$',
      caseSensitive: false,
    ).firstMatch(formula);
    return match?.group(1) ?? formula;
  }

  double _number(String value) => double.parse(value.replaceAll(',', '.'));
}
