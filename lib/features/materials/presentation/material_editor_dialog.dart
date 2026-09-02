import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/formatting/argentine_number_parser.dart';
import '../../../domain/materials/material_models.dart' hide Material;
import '../../../domain/repositories/product_repository.dart';
import '../application/material_form_value.dart';
import '../application/materials_controller.dart';
import 'material_display.dart';

Future<bool> showMaterialEditor({
  required BuildContext context,
  required MaterialsController controller,
  String currency = 'ARS',
  MaterialBundle? bundle,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 700;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => compact
            ? Dialog.fullscreen(
                child: MaterialEditor(
                  controller: controller,
                  currency: currency,
                  bundle: bundle,
                ),
              )
            : Dialog(
                insetPadding: const EdgeInsets.all(AppSpacing.lg),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 860,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                  ),
                  child: MaterialEditor(
                    controller: controller,
                    currency: currency,
                    bundle: bundle,
                  ),
                ),
              ),
      ) ??
      false;
}

final class MaterialEditor extends StatefulWidget {
  const MaterialEditor({
    required this.controller,
    required this.currency,
    this.bundle,
    super.key,
  });

  final MaterialsController controller;
  final String currency;
  final MaterialBundle? bundle;

  @override
  State<MaterialEditor> createState() => _MaterialEditorState();
}

