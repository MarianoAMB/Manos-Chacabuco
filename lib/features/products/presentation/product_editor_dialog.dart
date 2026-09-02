import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/formatting/argentine_number_parser.dart';
import '../../../core/money/decimal_value.dart';
import '../../../domain/common/sync_metadata.dart';
import '../../../domain/geometry/geometry_models.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/pricing/pricing_models.dart';
import '../../../domain/products/product_models.dart';
import '../../materials/application/materials_controller.dart';
import '../../calculator/presentation/geometry_profile_editor_dialog.dart';
import '../../calculator/presentation/material_estimation_dialog.dart';
import '../application/product_form_value.dart';
import '../application/products_controller.dart';

Future<bool> showProductEditor({
  required BuildContext context,
  required ProductsController controller,
  ProductBundle? bundle,
  ProductBundle? initialDraft,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProductEditorDialog(
        controller: controller,
        bundle: bundle,
        initialDraft: initialDraft,
      ),
    ) ??
    false;

final class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.controller,
    this.bundle,
    this.initialDraft,
  });

  final ProductsController controller;
  final ProductBundle? bundle;
  final ProductBundle? initialDraft;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

final class _MeasureDraft {
  _MeasureDraft({required this.name, required this.quantity});

  String name;
  MeasuredQuantity quantity;
}

