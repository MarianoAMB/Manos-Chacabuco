import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_empty_state.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/formatting/argentine_number_parser.dart';
import '../../../core/money/decimal_value.dart';
import '../../../core/money/money.dart';
import '../../../domain/common/sync_metadata.dart';
import '../../../domain/geometry/geometry_models.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/pricing/pricing_models.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/services/material_estimation_engine.dart';
import '../../../domain/services/geometry_engine.dart';
import '../../products/application/product_form_value.dart';
import '../../products/application/products_controller.dart';
import '../../products/presentation/product_editor_dialog.dart';

enum CalculatorMode { product, newPiece }

final class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({required this.controller, super.key});

  final ProductsController controller;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

final class _CalculatorScreenState extends State<CalculatorScreen> {
  CalculatorMode _mode = CalculatorMode.product;
  ProductBundle? _reference;
  GeometryShape _shape = GeometryShape.cylinder;
  Set<GeometryComponent> _components = {
    GeometryComponent.base,
    GeometryComponent.lateral,
  };
  GeometryLidType _lidType = GeometryLidType.none;
  String? _materialId;
  String? _variantId;
  final Map<String, TextEditingController> _measureControllers = {};
  final TextEditingController _multiplier = TextEditingController();
  final TextEditingController _manualConsumption = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final List<ProductUsageFormValue> _extras = [];
  ProductMaterialEstimation? _result;
  String? _message;

  @override
  void initState() {
    super.initState();
    _multiplier.text =
        widget.controller.settingsController.settings.defaultProductMultiplier
            ?.toDecimalString(fractionDigits: 2) ??
        '';
    _syncMeasureControllers(_newProfile);
  }

  @override
  void dispose() {
    for (final controller in _measureControllers.values) {
      controller.dispose();
    }
    _multiplier.dispose();
    _manualConsumption.dispose();
    _name.dispose();
    super.dispose();
  }

  GeometryProfile get _newProfile => GeometryProfile(
    shapeCode: _shape.code,
    components: _components,
    dimensionBindings: {
      for (final parameter in GeometryParameters.requiredFor(
        GeometryProfile(
          shapeCode: _shape.code,
          components: _components,
          dimensionBindings: const {},
          lidType: _lidType,
        ),
      ))
        parameter: GeometryParameters.label(parameter),
    },
    lidType: _components.contains(GeometryComponent.lid)
        ? _lidType
        : GeometryLidType.none,
  );

