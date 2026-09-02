import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_empty_state.dart';
import '../../../core/design_system/components/status_pill.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/money/money.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/repositories/product_catalog_repository.dart';
import '../application/products_controller.dart';
import 'product_editor_dialog.dart';

enum ProductStatusFilter { active, inactive, all }

extension on ProductStatusFilter {
  String get label => switch (this) {
    ProductStatusFilter.active => 'Activos',
    ProductStatusFilter.inactive => 'Inactivos',
    ProductStatusFilter.all => 'Todos',
  };
}

final class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    required this.controller,
    super.key,
    this.createRequested = false,
    this.onCreateRequestConsumed,
    this.onCreateQuote,
  });

  final ProductsController controller;
  final bool createRequested;
  final VoidCallback? onCreateRequestConsumed;
  final ValueChanged<ProductBundle>? onCreateQuote;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

final class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  ProductStatusFilter _status = ProductStatusFilter.active;
  String? _categoryId;
  String? _materialId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
    _scheduleRequestedCreation();
  }

  @override
  void didUpdateWidget(ProductsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.createRequested && !oldWidget.createRequested) {
      _scheduleRequestedCreation();
    }
  }

  void _scheduleRequestedCreation() {
    if (!widget.createRequested) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCreateRequestConsumed?.call();
      _addProduct();
    });
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          _addProduct,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
          _searchFocus.requestFocus(),
    },
    child: FocusTraversalGroup(
      child: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final products = _filteredProducts();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                _filters(context),
                if (widget.controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xs,
                      AppSpacing.xl,
                      0,
                    ),
                    child: Text(
                      widget.controller.errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                Expanded(child: _content(products)),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Productos', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${widget.controller.activeCount} activos · costos siempre actualizados',
        ),
      ],
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: _manageCategories,
          icon: const Icon(Icons.category_outlined),
          label: const Text('Categorías'),
        ),
        FilledButton.icon(
          key: const Key('add-product'),
          onPressed: _addProduct,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar'),
        ),
      ],
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
                actions,
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                actions,
              ],
            ),
    );
  }

  Widget _filters(BuildContext context) {
    // En escritorio la barra lateral ocupa 256 px; el corte considera ese
    // ancho para no comprimir los cuatro filtros en ventanas medianas.
    final compact = MediaQuery.sizeOf(context).width < 1200;
    final search = TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, categoría o material',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final status = DropdownButtonFormField<ProductStatusFilter>(
      isExpanded: true,
      initialValue: _status,
      decoration: const InputDecoration(labelText: 'Estado'),
      items: [
        for (final value in ProductStatusFilter.values)
          DropdownMenuItem(value: value, child: Text(value.label)),
      ],
      onChanged: (value) => setState(() => _status = value ?? _status),
    );
    final category = DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: _categoryId,
      decoration: const InputDecoration(labelText: 'Categoría'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todas')),
        for (final value in widget.controller.categories)
          DropdownMenuItem(value: value.metadata.id, child: Text(value.name)),
      ],
      onChanged: (value) => setState(() => _categoryId = value),
    );
    final material = DropdownButtonFormField<String?>(
      initialValue: _materialId,
      decoration: const InputDecoration(labelText: 'Materia prima'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todas')),
        for (final value in widget.controller.materialsController.materials)
          DropdownMenuItem(
            value: value.material.metadata.id,
            child: Text(value.material.name),
          ),
      ],
      onChanged: (value) => setState(() => _materialId = value),
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
                  Row(
                    children: [
                      Expanded(child: status),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: category),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  material,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: search),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 150, child: status),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 210, child: category),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 230, child: material),
                ],
              ),
      ),
    );
  }

  Widget _content(List<ProductBundle> products) {
    if (widget.controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.controller.products.isEmpty) {
      return AppEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Todavía no cargaste productos',
        message: 'Combiná tus materias primas y obtené el costo y los precios automáticamente.',
        actionLabel: 'Crear primer producto',
        onAction: _addProduct,
      );
    }
    if (products.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No encontramos coincidencias',
        message: 'Probá cambiar la búsqueda o quitar algún filtro.',
      );
    }
    final desktop = MediaQuery.sizeOf(context).width >= 1180;
    return ListView.separated(
      padding: EdgeInsets.all(desktop ? AppSpacing.xl : AppSpacing.md),
      itemCount: products.length + (desktop ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (desktop && index == 0) return const _DesktopProductHeader();
        final bundle = products[index - (desktop ? 1 : 0)];
        return _ProductCard(
          bundle: bundle,
          controller: widget.controller,
          desktop: desktop,
          onTap: () => _showDetail(bundle),
        );
      },
    );
  }

  List<ProductBundle> _filteredProducts() {
    final query = _searchController.text.trim().toLowerCase();
    return widget.controller.products
        .where((bundle) {
          final product = bundle.product;
          final statusMatches = switch (_status) {
            ProductStatusFilter.active => product.isActive,
            ProductStatusFilter.inactive => !product.isActive,
            ProductStatusFilter.all => true,
          };
          if (!statusMatches) return false;
          if (_categoryId != null && product.categoryId != _categoryId) {
            return false;
          }
          if (_materialId != null &&
              !bundle.usages.any((usage) => usage.materialId == _materialId)) {
            return false;
          }
          if (query.isEmpty) return true;
          final category =
              widget.controller.categoryById(product.categoryId)?.name ?? '';
          final materialNames = bundle.usages.expand((usage) {
            final materialBundle = widget
                .controller
                .materialsController
                .materials
                .where((item) => item.material.metadata.id == usage.materialId)
                .firstOrNull;
            final variant = materialBundle?.variants
                .where((item) => item.metadata.id == usage.materialVariantId)
                .firstOrNull;
            return [materialBundle?.material.name ?? '', variant?.name ?? ''];
          });
          return [
            product.name,
            product.description ?? '',
            category,
            ...materialNames,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _addProduct() async {
    final saved = await showProductEditor(
      context: context,
      controller: widget.controller,
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Producto guardado.')));
    }
  }

  Future<void> _showDetail(ProductBundle bundle) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ProductDetailDialog(
        controller: widget.controller,
        initialBundle: bundle,
        onCreateQuote: widget.onCreateQuote,
      ),
    );
  }

  Future<void> _manageCategories() async {
    await showProductCategoryManager(
      context: context,
      controller: widget.controller,
    );
    if (mounted) setState(() {});
  }
}

final class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.bundle,
    required this.controller,
    required this.desktop,
    required this.onTap,
  });

  final ProductBundle bundle;
  final ProductsController controller;
  final bool desktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ProductCalculation? calculation;
    try {
      calculation = controller.calculate(bundle.product, bundle.usages);
    } catch (_) {}
    final product = bundle.product;
    final photoPath = controller.photoAbsolutePath(product.photoPath);
    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: SizedBox(
        width: 58,
        height: 58,
        child: photoPath != null && File(photoPath).existsSync()
            ? Image.file(File(photoPath), fit: BoxFit.cover)
            : Container(
                color: AppColors.terracottaSoft,
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.terracottaDark,
                ),
              ),
      ),
    );
    if (!desktop) {
      return AppCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            thumbnail,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (!product.isActive)
                        const StatusPill(
                          label: 'Inactivo',
                          icon: Icons.pause_circle_outline_rounded,
                          color: AppColors.mutedInk,
                          backgroundColor: AppColors.softSurface,
                        ),
                    ],
                  ),
                  Text(
                    controller.categoryById(product.categoryId)?.name ??
                        'Sin categoría',
                  ),
                  if (product.dimensions?.values.isNotEmpty ?? false)
                    Text(
                      _dimensionsLabel(product, controller),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    calculation == null
                        ? 'Revisar materiales'
                        : 'Mayorista ${ArgentineNumberFormatter.money(calculation.pricing.wholesalePrice)}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (calculation?.pricing.retailPrice != null)
                    Text(
                      'Minorista ${ArgentineNumberFormatter.money(calculation!.pricing.retailPrice!)}',
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
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
          thumbnail,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Text(
              product.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              controller.categoryById(product.categoryId)?.name ?? '—',
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              calculation == null
                  ? '—'
                  : ArgentineNumberFormatter.money(calculation.cost.totalCost),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              calculation == null
                  ? '—'
                  : ArgentineNumberFormatter.money(
                      calculation.pricing.wholesalePrice,
                    ),
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              calculation?.pricing.retailPrice == null
                  ? 'Sin configurar'
                  : ArgentineNumberFormatter.money(
                      calculation!.pricing.retailPrice!,
                    ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(product.isActive ? 'Activo' : 'Inactivo'),
          ),
          const SizedBox(width: 40, child: Icon(Icons.more_horiz_rounded)),
        ],
      ),
    );
  }
}

