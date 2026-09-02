import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_empty_state.dart';
import '../../../core/design_system/components/status_pill.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/money/money.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/quotes/quote_models.dart';
import '../../products/application/products_controller.dart';
import '../../products/presentation/product_editor_dialog.dart';
import '../application/quotes_controller.dart';
import 'quote_editor_dialog.dart';

enum QuoteFilter { all, current, expired, retail, wholesale }

extension on QuoteFilter {
  String get label => switch (this) {
    QuoteFilter.all => 'Todos',
    QuoteFilter.current => 'Vigentes',
    QuoteFilter.expired => 'Vencidos',
    QuoteFilter.retail => 'Minoristas',
    QuoteFilter.wholesale => 'Mayoristas',
  };
}

extension QuotePriceTypeLabel on QuotePriceType {
  String get label => this == QuotePriceType.retail ? 'Minorista' : 'Mayorista';
}

final class QuotesScreen extends StatefulWidget {
  const QuotesScreen({
    required this.controller,
    super.key,
    this.createRequested = false,
    this.initialProduct,
    this.onCreateRequestConsumed,
  });

  final QuotesController controller;
  final bool createRequested;
  final ProductBundle? initialProduct;
  final VoidCallback? onCreateRequestConsumed;

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

final class _QuotesScreenState extends State<QuotesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  QuoteFilter _filter = QuoteFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    _scheduleCreation();
  }

  @override
  void didUpdateWidget(QuotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.createRequested && !oldWidget.createRequested) {
      _scheduleCreation();
    }
  }

  void _scheduleCreation() {
    if (!widget.createRequested) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCreateRequestConsumed?.call();
      _create(initialProduct: widget.initialProduct);
    });
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): _create,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
          _searchFocus.requestFocus(),
    },
    child: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final items = _filtered();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              _filters(),
              if (widget.controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Text(
                    widget.controller.errorMessage!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              Expanded(child: _content(items)),
            ],
          );
        },
      ),
    ),
  );

  Widget _header() {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Presupuestos', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${widget.controller.currentCount} vigentes · precios históricos protegidos',
        ),
      ],
    );
    final button = FilledButton.icon(
      key: const Key('add-quote'),
      onPressed: _create,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Nuevo presupuesto'),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.md : AppSpacing.xl,
        AppSpacing.lg,
        compact ? AppSpacing.md : AppSpacing.xl,
        AppSpacing.md,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: AppSpacing.md),
                button,
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                button,
              ],
            ),
    );
  }

  Widget _filters() {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final search = TextField(
      controller: _search,
      focusNode: _searchFocus,
      decoration: InputDecoration(
        hintText: 'Buscar por cliente, producto o fecha',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                onPressed: _search.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final filter = DropdownButtonFormField<QuoteFilter>(
      isExpanded: true,
      initialValue: _filter,
      decoration: const InputDecoration(labelText: 'Mostrar'),
      items: [
        for (final value in QuoteFilter.values)
          DropdownMenuItem(value: value, child: Text(value.label)),
      ],
      onChanged: (value) => setState(() => _filter = value ?? _filter),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.md : AppSpacing.xl,
      ),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: compact
            ? Column(
                children: [
                  search,
                  const SizedBox(height: AppSpacing.sm),
                  filter,
                ],
              )
            : Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(width: 190, child: filter),
                ],
              ),
      ),
    );
  }

  Widget _content(List<QuoteAggregate> items) {
    if (widget.controller.isLoading && widget.controller.quotes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return AppEmptyState(
        icon: Icons.request_quote_outlined,
        title: widget.controller.quotes.isEmpty
            ? 'Todavía no creaste presupuestos'
            : 'No encontramos presupuestos',
        message: widget.controller.quotes.isEmpty
            ? 'Armá un presupuesto personalizado a partir de tus productos y materiales.'
            : 'Probá cambiar la búsqueda o el filtro.',
        actionLabel: widget.controller.quotes.isEmpty
            ? 'Nuevo presupuesto'
            : null,
        onAction: widget.controller.quotes.isEmpty ? _create : null,
      );
    }
    final desktop = MediaQuery.sizeOf(context).width >= 1050;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        desktop ? AppSpacing.xl : AppSpacing.md,
        AppSpacing.md,
        desktop ? AppSpacing.xl : AppSpacing.md,
        AppSpacing.xxl,
      ),
      itemCount: items.length + (desktop ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (desktop && index == 0) return const _DesktopQuoteHeader();
        final aggregate = items[index - (desktop ? 1 : 0)];
        return _QuoteCard(
          aggregate: aggregate,
          controller: widget.controller,
          desktop: desktop,
          onTap: () => _open(aggregate),
        );
      },
    );
  }

  List<QuoteAggregate> _filtered() {
    final query = _search.text.trim().toLowerCase();
    final dateFormat = DateFormat('dd/MM/yyyy', 'es_AR');
    return widget.controller.quotes
        .where((aggregate) {
          final quote = aggregate.quote;
          final status = widget.controller.engine.validityStatus(
            quote,
            widget.controller.today,
          );
          final matchesFilter = switch (_filter) {
            QuoteFilter.all => true,
            QuoteFilter.current => status == QuoteValidityStatus.current,
            QuoteFilter.expired => status == QuoteValidityStatus.expired,
            QuoteFilter.retail => quote.priceType == QuotePriceType.retail,
            QuoteFilter.wholesale =>
              quote.priceType == QuotePriceType.wholesale,
          };
          if (!matchesFilter) return false;
          if (query.isEmpty) return true;
          return [
            quote.customerName,
            dateFormat.format(quote.date),
            ...aggregate.items.map((item) => item.name),
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _create({ProductBundle? initialProduct}) async {
    final saved = await showQuoteEditor(
      context: context,
      controller: widget.controller,
      initialProduct: initialProduct,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Presupuesto guardado.')));
    }
  }

  Future<void> _open(QuoteAggregate aggregate) => showDialog<void>(
    context: context,
    builder: (context) => _QuoteDetailDialog(
      controller: widget.controller,
      initialAggregate: aggregate,
    ),
  );
}

final class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.aggregate,
    required this.controller,
    required this.desktop,
    required this.onTap,
  });

  final QuoteAggregate aggregate;
  final QuotesController controller;
  final bool desktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quote = aggregate.quote;
    final expired =
        controller.engine.validityStatus(quote, controller.today) ==
        QuoteValidityStatus.expired;
    final date = DateFormat('dd/MM/yyyy', 'es_AR');
    final status = StatusPill(
      label: expired ? 'Vencido' : 'Vigente',
      icon: expired
          ? Icons.event_busy_outlined
          : Icons.event_available_outlined,
      color: expired ? AppColors.mutedInk : AppColors.success,
      backgroundColor: expired ? AppColors.softSurface : AppColors.sageSoft,
    );
    if (!desktop) {
      return AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quote.customerName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                status,
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Fecha ${date.format(quote.date)} · Válido hasta ${date.format(quote.validUntil)}',
            ),
            Text(
              '${aggregate.items.length} ${aggregate.items.length == 1 ? 'ítem' : 'ítems'} · ${quote.priceType.label}',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              ArgentineNumberFormatter.money(quote.total),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              quote.customerName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(flex: 2, child: Text(date.format(quote.date))),
          Expanded(flex: 2, child: Text(date.format(quote.validUntil))),
          Expanded(flex: 2, child: Text(quote.priceType.label)),
          Expanded(child: Text('${aggregate.items.length}')),
          Expanded(
            flex: 2,
            child: Text(
              ArgentineNumberFormatter.money(quote.total),
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 110, child: status),
          const SizedBox(width: 36, child: Icon(Icons.more_horiz_rounded)),
        ],
      ),
    );
  }
}

