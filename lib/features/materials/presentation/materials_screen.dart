import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_empty_state.dart';
import '../../../core/design_system/components/status_pill.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/repositories/material_catalog_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../application/materials_controller.dart';
import 'material_display.dart';
import 'material_editor_dialog.dart';

enum MaterialStatusFilter { active, inactive, all }

extension on MaterialStatusFilter {
  String get label => switch (this) {
    MaterialStatusFilter.active => 'Activos',
    MaterialStatusFilter.inactive => 'Inactivos',
    MaterialStatusFilter.all => 'Todos',
  };
}

final class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({
    required this.controller,
    super.key,
    this.currency = 'ARS',
    this.createRequested = false,
    this.onCreateRequestConsumed,
  });

  final MaterialsController controller;
  final String currency;
  final bool createRequested;
  final VoidCallback? onCreateRequestConsumed;

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

final class _MaterialsScreenState extends State<MaterialsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  MaterialStatusFilter _status = MaterialStatusFilter.active;
  String? _categoryId;
  MeasurementDimension? _dimension;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
    _scheduleRequestedCreation();
  }

  @override
  void didUpdateWidget(MaterialsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.createRequested && !oldWidget.createRequested) {
      _scheduleRequestedCreation();
    }
  }

  void _scheduleRequestedCreation() {
    if (!widget.createRequested) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCreateRequestConsumed?.call();
      _addMaterial();
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
          _addMaterial,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
          _searchFocus.requestFocus(),
    },
    child: FocusTraversalGroup(
      child: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final filtered = _filteredMaterials();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                _buildFilters(context),
                if (widget.controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      widget.controller.errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                Expanded(child: _buildContent(context, filtered)),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Materias primas',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${widget.controller.activeCount} activas',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    final categoryButton = OutlinedButton.icon(
      onPressed: _manageCategories,
      icon: const Icon(Icons.category_outlined),
      label: const Text('Categorías'),
    );
    final addButton = FilledButton.icon(
      onPressed: _addMaterial,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Agregar'),
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
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 330
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            categoryButton,
                            const SizedBox(height: AppSpacing.sm),
                            addButton,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: categoryButton),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: addButton),
                          ],
                        ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                categoryButton,
                const SizedBox(width: AppSpacing.sm),
                addButton,
              ],
            ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1100;
    final search = TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, color, categoría o proveedor',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final status = DropdownButtonFormField<MaterialStatusFilter>(
      isExpanded: true,
      initialValue: _status,
      decoration: const InputDecoration(labelText: 'Estado'),
      items: [
        for (final value in MaterialStatusFilter.values)
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
    final dimension = DropdownButtonFormField<MeasurementDimension?>(
      isExpanded: true,
      initialValue: _dimension,
      decoration: const InputDecoration(labelText: 'Forma de compra'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todas')),
        for (final value in MeasurementDimension.values)
          DropdownMenuItem(value: value, child: Text(value.label)),
      ],
      onChanged: (value) => setState(() => _dimension = value),
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
                  dimension,
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
                  SizedBox(width: 180, child: dimension),
                ],
              ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<MaterialBundle> filtered) {
    if (widget.controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.controller.materials.isEmpty) {
      return AppEmptyState(
        icon: Icons.spa_rounded,
        title: 'No cargaste materias primas todavía',
        message: 'Agregá cordones, cueros, cierres y otros materiales para empezar a calcular tus costos.',
        actionLabel: 'Agregar materia prima',
        onAction: _addMaterial,
      );
    }
    if (filtered.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No encontramos coincidencias',
        message: 'Probá cambiar la búsqueda o quitar algún filtro.',
      );
    }

    final compact = MediaQuery.sizeOf(context).width < 900;
    return compact
        ? ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _MaterialCard(
              bundle: filtered[index],
              controller: widget.controller,
              onTap: () => _showDetail(filtered[index]),
            ),
          )
        : _DesktopMaterialList(
            materials: filtered,
            controller: widget.controller,
            onOpen: _showDetail,
          );
  }

  List<MaterialBundle> _filteredMaterials() {
    final query = _searchController.text.trim().toLowerCase();
    return widget.controller.materials
        .where((bundle) {
          final material = bundle.material;
          final statusMatches = switch (_status) {
            MaterialStatusFilter.active => material.isActive,
            MaterialStatusFilter.inactive => !material.isActive,
            MaterialStatusFilter.all => true,
          };
          if (!statusMatches) return false;
          if (_categoryId != null && material.categoryId != _categoryId) {
            return false;
          }
          final unit = widget.controller.unitById(
            material.purchase.quantity.unitId,
          );
          if (_dimension != null && unit?.dimension != _dimension) return false;
          if (query.isEmpty) return true;
          final category =
              widget.controller.categoryById(material.categoryId)?.name ?? '';
          final searchable = [
            material.name,
            material.brandOrSupplier ?? '',
            category,
            ...bundle.variants.map((variant) => variant.name),
          ].join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _addMaterial() async {
    final saved = await showMaterialEditor(
      context: context,
      controller: widget.controller,
      currency: widget.currency,
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Materia prima guardada.')));
    }
  }

  Future<void> _showDetail(MaterialBundle bundle) async {
    await showMaterialDetail(
      context: context,
      controller: widget.controller,
      bundle: bundle,
      currency: widget.currency,
    );
  }

  Future<void> _manageCategories() async {
    await showCategoryManager(context: context, controller: widget.controller);
    if (mounted) setState(() {});
  }
}

final class _MaterialCard extends StatelessWidget {
  const _MaterialCard({
    required this.bundle,
    required this.controller,
    required this.onTap,
  });

  final MaterialBundle bundle;
  final MaterialsController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final material = bundle.material;
    final category =
        controller.categoryById(material.categoryId)?.name ?? 'Sin categoría';
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: material.isActive
                  ? AppColors.terracottaSoft
                  : AppColors.softSurface,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              Icons.spa_rounded,
              color: material.isActive
                  ? AppColors.terracottaDark
                  : AppColors.mutedInk,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        material.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!material.isActive)
                      const StatusPill(
                        label: 'Inactiva',
                        icon: Icons.pause_circle_outline_rounded,
                        color: AppColors.mutedInk,
                        backgroundColor: AppColors.softSurface,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(category),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  unitCostLabel(
                    material.purchase,
                    material.consumptionUnitId,
                    controller,
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (bundle.variants.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${bundle.variants.length} ${bundle.variants.length == 1 ? 'variante' : 'variantes'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

final class _DesktopMaterialList extends StatelessWidget {
  const _DesktopMaterialList({
    required this.materials,
    required this.controller,
    required this.onOpen,
  });

  final List<MaterialBundle> materials;
  final MaterialsController controller;
  final ValueChanged<MaterialBundle> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _DesktopHeaderRow(),
          const Divider(),
          Expanded(
            child: ListView.separated(
              itemCount: materials.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) => _DesktopMaterialRow(
                bundle: materials[index],
                controller: controller,
                onTap: () => onOpen(materials[index]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _DesktopHeaderRow extends StatelessWidget {
  const _DesktopHeaderRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text('Materia prima')),
        Expanded(flex: 2, child: Text('Categoría')),
        Expanded(flex: 2, child: Text('Presentación')),
        Expanded(flex: 2, child: Text('Costo unitario')),
        SizedBox(width: 92, child: Text('Estado')),
        SizedBox(width: 40),
      ],
    ),
  );
}

final class _DesktopMaterialRow extends StatelessWidget {
  const _DesktopMaterialRow({
    required this.bundle,
    required this.controller,
    required this.onTap,
  });

  final MaterialBundle bundle;
  final MaterialsController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final material = bundle.material;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    material.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (bundle.variants.isNotEmpty)
                    Text('${bundle.variants.length} variantes'),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                controller.categoryById(material.categoryId)?.name ?? '—',
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(presentationLabel(material.purchase, controller)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                unitCostLabel(
                  material.purchase,
                  material.consumptionUnitId,
                  controller,
                ),
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(material.isActive ? 'Activa' : 'Inactiva'),
            ),
            const SizedBox(width: 40, child: Icon(Icons.chevron_right_rounded)),
          ],
        ),
      ),
    );
  }
}

Future<void> showMaterialDetail({
  required BuildContext context,
  required MaterialsController controller,
  required MaterialBundle bundle,
  String currency = 'ARS',
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _MaterialDetailDialog(
      controller: controller,
      bundle: bundle,
      parentContext: context,
      currency: currency,
    ),
  );
}

final class _MaterialDetailDialog extends StatelessWidget {
  const _MaterialDetailDialog({
    required this.controller,
    required this.bundle,
    required this.parentContext,
    required this.currency,
  });

  final MaterialsController controller;
  final MaterialBundle bundle;
  final BuildContext parentContext;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final material = bundle.material;
    final category =
        controller.categoryById(material.categoryId)?.name ?? 'Sin categoría';
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: const Text('Detalle de materia prima'),
            actions: [
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  material.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Text(category),
                    if (!material.isActive) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const StatusPill(
                        label: 'Inactiva',
                        icon: Icons.pause_circle_outline_rounded,
                        color: AppColors.mutedInk,
                        backgroundColor: AppColors.softSurface,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    children: [
                      _DetailRow(
                        label: 'Precio de compra',
                        value: presentationLabel(
                          material.purchase,
                          controller,
                        ).split(' · ').last,
                      ),
                      const Divider(height: AppSpacing.xl),
                      _DetailRow(
                        label: 'Presentación',
                        value: presentationLabel(
                          material.purchase,
                          controller,
                        ).split(' · ').first,
                      ),
                      const Divider(height: AppSpacing.xl),
                      _DetailRow(
                        label: 'Costo unitario',
                        value: unitCostLabel(
                          material.purchase,
                          material.consumptionUnitId,
                          controller,
                        ),
                        emphasized: true,
                      ),
                      if (material.brandOrSupplier != null) ...[
                        const Divider(height: AppSpacing.xl),
                        _DetailRow(
                          label: 'Marca o proveedor',
                          value: material.brandOrSupplier!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (bundle.variants.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Variantes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final variant in bundle.variants)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    variant.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  if (variant.purchaseOverride != null) ...[
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      presentationLabel(
                                        variant.purchaseOverride!,
                                        controller,
                                      ),
                                    ),
                                    Text(
                                      unitCostLabel(
                                        variant.purchaseOverride!,
                                        material.consumptionUnitId,
                                        controller,
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!variant.isActive) const Text('Inactiva'),
                          ],
                        ),
                      ),
                    ),
                ],
                if (material.description != null || material.notes != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Text(material.notes ?? material.description ?? ''),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _delete(context),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Eliminar'),
                  ),
                  OutlinedButton(
                    onPressed: () => _toggle(context),
                    child: Text(material.isActive ? 'Desactivar' : 'Activar'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Editar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    Navigator.pop(context);
    final saved = await showMaterialEditor(
      context: parentContext,
      controller: controller,
      bundle: bundle,
      currency: currency,
    );
    if (saved && parentContext.mounted) {
      ScaffoldMessenger.of(parentContext)
          .showSnackBar(const SnackBar(content: Text('Cambios guardados.')));
    }
  }

  Future<void> _toggle(BuildContext context) async {
    await controller.setMaterialActive(bundle, !bundle.material.isActive);
    if (context.mounted) Navigator.pop(context);
    if (parentContext.mounted) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(
          content: Text(
            bundle.material.isActive
                ? 'Materia prima desactivada.'
                : 'Materia prima activada.',
          ),
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar esta materia prima?'),
        content: const Text(
          'Dejará de aparecer en la aplicación. Para conservarla sin usarla, elegí Desactivar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.deleteMaterial(bundle);
    } on MaterialInUseException {
      if (parentContext.mounted) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta materia prima está usada por un producto. Desactivala para conservar los cálculos.',
            ),
          ),
        );
      }
      return;
    }
    if (context.mounted) Navigator.pop(context);
    if (parentContext.mounted) {
      ScaffoldMessenger.of(
        parentContext,
      ).showSnackBar(const SnackBar(content: Text('Materia prima eliminada.')));
    }
  }
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      const SizedBox(width: AppSpacing.md),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: emphasized ? AppColors.success : null),
        ),
      ),
    ],
  );
}

