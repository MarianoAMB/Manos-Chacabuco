import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/services/geometry_engine.dart';
import '../../../domain/services/material_estimation_engine.dart';
import '../../products/application/products_controller.dart';

Future<ProductMaterialEstimation?> showMaterialEstimationDialog({
  required BuildContext context,
  required ProductsController controller,
  required Product targetProduct,
  required List<ProductMaterialUsage> currentUsages,
  ProductBundle? reference,
}) async {
  ProductMaterialEstimation? estimation;
  Object? error;
  try {
    estimation = reference == null
        ? controller.estimateRecipeFromHistory(
            targetProduct: targetProduct,
            currentUsages: currentUsages,
          )
        : controller.estimateFromProduct(
            reference: reference,
            targetProduct: targetProduct,
          );
  } catch (value) {
    error = value;
  }
  if (!context.mounted) return null;
  return showDialog<ProductMaterialEstimation>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Estimación de material'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: error != null
              ? _ErrorMessage(error: error)
              : estimation == null
              ? const _NoReferencesMessage()
              : _EstimationSummary(
                  estimation: estimation,
                  controller: controller,
                  currentUsages: currentUsages,
                  reference: reference,
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (estimation != null)
          FilledButton(
            key: const Key('apply-material-estimation'),
            onPressed: () => Navigator.pop(context, estimation),
            child: const Text('Usar estimación'),
          ),
      ],
    ),
  );
}

final class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Text(
    error is GeometryValidationException
        ? (error as GeometryValidationException).message
        : '$error',
  );
}

final class _NoReferencesMessage extends StatelessWidget {
  const _NoReferencesMessage();

  @override
  Widget build(BuildContext context) => const AppCard(
    color: AppColors.terracottaSoft,
    child: Text(
      'No tenemos suficientes referencias para estimar este material todavía. Podés ingresar el consumo manualmente y guardarlo igual.',
    ),
  );
}

final class _EstimationSummary extends StatelessWidget {
  const _EstimationSummary({
    required this.estimation,
    required this.controller,
    required this.currentUsages,
    this.reference,
  });

  final ProductMaterialEstimation estimation;
  final ProductsController controller;
  final List<ProductMaterialUsage> currentUsages;
  final ProductBundle? reference;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppCard(
        color: AppColors.sageSoft,
        borderColor: AppColors.sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consumo estimado',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final usage in estimation.usages.where(
              (value) => value.role == ProductMaterialRole.primary,
            ))
              _UsageLine(controller: controller, usage: usage),
            const SizedBox(height: AppSpacing.sm),
            Text(
              reference == null
                  ? _referenceSummary(estimation.estimates)
                  : 'Basado en ${reference!.product.name}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (estimation.ratio != null)
              Text(
                'La nueva superficie es aproximadamente ${(estimation.ratio! * 100).round()}% de la referencia.',
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          _MoneyValue(
            label: 'Costo estimado',
            value: ArgentineNumberFormatter.money(
              estimation.calculation.cost.totalCost,
            ),
          ),
          _MoneyValue(
            label: 'Mayorista sugerido',
            value: ArgentineNumberFormatter.money(
              estimation.calculation.pricing.wholesalePrice,
            ),
          ),
          if (estimation.calculation.pricing.retailPrice != null)
            _MoneyValue(
              label: 'Minorista sugerido',
              value: ArgentineNumberFormatter.money(
                estimation.calculation.pricing.retailPrice!,
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      const Text(
        'Esta es una estimación basada en productos similares. El consumo real puede variar. Revisalo antes de confirmar.',
      ),
      if (estimation.estimates.any((item) => item.references.isNotEmpty)) ...[
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showReferences(context),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Ver referencias utilizadas'),
          ),
        ),
      ],
    ],
  );

  String _referenceSummary(List<MaterialEstimate> values) {
    final references = values.expand((item) => item.references).length;
    final confidence = values.isEmpty
        ? EstimationConfidence.limited
        : values
              .map((item) => item.confidence)
              .reduce((left, right) => left.index > right.index ? left : right);
    return '${confidence.label} · Basado en $references ${references == 1 ? 'producto similar' : 'productos similares'}';
  }

  Future<void> _showReferences(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Referencias utilizadas'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final prediction in estimation.estimates.expand(
              (item) => item.references,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(prediction.reference.productName),
                subtitle: Text(
                  prediction.reference.consumptionSource ==
                          ConsumptionSource.confirmed
                      ? 'Consumo real confirmado'
                      : 'Consumo registrado',
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

final class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.controller, required this.usage});

  final ProductsController controller;
  final ProductMaterialUsage usage;

  @override
  Widget build(BuildContext context) {
    final material = controller.materialsController.materials
        .where((item) => item.material.metadata.id == usage.materialId)
        .firstOrNull;
    final variant = material?.variants
        .where((item) => item.metadata.id == usage.materialVariantId)
        .firstOrNull;
    final unit = controller.materialsController.unitById(
      usage.consumption.unitId,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        '${material?.material.name ?? 'Material'}${variant == null ? '' : ' · ${variant.name}'}: ≈ ${ArgentineNumberFormatter.decimal(usage.consumption.amount, fractionDigits: 0)} ${unit?.symbol ?? ''}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }
}

final class _MoneyValue extends StatelessWidget {
  const _MoneyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );
}