final class _MaterialEditorState extends State<MaterialEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _supplier;
  late final TextEditingController _notes;
  String? _categoryId;
  late MeasurementDimension _dimension;
  String? _purchaseUnitId;
  String? _consumptionUnitId;
  late bool _isActive;
  late bool _hasVariants;
  late List<VariantFormValue> _variants;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final material = widget.bundle?.material;
    final purchaseUnit = material == null
        ? null
        : widget.controller.unitById(material.purchase.quantity.unitId);
    _name = TextEditingController(text: material?.name ?? '');
    _description = TextEditingController(text: material?.description ?? '');
    _price = TextEditingController(
      text: material == null
          ? ''
          : ArgentineNumberFormatter.moneyAmount(material.purchase.price),
    );
    _quantity = TextEditingController(
      text: material == null
          ? ''
          : ArgentineNumberFormatter.decimal(material.purchase.quantity.amount),
    );
    _supplier = TextEditingController(text: material?.brandOrSupplier ?? '');
    _notes = TextEditingController(text: material?.notes ?? '');
    _categoryId =
        material?.categoryId ??
        widget.controller.categories.firstOrNull?.metadata.id;
    _dimension = purchaseUnit?.dimension ?? MeasurementDimension.weight;
    _purchaseUnitId = purchaseUnit?.id ?? _unitsForDimension.firstOrNull?.id;
    _consumptionUnitId =
        material?.consumptionUnitId ?? _defaultConsumptionUnitId;
    _isActive = material?.isActive ?? true;
    _variants = [
      for (final variant
          in widget.bundle?.variants ?? const <MaterialVariant>[])
        if (variant.purchaseOverride != null)
          VariantFormValue(
            id: variant.metadata.id,
            name: variant.name,
            purchase: variant.purchaseOverride!,
            notes: variant.notes,
            isActive: variant.isActive,
          ),
    ];
    _hasVariants = _variants.isNotEmpty;
    for (final controller in [
      _name,
      _description,
      _price,
      _quantity,
      _supplier,
      _notes,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  List<MeasurementUnit> get _unitsForDimension => widget.controller.units
      .where((unit) => unit.dimension == _dimension)
      .toList(growable: false);

  String? get _defaultConsumptionUnitId {
    final preferredCode = switch (_dimension) {
      MeasurementDimension.weight => 'gram',
      MeasurementDimension.length => 'meter',
      MeasurementDimension.area => 'square_meter',
      MeasurementDimension.count => 'item',
    };
    return _unitsForDimension
        .where((unit) => unit.code == preferredCode)
        .firstOrNull
        ?.id;
  }

  PurchasePresentation? get _currentPurchase {
    final amount = ArgentineNumberParser.tryParseDecimal(_quantity.text);
    final price = ArgentineNumberParser.tryParseMoney(
      _price.text,
      currency: widget.currency,
    );
    if (amount == null ||
        price == null ||
        amount.scaledValue <= 0 ||
        _purchaseUnitId == null) {
      return null;
    }
    return PurchasePresentation(
      quantity: MeasuredQuantity(amount: amount, unitId: _purchaseUnitId!),
      price: price,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _quantity.dispose();
    _supplier.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (mounted) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await _confirmDiscard() && context.mounted) {
        Navigator.pop(context, false);
      }
    },
    child: FocusTraversalGroup(
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            widget.bundle == null
                ? 'Nueva materia prima'
                : 'Editar materia prima',
          ),
          actions: [
            TextButton(onPressed: _cancel, child: const Text('Cancelar')),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600
                  ? AppSpacing.md
                  : AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIdentity(context),
                const SizedBox(height: AppSpacing.md),
                _buildPurchase(context),
                const SizedBox(height: AppSpacing.md),
                _buildVariants(context),
                const SizedBox(height: AppSpacing.md),
                _buildOptional(context),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Material(
          color: AppColors.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: widget.controller.isSaving ? null : _cancel,
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: widget.controller.isSaving ? null : _save,
                    icon: widget.controller.isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      widget.controller.isSaving ? 'Guardando…' : 'Guardar',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildIdentity(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lo principal', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _name,
          autofocus: widget.bundle == null,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej.: Cordón PP 7 mm sin alma',
          ),
          textInputAction: TextInputAction.next,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Ingresá un nombre'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _categoryId,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            for (final category in widget.controller.categories)
              DropdownMenuItem(
                value: category.metadata.id,
                child: Text(category.name),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _categoryId = value;
              _dirty = true;
            });
          },
          validator: (value) => value == null ? 'Elegí una categoría' : null,
        ),
      ],
    ),
  );

  Widget _buildPurchase(BuildContext context) {
    final purchase = _currentPurchase;
    final cost = purchase == null || _consumptionUnitId == null
        ? null
        : unitCostLabel(purchase, _consumptionUnitId!, widget.controller);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Cómo lo comprás?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Elegí la forma de medida. La app hace las conversiones por vos.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<MeasurementDimension>(
              segments: [
                for (final dimension in MeasurementDimension.values)
                  ButtonSegment(
                    value: dimension,
                    label: Text(dimension.label),
                    icon: Icon(_dimensionIcon(dimension)),
                  ),
              ],
              selected: {_dimension},
              onSelectionChanged: (selection) {
                setState(() {
                  _dimension = selection.single;
                  _purchaseUnitId = _unitsForDimension.firstOrNull?.id;
                  _consumptionUnitId = _defaultConsumptionUnitId;
                  _dirty = true;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                TextFormField(
                  controller: _price,
                  decoration: InputDecoration(
                    labelText: 'Precio de compra',
                    prefixText: widget.currency == 'ARS'
                        ? r'$ '
                        : '${widget.currency} ',
                    hintText: '35.438,98',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validatePrice,
                ),
                TextFormField(
                  controller: _quantity,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad comprada',
                    hintText: '2,1',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validateQuantity,
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('purchase-${_dimension.name}-$_purchaseUnitId'),
                  initialValue: _purchaseUnitId,
                  decoration: const InputDecoration(
                    labelText: 'Unidad de compra',
                  ),
                  items: [
                    for (final unit in _unitsForDimension)
                      DropdownMenuItem(
                        value: unit.id,
                        child: Text('${unit.name} (${unit.symbol})'),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _purchaseUnitId = value;
                    _dirty = true;
                  }),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey(
                    'consumption-${_dimension.name}-$_consumptionUnitId',
                  ),
                  initialValue: _consumptionUnitId,
                  decoration: const InputDecoration(
                    labelText: 'Mostrar costo por',
                  ),
                  items: [
                    for (final unit in _unitsForDimension)
                      DropdownMenuItem(
                        value: unit.id,
                        child: Text(unit.symbol),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _consumptionUnitId = value;
                    _dirty = true;
                  }),
                ),
              ];
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [
                    for (var index = 0; index < fields.length; index++) ...[
                      fields[index],
                      if (index < fields.length - 1)
                        const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: (constraints.maxWidth - AppSpacing.md) / 2,
                      child: field,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: cost == null ? AppColors.softSurface : AppColors.sageSoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Icon(
                  cost == null ? Icons.calculate_outlined : Icons.check_circle,
                  color: cost == null ? AppColors.mutedInk : AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Costo calculado'),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        cost ?? 'Completá precio y cantidad para verlo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariants(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Este material tiene variantes'),
          subtitle: const Text(
            'Útil para colores que tienen precios o presentaciones diferentes.',
          ),
          value: _hasVariants,
          onChanged: _toggleVariants,
        ),
        if (_hasVariants) ...[
          const Divider(height: AppSpacing.lg),
          if (_variants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Todavía no agregaste colores o variantes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (var index = 0; index < _variants.length; index++)
            _VariantRow(
              value: _variants[index],
              controller: widget.controller,
              consumptionUnitId: _consumptionUnitId,
              onEdit: () => _editVariant(index),
              onDelete: () => setState(() {
                _variants.removeAt(index);
                _dirty = true;
              }),
            ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addVariant,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar variante'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildOptional(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      title: const Text('Más información'),
      subtitle: const Text('Descripción, proveedor y notas (opcional)'),
      children: [
        TextFormField(
          controller: _description,
          decoration: const InputDecoration(labelText: 'Descripción'),
          maxLines: 2,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _supplier,
          decoration: const InputDecoration(labelText: 'Marca o proveedor'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Notas'),
          maxLines: 3,
        ),
        if (widget.bundle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Materia prima activa'),
            subtitle: const Text(
              'Las inactivas se conservan, pero no se ofrecerán en nuevos productos.',
            ),
            value: _isActive,
            onChanged: (value) => setState(() {
              _isActive = value;
              _dirty = true;
            }),
          ),
        ],
      ],
    ),
  );

  Future<void> _toggleVariants(bool enabled) async {
    if (!enabled && _variants.isNotEmpty) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Quitar las variantes?'),
          content: const Text(
            'Los colores cargados se eliminarán de esta materia prima al guardar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Conservar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar variantes'),
            ),
          ],
        ),
      );
      if (remove != true) return;
      _variants.clear();
    }
    setState(() {
      _hasVariants = enabled;
      _dirty = true;
    });
  }

  Future<void> _addVariant() async {
    final basePurchase = _currentPurchase;
    if (basePurchase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero completá el precio y la presentación base.'),
        ),
      );
      return;
    }
    final result = await showVariantEditor(
      context: context,
      controller: widget.controller,
      purchaseUnitId: _purchaseUnitId!,
      consumptionUnitId: _consumptionUnitId!,
      initialPurchase: basePurchase,
    );
    if (result != null) {
      setState(() {
        _variants.add(result);
        _dirty = true;
      });
    }
  }

  Future<void> _editVariant(int index) async {
    final result = await showVariantEditor(
      context: context,
      controller: widget.controller,
      purchaseUnitId: _purchaseUnitId!,
      consumptionUnitId: _consumptionUnitId!,
      initialPurchase: _variants[index].purchase,
      value: _variants[index],
    );
    if (result != null) {
      setState(() {
        _variants[index] = result;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final purchase = _currentPurchase;
    if (purchase == null || _categoryId == null || _consumptionUnitId == null) {
      return;
    }
    if (_hasVariants && _variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregá al menos una variante o desactivá esa opción.'),
        ),
      );
      return;
    }
    try {
      await widget.controller.save(
        MaterialFormValue(
          id: widget.bundle?.material.metadata.id,
          name: _name.text,
          categoryId: _categoryId!,
          purchase: purchase,
          consumptionUnitId: _consumptionUnitId!,
          description: _description.text,
          brandOrSupplier: _supplier.text,
          notes: _notes.text,
          isActive: _isActive,
          variants: _hasVariants ? _variants : const [],
        ),
      );
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MaterialVariantInUseException
                ? 'Una variante que intentaste quitar está usada por un producto. Podés desactivarla, pero no eliminarla.'
                : widget.controller.errorMessage ?? 'No pudimos guardar.',
          ),
        ),
      );
    }
  }

  String? _validatePrice(String? value) {
    final parsed = ArgentineNumberParser.tryParseMoney(
      value ?? '',
      currency: widget.currency,
    );
    if (parsed == null) return 'Ingresá un precio válido';
    if (parsed.minorUnits < 0) return 'El precio no puede ser negativo';
    return null;
  }

  String? _validateQuantity(String? value) {
    final parsed = ArgentineNumberParser.tryParseDecimal(value ?? '');
    if (parsed == null) return 'Ingresá una cantidad válida';
    if (parsed.scaledValue <= 0) return 'La cantidad debe ser mayor que cero';
    return null;
  }

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
          content: const Text(
            'Lo que completaste en este formulario no se guardará.',
          ),
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

  IconData _dimensionIcon(MeasurementDimension dimension) =>
      switch (dimension) {
        MeasurementDimension.weight => Icons.scale_rounded,
        MeasurementDimension.length => Icons.straighten_rounded,
        MeasurementDimension.area => Icons.crop_square_rounded,
        MeasurementDimension.count => Icons.tag_rounded,
      };
}