final class _DesktopProductHeader extends StatelessWidget {
  const _DesktopProductHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Row(
      children: [
        SizedBox(width: 74),
        Expanded(flex: 3, child: Text('Producto')),
        Expanded(flex: 2, child: Text('Categoría')),
        Expanded(flex: 2, child: Text('Costo')),
        Expanded(flex: 2, child: Text('Mayorista')),
        Expanded(flex: 2, child: Text('Minorista')),
        SizedBox(width: 90, child: Text('Estado')),
        SizedBox(width: 40, child: Text('Acc.')),
      ],
    ),
  );
}

String _dimensionsLabel(Product product, ProductsController controller) =>
    product.dimensions?.values.entries
        .map((entry) {
          final unit = controller.materialsController.unitById(
            entry.value.unitId,
          );
          return '${entry.key} ${ArgentineNumberFormatter.decimal(entry.value.amount)} ${unit?.symbol ?? ''}';
        })
        .join(' · ') ??
    '';

final class _ProductDetailDialog extends StatefulWidget {
  const _ProductDetailDialog({
    required this.controller,
    required this.initialBundle,
    this.onCreateQuote,
  });

  final ProductsController controller;
  final ProductBundle initialBundle;
  final ValueChanged<ProductBundle>? onCreateQuote;

  @override
  State<_ProductDetailDialog> createState() => _ProductDetailDialogState();
}