  List<ProductBundle> get _eligibleProducts => widget.controller.products
      .where(
        (bundle) =>
            bundle.product.isActive &&
            bundle.product.geometryProfile != null &&
            bundle.product.dimensions != null &&
            bundle.usages.any(
              (usage) => usage.role == ProductMaterialRole.primary,
            ),
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calculadora',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                'Estimá material, costo y precio con geometría y productos reales.',
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                constraints.maxWidth < 700 ? AppSpacing.md : AppSpacing.xl,
                0,
                constraints.maxWidth < 700 ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _modeSelector(),
                      const SizedBox(height: AppSpacing.lg),
                      if (_mode == CalculatorMode.product)
                        _productMode()
                      else
                        _newPieceMode(),
                      if (_message != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          color: AppColors.terracottaSoft,
                          child: Text(_message!),
                        ),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _resultCard(_result!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _modeSelector() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '¿Qué querés calcular?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _mobileModeButton(
                    CalculatorMode.product,
                    'Basado en un producto',
                    Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _mobileModeButton(
                    CalculatorMode.newPiece,
                    'Pieza nueva',
                    Icons.add_box_outlined,
                  ),
                ],
              );
            }
            return SegmentedButton<CalculatorMode>(
              key: const Key('calculator-mode'),
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: CalculatorMode.product,
                  label: Text('Basado en un producto'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: CalculatorMode.newPiece,
                  label: Text('Pieza nueva'),
                  icon: Icon(Icons.add_box_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) => _changeMode(value.first),
            );
          },
        ),
      ],
    ),
  );

  Widget _mobileModeButton(CalculatorMode value, String label, IconData icon) =>
      _mode == value
      ? FilledButton.tonalIcon(
          key: Key('calculator-mode-${value.name}'),
          onPressed: () => _changeMode(value),
          icon: Icon(icon),
          label: Text(label),
        )
      : OutlinedButton.icon(
          key: Key('calculator-mode-${value.name}'),
          onPressed: () => _changeMode(value),
          icon: Icon(icon),
          label: Text(label),
        );

  void _changeMode(CalculatorMode value) => setState(() {
    _mode = value;
    _result = null;
    _message = null;
  });

  Widget _productMode() {
    if (_eligibleProducts.isEmpty) {
      return const AppEmptyState(
        icon: Icons.straighten_outlined,
        title: 'Todavía no hay productos de referencia',
        message: 'Configurá la forma y confirmá el consumo de un producto para poder estimar otro tamaño.',
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Producto de referencia',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('calculator-reference-product'),
            initialValue: _reference?.product.metadata.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Producto conocido'),
            items: [
              for (final bundle in _eligibleProducts)
                DropdownMenuItem(
                  value: bundle.product.metadata.id,
                  child: Text(bundle.product.name),
                ),
            ],
            onChanged: (id) {
              final selected = _eligibleProducts
                  .where((item) => item.product.metadata.id == id)
                  .firstOrNull;
              if (selected == null) return;
              _selectReference(selected);
            },
          ),
          if (_reference != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Nuevas medidas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Ingresalas en centímetros.'),
            const SizedBox(height: AppSpacing.sm),
            _measureFields(_reference!.product.geometryProfile!),
            const SizedBox(height: AppSpacing.md),
            _multiplierField(),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const Key('calculate-from-product'),
              onPressed: _calculateFromProduct,
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('Calcular estimación'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _newPieceMode() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pieza nueva', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<GeometryShape>(
          key: const Key('calculator-shape'),
          initialValue: _shape,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Forma'),
          items: [
            for (final shape in GeometryShape.values)
              DropdownMenuItem(value: shape, child: Text(shape.label)),
          ],
          onChanged: (shape) {
            if (shape == null) return;
            setState(() {
              _shape = shape;
              _components = switch (shape) {
                GeometryShape.circle => {GeometryComponent.base},
                GeometryShape.other => <GeometryComponent>{},
                _ => {GeometryComponent.base, GeometryComponent.lateral},
              };
              _lidType = GeometryLidType.none;
              _syncMeasureControllers(_newProfile);
              _clearResult();
            });
          },
        ),
        if (_shape == GeometryShape.other) ...[
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Esta forma no tiene una fórmula automática. Podés ingresar el consumo manualmente.',
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.md),
          Text('Superficies', style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final component in GeometryComponent.values)
                FilterChip(
                  key: Key('calculator-component-${component.name}'),
                  label: Text(component.label),
                  selected: _components.contains(component),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _components.add(component)
                        : _components.remove(component);
                    if (component == GeometryComponent.lid) {
                      _lidType = selected
                          ? GeometryLidType.flat
                          : GeometryLidType.none;
                    }
                    _syncMeasureControllers(_newProfile);
                    _clearResult();
                  }),
                ),
            ],
          ),
          if (_components.contains(GeometryComponent.lid)) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<GeometryLidType>(
              key: const Key('calculator-lid-type'),
              initialValue: _lidType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de tapa'),
              items: [
                for (final type in GeometryLidType.values.where(
                  (value) => value != GeometryLidType.none,
                ))
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() {
                _lidType = value ?? GeometryLidType.flat;
                _syncMeasureControllers(_newProfile);
                _clearResult();
              }),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _measureFields(_newProfile),
        ],
        const SizedBox(height: AppSpacing.md),
        _materialFields(),
        const SizedBox(height: AppSpacing.md),
        _complementaryFields(),
        const SizedBox(height: AppSpacing.md),
        _multiplierField(),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('calculator-manual-consumption'),
          controller: _manualConsumption,
          decoration: const InputDecoration(
            labelText: 'Consumo manual (opcional)',
            helperText: 'Usalo si todavía no hay referencias.',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('calculate-new-piece'),
          onPressed: _calculateNewPiece,
          icon: const Icon(Icons.calculate_rounded),
          label: const Text('Calcular estimación'),
        ),
      ],
    ),
  );

  Widget _measureFields(GeometryProfile profile) => LayoutBuilder(
    builder: (context, constraints) {
      final fields = [
        for (final parameter in GeometryParameters.requiredFor(profile))
          TextField(
            key: Key('calculator-measure-$parameter'),
            controller: _measureControllers[parameter],
            decoration: InputDecoration(
              labelText: GeometryParameters.label(parameter),
              suffixText: 'cm',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _clearResult(),
          ),
      ];
      if (constraints.maxWidth < 620) {
        return Column(
          children: [
            for (var index = 0; index < fields.length; index++) ...[
              fields[index],
              if (index < fields.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      }
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final field in fields) SizedBox(width: 250, child: field),
        ],
      );
    },
  );

  Widget _materialFields() {
    final materials = widget.controller.materialsController.materials
        .where((bundle) => bundle.material.isActive)
        .toList(growable: false);
    final selected = materials
        .where((bundle) => bundle.material.metadata.id == _materialId)
        .firstOrNull;
    final variants =
        selected?.variants
            .where((variant) => variant.isActive)
            .toList(growable: false) ??
        const <MaterialVariant>[];
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: const Key('calculator-material'),
          initialValue: _materialId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Materia prima principal',
          ),
          items: [
            for (final bundle in materials)
              DropdownMenuItem(
                value: bundle.material.metadata.id,
                child: Text(bundle.material.name),
              ),
          ],
          onChanged: (value) => setState(() {
            _materialId = value;
            _variantId = null;
            _clearResult();
          }),
        ),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            key: const Key('calculator-variant'),
            initialValue: _variantId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Color / variante para el costo',
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Precio base del material'),
              ),
              for (final variant in variants)
                DropdownMenuItem(
                  value: variant.metadata.id,
                  child: Text(variant.name),
                ),
            ],
            onChanged: (value) => setState(() {
              _variantId = value;
              _clearResult();
            }),
          ),
        ],
      ],
    );
  }

  Widget _multiplierField() => TextField(
    key: const Key('calculator-multiplier'),
    controller: _multiplier,
    decoration: const InputDecoration(labelText: 'Multiplicador mayorista'),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => _clearResult(),
  );

  Widget _complementaryFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Avíos opcionales',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            key: const Key('calculator-add-extra'),
            onPressed: _addExtra,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar'),
          ),
        ],
      ),
      const Text(
        'Hebillas, cierres, mosquetones u otros complementos se suman sin hilo ni desperdicio.',
      ),
      for (var index = 0; index < _extras.length; index++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.extension_rounded),
          title: Text(_usageName(_extras[index])),
          subtitle: Text(_usageAmount(_extras[index])),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: 'Editar avío',
                onPressed: () => _editExtra(index),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Quitar avío',
                onPressed: () => setState(() {
                  _extras.removeAt(index);
                  _clearResult();
                }),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _resultCard(ProductMaterialEstimation result) {
    final estimates = result.estimates;
    final referenceCount = estimates.expand((item) => item.references).length;
    final waste = result.calculation.rules.wastePercentage;
    return AppCard(
      color: AppColors.sageSoft,
      borderColor: AppColors.sage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Resultado', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Material estimado',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final usage in result.usages.where(
            (value) => value.role == ProductMaterialRole.primary,
          ))
            _resultUsage(usage, waste),
          if (result.usages.any(
            (value) => value.role == ProductMaterialRole.complementary,
          )) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Avíos', style: Theme.of(context).textTheme.titleMedium),
            for (final usage in result.usages.where(
              (value) => value.role == ProductMaterialRole.complementary,
            ))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text('${_usageName(usage)} · ${_usageAmount(usage)}'),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            _mode == CalculatorMode.product
                ? 'Basado en 1 producto similar'
                : referenceCount == 0
                ? 'Consumo ingresado manualmente'
                : 'Basado en $referenceCount ${referenceCount == 1 ? 'producto similar' : 'productos similares'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (estimates.isNotEmpty) Text(estimates.first.confidence.label),
          if (estimates.isNotEmpty &&
              estimates.first.minimumBaseUnits != null &&
              estimates.first.maximumBaseUnits != null)
            Text(_rangeText(estimates.first)),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _price('Costo estimado', result.calculation.cost.totalCost),
              _price(
                'Mayorista sugerido',
                result.calculation.pricing.wholesalePrice,
              ),
              if (result.calculation.pricing.retailPrice != null)
                _price(
                  'Minorista sugerido',
                  result.calculation.pricing.retailPrice!,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Esta es una estimación basada en productos similares. El consumo real puede variar. Revisalo antes de confirmar.',
          ),
          if (_mode == CalculatorMode.product || referenceCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('calculator-show-references'),
                onPressed: () => _showReferences(result),
                icon: const Icon(Icons.history_rounded),
                label: const Text('Ver referencias utilizadas'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('calculator-create-product'),
              onPressed: _createProduct,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Crear producto con esta estimación'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultUsage(ProductMaterialUsage usage, DecimalValue waste) {
    final material = widget.controller.materialsController.materials
        .where((item) => item.material.metadata.id == usage.materialId)
        .firstOrNull;
    final variant = material?.variants
        .where((item) => item.metadata.id == usage.materialVariantId)
        .firstOrNull;
    final unit = widget.controller.materialsController.unitById(
      usage.consumption.unitId,
    );
    final withWaste = DecimalValue.scaled(
      usage.consumption.amount.scaledValue +
          (usage.consumption.amount.scaledValue *
                  waste.scaledValue /
                  DecimalValue.scale)
              .round(),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${material?.material.name ?? 'Material'}${variant == null ? '' : ' · ${variant.name}'} · ≈ ${ArgentineNumberFormatter.decimal(usage.consumption.amount, fractionDigits: 0)} ${unit?.symbol ?? ''}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            'Con desperdicio: ≈ ${ArgentineNumberFormatter.decimal(withWaste, fractionDigits: 0)} ${unit?.symbol ?? ''}',
          ),
        ],
      ),
    );
  }

  Widget _price(String label, Money value) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          ArgentineNumberFormatter.money(value),
          style: const TextStyle(
            color: AppColors.success,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  String _rangeText(MaterialEstimate estimate) {
    final material = widget.controller.materialsController.materials
        .where((item) => item.material.metadata.id == estimate.materialId)
        .firstOrNull;
    if (material == null) return '';
    final unitId = material.material.consumptionUnitId;
    final unit = widget.controller.materialsController.unitById(unitId);
    final minimum = widget.controller.amountFromBaseUnits(
      estimate.minimumBaseUnits!,
      unitId,
    );
    final maximum = widget.controller.amountFromBaseUnits(
      estimate.maximumBaseUnits!,
      unitId,
    );
    return 'Rango observado: ${ArgentineNumberFormatter.decimal(minimum, fractionDigits: 0)}–${ArgentineNumberFormatter.decimal(maximum, fractionDigits: 0)} ${unit?.symbol ?? ''}';
  }

  Future<void> _showReferences(ProductMaterialEstimation result) {
    final predictions = result.estimates.expand(
      (estimate) => estimate.references,
    );
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Referencias utilizadas'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _mode == CalculatorMode.product
                ? [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(_reference!.product.name),
                      subtitle: const Text('Producto base seleccionado'),
                    ),
                  ]
                : [
                    for (final prediction in predictions)
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

  void _selectReference(ProductBundle value) {
    final profile = value.product.geometryProfile!;
    _reference = value;
    _name.text = '${value.product.name} nueva medida';
    _multiplier.text = value.product.priceMultiplier.toDecimalString(
      fractionDigits: 2,
    );
    _syncMeasureControllers(profile);
    for (final parameter in GeometryParameters.requiredFor(profile)) {
      final name = profile.dimensionBindings[parameter];
      final quantity = name == null
          ? null
          : value.product.dimensions?.values[name];
      if (quantity != null) {
        _measureControllers[parameter]!.text = widget.controller
            .lengthInCentimeters(quantity)
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'\.0+$'), '');
      }
    }
    setState(_clearResult);
  }

  void _calculateFromProduct() {
    final reference = _reference;
    if (reference == null) return;
    try {
      final target = _targetProduct(reference.product.geometryProfile!);
      setState(() {
        _result = widget.controller.estimateFromProduct(
          reference: reference,
          targetProduct: target,
        );
        _message = null;
      });
    } catch (error) {
      setState(() => _message = _friendlyError(error));
    }
  }

  void _calculateNewPiece() {
    if (_materialId == null) {
      setState(() => _message = 'Elegí una materia prima principal.');
      return;
    }
    try {
      final target = _targetProduct(_newProfile);
      var estimation = _shape == GeometryShape.other
          ? null
          : widget.controller.estimateNewPiece(
              targetProduct: target,
              materialId: _materialId!,
              materialVariantId: _variantId,
            );
      if (estimation == null) {
        final manual = ArgentineNumberParser.tryParseDecimal(
          _manualConsumption.text,
        );
        if (manual == null || manual.scaledValue <= 0) {
          setState(() {
            _result = null;
            _message = 'No tenemos suficientes referencias para estimar este material todavía. Ingresá el consumo manualmente para continuar.';
          });
          return;
        }
        final material = widget.controller.materialsController.materials
            .where((item) => item.material.metadata.id == _materialId)
            .first;
        final now = DateTime.now().toUtc();
        final usage = ProductMaterialUsage(
          metadata: SyncMetadata(
            id: 'calculator-manual',
            createdAt: now,
            updatedAt: now,
          ),
          productId: target.metadata.id,
          materialId: _materialId!,
          materialVariantId: _variantId,
          consumption: MeasuredQuantity(
            amount: manual,
            unitId: material.material.consumptionUnitId,
          ),
          consumptionSource: ConsumptionSource.manual,
        );
        estimation = ProductMaterialEstimation(
          targetGeometry: _shape == GeometryShape.other
              ? const GeometryResult(
                  shapeCode: 'other',
                  baseArea: 0,
                  lateralArea: 0,
                  lidArea: 0,
                )
              : widget.controller.calculateGeometry(
                  target.geometryProfile!,
                  target.dimensions!,
                ),
          usages: [usage],
          estimates: const [],
          calculation: widget.controller.calculate(target, [usage]),
        );
      }
      estimation = _withComplementaries(estimation, target);
      setState(() {
        _result = estimation;
        _message = null;
      });
    } catch (error) {
      setState(() => _message = _friendlyError(error));
    }
  }

  Future<void> _addExtra() async {
    final value = await showProductUsageEditor(
      context: context,
      materialsController: widget.controller.materialsController,
    );
    if (!mounted || value == null) return;
    setState(() {
      _extras.add(_asComplementary(value));
      _clearResult();
    });
  }

  Future<void> _editExtra(int index) async {
    final value = await showProductUsageEditor(
      context: context,
      materialsController: widget.controller.materialsController,
      value: _extras[index],
    );
    if (!mounted || value == null) return;
    setState(() {
      _extras[index] = _asComplementary(value);
      _clearResult();
    });
  }

  ProductUsageFormValue _asComplementary(ProductUsageFormValue value) =>
      ProductUsageFormValue(
        id: value.id,
        materialId: value.materialId,
        materialVariantId: value.materialVariantId,
        consumption: value.consumption,
        consumptionSource: value.consumptionSource,
        role: ProductMaterialRole.complementary,
        calibrationEligible: false,
        notes: value.notes,
      );

  ProductMaterialEstimation _withComplementaries(
    ProductMaterialEstimation estimation,
    Product target,
  ) {
    if (_extras.isEmpty) return estimation;
    final now = DateTime.now().toUtc();
    final usages = [...estimation.usages];
    for (var index = 0; index < _extras.length; index++) {
      final extra = _extras[index];
      usages.add(
        ProductMaterialUsage(
          metadata: SyncMetadata(
            id: extra.id ?? 'calculator-extra-$index',
            createdAt: now,
            updatedAt: now,
          ),
          productId: target.metadata.id,
          materialId: extra.materialId,
          materialVariantId: extra.materialVariantId,
          consumption: extra.consumption,
          role: ProductMaterialRole.complementary,
          consumptionSource: extra.consumptionSource,
          calibrationEligible: false,
          notes: extra.notes,
        ),
      );
    }
    return ProductMaterialEstimation(
      targetGeometry: estimation.targetGeometry,
      referenceGeometry: estimation.referenceGeometry,
      ratio: estimation.ratio,
      usages: usages,
      estimates: estimation.estimates,
      calculation: widget.controller.calculate(target, usages),
    );
  }

  String _usageName(Object value) {
    final materialId = switch (value) {
      ProductUsageFormValue item => item.materialId,
      ProductMaterialUsage item => item.materialId,
      _ => '',
    };
    final variantId = switch (value) {
      ProductUsageFormValue item => item.materialVariantId,
      ProductMaterialUsage item => item.materialVariantId,
      _ => null,
    };
    final bundle = widget.controller.materialsController.materials
        .where((item) => item.material.metadata.id == materialId)
        .firstOrNull;
    final variant = bundle?.variants
        .where((item) => item.metadata.id == variantId)
        .firstOrNull;
    return '${bundle?.material.name ?? 'Material'}${variant == null ? '' : ' · ${variant.name}'}';
  }

  String _usageAmount(Object value) {
    final quantity = switch (value) {
      ProductUsageFormValue item => item.consumption,
      ProductMaterialUsage item => item.consumption,
      _ => null,
    };
    if (quantity == null) return '';
    final unit = widget.controller.materialsController.unitById(
      quantity.unitId,
    );
    return '${ArgentineNumberFormatter.decimal(quantity.amount)} ${unit?.symbol ?? ''}';
  }

  Product _targetProduct(GeometryProfile profile) {
    final multiplier = ArgentineNumberParser.tryParseDecimal(_multiplier.text);
    if (multiplier == null || multiplier.scaledValue <= 0) {
      throw ArgumentError('Ingresá un multiplicador mayor que cero.');
    }
    final centimeter = widget.controller.materialsController.units
        .where((unit) => unit.code == 'centimeter')
        .firstOrNull;
    if (centimeter == null) {
      throw StateError('No está disponible la unidad cm.');
    }
    final values = <String, MeasuredQuantity>{};
    for (final parameter in GeometryParameters.requiredFor(profile)) {
      final amount = ArgentineNumberParser.tryParseDecimal(
        _measureControllers[parameter]?.text ?? '',
      );
      final allowsZero =
          parameter == GeometryParameters.topDiameter ||
          parameter == GeometryParameters.lidTopDiameter;
      if (amount == null ||
          amount.scaledValue < 0 ||
          (!allowsZero && amount.scaledValue == 0)) {
        throw ArgumentError(
          'Revisá ${GeometryParameters.label(parameter).toLowerCase()}.',
        );
      }
      values[profile.dimensionBindings[parameter]!] = MeasuredQuantity(
        amount: amount,
        unitId: centimeter.id,
      );
    }
    final now = DateTime.now().toUtc();
    return Product(
      metadata: SyncMetadata(
        id: 'calculator-${now.microsecondsSinceEpoch}',
        createdAt: now,
        updatedAt: now,
      ),
      name: _name.text.trim().isEmpty ? 'Nueva pieza' : _name.text.trim(),
      categoryId:
          _reference?.product.categoryId ??
          widget.controller.categories.firstOrNull?.metadata.id ??
          'custom',
      dimensions: ProductDimensions(
        shapeCode: profile.shapeCode,
        values: values,
      ),
      geometryProfile: profile,
      priceMultiplier: multiplier,
      pricingOverrides:
          _reference?.product.pricingOverrides ?? const PricingOverrides(),
    );
  }

  Future<void> _createProduct() async {
    final result = _result;
    if (result == null) return;
    try {
      final profile = _mode == CalculatorMode.product
          ? _reference!.product.geometryProfile!
          : _newProfile;
      final product = _targetProduct(profile);
      await showProductEditor(
        context: context,
        controller: widget.controller,
        initialDraft: ProductBundle(product: product, usages: result.usages),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _message = _friendlyError(error));
      }
    }
  }

  void _syncMeasureControllers(GeometryProfile profile) {
    final needed = GeometryParameters.requiredFor(profile).toSet();
    final obsolete = _measureControllers.keys
        .where((key) => !needed.contains(key))
        .toList();
    for (final key in obsolete) {
      _measureControllers.remove(key)?.dispose();
    }
    for (final key in needed) {
      _measureControllers.putIfAbsent(key, TextEditingController.new);
    }
  }

  void _clearResult() {
    _result = null;
    _message = null;
  }

  String _friendlyError(Object error) {
    if (error is ArgumentError) return '${error.message}';
    return '$error';
  }
}
