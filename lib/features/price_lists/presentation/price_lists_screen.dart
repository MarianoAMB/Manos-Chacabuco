import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_empty_state.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../domain/price_lists/price_list_models.dart';
import '../application/price_lists_controller.dart';
import 'price_list_preview.dart';

final class PriceListsScreen extends StatefulWidget {
  const PriceListsScreen({
    required this.controller,
    required this.onOpenProducts,
    required this.onOpenSettings,
    super.key,
  });

  final PriceListsController controller;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenSettings;

  @override
  State<PriceListsScreen> createState() => _PriceListsScreenState();
}

final class _PriceListsScreenState extends State<PriceListsScreen> {
  final _search = TextEditingController();
  final _footer = TextEditingController();
  String? _filterCategoryId;

  @override
  void dispose() {
    _search.dispose();
    _footer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final config = widget.controller.config;
        if (config == null) return _landing(context);
        return _draft(context, config);
      },
    ),
  );

  Widget _landing(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 600 ? AppSpacing.md : AppSpacing.xl,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Listas de precios',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Prepará un catálogo comercial con los precios actuales de tus productos.',
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 680;
                final cards = [
                  _TypeCard(
                    key: const Key('create-retail-list'),
                    icon: Icons.storefront_rounded,
                    title: 'Crear lista minorista',
                    description: 'Para clientas finales. Usa el porcentaje minorista configurado.',
                    color: AppColors.terracottaSoft,
                    onTap: () => _start(PriceListType.retail),
                  ),
                  _TypeCard(
                    key: const Key('create-wholesale-list'),
                    icon: Icons.local_mall_rounded,
                    title: 'Crear lista mayorista',
                    description: 'Para comercios. Puede mostrar el monto mínimo de compra.',
                    color: AppColors.sageSoft,
                    onTap: () => _start(PriceListType.wholesale),
                  ),
                ];
                return compact
                    ? Column(
                        children: [
                          cards.first,
                          const SizedBox(height: AppSpacing.md),
                          cards.last,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cards.first),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: cards.last),
                        ],
                      );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              color: AppColors.softSurface,
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, color: AppColors.sage),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'La lista sólo muestra información comercial. Nunca incluye costos, desperdicio, hilo ni multiplicadores.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _draft(BuildContext context, PriceListConfig config) => Padding(
    padding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 600 ? AppSpacing.sm : AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DraftHeader(
          type: config.priceType,
          selectedCount: widget.controller.selectedCount,
          onBack: widget.controller.closeDraft,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1050) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 450,
                      child: SingleChildScrollView(
                        child: _controls(context, config),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: _previewPanel(context)),
                  ],
                );
              }
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _controls(context, config),
                    const SizedBox(height: AppSpacing.lg),
                    _previewPanel(context, embedded: true),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _controls(BuildContext context, PriceListConfig config) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Productos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.controller.selectedCount} seleccionados',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton(
                  key: const Key('select-all-products'),
                  onPressed: widget.controller.selectAll,
                  child: const Text('Seleccionar todos'),
                ),
                TextButton(
                  key: const Key('clear-all-products'),
                  onPressed: widget.controller.clearAll,
                  child: const Text('Quitar todos'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('price-list-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String?>(
              initialValue: _filterCategoryId,
              decoration: const InputDecoration(
                labelText: 'Filtrar productos por categoría',
                prefixIcon: Icon(Icons.filter_list_rounded),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final id in widget.controller.availableCategoryIds)
                  DropdownMenuItem(
                    value: id,
                    child: Text(widget.controller.categoryName(id)),
                  ),
              ],
              onChanged: (value) => setState(() => _filterCategoryId = value),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Incluir categorías',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final id in widget.controller.availableCategoryIds)
                  FilterChip(
                    label: Text(widget.controller.categoryName(id)),
                    selected: config.selectedCategoryIds.contains(id),
                    onSelected: (value) =>
                        widget.controller.toggleCategory(id, value),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 360,
              child: _ProductSelectionList(
                products: _filteredProducts(),
                config: config,
                onChanged: widget.controller.toggleProduct,
              ),
            ),
            if (widget.controller.missingPriceCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.terracottaSoft,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.terracottaDark,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${widget.controller.missingPriceCount} productos no tienen ${config.priceType == PriceListType.retail ? 'precio minorista' : 'un precio mayorista válido'} y quedan fuera.',
                      ),
                    ),
                    TextButton(
                      onPressed: config.priceType == PriceListType.retail
                          ? widget.onOpenSettings
                          : widget.onOpenProducts,
                      child: const Text('Resolver'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Presentación', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<PriceListSort>(
              key: const Key('price-list-sort'),
              initialValue: config.sort,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Orden',
                prefixIcon: Icon(Icons.sort_rounded),
              ),
              items: [
                for (final value in PriceListSort.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      value.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) widget.controller.setSort(value);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _OptionSwitch(
              key: const Key('show-photos'),
              title: 'Mostrar fotos',
              value: config.showPhotos,
              onChanged: widget.controller.setShowPhotos,
            ),
            _OptionSwitch(
              title: 'Mostrar productos sin foto',
              value: config.showProductsWithoutPhoto,
              onChanged: widget.controller.setShowProductsWithoutPhoto,
            ),
            _OptionSwitch(
              key: const Key('show-dimensions'),
              title: 'Mostrar medidas',
              value: config.showDimensions,
              onChanged: widget.controller.setShowDimensions,
            ),
            _OptionSwitch(
              key: const Key('show-material'),
              title: 'Mostrar material principal',
              value: config.showMaterial,
              onChanged: widget.controller.setShowMaterial,
            ),
            _OptionSwitch(
              key: const Key('group-by-category'),
              title: 'Agrupar por categoría',
              value: config.groupByCategory,
              onChanged: widget.controller.setGroupByCategory,
            ),
            _OptionSwitch(
              title: 'Mostrar fecha de actualización',
              value: config.showUpdatedDate,
              onChanged: widget.controller.setShowUpdatedDate,
            ),
            if (config.priceType == PriceListType.wholesale)
              _OptionSwitch(
                key: const Key('show-wholesale-minimum'),
                title: 'Mostrar mínimo mayorista',
                value: config.showWholesaleMinimum,
                onChanged: widget.controller.setShowWholesaleMinimum,
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('price-list-footer-note'),
              controller: _footer,
              onChanged: widget.controller.setFooterNote,
              maxLength: 160,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota al pie (opcional)',
                hintText: 'Ej.: Consultar colores disponibles.',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _previewPanel(BuildContext context, {bool embedded = false}) {
    final document = widget.controller.preview;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vista previa',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text('Así quedará la lista que vas a compartir.'),
                ],
              ),
            ),
            if (widget.controller.isBusy)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            FilledButton.icon(
              key: const Key('export-price-list'),
              onPressed: _canExport ? _export : null,
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Exportar'),
            ),
          ],
        ),
        if (widget.controller.status != PriceListWorkStatus.idle) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_progressLabel(widget.controller.status)),
        ],
        if (widget.controller.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.controller.errorMessage!,
            style: const TextStyle(color: AppColors.danger),
          ),
        ],
        if (widget.controller.successMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.sageSoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.controller.successMessage!),
                if (widget.controller.lastSavedPaths.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    widget.controller.lastSavedPaths.first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (Platform.isWindows)
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        TextButton.icon(
                          onPressed: widget.controller.openLastFile,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Abrir archivo'),
                        ),
                        TextButton.icon(
                          onPressed: widget.controller.openLastFolder,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Abrir carpeta'),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (document != null) PriceListPreview(document: document),
      ],
    );
    if (embedded) return AppCard(child: content);
    return AppCard(child: SingleChildScrollView(child: content));
  }

  bool get _canExport =>
      widget.controller.selectedCount > 0 && !widget.controller.isBusy;

  List<PriceListSourceProduct> _filteredProducts() {
    final search = _search.text.trim().toLowerCase();
    final result = widget.controller.products.where((source) {
      if (!source.isActive) return false;
      if (_filterCategoryId != null && source.categoryId != _filterCategoryId) {
        return false;
      }
      return search.isEmpty || source.name.toLowerCase().contains(search);
    }).toList();
    result.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return result;
  }

  Future<void> _start(PriceListType type) async {
    await widget.controller.start(type);
    if (!mounted) return;
    _footer.text = widget.controller.config?.footerNote ?? '';
    _filterCategoryId = null;
    _search.clear();
  }

  Future<void> _share() async {
    final selected = await showModalBottomSheet<_ShareChoice>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Qué querés compartir?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('PDF'),
              subtitle: const Text('Ideal para email e impresión.'),
              onTap: () => Navigator.pop(context, _ShareChoice.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.image_rounded),
              title: const Text('Imágenes'),
              subtitle: const Text('Se comparten todas las páginas juntas.'),
              onTap: () => Navigator.pop(context, _ShareChoice.images),
            ),
          ],
        ),
      ),
    );
    if (selected == _ShareChoice.pdf) await widget.controller.sharePdf();
    if (selected == _ShareChoice.images) await widget.controller.shareImages();
  }

  Future<void> _export() async {
    final style = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Cómo querés presentar la lista?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              key: const Key('export-style-photos'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Con fotos'),
              subtitle: const Text(
                'Catálogo visual con una foto por producto.',
              ),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              key: const Key('export-style-no-photos'),
              leading: const Icon(Icons.view_column_outlined),
              title: const Text('Sin fotos'),
              subtitle: const Text('Lista editorial de dos columnas.'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (style == null || !mounted) return;
    await widget.controller.selectExportStyle(style);
    if (!mounted) return;
    final action = await showModalBottomSheet<_ExportChoice>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              style ? 'Exportar con fotos' : 'Exportar sin fotos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              key: const Key('export-price-list-pdf'),
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('PDF'),
              onTap: () => Navigator.pop(context, _ExportChoice.pdf),
            ),
            ListTile(
              key: const Key('export-price-list-images'),
              leading: const Icon(Icons.image_rounded),
              title: const Text('Exportar imágenes'),
              onTap: () => Navigator.pop(context, _ExportChoice.images),
            ),
            if (Platform.isAndroid)
              ListTile(
                key: const Key('share-price-list'),
                leading: const Icon(Icons.share_rounded),
                title: const Text('Compartir'),
                onTap: () => Navigator.pop(context, _ExportChoice.share),
              ),
          ],
        ),
      ),
    );
    if (action == _ExportChoice.pdf) {
      await widget.controller.exportPdf(askLocation: Platform.isWindows);
    }
    if (action == _ExportChoice.images) {
      await widget.controller.exportImages(askLocation: Platform.isWindows);
    }
    if (action == _ExportChoice.share) await _share();
  }

  String _progressLabel(PriceListWorkStatus status) => switch (status) {
    PriceListWorkStatus.loading => 'Preparando lista…',
    PriceListWorkStatus.generatingPdf => 'Generando PDF…',
    PriceListWorkStatus.generatingImages => 'Generando imágenes…',
    PriceListWorkStatus.sharing => 'Preparando archivos para compartir…',
    PriceListWorkStatus.idle => '',
  };
}

