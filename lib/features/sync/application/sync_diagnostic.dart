import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' show DetailedApiRequestError;
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../../core/sync/sync_contracts.dart';

/// Datos suficientes para investigar un fallo sin copiar tokens ni datos del cliente.
abstract final class SyncDiagnostic {
  static String describe(String stage, Object error) {
    final details = switch (error) {
      SyncFileFormatException(:final fileName, :final cause) => _fileFormat(
        fileName,
        cause,
      ),
      DetailedApiRequestError(:final status, :final errors) => _driveResponse(
        status,
        errors.map((detail) => detail.reason),
      ),
      DatabaseException() => _databaseResponse(error),
      SocketException() => 'RED: No se pudo establecer la conexión con Google.',
      HandshakeException() =>
        'CONEXIÓN_SEGURA: Falló la conexión segura con Google.',
      TimeoutException() => 'TIEMPO_AGOTADO: Google no respondió a tiempo.',
      FileSystemException() =>
        'ARCHIVO_LOCAL: Windows no pudo leer o guardar un archivo local.',
      FormatException() || TypeError() =>
        'FORMATO_DATOS: Un dato recibido no tiene el formato esperado.',
      StateError()
          when error.toString().contains(
            'La foto o el logo recibido está incompleto.',
          ) =>
        'FOTO_INCOMPLETA: Una foto o un logo no está completo en Drive.',
      StateError()
          when error.toString().contains(
            'No se encontró un archivo local para sincronizar.',
          ) =>
        'ARCHIVO_LOCAL_FALTANTE: Falta una foto o un logo en esta PC.',
      _ => 'ERROR_NO_CLASIFICADO: ${error.runtimeType}.',
    };
    return 'Paso: $stage\n$details';
  }

  static String _fileFormat(String fileName, Object cause) {
    final safeName =
        RegExp(r'^mc-change-[A-Za-z0-9_-]{1,100}\.json$').hasMatch(fileName)
        ? ' ($fileName)'
        : '';
    final reason = cause is UnsupportedError
        ? 'Su versión o contenido no es compatible.'
        : 'Su contenido no tiene el formato esperado.';
    return 'JSON_INVALIDO: No se pudo leer un archivo de cambios de Drive'
        '$safeName. $reason';
  }

  static String _driveResponse(int? status, Iterable<String?> reasons) {
    String? safeReason;
    for (final reason in reasons) {
      if (reason != null &&
          RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,79}$').hasMatch(reason)) {
        safeReason = reason;
        break;
      }
    }
    return 'GOOGLE_DRIVE: Respuesta HTTP ${status ?? 'desconocida'}'
        '${safeReason == null ? '' : ' ($safeReason)'}. No se incluyeron datos de la cuenta.';
  }

  static String _databaseResponse(DatabaseException error) {
    final code = error.getResultCode();
    final category = switch (code) {
      2067 || 1555 => 'DUPLICADO',
      787 => 'REFERENCIA_FALTANTE',
      1299 => 'CAMPO_OBLIGATORIO',
      5 || 6 => 'BASE_BLOQUEADA',
      8 => 'SOLO_LECTURA',
      13 => 'DISCO_LLENO',
      _ when error.isUniqueConstraintError() => 'DUPLICADO',
      _ when error.isNotNullConstraintError() => 'CAMPO_OBLIGATORIO',
      _ when error.isNoSuchTableError() => 'ESQUEMA',
      _ => 'OTRO',
    };
    final match = RegExp(
      r'(?:UNIQUE|NOT NULL) constraint failed:\s*'
      r'([a-z_]+\.[a-z_]+(?:,\s*[a-z_]+\.[a-z_]+)*)',
      caseSensitive: false,
    ).firstMatch(error.toString());
    final field = match?.group(1);
    return 'BASE_LOCAL_$category: Código SQLite ${code ?? 'desconocido'}'
        '${field == null ? '' : '. Campo: $field'}. No se incluyeron valores ni datos personales.';
  }
}
