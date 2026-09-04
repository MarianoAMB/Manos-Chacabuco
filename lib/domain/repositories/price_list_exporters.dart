import '../price_lists/price_list_models.dart';

abstract interface class PriceListPdfExporter {
  Future<GeneratedPriceListFile> export(PriceListDocument document);
}

abstract interface class PriceListImageExporter {
  Future<List<GeneratedPriceListFile>> export(PriceListDocument document);
}

abstract interface class PriceListFileService {
  Future<List<String>> save(
    List<GeneratedPriceListFile> files, {
    required bool askLocation,
  });

  Future<void> openFile(String path);
  Future<void> openContainingFolder(String path);
}

abstract interface class ShareService {
  Future<void> share(List<GeneratedPriceListFile> files, {String? text});
}