final class _ProductDetailDialogState extends State<_ProductDetailDialog> {
  ProductBundle? get _bundle => widget.controller.products
      .where(
        (item) =>
            item.product.metadata.id ==
            widget.initialBundle.product.metadata.id,
      )
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    if (bundle == null) {
      return const AlertDialog(content: Text('El producto fue eliminado.'));
    }
    final calculation = widget.controller.calculate(
      bundle.product,
      bundle.usages,
    );
    final photo = widget.controller.photoAbsolutePath(bundle.product.photoPath);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(bundle.product.name)),
          if (!bundle.product.isActive)
            const StatusPill(
              label: 'Inactivo',
              icon: Icons.pause_circle_outline_rounded,
              color: AppColors.mutedInk,
              backgroundColor: AppColors.softSurface,
            ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photo != null && File(photo).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: Image.file(
                    File(photo),
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.controller
                        .categoryById(bundle.product.categoryId)
                        ?.name ??
                    'Sin categoría',
              ),
              if (bundle.product.description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(bundle.product.description!),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                color: AppColors.sageSoft,
                borderColor: AppColors.sageSoft,
                child: Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.md,
                  children: [
                    _resultValue('Costo total', calculation.cost.totalCost),
                    _resultValue(
                      'Mayorista',
                      calculation.pricing.wholesalePrice,
                    ),
                    if (calculation.pricing.retailPrice != null)
                      _resultValue(
                        'Minorista',
                        calculation.pricing.retailPrice!,
                      )
                    else
                      const SizedBox(
                        width: 190,
                        child: Text(
                          'Minorista sin configurar. Podés definirlo en Configuración.',
                        ),
                      ),
                  ],
                ),
              ),
              if (bundle.product.dimensions?.values.isNotEmpty ?? false) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Medidas', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(_dimensionsLabel(bundle.product, widget.controller)),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Materiales utilizados',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final line in calculation.lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    line.usage.role == ProductMaterialRole.primary
                        ? Icons.layers_rounded
                        : Icons.extension_rounded,
                    color: line.usage.role == ProductMaterialRole.primary
                        ? AppColors.terracottaDark
                        : AppColors.sage,
                  ),
                  title: Text(
                    '${line.material.name}${line.variant == null ? '' : ' · ${line.variant!.name}'}',
                  ),
                  subtitle: Text(
                    '${ArgentineNumberFormatter.decimal(line.usage.consumption.amount)} '
                    '${widget.controller.materialsController.unitById(line.usage.consumption.unitId)?.symbol ?? ''} · '
                    '${line.usage.role == ProductMaterialRole.primary ? 'Principal' : 'Complementario'} · '
                    '${line.usage.consumptionSource.label}',
                  ),
                  trailing: Text(
                    ArgentineNumberFormatter.money(line.resolved.cost),
                  ),
                ),
              Text(
                'Multiplicador × ${bundle.product.priceMultiplier.toDecimalString()} · '
                'Hilo ${bundle.product.pricingOverrides.threadPercentage == null ? 'general' : 'personalizado'} · '
                'Desperdicio ${bundle.product.pricingOverrides.wastePercentage == null ? 'general' : 'personalizado'} · '
                'Minorista ${bundle.product.pricingOverrides.retailPercentage == null ? 'general' : 'personalizado'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Ver detalle del cálculo'),
                children: [
                  for (final line in calculation.lines)
                    _amountRow(
                      '${line.material.name}${line.variant == null ? '' : ' · ${line.variant!.name}'}',
                      line.resolved.cost,
                    ),
                  const Divider(),
                  _amountRow(
                    'Materiales principales',
                    calculation.cost.primaryMaterials,
                  ),
                  _amountRow(
                    'Hilo (${calculation.rules.threadPercentage.toPercentString()}%)',
                    calculation.cost.thread,
                  ),
                  _amountRow(
                    'Desperdicio (${calculation.rules.wastePercentage.toPercentString()}%)',
                    calculation.cost.waste,
                  ),
                  _amountRow(
                    'Complementarios',
                    calculation.cost.complementaryMaterials,
                  ),
                  const Divider(),
                  _amountRow(
                    'Costo total',
                    calculation.cost.totalCost,
                    strong: true,
                  ),
                ],
              ),
              if (bundle.product.notes != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Notas', style: Theme.of(context).textTheme.titleMedium),
                Text(bundle.product.notes!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onCreateQuote != null)
          TextButton.icon(
            key: const Key('create-quote-from-product'),
            onPressed: () {
              Navigator.pop(context);
              widget.onCreateQuote!(bundle);
            },
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Crear presupuesto'),
          ),
        TextButton.icon(
          onPressed: () => _delete(bundle),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Eliminar'),
        ),
        TextButton.icon(
          onPressed: () => _toggle(bundle),
          icon: Icon(
            bundle.product.isActive
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
          ),
          label: Text(bundle.product.isActive ? 'Desactivar' : 'Activar'),
        ),
        TextButton.icon(
          onPressed: () => _duplicate(bundle),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Duplicar'),
        ),
        FilledButton.icon(
          onPressed: () => _edit(bundle),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar'),
        ),
      ],
    );
  }

  Widget _amountRow(String label, Money amount, {bool strong = false}) =>
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
              ArgentineNumberFormatter.money(amount),
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                color: strong ? AppColors.success : null,
              ),
            ),
          ],
        ),
      );

  Widget _resultValue(String label, Money amount) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          ArgentineNumberFormatter.money(amount),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: AppColors.success),
        ),
      ],
    ),
  );

  Future<void> _edit(ProductBundle bundle) async {
    final saved = await showProductEditor(
      context: context,
      controller: widget.controller,
      bundle: bundle,
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _duplicate(ProductBundle bundle) async {
    await widget.controller.duplicate(bundle);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Producto duplicado.')));
  }

  Future<void> _toggle(ProductBundle bundle) async {
    await widget.controller.setProductActive(bundle, !bundle.product.isActive);
    if (mounted) setState(() {});
  }

  Future<void> _delete(ProductBundle bundle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este producto?'),
        content: const Text(
          'Se quitará del catálogo local. Tus materias primas no se modificarán.',
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
    await widget.controller.deleteProduct(bundle);
    if (mounted) Navigator.pop(context);
  }
}

Future<void> showProductCategoryManager({
  required BuildContext context,
  required ProductsController controller,
}) => showDialog<void>(
  context: context,
  builder: (context) => _ProductCategoryManager(controller: controller),
);

final class _ProductCategoryManager extends StatefulWidget {
  const _ProductCategoryManager({required this.controller});

  final ProductsController controller;

  @override
  State<_ProductCategoryManager> createState() =>
      _ProductCategoryManagerState();
}

final class _ProductCategoryManagerState
    extends State<_ProductCategoryManager> {
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Categorías de productos'),
    content: SizedBox(
      width: 520,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final category in widget.controller.categories)
            ListTile(
              title: Text(category.name),
              trailing: Wrap(
                children: [
                  IconButton(
                    onPressed: () => _rename(category),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: () => _delete(category),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      FilledButton.icon(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Agregar'),
      ),
    ],
  );

  Future<String?> _askName(String title, [String initial = '']) async {
    final input = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    input.dispose();
    return value;
  }

  Future<void> _add() async {
    final name = await _askName('Nueva categoría');
    if (name == null || name.isEmpty) return;
    try {
      await widget.controller.addCategory(name);
      if (mounted) setState(() {});
    } on DuplicateProductCategoryException {
      _message('Ya existe una categoría con ese nombre.');
    }
  }

  Future<void> _rename(ProductCategory category) async {
    final name = await _askName('Renombrar categoría', category.name);
    if (name == null || name.isEmpty) return;
    try {
      await widget.controller.renameCategory(category, name);
      if (mounted) setState(() {});
    } on DuplicateProductCategoryException {
      _message('Ya existe una categoría con ese nombre.');
    }
  }

  Future<void> _delete(ProductCategory category) async {
    try {
      await widget.controller.deleteCategory(category);
      if (mounted) setState(() {});
    } on ProductCategoryInUseException {
      _message(
        'Esta categoría está usada por un producto y no se puede eliminar.',
      );
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
