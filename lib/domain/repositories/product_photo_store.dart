abstract interface class ProductPhotoStore {
  Future<String> importFile(String sourcePath);
  Future<String?> duplicate(String? reference);
  Future<void> delete(String reference);
  String absolutePath(String reference);
}
