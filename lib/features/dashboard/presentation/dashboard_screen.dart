import 'package:flutter/material.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_section_header.dart';
import '../../../core/design_system/components/status_pill.dart';
import '../../materials/application/materials_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../../products/application/products_controller.dart';
import '../../quotes/application/quotes_controller.dart';

final class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.settingsController,
    required this.materialsController,
    required this.onOpenDestination,
    required this.onAddMaterial,
    required this.productsController,
    required this.onAddProduct,
    required this.quotesController,
    required this.onAddQuote,
    super.key,
  });

  final SettingsController settingsController;
  final MaterialsController materialsController;
  final ValueChanged<AppDestination> onOpenDestination;
  final VoidCallback onAddMaterial;
  final ProductsController productsController;
  final VoidCallback onAddProduct;
  final QuotesController quotesController;
  final VoidCallback onAddQuote;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        settingsController,
        materialsController,
        productsController,
        quotesController,
      ]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 600
              ? AppSpacing.md
              : AppSpacing.xl;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.lg,
              horizontalPadding,
              AppSpacing.xxl,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      businessName: settingsController.settings.businessName,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _WelcomeCard(
                      activeMaterials: materialsController.activeCount,
                      onAddMaterial: onAddMaterial,
                      activeProducts: productsController.activeCount,
                      onAddProduct: onAddProduct,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const AppSectionHeader(
                      title: '¿Qué querés hacer?',
                      subtitle: 'Todo lo importante, a un toque de distancia.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ActionGrid(onOpen: onOpenDestination),
                    const SizedBox(height: AppSpacing.xl),
                    _MaterialsSummary(
                      controller: materialsController,
                      onOpen: () => onOpenDestination(AppDestination.materials),
                      onAdd: onAddMaterial,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ProductsSummary(
                      controller: productsController,
                      onOpen: () => onOpenDestination(AppDestination.products),
                      onAdd: onAddProduct,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _QuotesSummary(
                      controller: quotesController,
                      onOpen: () => onOpenDestination(AppDestination.quotes),
                      onAdd: onAddQuote,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SettingsSummary(
                      settingsController: settingsController,
                      onOpen: () => onOpenDestination(AppDestination.settings),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

final class _QuotesSummary extends StatelessWidget {
  const _QuotesSummary({
    required this.controller,
    required this.onOpen,
    required this.onAdd,
  });

  final QuotesController controller;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => AppCard(
    color: AppColors.terracottaSoft,
    borderColor: AppColors.terracottaSoft,
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(
            Icons.request_quote_outlined,
            color: AppColors.terracottaDark,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${controller.currentCount} presupuestos vigentes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                'Las cotizaciones guardadas conservan su precio histórico.',
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Nuevo presupuesto',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        IconButton(
          tooltip: 'Ver presupuestos',
          onPressed: onOpen,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
  );
}

final class _Header extends StatelessWidget {
  const _Header({required this.businessName});

  final String businessName;

  @override
  Widget build(BuildContext context) {
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hola 👋', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.xxs),
        Text(businessName, style: Theme.of(context).textTheme.headlineMedium),
      ],
    );
    const status = StatusPill(
      label: 'Todo funciona sin conexión',
      icon: Icons.cloud_off_rounded,
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 560
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                greeting,
                const SizedBox(height: AppSpacing.sm),
                status,
              ],
            )
          : Row(
              children: [
                Expanded(child: greeting),
                status,
              ],
            ),
    );
  }
}

final class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.activeMaterials,
    required this.onAddMaterial,
    required this.activeProducts,
    required this.onAddProduct,
  });

  final int activeMaterials;
  final VoidCallback onAddMaterial;
  final int activeProducts;
  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) => AppCard(
    color: AppColors.terracottaDark,
    borderColor: AppColors.terracottaDark,
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.lg,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activeMaterials == 0
                    ? 'Empecemos por tus materiales'
                    : 'Tus costos empiezan acá',
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(color: Colors.white, fontSize: 36),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                activeMaterials == 0
                    ? 'Cargá el primer cordón, cuero, cierre o accesorio.'
                    : 'Tenés $activeMaterials ${activeMaterials == 1 ? 'materia prima activa' : 'materias primas activas'} guardadas en este equipo.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: activeMaterials == 0 ? onAddMaterial : onAddProduct,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.terracottaDark,
          ),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            activeMaterials == 0 ? 'Agregar materia prima' : 'Crear producto',
          ),
        ),
      ],
    ),
  );
}

final class _ProductsSummary extends StatelessWidget {
  const _ProductsSummary({
    required this.controller,
    required this.onOpen,
    required this.onAdd,
  });

  final ProductsController controller;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.terracottaSoft,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.terracottaDark,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${controller.activeCount} productos activos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xxs),
              const Text(
                'Costos recalculados con los precios actuales de tus materiales.',
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Crear producto',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        IconButton(
          tooltip: 'Ver productos',
          onPressed: onOpen,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
  );
}

final class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.onOpen});

  final ValueChanged<AppDestination> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 520
          ? 2
          : constraints.maxWidth < 1000
          ? 3
          : 6;
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: columns == 2
            ? 0.8
            : columns >= 6
            ? 0.95
            : 1.1,
        children: [
          for (final destination in AppDestination.values.where(
            (item) => item != AppDestination.home,
          ))
            AppCard(
              onTap: () => onOpen(destination),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.terracottaSoft,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Icon(
                      destination.icon,
                      color: AppColors.terracottaDark,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    destination.label,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text('Abrir'),
                ],
              ),
            ),
        ],
      );
    },
  );
}

final class _MaterialsSummary extends StatelessWidget {
  const _MaterialsSummary({
    required this.controller,
    required this.onOpen,
    required this.onAdd,
  });

  final MaterialsController controller;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.sageSoft,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(Icons.spa_rounded, color: AppColors.sage),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${controller.activeCount} materias primas activas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                controller.materials.isEmpty
                    ? 'Todavía no cargaste materiales.'
                    : 'Precios y presentaciones guardados localmente.',
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Agregar materia prima',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        IconButton(
          tooltip: 'Ver materias primas',
          onPressed: onOpen,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
  );
}

final class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({
    required this.settingsController,
    required this.onOpen,
  });

  final SettingsController settingsController;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final settings = settingsController.settings;
    return AppCard(
      color: AppColors.sageSoft,
      borderColor: AppColors.sageSoft,
      onTap: onOpen,
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: AppColors.sage),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Desperdicio ${settings.defaultWastePercentage.toPercentString()}% · '
              'Hilo ${settings.defaultThreadPercentage.toPercentString()}% · '
              '${settings.currency}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