final class _DesktopQuoteHeader extends StatelessWidget {
  const _DesktopQuoteHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text('Cliente')),
        Expanded(flex: 2, child: Text('Fecha')),
        Expanded(flex: 2, child: Text('Válido hasta')),
        Expanded(flex: 2, child: Text('Tipo')),
        Expanded(child: Text('Ítems')),
        Expanded(flex: 2, child: Text('Total')),
        SizedBox(width: 110, child: Text('Estado')),
        SizedBox(width: 36, child: Text('Acc.')),
      ],
    ),
  );
}

final class _QuoteDetailDialog extends StatefulWidget {
  const _QuoteDetailDialog({
    required this.controller,
    required this.initialAggregate,
  });

  final QuotesController controller;
  final QuoteAggregate initialAggregate;

  @override
  State<_QuoteDetailDialog> createState() => _QuoteDetailDialogState();
}

final class _QuoteDetailDialogState extends State<_QuoteDetailDialog> {
  QuoteAggregate? get _aggregate => widget.controller.quotes
      .where(
        (item) =>
            item.quote.metadata.id == widget.initialAggregate.quote.metadata.id,
      )
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final aggregate = _aggregate;
    if (aggregate == null) {
      return const AlertDialog(content: Text('El presupuesto fue eliminado.'));
    }
    final compact = MediaQuery.sizeOf(context).width < 760;
    final quote = aggregate.quote;
    final expired =
        widget.controller.engine.validityStatus(
          quote,
          widget.controller.today,
        ) ==
        QuoteValidityStatus.expired;
    final body = Column(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Presupuesto',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      quote.customerName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: expired ? 'Vencido' : 'Vigente',
                icon: expired
                    ? Icons.event_busy_outlined
                    : Icons.event_available_outlined,
                color: expired ? AppColors.mutedInk : AppColors.success,
                backgroundColor: expired
                    ? AppColors.softSurface
                    : AppColors.sageSoft,
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
                _commercialHeader(aggregate),
                const SizedBox(height: AppSpacing.lg),
                for (final item in aggregate.items) ...[
                  _itemCard(aggregate, item),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (aggregate.generalAdjustments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Ajustes generales',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final adjustment in aggregate.generalAdjustments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(adjustment.description),
                      trailing: Text(
                        ArgentineNumberFormatter.money(adjustment.amount),
                      ),
                    ),
                ],
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
                        ArgentineNumberFormatter.money(quote.total),
                        key: const Key('quote-detail-total'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                if (widget.controller.belowWholesaleMinimum(quote)) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderColor: AppColors.warning,
                    child: Text(
                      'Este presupuesto no alcanza el monto mínimo mayorista configurado de ${ArgentineNumberFormatter.money(widget.controller.settingsController.settings.minimumWholesaleAmount!)}.',
                    ),
                  ),
                ],
                if (quote.notes != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Observaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(quote.notes!),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        _actions(aggregate, compact),
      ],
    );
    return compact
        ? Dialog.fullscreen(child: SafeArea(child: body))
        : Dialog(child: SizedBox(width: 880, height: 780, child: body));
  }

  Widget _commercialHeader(QuoteAggregate aggregate) {
    final quote = aggregate.quote;
    final date = DateFormat('dd/MM/yyyy', 'es_AR');
    return AppCard(
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: [
          _labelValue('Fecha', date.format(quote.date)),
          _labelValue('Validez', '${quote.validityDays} días'),
          _labelValue('Válido hasta', date.format(quote.validUntil)),
          _labelValue('Tipo', quote.priceType.label),
          _labelValue('Ítems', '${aggregate.items.length}'),
        ],
      ),
    );
  }

  Widget _labelValue(String label, String value) => SizedBox(
    width: 140,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );

  Widget _itemCard(QuoteAggregate aggregate, QuoteItem item) {
    final subtotal = widget.controller.engine.itemSubtotal(item);
    final adjustments = aggregate.adjustmentsFor(item.metadata.id);
    return AppCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        title: Text('${item.quantity} × ${item.name}'),
        subtitle: Text('${ArgentineNumberFormatter.money(item.unitPrice)} c/u'),
        trailing: Text(
          ArgentineNumberFormatter.money(subtotal),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        children: [
          if (item.personalizationDescription != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(item.personalizationDescription!),
            ),
          if (item.dimensions?.values.isNotEmpty ?? false)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Medidas'),
              subtitle: Text(
                item.dimensions!.values.entries
                    .map((entry) {
                      final unit = widget
                          .controller
                          .productsController
                          .materialsController
                          .unitById(entry.value.unitId);
                      return '${entry.key} ${ArgentineNumberFormatter.decimal(entry.value.amount)} ${unit?.symbol ?? ''}';
                    })
                    .join(' · '),
              ),
            ),
          for (final material in item.snapshot.materials)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                material.role == ProductMaterialRole.primary
                    ? Icons.layers_rounded
                    : Icons.extension_rounded,
              ),
              title: Text(
                '${material.materialName}${material.variantName == null ? '' : ' · ${material.variantName}'}',
              ),
              subtitle: Text(
                '${ArgentineNumberFormatter.decimal(material.consumption.amount)} ${material.unitSymbol} · ${material.role == ProductMaterialRole.primary ? 'Principal' : 'Complementario'}',
              ),
              trailing: Text(ArgentineNumberFormatter.money(material.cost)),
            ),
          for (final adjustment in adjustments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: Text(adjustment.description),
              subtitle: const Text('Ajuste sobre precio final por unidad'),
              trailing: Text(ArgentineNumberFormatter.money(adjustment.amount)),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Ver cálculo'),
            children: [
              _amountRow(
                'Materiales principales',
                item.snapshot.primaryMaterials,
              ),
              _amountRow(
                'Hilo (${item.snapshot.threadPercentage.toPercentString()}%)',
                item.snapshot.thread,
              ),
              _amountRow(
                'Desperdicio (${item.snapshot.wastePercentage.toPercentString()}%)',
                item.snapshot.waste,
              ),
              _amountRow(
                'Complementarios',
                item.snapshot.complementaryMaterials,
              ),
              const Divider(),
              _amountRow('Costo total', item.snapshot.totalCost, strong: true),
              _amountRow('Mayorista', item.snapshot.wholesalePrice),
              if (item.snapshot.retailPrice != null)
                _amountRow('Minorista', item.snapshot.retailPrice!),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _convertToProduct(aggregate, item),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Guardar como producto'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(
    String label,
    Money amount, {
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: strong ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        ),
        Text(
          ArgentineNumberFormatter.money(amount),
          style: strong ? const TextStyle(fontWeight: FontWeight.w800) : null,
        ),
      ],
    ),
  );

  Widget _actions(QuoteAggregate aggregate, bool compact) {
    final buttons = [
      TextButton.icon(
        onPressed: () => _delete(aggregate),
        icon: const Icon(Icons.delete_outline_rounded),
        label: const Text('Eliminar'),
      ),
      TextButton.icon(
        key: const Key('recalculate-quote'),
        onPressed: () => _recalculate(aggregate),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Recalcular con precios actuales'),
      ),
      TextButton.icon(
        key: const Key('duplicate-quote'),
        onPressed: () => _duplicate(aggregate),
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Duplicar'),
      ),
      FilledButton.icon(
        onPressed: () => _edit(aggregate),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Editar'),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: compact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final button in buttons) ...[
                    button,
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            )
          : Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
    );
  }

  Future<void> _edit(QuoteAggregate aggregate) async {
    final saved = await showQuoteEditor(
      context: context,
      controller: widget.controller,
      aggregate: aggregate,
    );
    if (saved != null && mounted) setState(() {});
  }

  Future<void> _duplicate(QuoteAggregate aggregate) async {
    final copy = await widget.controller.duplicate(aggregate);
    if (!mounted) return;
    final saved = await showQuoteEditor(
      context: context,
      controller: widget.controller,
      aggregate: copy,
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? 'Presupuesto duplicado.' : 'Copia guardada.',
          ),
        ),
      );
    }
  }

  Future<void> _recalculate(QuoteAggregate aggregate) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Recalcular con precios actuales?'),
        content: const Text(
          'Se consultarán los precios actuales de los materiales. Todavía no se modificará el presupuesto: primero vas a ver una comparación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Comparar'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    QuoteRecalculationPreview preview;
    try {
      preview = widget.controller.previewRecalculation(aggregate);
    } catch (_) {
      if (mounted) {
        _message(
          'No se pudo recalcular. Revisá si algún material o variante ya no está disponible.',
        );
      }
      return;
    }
    if (!mounted) return;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comparación de importes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _comparisonRow('Total cotizado', preview.comparison.quotedTotal),
            _comparisonRow('Nuevo total', preview.comparison.currentTotal),
            const Divider(),
            _comparisonRow(
              'Diferencia',
              preview.comparison.difference,
              strong: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('apply-recalculation'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Actualizar presupuesto'),
          ),
        ],
      ),
    );
    if (apply != true) return;
    await widget.controller.applyRecalculation(preview);
    if (mounted) {
      setState(() {});
      _message('Presupuesto actualizado con los precios actuales.');
    }
  }

  Widget _comparisonRow(
    String label,
    Money amount, {
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: strong ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        ),
        Text(
          ArgentineNumberFormatter.money(amount),
          style: strong ? const TextStyle(fontWeight: FontWeight.w800) : null,
        ),
      ],
    ),
  );

  Future<void> _convertToProduct(
    QuoteAggregate aggregate,
    QuoteItem item,
  ) async {
    final hasCommercialDetails =
        aggregate.adjustmentsFor(item.metadata.id).isNotEmpty ||
        (item.personalizationDescription?.isNotEmpty ?? false);
    if (hasCommercialDetails) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Revisar antes de guardar'),
          content: const Text(
            'Este presupuesto tiene ajustes adicionales o una personalización especial. Revisá el nuevo producto antes de guardarlo. Los importes comerciales no se copiarán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revisar producto'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      final draft = widget.controller.productDraftFromItem(item);
      if (!mounted) return;
      final saved = await showProductEditor(
        context: context,
        controller: widget.controller.productsController,
        initialDraft: draft,
      );
      if (saved && mounted) {
        _message('Nuevo producto guardado. El producto original no cambió.');
      }
    } catch (error) {
      if (mounted) _message('No se pudo preparar el producto: $error');
    }
  }

  Future<void> _delete(QuoteAggregate aggregate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este presupuesto?'),
        content: const Text(
          'Se quitará del listado. Los productos y materiales asociados no se modificarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.deleteQuote(aggregate);
    if (mounted) Navigator.pop(context);
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
}
