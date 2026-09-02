import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/formatting/argentine_number_parser.dart';
import '../../../core/money/decimal_value.dart';
import '../../../core/money/money.dart';
import '../../../domain/common/sync_metadata.dart';
import '../../../domain/geometry/geometry_models.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/pricing/pricing_models.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/quotes/quote_models.dart';
import '../../products/application/product_form_value.dart';
import '../../products/application/products_controller.dart';
import '../../products/presentation/product_editor_dialog.dart';
import '../../calculator/presentation/geometry_profile_editor_dialog.dart';
import '../../calculator/presentation/material_estimation_dialog.dart';
import '../application/quote_form_value.dart';
import '../application/quotes_controller.dart';

Future<QuoteAggregate?> showQuoteEditor({
  required BuildContext context,
  required QuotesController controller,
  QuoteAggregate? aggregate,
  ProductBundle? initialProduct,
}) => showDialog<QuoteAggregate>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _QuoteEditorDialog(
    controller: controller,
    aggregate: aggregate,
    initialProduct: initialProduct,
  ),
);

final class _QuoteEditorDialog extends StatefulWidget {
  const _QuoteEditorDialog({
    required this.controller,
    this.aggregate,
    this.initialProduct,
  });

  final QuotesController controller;
  final QuoteAggregate? aggregate;
  final ProductBundle? initialProduct;

  @override
  State<_QuoteEditorDialog> createState() => _QuoteEditorDialogState();
}

final class _QuoteEditorDialogState extends State<_QuoteEditorDialog> {
  final _customer = TextEditingController();
  final _validityDays = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date;
  late DateTime _validUntil;
  late QuotePriceType _priceType;
  late List<QuoteItemFormValue> _items;
  late List<QuoteAdjustmentFormValue> _generalAdjustments;
  int _step = 0;
  bool _saving = false;

  DateFormat get _dateFormat => DateFormat('dd/MM/yyyy', 'es_AR');

  @override
  void initState() {
    super.initState();
    final existing = widget.aggregate == null
        ? null
        : QuoteFormValue.fromAggregate(widget.aggregate!);
    _date = existing?.date ?? widget.controller.today;
    final days = existing?.validityDays ?? 15;
    _validUntil =
        existing?.validUntil ??
        widget.controller.engine.calculateValidUntil(_date, days);
    _priceType = existing?.priceType ?? QuotePriceType.retail;
    _customer.text = existing?.customerName ?? '';
    _validityDays.text = days.toString();
    _notes.text = existing?.notes ?? '';
    _items = [...?existing?.items];
    if (widget.initialProduct != null) {
      _items.add(widget.controller.itemFromProduct(widget.initialProduct!));
    }
    _generalAdjustments = [...?existing?.generalAdjustments];
  }

