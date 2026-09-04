import 'package:printing/printing.dart';

import '../../domain/price_lists/price_list_models.dart';

final class NativePrintService {
  const NativePrintService();

  Future<void> printPdf(GeneratedPriceListFile file) async {
    await Printing.layoutPdf(
      name: file.name,
      onLayout: (_) async => file.bytes,
    );
  }
}