enum _ShareChoice { pdf, images }

enum _ExportChoice { pdf, images, share }

final class _ProductSelectionList extends StatelessWidget {
  const _ProductSelectionList({
    required this.products,
    required this.config,
    required this.onChanged,
  });

  final List<PriceListSourceProduct> products;
  final PriceListConfig config;
  final void Function(PriceListSourceProduct, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No encontramos productos',
        message: 'Probá otra búsqueda o categoría.',
      );
    }
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final source = products[index];
        final eligible = source.isEligibleFor(config.priceType);
        final price = source.priceFor(config.priceType);
        return CheckboxListTile(
          key: Key('price-list-product-${source.productId}'),
          value:
              eligible && config.selectedProductIds.contains(source.productId),
          onChanged: eligible
              ? (value) => onChanged(source, value ?? false)
              : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            source.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            eligible
                ? source.categoryName
                : config.priceType == PriceListType.retail
                ? 'Sin precio minorista'
                : 'Sin precio mayorista',
            style: !eligible ? const TextStyle(color: AppColors.warning) : null,
          ),
          secondary: Text(
            price == null || price.minorUnits <= 0
                ? '—'
                : ArgentineNumberFormatter.commercialMoney(price),
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}

final class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: onChanged,
  );
}

final class _DraftHeader extends StatelessWidget {
  const _DraftHeader({
    required this.type,
    required this.selectedCount,
    required this.onBack,
  });

  final PriceListType type;
  final int selectedCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Volver',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.title, style: Theme.of(context).textTheme.headlineSmall),
            Text('$selectedCount productos listos para exportar'),
          ],
        ),
      ),
    ],
  );
}

final class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    color: color,
    borderColor: color,
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 42, color: AppColors.terracottaDark),
        const SizedBox(height: AppSpacing.lg),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(description),
        const SizedBox(height: AppSpacing.lg),
        const Align(
          alignment: Alignment.centerRight,
          child: Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
  );
}