  @override
  void dispose() {
    _customer.dispose();
    _validityDays.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final body = Column(
      children: [
        _header(compact),
        const Divider(height: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: SingleChildScrollView(
              key: ValueKey(_step),
              padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
              child: switch (_step) {
                0 => _dataStep(),
                1 => _itemsStep(),
                _ => _summaryStep(),
              },
            ),
          ),
        ),
        const Divider(height: 1),
        _footer(compact),
      ],
    );
    if (compact) return Dialog.fullscreen(child: SafeArea(child: body));
    return Dialog(child: SizedBox(width: 920, height: 760, child: body));
  }

  Widget _header(bool compact) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.aggregate == null
                    ? 'Nuevo presupuesto'
                    : 'Editar presupuesto',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${_step + 1} de 3 · ${['Datos', 'Productos', 'Resumen'][_step]}',
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: _saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _dataStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Datos del presupuesto',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.xs),
      const Text(
        'La fecha se completa con hoy y podés cambiarla cuando lo necesites.',
      ),
      const SizedBox(height: AppSpacing.lg),
      TextField(
        key: const Key('quote-customer'),
        controller: _customer,
        decoration: const InputDecoration(labelText: 'Nombre del cliente'),
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: AppSpacing.md),
      LayoutBuilder(
        builder: (context, constraints) {
          final children = [
            _DateField(
              key: const Key('quote-date'),
              label: 'Fecha',
              value: _dateFormat.format(_date),
              onTap: _pickDate,
            ),
            TextField(
              key: const Key('quote-validity-days'),
              controller: _validityDays,
              decoration: const InputDecoration(
                labelText: 'Válido por',
                suffixText: 'días',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: _daysChanged,
            ),
            _DateField(
              key: const Key('quote-valid-until'),
              label: 'Válido hasta',
              value: _dateFormat.format(_validUntil),
              onTap: _pickValidUntil,
            ),
          ];
          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index < children.length - 1)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                Expanded(child: children[index]),
                if (index < children.length - 1)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Tipo de precio', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.xs),
      SegmentedButton<QuotePriceType>(
        expandedInsets: EdgeInsets.zero,
        segments: const [
          ButtonSegment(
            value: QuotePriceType.retail,
            label: Text('Minorista'),
            icon: Icon(Icons.person_outline_rounded),
          ),
          ButtonSegment(
            value: QuotePriceType.wholesale,
            label: Text('Mayorista'),
            icon: Icon(Icons.storefront_outlined),
          ),
        ],
        selected: {_priceType},
        onSelectionChanged: (value) => setState(() => _priceType = value.first),
      ),
    ],
  );

  Widget _itemsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Productos', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xs),
      const Text('Partí de un producto existente o armá un trabajo nuevo.'),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          FilledButton.icon(
            key: const Key('quote-add-from-product'),
            onPressed: _addFromProduct,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Agregar desde producto'),
          ),
          OutlinedButton.icon(
            key: const Key('quote-add-custom'),
            onPressed: _addCustom,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Crear personalizado'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      if (_items.isEmpty)
        const AppCard(
          child: Text('Todavía no agregaste productos a este presupuesto.'),
        )
      else
        for (var index = 0; index < _items.length; index++) ...[
          _editableItemCard(index),
          const SizedBox(height: AppSpacing.sm),
        ],
    ],
  );

  Widget _editableItemCard(int index) {
    final item = _items[index];
    Money? unit;
    Money? subtotal;
    try {
      if (item.existingSnapshot != null) {
        final base = item.existingSnapshot!.priceFor(_priceType);
        var adjustment = Money(minorUnits: 0, currency: base.currency);
        for (final value in item.adjustments) {
          adjustment = adjustment + value.amount;
        }
        unit = base + adjustment;
        subtotal = Money(
          minorUnits: unit.minorUnits * item.quantity,
          currency: unit.currency,
        );
      } else {
        final result = widget.controller.calculateDraftItem(item, _priceType);
        unit = result.finalUnitPrice;
        subtotal = result.subtotal;
      }
    } catch (_) {}
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppColors.terracottaSoft,
            foregroundColor: AppColors.terracottaDark,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name.isEmpty ? 'Producto personalizado' : item.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${item.quantity} ${item.quantity == 1 ? 'unidad' : 'unidades'} · ${item.usages.length} materiales',
                ),
                if (unit != null)
                  Text(
                    '${ArgentineNumberFormatter.money(unit)} c/u · ${ArgentineNumberFormatter.money(subtotal!)}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  const Text('Completá materiales y reglas de precio.'),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Personalizar',
            onPressed: () => _editItem(index),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Quitar',
            onPressed: () => setState(() => _items.removeAt(index)),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _summaryStep() {
    Money? total;
    try {
      total = widget.controller.calculateDraftTotal(_value());
    } catch (_) {}
    final minimum =
        widget.controller.settingsController.settings.minimumWholesaleAmount;
    final belowMinimum =
        total != null &&
        widget.controller.engine.isBelowWholesaleMinimum(
          priceType: _priceType,
          total: total,
          minimum: minimum,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Resumen', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: [
              for (var index = 0; index < _items.length; index++) ...[
                _summaryItem(_items[index]),
                if (index < _items.length - 1) const Divider(),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Ajustes generales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _addGeneralAdjustment,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar ajuste'),
            ),
          ],
        ),
        for (var index = 0; index < _generalAdjustments.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_generalAdjustments[index].description),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ArgentineNumberFormatter.money(
                    _generalAdjustments[index].amount,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _generalAdjustments.removeAt(index)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          color: AppColors.sageSoft,
          borderColor: AppColors.sageSoft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'TOTAL',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                total == null
                    ? 'Revisar datos'
                    : ArgentineNumberFormatter.money(total),
                key: const Key('quote-total'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (belowMinimum) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderColor: AppColors.warning,
            child: Text(
              'Este presupuesto no alcanza el monto mínimo mayorista configurado de ${ArgentineNumberFormatter.money(minimum!)}. Podés volver a editar o continuar conscientemente.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Observaciones (opcional)',
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _summaryItem(QuoteItemFormValue item) {
    Money? unit;
    Money? subtotal;
    try {
      if (item.existingSnapshot != null) {
        var resolvedUnit = item.existingSnapshot!.priceFor(_priceType);
        for (final adjustment in item.adjustments) {
          resolvedUnit = resolvedUnit + adjustment.amount;
        }
        unit = resolvedUnit;
        subtotal = Money(
          minorUnits: resolvedUnit.minorUnits * item.quantity,
          currency: resolvedUnit.currency,
        );
      } else {
        final result = widget.controller.calculateDraftItem(item, _priceType);
        unit = result.finalUnitPrice;
        subtotal = result.subtotal;
      }
    } catch (_) {}
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${item.quantity} × ${item.name}'),
      subtitle: Text(
        unit == null
            ? 'Revisar cálculo'
            : '${ArgentineNumberFormatter.money(unit)} c/u',
      ),
      trailing: Text(
        subtotal == null ? '—' : ArgentineNumberFormatter.money(subtotal),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _footer(bool compact) => Padding(
    padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
    child: Row(
      children: [
        TextButton(
          onPressed: _saving
              ? null
              : _step == 0
              ? () => Navigator.pop(context)
              : () => setState(() => _step--),
          child: Text(_step == 0 ? 'Cancelar' : 'Atrás'),
        ),
        const Spacer(),
        FilledButton.icon(
          key: Key(_step == 2 ? 'save-quote' : 'next-quote-step'),
          onPressed: _saving ? null : _next,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _step == 2
                      ? Icons.save_outlined
                      : Icons.arrow_forward_rounded,
                ),
          label: Text(
            compact
                ? _step == 2
                      ? 'Guardar'
                      : 'Siguiente'
                : _step == 2
                ? 'Guardar presupuesto'
                : 'Continuar',
          ),
        ),
      ],
    ),
  );

  Future<void> _next() async {
    if (_step == 0 && _customer.text.trim().isEmpty) {
      _message('Ingresá el nombre del cliente.');
      return;
    }
    if (_step == 1 && _items.isEmpty) {
      _message('Agregá al menos un producto.');
      return;
    }
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.save(_value());
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  QuoteFormValue _value() => QuoteFormValue(
    id: widget.aggregate?.quote.metadata.id,
    customerName: _customer.text,
    date: _date,
    validityDays: int.tryParse(_validityDays.text) ?? 0,
    validUntil: _validUntil,
    priceType: _priceType,
    notes: _notes.text,
    items: _items,
    generalAdjustments: _generalAdjustments,
  );

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    final days = int.tryParse(_validityDays.text) ?? 0;
    setState(() {
      _date = value;
      _validUntil = widget.controller.engine.calculateValidUntil(value, days);
    });
  }

  void _daysChanged(String source) {
    final days = int.tryParse(source);
    if (days == null) return;
    setState(() {
      _validUntil = widget.controller.engine.calculateValidUntil(_date, days);
    });
  }

  Future<void> _pickValidUntil() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: _date,
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    final days = widget.controller.engine.calculateValidityDays(_date, value);
    setState(() {
      _validUntil = value;
      _validityDays.text = days.toString();
    });
  }

  Future<void> _addFromProduct() async {
    final available = widget.controller.productsController.products
        .where((item) => item.product.isActive)
        .toList(growable: false);
    final selected = await showDialog<ProductBundle>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar desde producto'),
        content: SizedBox(
          width: 560,
          child: available.isEmpty
              ? const Text('Todavía no hay productos activos para elegir.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: available.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(available[index].product.name),
                    subtitle: Text(
                      '${available[index].usages.length} materiales',
                    ),
                    trailing: const Icon(Icons.add_circle_outline_rounded),
                    onTap: () => Navigator.pop(context, available[index]),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final item = widget.controller.itemFromProduct(selected);
    if (!mounted) return;
    final edited = await showQuoteItemEditor(
      context: context,
      controller: widget.controller,
      value: item,
      priceType: _priceType,
    );
    if (edited != null && mounted) setState(() => _items.add(edited));
  }

  Future<void> _addCustom() async {
    try {
      final item = widget.controller.emptyCustomItem();
      final edited = await showQuoteItemEditor(
        context: context,
        controller: widget.controller,
        value: item,
        priceType: _priceType,
      );
      if (edited != null && mounted) setState(() => _items.add(edited));
    } catch (error) {
      _message(_friendlyError(error));
    }
  }

  Future<void> _editItem(int index) async {
    final original = _items[index];
    final edited = await showQuoteItemEditor(
      context: context,
      controller: widget.controller,
      value: original,
      priceType: _priceType,
    );
    if (edited == null || !mounted) return;
    final configurationChanged =
        original.configurationSignature != edited.configurationSignature;
    setState(() {
      _items[index] = configurationChanged
          ? edited.copyWith(clearExistingSnapshot: true)
          : edited;
    });
  }

  Future<void> _addGeneralAdjustment() async {
    final value = await showQuoteAdjustmentEditor(
      context: context,
      currency: widget.controller.settingsController.settings.currency,
    );
    if (value != null && mounted) {
      setState(() => _generalAdjustments.add(value));
    }
  }

  String _friendlyError(Object error) => switch (error) {
    ArgumentError(:final message) => message.toString(),
    StateError(:final message) => message,
    _ => 'No pudimos completar la acción. Revisá los datos.',
  };

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

final class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.sm),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(value),
    ),
  );
}

final class _MeasureDraft {
  const _MeasureDraft({required this.name, required this.quantity});
  final String name;
  final MeasuredQuantity quantity;
}

Future<QuoteItemFormValue?> showQuoteItemEditor({
  required BuildContext context,
  required QuotesController controller,
  required QuoteItemFormValue value,
  required QuotePriceType priceType,
}) => showDialog<QuoteItemFormValue>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _QuoteItemEditor(
    controller: controller,
    value: value,
    priceType: priceType,
  ),
);

final class _QuoteItemEditor extends StatefulWidget {
  const _QuoteItemEditor({
    required this.controller,
    required this.value,
    required this.priceType,
  });

  final QuotesController controller;
  final QuoteItemFormValue value;
  final QuotePriceType priceType;

  @override
  State<_QuoteItemEditor> createState() => _QuoteItemEditorState();
}

final class _QuoteItemEditorState extends State<_QuoteItemEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _personalization;
  late final TextEditingController _quantity;
  late final TextEditingController _multiplier;
  late final TextEditingController _waste;
  late final TextEditingController _thread;
  late final TextEditingController _retail;
  late String? _categoryId;
  late bool _overrideWaste;
  late bool _overrideThread;
  late bool _overrideRetail;
  late List<_MeasureDraft> _measures;
  late List<ProductUsageFormValue> _usages;
  late List<QuoteAdjustmentFormValue> _adjustments;
  GeometryProfile? _geometryProfile;

  @override
  void initState() {
    super.initState();
    final value = widget.value;
    _name = TextEditingController(text: value.name);
    _description = TextEditingController(text: value.description ?? '');
    _personalization = TextEditingController(
      text: value.personalizationDescription ?? '',
    );
    _quantity = TextEditingController(text: value.quantity.toString());
    _multiplier = TextEditingController(
      text: value.priceMultiplier.toDecimalString(fractionDigits: 2),
    );
    _waste = TextEditingController(
      text: value.wasteOverride?.toPercentString(fractionDigits: 2) ?? '',
    );
    _thread = TextEditingController(
      text: value.threadOverride?.toPercentString(fractionDigits: 2) ?? '',
    );
    _retail = TextEditingController(
      text: value.retailOverride?.toPercentString(fractionDigits: 2) ?? '',
    );
    _categoryId = value.categoryId;
    _overrideWaste = value.wasteOverride != null;
    _overrideThread = value.threadOverride != null;
    _overrideRetail = value.retailOverride != null;
    _measures = [
      for (final entry
          in value.dimensions?.values.entries ??
              const <MapEntry<String, MeasuredQuantity>>[])
        _MeasureDraft(name: entry.key, quantity: entry.value),
    ];
    _usages = [...value.usages];
    _adjustments = [...value.adjustments];
    _geometryProfile = value.geometryProfile;
    for (final controller in [
      _name,
      _description,
      _personalization,
      _quantity,
      _multiplier,
      _waste,
      _thread,
      _retail,
    ]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _personalization,
      _quantity,
      _multiplier,
      _waste,
      _thread,
      _retail,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  QuoteItemFormValue? get _draft {
    final quantity = int.tryParse(_quantity.text);
    final multiplier = ArgentineNumberParser.tryParseDecimal(_multiplier.text);
    if (quantity == null || multiplier == null) return null;
    DecimalValue? percent(TextEditingController controller, bool enabled) {
      if (!enabled) return null;
      final parsed = ArgentineNumberParser.tryParseDecimal(controller.text);
      return parsed == null
          ? null
          : DecimalValue.percent(parsed.toDecimalString());
    }

    return QuoteItemFormValue(
      id: widget.value.id,
      sourceProductId: widget.value.sourceProductId,
      name: _name.text,
      categoryId: _categoryId,
      description: _description.text,
      personalizationDescription: _personalization.text,
      dimensions: _measures.isEmpty
          ? null
          : ProductDimensions(
              shapeCode:
                  _geometryProfile?.shapeCode ??
                  widget.value.dimensions?.shapeCode ??
                  'custom',
              values: {
                for (final measure in _measures) measure.name: measure.quantity,
              },
            ),
      geometryProfile: _geometryProfile,
      quantity: quantity,
      priceMultiplier: multiplier,
      wasteOverride: percent(_waste, _overrideWaste),
      threadOverride: percent(_thread, _overrideThread),
      retailOverride: percent(_retail, _overrideRetail),
      usages: _usages,
      adjustments: _adjustments,
      existingSnapshot: widget.value.existingSnapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Personalizar producto',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _basicSection(),
                const SizedBox(height: AppSpacing.lg),
                _measuresSection(),
                const SizedBox(height: AppSpacing.lg),
                _materialsSection(),
                const SizedBox(height: AppSpacing.lg),
                _rulesSection(),
                const SizedBox(height: AppSpacing.lg),
                _adjustmentsSection(),
                const SizedBox(height: AppSpacing.lg),
                _calculationCard(),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                key: const Key('save-quote-item'),
                onPressed: _save,
                child: const Text('Aceptar'),
              ),
            ],
          ),
        ),
      ],
    );
    return compact
        ? Dialog.fullscreen(child: SafeArea(child: content))
        : Dialog(child: SizedBox(width: 820, height: 780, child: content));
  }

  Widget _basicSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Información', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.md),
      TextField(
        key: const Key('quote-item-name'),
        controller: _name,
        decoration: const InputDecoration(labelText: 'Nombre / descripción'),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoría (opcional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Sin categoría'),
                ),
                for (final category
                    in widget.controller.productsController.categories)
                  DropdownMenuItem(
                    value: category.metadata.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: const Key('quote-item-quantity'),
              controller: _quantity,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _description,
        decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
        maxLines: 2,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _personalization,
        decoration: const InputDecoration(
          labelText: 'Descripción de personalización (opcional)',
          hintText: 'Ej.: Tapa cónica en lugar de tapa plana',
        ),
        maxLines: 2,
      ),
    ],
  );

  Widget _measuresSection() {
    final changed =
        _dimensionsSignature(_measures) !=
        _dimensionsSignature([
          for (final entry
              in widget.value.dimensions?.values.entries ??
                  const <MapEntry<String, MeasuredQuantity>>[])
            _MeasureDraft(name: entry.key, quantity: entry.value),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Text('Medidas', style: Theme.of(context).textTheme.titleLarge),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  key: const Key('quote-item-geometry'),
                  onPressed: _configureGeometry,
                  icon: const Icon(Icons.category_outlined),
                  label: Text(
                    _geometryProfile == null ? 'Definir forma' : 'Editar forma',
                  ),
                ),
                TextButton.icon(
                  key: const Key('quote-item-add-measure'),
                  onPressed: _addMeasure,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agregar'),
                ),
              ],
            ),
          ],
        ),
        if (_geometryProfile != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${_geometryProfile!.shape.label} · ${_geometryProfile!.components.map((item) => item.label).join(' + ')}',
            ),
          ),
        for (var index = 0; index < _measures.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_measures[index].name),
            subtitle: Text(
              '${ArgentineNumberFormatter.decimal(_measures[index].quantity.amount)} ${widget.controller.productsController.materialsController.unitById(_measures[index].quantity.unitId)?.symbol ?? ''}',
            ),
            onTap: () => _editMeasure(index),
            trailing: IconButton(
              onPressed: () => setState(() => _measures.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        if (changed)
          AppCard(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderColor: AppColors.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cambiaste las medidas. Revisá el consumo de materiales.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_geometryProfile != null &&
                    _geometryProfile!.shape != GeometryShape.other &&
                    _usages.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.tonalIcon(
                    key: const Key('estimate-quote-item-material'),
                    onPressed: _estimateMaterial,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Estimar consumo'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _materialsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Consumo por unidad',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton.icon(
            key: const Key('quote-item-add-material'),
            onPressed: _addUsage,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar'),
          ),
        ],
      ),
      const Text(
        'Las cantidades representan una sola unidad, aunque cotices varias.',
      ),
      for (var index = 0; index < _usages.length; index++) _usageTile(index),
    ],
  );

  Widget _usageTile(int index) {
    final usage = _usages[index];
    final material = widget
        .controller
        .productsController
        .materialsController
        .materials
        .where((item) => item.material.metadata.id == usage.materialId)
        .firstOrNull;
    final variant = material?.variants
        .where((item) => item.metadata.id == usage.materialVariantId)
        .firstOrNull;
    final unit = widget.controller.productsController.materialsController
        .unitById(usage.consumption.unitId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        usage.role == ProductMaterialRole.primary
            ? Icons.layers_rounded
            : Icons.extension_rounded,
      ),
      title: Text(
        '${material?.material.name ?? 'Material no disponible'}${variant == null ? '' : ' · ${variant.name}'}',
      ),
      subtitle: Text(
        '${ArgentineNumberFormatter.decimal(usage.consumption.amount)} ${unit?.symbol ?? ''} · ${usage.role == ProductMaterialRole.primary ? 'Principal' : 'Complementario'}',
      ),
      onTap: () => _editUsage(index),
      trailing: IconButton(
        onPressed: () => setState(() => _usages.removeAt(index)),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }

  Widget _rulesSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Reglas de precio', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _multiplier,
        decoration: const InputDecoration(labelText: 'Multiplicador'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      const SizedBox(height: AppSpacing.sm),
      _overrideField(
        'Desperdicio personalizado',
        _overrideWaste,
        _waste,
        (value) => setState(() => _overrideWaste = value),
      ),
      _overrideField(
        'Hilo personalizado',
        _overrideThread,
        _thread,
        (value) => setState(() => _overrideThread = value),
      ),
      _overrideField(
        'Minorista personalizado',
        _overrideRetail,
        _retail,
        (value) => setState(() => _overrideRetail = value),
      ),
    ],
  );

  Widget _overrideField(
    String label,
    bool enabled,
    TextEditingController controller,
    ValueChanged<bool> onChanged,
  ) => Row(
    children: [
      Expanded(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: enabled,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 150,
        child: TextField(
          enabled: enabled,
          controller: controller,
          decoration: const InputDecoration(suffixText: '%'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ),
    ],
  );

  Widget _adjustmentsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Ajustes adicionales',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton.icon(
            key: const Key('quote-item-add-adjustment'),
            onPressed: _addAdjustment,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar ajuste'),
          ),
        ],
      ),
      const Text('Se suman o restan directamente al precio final por unidad.'),
      for (var index = 0; index < _adjustments.length; index++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_adjustments[index].description),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ArgentineNumberFormatter.money(_adjustments[index].amount)),
              IconButton(
                onPressed: () => setState(() => _adjustments.removeAt(index)),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _calculationCard() {
    final draft = _draft;
    QuoteDraftItemCalculation? result;
    try {
      if (draft != null && draft.usages.isNotEmpty) {
        result = widget.controller.calculateDraftItem(draft, widget.priceType);
      }
    } catch (_) {}
    return AppCard(
      color: AppColors.sageSoft,
      borderColor: AppColors.sageSoft,
      child: result == null
          ? const Text(
              'Completá nombre, cantidad, materiales y multiplicador para ver el precio.',
            )
          : Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _moneyValue('Precio calculado', result.calculatedUnitPrice),
                _moneyValue('Ajustes', result.adjustments),
                _moneyValue('Precio unitario', result.finalUnitPrice),
                _moneyValue('Subtotal', result.subtotal),
              ],
            ),
    );
  }

  Widget _moneyValue(String label, Money value) => SizedBox(
    width: 160,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          ArgentineNumberFormatter.money(value),
          style: const TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );

  Future<void> _addUsage() async {
    final value = await showProductUsageEditor(
      context: context,
      materialsController:
          widget.controller.productsController.materialsController,
    );
    if (value != null && mounted) setState(() => _usages.add(value));
  }

  Future<void> _configureGeometry() async {
    final value = await showGeometryProfileEditorDialog(
      context: context,
      measureNames: _measures.map((item) => item.name).toList(),
      current: _geometryProfile,
    );
    if (!mounted) return;
    setState(() => _geometryProfile = value);
  }

  Future<void> _estimateMaterial() async {
    final draft = _draft;
    if (draft == null ||
        draft.dimensions == null ||
        draft.geometryProfile == null ||
        draft.usages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completá forma, medidas y materiales.')),
      );
      return;
    }
    final now = DateTime.now().toUtc();
    final itemId = draft.id ?? 'draft-quote-item';
    final product = Product(
      metadata: SyncMetadata(id: itemId, createdAt: now, updatedAt: now),
      name: draft.name,
      categoryId:
          draft.categoryId ??
          widget
              .controller
              .productsController
              .categories
              .firstOrNull
              ?.metadata
              .id ??
          'custom',
      description: draft.description,
      dimensions: draft.dimensions,
      geometryProfile: draft.geometryProfile,
      priceMultiplier: draft.priceMultiplier,
      pricingOverrides: PricingOverrides(
        wastePercentage: draft.wasteOverride,
        threadPercentage: draft.threadOverride,
        retailPercentage: draft.retailOverride,
      ),
    );
    final usages = [
      for (var index = 0; index < draft.usages.length; index++)
        ProductMaterialUsage(
          metadata: SyncMetadata(
            id: draft.usages[index].id ?? 'draft-$index',
            createdAt: now,
            updatedAt: now,
          ),
          productId: itemId,
          materialId: draft.usages[index].materialId,
          materialVariantId: draft.usages[index].materialVariantId,
          consumption: draft.usages[index].consumption,
          role: draft.usages[index].role,
          consumptionSource: draft.usages[index].consumptionSource,
          calibrationEligible: draft.usages[index].calibrationEligible,
          notes: draft.usages[index].notes,
        ),
    ];
    final reference = widget.controller.productsController.products
        .where(
          (bundle) =>
              bundle.product.metadata.id == widget.value.sourceProductId,
        )
        .firstOrNull;
    final estimation = await showMaterialEstimationDialog(
      context: context,
      controller: widget.controller.productsController,
      targetProduct: product,
      currentUsages: usages,
      reference: reference,
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
    });
  }

  Future<void> _editUsage(int index) async {
    final previous = _usages[index];
    final value = await showProductUsageEditor(
      context: context,
      materialsController:
          widget.controller.productsController.materialsController,
      value: _usages[index],
    );
    if (value != null && mounted) {
      setState(() => _usages[index] = value);
      if (value.materialId != previous.materialId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cambiaste el material principal. Revisá el consumo: la cantidad no se ajustó automáticamente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _addAdjustment() async {
    final value = await showQuoteAdjustmentEditor(
      context: context,
      currency: widget.controller.settingsController.settings.currency,
    );
    if (value != null && mounted) setState(() => _adjustments.add(value));
  }

  Future<void> _addMeasure() async {
    final value = await _showMeasureEditor();
    if (value != null && mounted) setState(() => _measures.add(value));
  }

  Future<void> _editMeasure(int index) async {
    final value = await _showMeasureEditor(_measures[index]);
    if (value != null && mounted) setState(() => _measures[index] = value);
  }

  Future<_MeasureDraft?> _showMeasureEditor([_MeasureDraft? current]) {
    final name = TextEditingController(text: current?.name ?? '');
    final amount = TextEditingController(
      text: current == null
          ? ''
          : ArgentineNumberFormatter.decimal(current.quantity.amount),
    );
    var unitId = current?.quantity.unitId;
    final units =
        widget.controller.productsController.materialsController.units;
    unitId ??= units.firstOrNull?.id;
    return showDialog<_MeasureDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(current == null ? 'Agregar medida' : 'Editar medida'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('quote-measure-name'),
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Ej.: Alto',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('quote-measure-amount'),
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Valor'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  key: const Key('quote-measure-unit'),
                  isExpanded: true,
                  initialValue: unitId,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: [
                    for (final unit in units)
                      DropdownMenuItem(
                        value: unit.id,
                        child: Text(
                          '${unit.name} (${unit.symbol})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => unitId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = ArgentineNumberParser.tryParseDecimal(
                  amount.text,
                );
                if (name.text.trim().isEmpty ||
                    parsed == null ||
                    parsed.scaledValue < 0 ||
                    unitId == null) {
                  return;
                }
                Navigator.pop(
                  context,
                  _MeasureDraft(
                    name: name.text.trim(),
                    quantity: MeasuredQuantity(amount: parsed, unitId: unitId!),
                  ),
                );
              },
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final draft = _draft;
    if (draft == null ||
        draft.name.trim().isEmpty ||
        draft.quantity <= 0 ||
        draft.priceMultiplier.scaledValue <= 0 ||
        draft.usages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completá nombre, cantidad, materiales y multiplicador.',
          ),
        ),
      );
      return;
    }
    try {
      widget.controller.calculateDraftItem(draft, widget.priceType);
      Navigator.pop(context, draft);
    } on StateError catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Revisá los materiales, variantes y unidades elegidas.',
          ),
        ),
      );
    }
  }

  String _dimensionsSignature(List<_MeasureDraft> values) => values
      .map(
        (value) =>
            '${value.name}:${value.quantity.amount.scaledValue}:${value.quantity.unitId}',
      )
      .join('|');
}

