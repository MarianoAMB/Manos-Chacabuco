import 'package:flutter/material.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_tokens.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/calculator/presentation/calculator_screen.dart';
import '../../features/materials/application/materials_controller.dart';
import '../../features/importing/application/historical_import_controller.dart';
import '../../features/materials/presentation/materials_screen.dart';
import '../../features/products/application/products_controller.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/quotes/application/quotes_controller.dart';
import '../../features/quotes/presentation/quotes_screen.dart';
import '../../features/settings/application/settings_controller.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shared/presentation/module_placeholder_screen.dart';
import '../navigation/app_destination.dart';

final class AdaptiveAppShell extends StatefulWidget {
  const AdaptiveAppShell({
    required this.settingsController,
    required this.materialsController,
    required this.productsController,
    required this.quotesController,
    this.importController,
    super.key,
  });

  final SettingsController settingsController;
  final MaterialsController materialsController;
  final ProductsController productsController;
  final QuotesController quotesController;
  final HistoricalImportController? importController;

  @override
  State<AdaptiveAppShell> createState() => _AdaptiveAppShellState();
}

final class _AdaptiveAppShellState extends State<AdaptiveAppShell> {
  AppDestination _selected = AppDestination.home;
  bool _createMaterialRequested = false;
  bool _createProductRequested = false;
  bool _createQuoteRequested = false;
  ProductBundle? _initialQuoteProduct;

  void _select(AppDestination destination) {
    if (destination == _selected) return;
    setState(() => _selected = destination);
  }

  void _requestMaterialCreation() {
    setState(() {
      _selected = AppDestination.materials;
      _createMaterialRequested = true;
    });
  }

  void _consumeMaterialCreationRequest() {
    if (_createMaterialRequested) {
      setState(() => _createMaterialRequested = false);
    }
  }

  void _requestProductCreation() {
    setState(() {
      _selected = AppDestination.products;
      _createProductRequested = true;
    });
  }

  void _consumeProductCreationRequest() {
    if (_createProductRequested) {
      setState(() => _createProductRequested = false);
    }
  }

  void _requestQuoteCreation([ProductBundle? product]) {
    setState(() {
      _selected = AppDestination.quotes;
      _initialQuoteProduct = product;
      _createQuoteRequested = true;
    });
  }

  void _consumeQuoteCreationRequest() {
    if (_createQuoteRequested) {
      setState(() {
        _createQuoteRequested = false;
        _initialQuoteProduct = null;
      });
    }
  }

  Widget _currentPage() => switch (_selected) {
    AppDestination.home => DashboardScreen(
      settingsController: widget.settingsController,
      materialsController: widget.materialsController,
      onOpenDestination: _select,
      onAddMaterial: _requestMaterialCreation,
      productsController: widget.productsController,
      onAddProduct: _requestProductCreation,
      quotesController: widget.quotesController,
      onAddQuote: _requestQuoteCreation,
    ),
    AppDestination.materials => MaterialsScreen(
      controller: widget.materialsController,
      currency: widget.settingsController.settings.currency,
      createRequested: _createMaterialRequested,
      onCreateRequestConsumed: _consumeMaterialCreationRequest,
    ),
    AppDestination.products => ProductsScreen(
      controller: widget.productsController,
      createRequested: _createProductRequested,
      onCreateRequestConsumed: _consumeProductCreationRequest,
      onCreateQuote: _requestQuoteCreation,
    ),
    AppDestination.quotes => QuotesScreen(
      controller: widget.quotesController,
      createRequested: _createQuoteRequested,
      initialProduct: _initialQuoteProduct,
      onCreateRequestConsumed: _consumeQuoteCreationRequest,
    ),
    AppDestination.calculator => CalculatorScreen(
      controller: widget.productsController,
    ),
    AppDestination.settings => SettingsScreen(
      controller: widget.settingsController,
      importController: widget.importController,
      onOpenProducts: () => _select(AppDestination.products),
    ),
    final destination => ModulePlaceholderScreen(destination: destination),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isCompact = constraints.maxWidth < AppBreakpoints.compact;
      return isCompact ? _buildCompact(context) : _buildExpanded(context);
    },
  );

  Widget _buildCompact(BuildContext context) {
    final primaryIndex = mobilePrimaryDestinations.indexOf(_selected);
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_selected), child: _currentPage()),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: primaryIndex < 0 ? 4 : primaryIndex,
        onDestinationSelected: (index) {
          if (index == 4) {
            _showMoreDestinations(context);
            return;
          }
          _select(mobilePrimaryDestinations[index]);
        },
        destinations: [
          for (final destination in mobilePrimaryDestinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: _mobileLabel(destination),
            ),
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Más',
          ),
        ],
      ),
    );
  }

  String _mobileLabel(AppDestination destination) => switch (destination) {
    AppDestination.materials => 'Materiales',
    AppDestination.quotes => 'Presup.',
    _ => destination.label,
  };

  Future<void> _showMoreDestinations(BuildContext context) async {
    final destination = await showModalBottomSheet<AppDestination>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                'Más herramientas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final item in const [
              AppDestination.calculator,
              AppDestination.priceLists,
              AppDestination.settings,
            ])
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                selected: _selected == item,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (destination != null) _select(destination);
  }

  Widget _buildExpanded(BuildContext context) {
    final selectedIndex = AppDestination.values.indexOf(_selected);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 256,
            selectedIndex: selectedIndex,
            groupAlignment: -0.78,
            onDestinationSelected: (index) =>
                _select(AppDestination.values[index]),
            leading: const _BusinessMark(),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Lista para trabajar sin conexión',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final destination in AppDestination.values)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_selected),
                child: _currentPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _BusinessMark extends StatelessWidget {
  const _BusinessMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.terracotta,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Text(
              'MC',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Manos\nChacabuco',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(height: 1.05),
            ),
          ),
        ],
      ),
    ),
  );
}