Future<void> showCategoryManager({
  required BuildContext context,
  required MaterialsController controller,
}) => showDialog<void>(
  context: context,
  builder: (context) => _CategoryManagerDialog(controller: controller),
);

final class _CategoryManagerDialog extends StatelessWidget {
  const _CategoryManagerDialog({required this.controller});

  final MaterialsController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Categorías'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView.separated(
          shrinkWrap: true,
          itemCount: controller.categories.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final category = controller.categories[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(category.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Renombrar',
                    onPressed: () => _rename(context, category),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: () => _delete(context, category),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      FilledButton.icon(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
    ],
  );

  Future<void> _add(BuildContext context) async {
    final name = await _askName(context, title: 'Nueva categoría');
    if (name == null) return;
    try {
      await controller.addCategory(name);
    } on DuplicateCategoryException {
      if (context.mounted) {
        _showMessage(context, 'Ya existe una categoría con ese nombre.');
      }
    }
  }

  Future<void> _rename(BuildContext context, MaterialCategory category) async {
    final name = await _askName(
      context,
      title: 'Renombrar categoría',
      initialValue: category.name,
    );
    if (name == null || name == category.name) return;
    try {
      await controller.renameCategory(category, name);
    } on DuplicateCategoryException {
      if (context.mounted) {
        _showMessage(context, 'Ya existe una categoría con ese nombre.');
      }
    }
  }

  Future<void> _delete(BuildContext context, MaterialCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar categoría?'),
        content: Text(
          'Se eliminará “${category.name}” si no está siendo utilizada.',
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
    try {
      await controller.deleteCategory(category);
    } on CategoryInUseException {
      if (context.mounted) {
        _showMessage(
          context,
          'Esta categoría tiene materias primas asociadas. Renombrala en lugar de eliminarla.',
        );
      }
    }
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    final formKey = GlobalKey<FormState>();
    final textController = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre'),
            textInputAction: TextInputAction.done,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Ingresá un nombre'
                : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, textController.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, textController.text.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    textController.dispose();
    return result;
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