Future<QuoteAdjustmentFormValue?> showQuoteAdjustmentEditor({
  required BuildContext context,
  required String currency,
}) {
  final description = TextEditingController();
  final amount = TextEditingController();
  var positive = true;
  return showDialog<QuoteAdjustmentFormValue>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Ajuste adicional'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('adjustment-description'),
                controller: description,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<bool>(
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Recargo'),
                    icon: Icon(Icons.add_rounded),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Descuento'),
                    icon: Icon(Icons.remove_rounded),
                  ),
                ],
                selected: {positive},
                onSelectionChanged: (value) =>
                    setState(() => positive = value.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('adjustment-amount'),
                controller: amount,
                decoration: const InputDecoration(
                  labelText: 'Importe',
                  prefixText: r'$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('save-adjustment'),
            onPressed: () {
              final parsed = ArgentineNumberParser.tryParseMoney(
                amount.text,
                currency: currency,
              );
              if (description.text.trim().isEmpty || parsed == null) return;
              Navigator.pop(
                context,
                QuoteAdjustmentFormValue(
                  description: description.text.trim(),
                  amount: positive
                      ? parsed
                      : Money(
                          minorUnits: -parsed.minorUnits.abs(),
                          currency: parsed.currency,
                        ),
                ),
              );
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    ),
  );
}
