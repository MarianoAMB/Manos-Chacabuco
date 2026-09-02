import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../domain/importing/import_models.dart';
import '../../../domain/products/product_models.dart';
import '../application/historical_import_controller.dart';

Future<bool> showHistoricalImportScreen({
  required BuildContext context,
  required HistoricalImportController controller,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => HistoricalImportScreen(controller: controller),
      ),
    ) ??
    false;

final class HistoricalImportScreen extends StatefulWidget {
  const HistoricalImportScreen({required this.controller, super.key});

  final HistoricalImportController controller;

  @override
  State<HistoricalImportScreen> createState() => _HistoricalImportScreenState();
}

final class _HistoricalImportScreenState extends State<HistoricalImportScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Importar planilla histórica')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600
                ? AppSpacing.md
                : AppSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _intro(),
                  if (widget.controller.isAnalyzing) ...[
                    const SizedBox(height: AppSpacing.md),
                    const LinearProgressIndicator(),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Leyendo valores, fórmulas y secciones…'),
                  ],
                  if (widget.controller.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      color: AppColors.terracottaSoft,
                      child: Text(widget.controller.errorMessage!),
                    ),
                  ],
                  if (widget.controller.preview case final preview?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _summary(preview),
                    const SizedBox(height: AppSpacing.md),
                    _review(preview),
                    const SizedBox(height: AppSpacing.md),
                    _references(preview),
                    const SizedBox(height: AppSpacing.md),
                    _comparison(preview),
                    const SizedBox(height: AppSpacing.lg),
                    _importAction(preview),
                  ],
                  if (widget.controller.latestReport case final report?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _lastReport(report),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _intro() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Precio Manos Chacabuco',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Esta es una importación inicial, no una sincronización. Primero se analiza el archivo y no se guarda nada hasta que confirmes.',
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('choose-import-xlsx'),
            onPressed:
                widget.controller.isAnalyzing || widget.controller.isImporting
                ? null
                : _chooseFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Elegir archivo XLSX'),
          ),
        ),
        if (widget.controller.selectedFilePath != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.controller.selectedFilePath!.split(RegExp(r'[/\\]')).last,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ],
    ),
  );

  Widget _summary(ImportPreview preview) => AppCard(
    color: AppColors.sageSoft,
    borderColor: AppColors.sage,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Resumen del análisis',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _metric('Materias primas', preview.materials.length),
            _metric('Productos', preview.products.length),
            _metric('Relaciones principales', preview.primaryRelationshipCount),
            _metric(
              'Avíos recuperados',
              preview.complementaryRelationshipCount,
            ),
            _metric('Con peso', preview.productsWithWeight),
            _metric('Con multiplicador', preview.productsWithMultiplier),
            _metric('Con medidas', preview.productsWithMeasures),
            _metric('Geometrías seguras', preview.safeGeometryCount),
            _metric('Listos para calcular', preview.calibrationReadyCount),
            _metric('Requieren revisión', preview.reviewCount),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${preview.omittedRows} filas vacías, separadores o errores fueron omitidas.',
        ),
      ],
    ),
  );

  Widget _metric(String label, int value) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ],
    ),
  );

  Widget _review(ImportPreview preview) {
    final grouped = <ImportIssueKind, List<ImportIssue>>{};
    for (final issue in preview.issues) {
      grouped.putIfAbsent(issue.kind, () => []).add(issue);
    }
    final conflicts = preview.products.where(
      (item) =>
          item.decision == ImportDecision.review &&
          item.existingTargetId != null,
    );
    final materialConflicts = preview.materials.where(
      (item) =>
          item.decision == ImportDecision.review &&
          item.existingTargetId != null,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Revisar pendientes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Los casos dudosos quedan separados; no se inventan ni bloquean los datos seguros.',
          ),
          for (final entry in grouped.entries)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${entry.key.label} · ${entry.value.length}'),
              children: [
                for (final issue in entry.value.take(12))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(issue.source.originalName),
                    subtitle: Text(issue.message),
                  ),
                if (entry.value.length > 12)
                  Text('Y ${entry.value.length - 12} casos más.'),
              ],
            ),
          for (final conflict in conflicts)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conflict.source.originalName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text('Ya existe un registro con ese nombre.'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolveProductConflict(
                              conflict.source.stableKey,
                              ImportDecision.useExisting,
                            ),
                        child: const Text('Usar existente'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolveProductConflict(
                              conflict.source.stableKey,
                              ImportDecision.create,
                            ),
                        child: const Text('Importar como nuevo'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolveProductConflict(
                              conflict.source.stableKey,
                              ImportDecision.skip,
                            ),
                        child: const Text('Omitir'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          for (final conflict in materialConflicts)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conflict.source.originalName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Ya existe una materia prima con ese nombre y otra unidad o categoría.',
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolveMaterialConflict(
                              conflict.source.stableKey,
                              ImportDecision.useExisting,
                            ),
                        child: const Text('Usar existente'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolveMaterialConflict(
                              conflict.source.stableKey,
                              ImportDecision.create,
                            ),
                        child: const Text('Importar como nueva'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolveMaterialConflict(
                              conflict.source.stableKey,
                              ImportDecision.skip,
                            ),
                        child: const Text('Omitir'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _references(ImportPreview preview) {
    final materialNames = {
      for (final item in preview.materials) item.targetId: item.material.name,
    };
    final grouped = <String, List<ProductImportCandidate>>{};
    for (final item in preview.products.where(
      (item) => item.calibrationReady,
    )) {
      final primary = item.usages
          .where((usage) => usage.role == ProductMaterialRole.primary)
          .firstOrNull;
      if (primary != null) {
        grouped.putIfAbsent(primary.materialId, () => []).add(item);
      }
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Referencias para estimación',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (grouped.isEmpty)
            const Text('Todavía no hay referencias geométricas completas.'),
          for (final entry in grouped.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '${materialNames[entry.key] ?? 'Materia prima'} · ${entry.value.length} referencias utilizables · ${_geometrySummary(entry.value)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          const Divider(),
          for (final item
              in preview.products
                  .where((item) => item.historicalWeight != null)
                  .take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item.calibrationReady
                    ? Icons.check_circle_rounded
                    : Icons.edit_note_rounded,
                color: item.calibrationReady
                    ? AppColors.success
                    : AppColors.terracotta,
              ),
              title: Text(item.source.originalName),
              subtitle: Text(
                '${_weightLabel(item.historicalWeight!)} g${item.calibrationReady ? ' · Lista' : ' · Revisar forma o distribución'}',
              ),
            ),
          if (preview.productsWithWeight > 10)
            Text(
              'Y ${preview.productsWithWeight - 10} referencias con consumo histórico.',
            ),
        ],
      ),
    );
  }

  String _geometrySummary(List<ProductImportCandidate> products) {
    final counts = <String, int>{};
    for (final item in products) {
      final shape = switch (item.product?.geometryProfile?.shapeCode) {
        'cylinder' => 'cilindros',
        'circle' => 'planos circulares',
        'oval' => 'ovales',
        _ => 'otras formas',
      };
      counts[shape] = (counts[shape] ?? 0) + 1;
    }
    return counts.entries
        .map((entry) => '${entry.value} ${entry.key}')
        .join(', ');
  }

  Widget _comparison(ImportPreview preview) {
    final comparable = preview.products
        .where(
          (item) =>
              item.priceComparison.sheetCost != null &&
              item.priceComparison.appCost != null,
        )
        .toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Comparación con la planilla',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Se usa para revisar diferencias; las reglas actuales de la app no se cambian para copiar porcentajes viejos.',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in comparable.take(6))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.source.originalName),
              subtitle: Text(
                'Planilla ${ArgentineNumberFormatter.money(item.priceComparison.sheetCost!)} · App ${ArgentineNumberFormatter.money(item.priceComparison.appCost!)}',
              ),
            ),
          if (comparable.isEmpty)
            const Text('Todavía no hay filas comparables completas.'),
        ],
      ),
    );
  }

  Widget _importAction(ImportPreview preview) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirmar importación',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'Se crearán ${preview.newMaterialCount} materias primas y ${preview.newProductCount} productos. Antes se hará un backup automático.',
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('confirm-safe-import'),
          onPressed: widget.controller.isImporting ? null : _confirmImport,
          icon: widget.controller.isImporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_done_rounded),
          label: Text(
            widget.controller.isImporting
                ? 'Importando…'
                : 'Importar datos seguros',
          ),
        ),
      ],
    ),
  );

  Widget _lastReport(ImportReport report) => AppCard(
    color: AppColors.sageSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Última importación terminada',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('Materias primas: ${report.importedMaterials}'),
        Text('Productos: ${report.importedProducts}'),
        Text('Listos para calcular: ${report.calibrationReady}'),
        Text('Requieren revisión: ${report.requiresReview}'),
        Text('Advertencias registradas: ${report.warnings}'),
        const SizedBox(height: AppSpacing.sm),
        const Text('Backup creado en:'),
        SelectableText(report.backupPath),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Ir a Productos'),
        ),
      ],
    ),
  );

  Future<void> _chooseFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Planilla Excel', extensions: ['xlsx']),
      ],
    );
    if (file != null) await widget.controller.analyzeFile(file.path);
  }

  Future<void> _confirmImport() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Importar los datos seguros?'),
        content: const Text(
          'La app hará un backup automático y guardará todo en una sola operación. Los casos dudosos seguirán marcados para revisión.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('accept-safe-import'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.controller.importSafeData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importación terminada correctamente.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se importó nada. La base quedó sin cambios parciales.',
          ),
        ),
      );
    }
  }

  String _weightLabel(double value) => value
      .toStringAsFixed(value == value.roundToDouble() ? 0 : 2)
      .replaceAll('.', ',');
}
