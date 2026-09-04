abstract interface class BusinessLogoStore {
  Future<String> importFile(String sourcePath);
  Future<void> delete(String reference);
  String absolutePath(String reference);
}