final class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.value,
    required this.controller,
    required this.consumptionUnitId,
    required this.onEdit,
    required this.onDelete,
  });

  final VariantFormValue value;
  final MaterialsController controller;
  final String? consumptionUnitId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: value.isActive
          ? AppColors.terracottaSoft
          : AppColors.softSurface,
      child: const Icon(Icons.palette_outlined),
    ),
    title: Text(value.name),
    subtitle: Text(
      consumptionUnitId == null
          ? presentationLabel(value.purchase, controller)
          : '${presentationLabel(value.purchase, controller)}\n'
                '${unitCostLabel(value.purchase, consumptionUnitId!, controller)}',
    ),
    isThreeLine: consumptionUnitId != null,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Editar variante',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Quitar variante',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}

Future<VariantFormValue?> showVariantEditor({
  required BuildContext context,
  required MaterialsController controller,
  required String purchaseUnitId,
  required String consumptionUnitId,
  required PurchasePresentation initialPurchase,
  VariantFormValue? value,
}) => showDialog<VariantFormValue>(
  context: context,
  builder: (context) => _VariantEditorDialog(
    controller: controller,
    purchaseUnitId: purchaseUnitId,
    consumptionUnitId: consumptionUnitId,
    initialPurchase: initialPurchase,
    value: value,
  ),
);

