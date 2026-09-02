final class ImportNameNormalizer {
  const ImportNameNormalizer();

  String displayName(String input) {
    final clean = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return clean;
    return clean
        .split(' ')
        .map((word) {
          if (RegExp(r'^[A-Z0-9/°º.]+$').hasMatch(word) && word.length <= 5) {
            return word;
          }
          final lower = word.toLowerCase();
          return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  String matchingKey(String input) =>
      _withoutAccents(input)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  String _withoutAccents(String input) {
    const source = 'áéíóúüñÁÉÍÓÚÜÑ';
    const target = 'aeiouunAEIOUUN';
    var result = input;
    for (var index = 0; index < source.length; index++) {
      result = result.replaceAll(source[index], target[index]);
    }
    return result;
  }
}