final class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late final TextEditingController _multiplier;
  late final TextEditingController _waste;
  late final TextEditingController _thread;
  late final TextEditingController _retail;
  late String? _categoryId;
  late bool _isActive;
  late bool _overrideWaste;
  late bool _overrideThread;
  late bool _overrideRetail;
  late List<_MeasureDraft> _measures;
  late List<ProductUsageFormValue> _usages;
  GeometryProfile? _geometryProfile;
  String? _newPhotoSourcePath;
  bool _removePhoto = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final product = widget.bundle?.product ?? widget.initialDraft?.product;
    final settings = widget.controller.settingsController.settings;
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _notes = TextEditingController(text: product?.notes ?? '');
    _multiplier = TextEditingController(
      text:
          product?.priceMultiplier.toDecimalString(fractionDigits: 2) ??
          settings.defaultProductMultiplier?.toDecimalString(
            fractionDigits: 2,
          ) ??
          '',
    );
    _waste = TextEditingController(
      text:
          product?.pricingOverrides.wastePercentage?.toPercentString(
            fractionDigits: 2,
          ) ??
          '',
    );
    _thread = TextEditingController(
      text:
          product?.pricingOverrides.threadPercentage?.toPercentString(
            fractionDigits: 2,
          ) ??
          '',
    );
    _retail = TextEditingController(
      text:
          product?.pricingOverrides.retailPercentage?.toPercentString(
            fractionDigits: 2,
          ) ??
          '',
    );
    _categoryId =
        product?.categoryId ??
        widget.controller.categories.firstOrNull?.metadata.id;
    _isActive = product?.isActive ?? true;
    _overrideWaste = product?.pricingOverrides.wastePercentage != null;
    _overrideThread = product?.pricingOverrides.threadPercentage != null;
    _overrideRetail = product?.pricingOverrides.retailPercentage != null;
    _measures = [
      for (final entry
          in product?.dimensions?.values.entries ??
              const <MapEntry<String, MeasuredQuantity>>[])
        _MeasureDraft(name: entry.key, quantity: entry.value),
    ];
    _usages = [
      for (final usage
          in widget.bundle?.usages ??
              widget.initialDraft?.usages ??
              const <ProductMaterialUsage>[])
        ProductUsageFormValue(
          id: usage.metadata.id,
          materialId: usage.materialId,
          materialVariantId: usage.materialVariantId,
          consumption: usage.consumption,
          role: usage.role,
          consumptionSource: usage.consumptionSource,
          calibrationEligible: usage.calibrationEligible,
          notes: usage.notes,
        ),
    ];
    _geometryProfile = product?.geometryProfile;
    for (final controller in [
      _name,
      _description,
      _notes,
      _multiplier,
      _waste,
      _thread,
      _retail,
    ]) {
      controller.addListener(_changed);
    }
  }

  void _changed() {
    _dirty = true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _notes.dispose();
    _multiplier.dispose();
    _waste.dispose();
    _thread.dispose();
    _retail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final content = Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _basicSection(),
            const SizedBox(height: AppSpacing.lg),
            _photoSection(),
            const SizedBox(height: AppSpacing.lg),
            _measureSection(),
            const SizedBox(height: AppSpacing.lg),
            _geometrySection(),
            const SizedBox(height: AppSpacing.lg),
            _materialsSection(),
            const SizedBox(height: AppSpacing.lg),
            _pricingSection(),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notas internas (opcional)',
              ),
              maxLines: 3,
            ),
            if (widget.bundle != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Producto activo'),
                subtitle: const Text(
                  'Los inactivos se conservan y pueden reactivarse.',
                ),
                value: _isActive,
                onChanged: (value) => setState(() {
                  _isActive = value;
                  _dirty = true;
                }),
              ),
            if (compact) ...[
              const SizedBox(height: AppSpacing.lg),
              _liveSummary(),
            ],
          ],
        ),
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 900),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.bundle == null
                          ? 'Nuevo producto'
                          : 'Editar producto',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _cancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: compact
                  ? content
                  : Row(
                      children: [
                        Expanded(flex: 3, child: content),
                        const VerticalDivider(),
                        SizedBox(
                          width: 360,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: _liveSummary(),
                          ),
                        ),
                      ],
                    ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: compact
                  ? Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _cancel,
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton(
                            key: const Key('save-product'),
                            onPressed: widget.controller.isSaving
                                ? null
                                : _save,
                            child: const Text('Guardar'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _cancel,
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          key: const Key('save-product'),
                          onPressed: widget.controller.isSaving ? null : _save,
                          icon: widget.controller.isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Guardar producto'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xxs),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: AppSpacing.md),
    ],
  );

  Widget _basicSection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Datos del producto',
          'Nombre, categoría y una descripción para reconocerlo.',
        ),
        TextFormField(
          key: const Key('product-name'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del producto'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Ingresá un nombre'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _categoryId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            for (final category in widget.controller.categories)
              DropdownMenuItem(
                value: category.metadata.id,
                child: Text(category.name),
              ),
          ],
          onChanged: (value) => setState(() {
            _categoryId = value;
            _dirty = true;
          }),
          validator: (value) => value == null ? 'Elegí una categoría' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _description,
          decoration: const InputDecoration(
            labelText: 'Descripción (opcional)',
          ),
          maxLines: 2,
        ),
      ],
    ),
  );

  Widget _photoSection() {
    final currentReference = widget.bundle?.product.photoPath;
    final path =
        _newPhotoSourcePath ??
        (!_removePhoto
            ? widget.controller.photoAbsolutePath(currentReference)
            : null);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'Foto',
            'Opcional. Se copia y guarda dentro de la aplicación.',
          ),
          if (path != null && File(path).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Image.file(File(path), height: 190, fit: BoxFit.cover),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: const Center(
                child: Icon(Icons.add_photo_alternate_outlined, size: 42),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _choosePhoto,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(path == null ? 'Elegir foto' : 'Cambiar foto'),
              ),
              if (path != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _newPhotoSourcePath = null;
                    _removePhoto = true;
                    _dirty = true;
                  }),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Quitar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _measureSection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Medidas',
          'Agregá las que necesites: diámetro, alto, ancho u otra.',
        ),
        if (_measures.isEmpty)
          const Text('Sin medidas cargadas. Este campo es opcional.'),
        for (var index = 0; index < _measures.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.straighten_rounded)),
            title: Text(_measures[index].name),
            subtitle: Text(_quantityLabel(_measures[index].quantity)),
            trailing: Wrap(
              children: [
                IconButton(
                  key: Key('edit-product-measure-$index'),
                  onPressed: () => _editMeasure(index),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: () => setState(() => _measures.removeAt(index)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addMeasure,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar medida'),
          ),
        ),
      ],
    ),
  );

  Widget _materialsSection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Materias primas',
          'El hilo y el desperdicio se aplican sólo sobre las líneas principales.',
        ),
        if (_usages.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.terracottaSoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Text(
              'Agregá al menos una materia prima para calcular el producto.',
            ),
          ),
        for (var index = 0; index < _usages.length; index++) _usageTile(index),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('add-product-material'),
            onPressed: _addUsage,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar materia prima'),
          ),
        ),
      ],
    ),
  );

  Widget _geometrySection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Forma para cálculo',
          'Opcional. Vincula la forma con las medidas sin duplicarlas.',
        ),
        if (_geometryProfile == null)
          const Text(
            'Sin forma configurada. El producto funciona normalmente, pero todavía no puede usarse como referencia geométrica.',
          )
        else ...[
          Text(
            _geometryProfile!.shape.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _geometryProfile!.components
                .map((component) => component.label)
                .join(' + '),
          ),
          if (_geometryProfile!.components.contains(GeometryComponent.lid))
            Text(_geometryProfile!.lidType.label),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              key: const Key('configure-product-geometry'),
              onPressed: _configureGeometry,
              icon: const Icon(Icons.category_outlined),
              label: Text(
                _geometryProfile == null ? 'Configurar forma' : 'Editar forma',
              ),
            ),
            if (_geometryProfile != null &&
                _geometryProfile!.shape != GeometryShape.other &&
                _usages.isNotEmpty)
              FilledButton.tonalIcon(
                key: const Key('estimate-product-material'),
                onPressed: _estimateMaterial,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Estimar material'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _usageTile(int index) {
    final usage = _usages[index];
    final bundle = widget.controller.materialsController.materials
        .where((item) => item.material.metadata.id == usage.materialId)
        .firstOrNull;
    final variant = bundle?.variants
        .where((item) => item.metadata.id == usage.materialVariantId)
        .firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: usage.role == ProductMaterialRole.primary
            ? AppColors.terracottaSoft
            : AppColors.sageSoft,
        child: Icon(
          usage.role == ProductMaterialRole.primary
              ? Icons.layers_rounded
              : Icons.extension_rounded,
        ),
      ),
      title: Text(
        '${bundle?.material.name ?? 'Material no disponible'}${variant == null ? '' : ' · ${variant.name}'}',
      ),
      subtitle: Text(
        '${_quantityLabel(usage.consumption)} · ${usage.role == ProductMaterialRole.primary ? 'Principal' : 'Complementario'} · ${usage.consumptionSource.label}',
      ),
      trailing: Wrap(
        children: [
          IconButton(
            onPressed: () => _editUsage(index),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => setState(() => _usages.removeAt(index)),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _pricingSection() {
    final settings = widget.controller.settingsController.settings;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'Precios',
            'Usá los valores generales o personalizalos para este producto.',
          ),
          TextFormField(
            key: const Key('product-multiplier'),
            controller: _multiplier,
            decoration: const InputDecoration(
              labelText: 'Multiplicador mayorista',
              prefixText: '× ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _validatePositiveDecimal,
          ),
          const SizedBox(height: AppSpacing.md),
          _overrideField(
            title: 'Desperdicio',
            inherited: '${settings.defaultWastePercentage.toPercentString()}%',
            enabled: _overrideWaste,
            controller: _waste,
            onChanged: (value) => setState(() => _overrideWaste = value),
          ),
          _overrideField(
            title: 'Hilo',
            inherited: '${settings.defaultThreadPercentage.toPercentString()}%',
            enabled: _overrideThread,
            controller: _thread,
            onChanged: (value) => setState(() => _overrideThread = value),
          ),
          _overrideField(
            title: 'Recargo minorista',
            inherited: settings.defaultRetailPercentage == null
                ? 'No configurado'
                : '${settings.defaultRetailPercentage!.toPercentString()}%',
            enabled: _overrideRetail,
            controller: _retail,
            onChanged: (value) => setState(() => _overrideRetail = value),
          ),
        ],
      ),
    );
  }

  Widget _overrideField({
    required String title,
    required String inherited,
    required bool enabled,
    required TextEditingController controller,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(
            enabled ? 'Valor propio del producto' : 'General: $inherited',
          ),
          value: enabled,
          onChanged: (value) {
            onChanged(value);
            _dirty = true;
          },
        ),
        if (enabled)
          TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: '$title del producto',
              suffixText: '%',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _validateNonNegativePercent,
          ),
      ],
    ),
  );

  Widget _liveSummary() {
    final calculation = _draftCalculation;
    return AppCard(
      color: AppColors.sageSoft,
      borderColor: AppColors.sageSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, color: AppColors.sage),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Cálculo en vivo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (calculation == null)
            const Text(
              'Completá el multiplicador y agregá materiales válidos para ver el desglose.',
            )
          else ...[
            _summaryRow(
              'Costo total',
              ArgentineNumberFormatter.money(calculation.cost.totalCost),
              strong: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _priceBox(
              'Precio mayorista',
              ArgentineNumberFormatter.money(
                calculation.pricing.wholesalePrice,
              ),
            ),
            if (calculation.pricing.retailPrice != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _priceBox(
                'Precio minorista',
                ArgentineNumberFormatter.money(
                  calculation.pricing.retailPrice!,
                ),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Minorista no configurado. Podés activarlo acá o desde Configuración.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            Text(
              'Detalle estimado',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final line in calculation.lines)
              _summaryRow(
                line.material.name,
                ArgentineNumberFormatter.money(line.resolved.cost),
              ),
            _summaryRow(
              'Principales',
              ArgentineNumberFormatter.money(calculation.cost.primaryMaterials),
            ),
            _summaryRow(
              'Hilo',
              ArgentineNumberFormatter.money(calculation.cost.thread),
            ),
            _summaryRow(
              'Desperdicio',
              ArgentineNumberFormatter.money(calculation.cost.waste),
            ),
            _summaryRow(
              'Complementarios',
              ArgentineNumberFormatter.money(
                calculation.cost.complementaryMaterials,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: strong
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _priceBox(String label, String value) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: AppColors.success),
        ),
      ],
    ),
  );

  ProductCalculation? get _draftCalculation {
    final multiplier = ArgentineNumberParser.tryParseDecimal(_multiplier.text);
    if (multiplier == null ||
        multiplier.scaledValue <= 0 ||
        _categoryId == null ||
        _usages.isEmpty) {
      return null;
    }
    try {
      final now = DateTime.now().toUtc();
      final productId = widget.bundle?.product.metadata.id ?? 'draft-product';
      final product = Product(
        metadata: SyncMetadata(id: productId, createdAt: now, updatedAt: now),
        name: _name.text,
        categoryId: _categoryId!,
        dimensions: _dimensions,
        geometryProfile: _geometryProfile,
        priceMultiplier: multiplier,
        pricingOverrides: PricingOverrides(
          wastePercentage: _overrideWaste ? _parsePercent(_waste.text) : null,
          threadPercentage: _overrideThread
              ? _parsePercent(_thread.text)
              : null,
          retailPercentage: _overrideRetail
              ? _parsePercent(_retail.text)
              : null,
        ),
      );
      final usages = [
        for (var index = 0; index < _usages.length; index++)
          ProductMaterialUsage(
            metadata: SyncMetadata(
              id: _usages[index].id ?? 'draft-$index',
              createdAt: now,
              updatedAt: now,
            ),
            productId: productId,
            materialId: _usages[index].materialId,
            materialVariantId: _usages[index].materialVariantId,
            consumption: _usages[index].consumption,
            role: _usages[index].role,
            consumptionSource: _usages[index].consumptionSource,
            calibrationEligible: _usages[index].calibrationEligible,
          ),
      ];
      return widget.controller.calculate(product, usages);
    } catch (_) {
      return null;
    }
  }

  ProductDimensions? get _dimensions => _measures.isEmpty
      ? null
      : ProductDimensions(
          shapeCode:
              _geometryProfile?.shapeCode ??
              widget.bundle?.product.dimensions?.shapeCode ??
              widget.initialDraft?.product.dimensions?.shapeCode ??
              'custom',
          values: {
            for (final measure in _measures)
              measure.name.trim(): measure.quantity,
          },
        );

  Future<void> _choosePhoto() async {
    const group = XTypeGroup(
      label: 'Imágenes',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    setState(() {
      _newPhotoSourcePath = file.path;
      _removePhoto = false;
      _dirty = true;
    });
  }

  Future<void> _addMeasure() async {
    final value = await _showMeasureEditor();
    if (value != null) setState(() => _measures.add(value));
  }

  Future<void> _editMeasure(int index) async {
    final value = await _showMeasureEditor(_measures[index]);
    if (value != null) setState(() => _measures[index] = value);
  }

  Future<_MeasureDraft?> _showMeasureEditor([_MeasureDraft? current]) async {
    return showDialog<_MeasureDraft>(
      context: context,
      builder: (context) => _ProductMeasureEditorDialog(
        current: current,
        units: widget.controller.materialsController.units,
      ),
    );
  }

  Future<void> _addUsage() async {
    final value = await showProductUsageEditor(
      context: context,
      materialsController: widget.controller.materialsController,
    );
    if (value != null) setState(() => _usages.add(value));
  }

  Future<void> _configureGeometry() async {
    final value = await showGeometryProfileEditorDialog(
      context: context,
      measureNames: _measures.map((item) => item.name).toList(),
      current: _geometryProfile,
    );
    if (!mounted) return;
    setState(() {
      _geometryProfile = value;
      _dirty = true;
    });
  }

  Future<void> _estimateMaterial() async {
    final multiplier = ArgentineNumberParser.tryParseDecimal(_multiplier.text);
    if (_categoryId == null ||
        multiplier == null ||
        multiplier.scaledValue <= 0 ||
        _dimensions == null ||
        _geometryProfile == null) {
      _message('Completá forma, medidas, categoría y multiplicador.');
      return;
    }
    final now = DateTime.now().toUtc();
    final productId =
        widget.bundle?.product.metadata.id ??
        widget.initialDraft?.product.metadata.id ??
        'draft-product';
    final product = Product(
      metadata: SyncMetadata(id: productId, createdAt: now, updatedAt: now),
      name: _name.text,
      categoryId: _categoryId!,
      description: _description.text,
      dimensions: _dimensions,
      geometryProfile: _geometryProfile,
      priceMultiplier: multiplier,
      pricingOverrides: PricingOverrides(
        wastePercentage: _overrideWaste ? _parsePercent(_waste.text) : null,
        threadPercentage: _overrideThread ? _parsePercent(_thread.text) : null,
        retailPercentage: _overrideRetail ? _parsePercent(_retail.text) : null,
      ),
    );
    final usages = [
      for (var index = 0; index < _usages.length; index++)
        ProductMaterialUsage(
          metadata: SyncMetadata(
            id: _usages[index].id ?? 'draft-$index',
            createdAt: now,
            updatedAt: now,
          ),
          productId: productId,
          materialId: _usages[index].materialId,
          materialVariantId: _usages[index].materialVariantId,
          consumption: _usages[index].consumption,
          role: _usages[index].role,
          consumptionSource: _usages[index].consumptionSource,
          calibrationEligible: _usages[index].calibrationEligible,
          notes: _usages[index].notes,
        ),
    ];
    final estimation = await showMaterialEstimationDialog(
      context: context,
      controller: widget.controller,
      targetProduct: product,
      currentUsages: usages,
      reference: widget.bundle,
    );
    if (estimation == null || !mounted) return;
    setState(() {
      _usages = [
        for (final usage in estimation.usages)
          ProductUsageFormValue(
            id: _usages
                .where(
                  (item) =>
                      item.materialId == usage.materialId &&
                      item.materialVariantId == usage.materialVariantId &&
                      item.role == usage.role,
                )
                .firstOrNull
                ?.id,
            materialId: usage.materialId,
            materialVariantId: usage.materialVariantId,
            consumption: usage.consumption,
            role: usage.role,
            consumptionSource: usage.consumptionSource,
            calibrationEligible: usage.calibrationEligible,
            notes: usage.notes,
          ),
      ];
      _dirty = true;
    });
  }

  Future<void> _editUsage(int index) async {
    final value = await showProductUsageEditor(
      context: context,
      materialsController: widget.controller.materialsController,
      value: _usages[index],
    );
    if (value != null) setState(() => _usages[index] = value);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) return;
    if (_usages.isEmpty) {
      _message('Agregá al menos una materia prima.');
      return;
    }
    final names = _measures
        .map((item) => item.name.trim().toLowerCase())
        .toList();
    if (names.toSet().length != names.length) {
      _message('No puede haber dos medidas con el mismo nombre.');
      return;
    }
    final multiplier = ArgentineNumberParser.tryParseDecimal(_multiplier.text)!;
    try {
      await widget.controller.save(
        ProductFormValue(
          id:
              widget.bundle?.product.metadata.id ??
              widget.initialDraft?.product.metadata.id,
          name: _name.text,
          categoryId: _categoryId!,
          description: _description.text,
          dimensions: _dimensions,
          geometryProfile: _geometryProfile,
          priceMultiplier: multiplier,
          wasteOverride: _overrideWaste ? _parsePercent(_waste.text) : null,
          threadOverride: _overrideThread ? _parsePercent(_thread.text) : null,
          retailOverride: _overrideRetail ? _parsePercent(_retail.text) : null,
          notes: _notes.text,
          isActive: _isActive,
          usages: _usages,
          currentPhotoReference: widget.bundle?.product.photoPath,
          newPhotoSourcePath: _newPhotoSourcePath,
          removePhoto: _removePhoto,
        ),
      );
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _message(
        error is ArgumentError
            ? '${error.message}'
            : widget.controller.errorMessage ?? 'No pudimos guardar.',
      );
    }
  }

  String? _validatePositiveDecimal(String? input) {
    final value = ArgentineNumberParser.tryParseDecimal(input ?? '');
    return value == null || value.scaledValue <= 0
        ? 'Ingresá un número mayor que cero'
        : null;
  }

  String? _validateNonNegativePercent(String? input) {
    final value = ArgentineNumberParser.tryParseDecimal(input ?? '');
    return value == null || value.scaledValue < 0
        ? 'Ingresá un porcentaje válido'
        : null;
  }

  DecimalValue _parsePercent(String input) => DecimalValue.percent(
    ArgentineNumberParser.parseDecimal(input)
        .toDecimalString(fractionDigits: 6),
  );

  String _quantityLabel(MeasuredQuantity quantity) {
    final unit = widget.controller.materialsController.unitById(
      quantity.unitId,
    );
    return '${ArgentineNumberFormatter.decimal(quantity.amount)} ${unit?.symbol ?? ''}';
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _cancel() async {
    if (!_dirty || await _confirmDiscard()) {
      if (mounted) Navigator.pop(context, false);
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar los cambios?'),
          content: const Text('Lo que completaste no se guardará.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;
}

final class _ProductMeasureEditorDialog extends StatefulWidget {
  const _ProductMeasureEditorDialog({required this.units, this.current});

  final List<MeasurementUnit> units;
  final _MeasureDraft? current;

  @override
  State<_ProductMeasureEditorDialog> createState() =>
      _ProductMeasureEditorDialogState();
}

final class _ProductMeasureEditorDialogState
    extends State<_ProductMeasureEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String? _unitId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.current?.name ?? '');
    _amount = TextEditingController(
      text: widget.current == null
          ? ''
          : ArgentineNumberFormatter.decimal(widget.current!.quantity.amount),
    );
    _unitId = widget.current?.quantity.unitId ?? widget.units.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current == null ? 'Agregar medida' : 'Editar medida'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('product-measure-name'),
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej.: Diámetro',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('product-measure-amount'),
                      controller: _amount,
                      decoration: const InputDecoration(labelText: 'Valor'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('product-measure-unit'),
                      initialValue: _unitId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                      items: [
                        for (final unit in widget.units)
                          DropdownMenuItem(
                            value: unit.id,
                            child: Text(
                              '${unit.name} (${unit.symbol})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _unitId = value),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = ArgentineNumberParser.tryParseDecimal(_amount.text);
            if (_name.text.trim().isEmpty ||
                parsed == null ||
                parsed.scaledValue < 0 ||
                _unitId == null) {
              return;
            }
            Navigator.pop(
              context,
              _MeasureDraft(
                name: _name.text.trim(),
                quantity: MeasuredQuantity(amount: parsed, unitId: _unitId!),
              ),
            );
          },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

Future<ProductUsageFormValue?> showProductUsageEditor({
  required BuildContext context,
  required MaterialsController materialsController,
  ProductUsageFormValue? value,
}) => showDialog<ProductUsageFormValue>(
  context: context,
  builder: (context) => _ProductUsageEditor(
    materialsController: materialsController,
    value: value,
  ),
);

final class _ProductUsageEditor extends StatefulWidget {
  const _ProductUsageEditor({required this.materialsController, this.value});

  final MaterialsController materialsController;
  final ProductUsageFormValue? value;

  @override
  State<_ProductUsageEditor> createState() => _ProductUsageEditorState();
}

final class _ProductUsageEditorState extends State<_ProductUsageEditor> {
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  String? _materialId;
  String? _variantId;
  String? _unitId;
  ProductMaterialRole _role = ProductMaterialRole.primary;
  ConsumptionSource _consumptionSource = ConsumptionSource.manual;
  bool _calibrationEligible = true;

  MaterialBundle? get _material => widget.materialsController.materials
      .where((item) => item.material.metadata.id == _materialId)
      .firstOrNull;

  List<MeasurementUnit> get _compatibleUnits {
    final material = _material;
    if (material == null) return const [];
    final reference = widget.materialsController.unitById(
      material.material.consumptionUnitId,
    );
    return widget.materialsController.units
        .where((unit) => unit.dimension == reference?.dimension)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _materialId = widget.value?.materialId;
    _variantId = widget.value?.materialVariantId;
    _unitId = widget.value?.consumption.unitId;
    _role = widget.value?.role ?? ProductMaterialRole.primary;
    _consumptionSource =
        widget.value?.consumptionSource ?? ConsumptionSource.manual;
    _calibrationEligible = widget.value?.calibrationEligible ?? true;
    _amount = TextEditingController(
      text: widget.value == null
          ? ''
          : ArgentineNumberFormatter.decimal(widget.value!.consumption.amount),
    );
    _notes = TextEditingController(text: widget.value?.notes ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final materialOptions = widget.materialsController.materials.where(
      (item) =>
          item.material.isActive || item.material.metadata.id == _materialId,
    );
    final variants =
        _material?.variants.where(
          (variant) => variant.isActive || variant.metadata.id == _variantId,
        ) ??
        const <MaterialVariant>[];
    return AlertDialog(
      title: Text(
        widget.value == null ? 'Agregar materia prima' : 'Editar materia prima',
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('usage-material'),
                initialValue: _materialId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Materia prima'),
                items: [
                  for (final bundle in materialOptions)
                    DropdownMenuItem(
                      value: bundle.material.metadata.id,
                      child: Text(bundle.material.name),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _materialId = value;
                  _variantId = null;
                  _unitId = _material?.material.consumptionUnitId;
                }),
              ),
              if (variants.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String?>(
                  key: const Key('usage-variant'),
                  initialValue: _variantId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Variante (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text(
                        'Precio base del material',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final variant in variants)
                      DropdownMenuItem(
                        value: variant.metadata.id,
                        child: Text(
                          variant.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _variantId = value),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<ProductMaterialRole>(
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: ProductMaterialRole.primary,
                    label: Text('Principal'),
                    icon: Icon(Icons.layers_rounded),
                  ),
                  ButtonSegment(
                    value: ProductMaterialRole.complementary,
                    label: Text('Complementario'),
                    icon: Icon(Icons.extension_rounded),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (value) =>
                    setState(() => _role = value.first),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<ConsumptionSource>(
                key: const Key('usage-consumption-source'),
                initialValue: _consumptionSource,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Origen del consumo',
                ),
                items: const [
                  DropdownMenuItem(
                    value: ConsumptionSource.manual,
                    child: Text(
                      'Registrado manualmente',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: ConsumptionSource.estimated,
                    child: Text('Estimado', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: ConsumptionSource.confirmed,
                    child: Text(
                      'Real confirmado',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _consumptionSource = value ?? ConsumptionSource.manual,
                ),
              ),
              CheckboxListTile(
                key: const Key('usage-calibration-eligible'),
                contentPadding: EdgeInsets.zero,
                value: _calibrationEligible,
                title: const Text('Usar como referencia de la calculadora'),
                subtitle: const Text(
                  'Desactivá esta opción si el consumo todavía necesita revisión.',
                ),
                onChanged: (value) =>
                    setState(() => _calibrationEligible = value ?? true),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('usage-amount'),
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Cantidad usada'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _unitId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Unidad compatible',
                ),
                items: [
                  for (final unit in _compatibleUnits)
                    DropdownMenuItem(
                      value: unit.id,
                      child: Text(
                        '${unit.name} (${unit.symbol})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _unitId = value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('save-product-material'),
          onPressed: () {
            final amount = ArgentineNumberParser.tryParseDecimal(_amount.text);
            if (_materialId == null ||
                _unitId == null ||
                amount == null ||
                amount.scaledValue <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Completá el material y una cantidad mayor que cero.',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              ProductUsageFormValue(
                id: widget.value?.id,
                materialId: _materialId!,
                materialVariantId: _variantId,
                consumption: MeasuredQuantity(amount: amount, unitId: _unitId!),
                role: _role,
                consumptionSource: _consumptionSource,
                calibrationEligible: _calibrationEligible,
                notes: _notes.text,
              ),
            );
          },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
