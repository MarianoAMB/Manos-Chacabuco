import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

abstract interface class DesktopTokenStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

/// Protege el refresh token con DPAPI, ligado al usuario actual de Windows.
final class WindowsProtectedTokenStore implements DesktopTokenStore {
  WindowsProtectedTokenStore({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? getApplicationSupportDirectory;

  static const _uiForbidden = 0x1;
  final Future<Directory> Function() _rootDirectory;

  @override
  Future<String?> read() async {
    _ensureWindows();
    final file = await _file();
    if (!await file.exists()) return null;
    final encrypted = await file.readAsBytes();
    if (encrypted.isEmpty) return null;
    return utf8.decode(_unprotect(encrypted));
  }

  @override
  Future<void> write(String value) async {
    _ensureWindows();
    final file = await _file();
    await file.parent.create(recursive: true);
    final encrypted = _protect(Uint8List.fromList(utf8.encode(value)));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(encrypted, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete() async {
    _ensureWindows();
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async {
    final root = await _rootDirectory();
    return File(paths.join(root.path, 'sync', 'google_oauth.dpapi'));
  }

  Uint8List _protect(Uint8List bytes) => _transform(
    bytes,
    (input, output) =>
        CryptProtectData(input, null, null, null, _uiForbidden, output),
    action: 'proteger',
  );

  Uint8List _unprotect(Uint8List bytes) => _transform(
    bytes,
    (input, output) =>
        CryptUnprotectData(input, null, null, null, _uiForbidden, output),
    action: 'recuperar',
  );

  Uint8List _transform(
    Uint8List bytes,
    Win32Result<bool> Function(
      Pointer<CRYPT_INTEGER_BLOB> input,
      Pointer<CRYPT_INTEGER_BLOB> output,
    )
    transform, {
    required String action,
  }) {
    final inputBytes = calloc<Uint8>(bytes.length);
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    try {
      inputBytes.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..cbData = bytes.length
        ..pbData = inputBytes;
      final result = transform(input, output);
      if (!result.value) {
        throw StateError(
          'Windows no pudo $action la sesión de Google (${result.error}).',
        );
      }
      return Uint8List.fromList(
        output.ref.pbData.asTypedList(output.ref.cbData),
      );
    } finally {
      inputBytes.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(inputBytes);
      calloc.free(input);
      if (output.ref.pbData != nullptr) {
        output.ref.pbData
            .asTypedList(output.ref.cbData)
            .fillRange(0, output.ref.cbData, 0);
        HLOCAL(output.ref.pbData).close();
      }
      calloc.free(output);
    }
  }

  void _ensureWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('El almacén DPAPI sólo existe en Windows.');
    }
  }
}
