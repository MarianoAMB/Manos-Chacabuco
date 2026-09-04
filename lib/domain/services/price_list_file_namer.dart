import '../price_lists/price_list_models.dart';

final class PriceListFileNamer {
  const PriceListFileNamer();

  String pdf(PriceListDocument document) => '${_base(document)}.pdf';

  String image(PriceListDocument document, int page) =>
      '${_base(document)}_${page.toString().padLeft(2, '0')}.png';

  String _base(PriceListDocument document) {
    final date = _date(document.generatedAt);
    final business = _sanitize(document.businessName);
    return '${business}_Lista_${document.type.label}_$date';
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _sanitize(String value) {
    var normalized = value
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N');
    normalized = normalized.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'Lista_de_precios' : normalized;
  }
}