final class _VariantEditorDialog extends StatefulWidget {
  const _VariantEditorDialog({
    required this.controller,
    required this.purchaseUnitId,
    required this.consumptionUnitId,
    required this.initialPurchase,
    this.value,
  });

  final MaterialsController controller;
  final String purchaseUnitId;
  final String consumptionUnitId;
  final PurchasePresentation initialPurchase;
  final VariantFormValue? value;

  @override
  State<_VariantEditorDialog> createState() => _VariantEditorDialogState();
}

final class _VariantEditorDialogState extends State<_VariantEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _notes;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final purchase = widget.value?.purchase ?? widget.initialPurchase;
    _name = TextEditingController(text: widget.value?.name ?? '');
    _price = TextEditingController(
      text: ArgentineNumberFormatter.moneyAmount(purchase.price),
    );
    _quantity = TextEditingController(
      text: ArgentineNumberFormatter.decimal(purchase.quantity.amount),
    );
    _notes = TextEditingController(text: widget.value?.notes ?? '');
    _active = widget.value?.isActive ?? true;
    _price.addListener(_refresh);
    _quantity.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  PurchasePresentation? get _purchase {
    final price = ArgentineNumberParser.tryParseMoney(
      _price.text,
      currency: widget.initialPurchase.price.currency,
    );
    final quantity = ArgentineNumberParser.tryParseDecimal(_quantity.text);
    if (price == null || quantity == null || quantity.scaledValue <= 0) {
      return null;
    }
    return PurchasePresentation(
      quantity: MeasuredQuantity(
        amount: quantity,
        unitId: widget.purchaseUnitId,
      ),
      price: price,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchase = _purchase;
    return AlertDialog(
      title: Text(
        widget.value == null ? 'Agregar variante' : 'Editar variante',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nombre o color',
                    hintText: 'Ej.: Natural',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ingresá un nombre o color'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _price,
                  decoration: InputDecoration(
                    labelText: 'Precio de compra',
                    prefixText: widget.initialPurchase.price.currency == 'ARS'
                        ? r'$ '
                        : '${widget.initialPurchase.price.currency} ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) =>
                      ArgentineNumberParser.tryParseMoney(
                            value ?? '',
                            currency: widget.initialPurchase.price.currency,
                          ) ==
                          null
                      ? 'Ingresá un precio válido'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _quantity,
                  decoration: InputDecoration(
                    labelText: 'Cantidad comprada',
                    suffixText: widget.controller
                        .unitById(widget.purchaseUnitId)
                        ?.symbol,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final parsed = ArgentineNumberParser.tryParseDecimal(
                      value ?? '',
                    );
                    return parsed == null || parsed.scaledValue <= 0
                        ? 'Ingresá una cantidad mayor que cero'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                if (purchase != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.sageSoft,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Text(
                      'Costo calculado: ${unitCostLabel(purchase, widget.consumptionUnitId, widget.controller)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Observación (opcional)',
                  ),
                  maxLines: 2,
                ),
                if (widget.value != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Variante activa'),
                    value: _active,
                    onChanged: (value) => setState(() => _active = value),
                  ),
              ],
            ),
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
            if (!_formKey.currentState!.validate() || _purchase == null) return;
            Navigator.pop(
              context,
              VariantFormValue(
                id: widget.value?.id,
                name: _name.text.trim(),
                purchase: _purchase!,
                notes: _notes.text.trim(),
                isActive: _active,
              ),
            );
          },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
