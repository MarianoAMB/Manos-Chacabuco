import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/formatting/argentine_number_parser.dart';
import '../../../core/money/decimal_value.dart';
import '../../../domain/settings/app_settings.dart';
import '../../importing/application/historical_import_controller.dart';
import '../../importing/presentation/historical_import_screen.dart';
import '../application/settings_controller.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.controller,
    this.importController,
    this.onOpenProducts,
    super.key,
  });

  final SettingsController controller;
  final HistoricalImportController? importController;
  final VoidCallback? onOpenProducts;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessName;
  late final TextEditingController _currency;
  late final TextEditingController _waste;
  late final TextEditingController _thread;
  late final TextEditingController _retail;
  late final TextEditingController _multiplier;
  late final TextEditingController _minimumWholesale;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _businessName = TextEditingController(text: settings.businessName);
    _currency = TextEditingController(text: settings.currency);
    _waste = TextEditingController(
      text: ArgentineNumberFormatter.decimal(
        DecimalValue.scaled(settings.defaultWastePercentage.scaledValue * 100),
        fractionDigits: 2,
      ),
    );
    _thread = TextEditingController(
      text: ArgentineNumberFormatter.decimal(
        DecimalValue.scaled(settings.defaultThreadPercentage.scaledValue * 100),
        fractionDigits: 2,
      ),
    );
    _retail = TextEditingController(
      text: settings.defaultRetailPercentage == null
          ? ''
          : ArgentineNumberFormatter.decimal(
              DecimalValue.scaled(
                settings.defaultRetailPercentage!.scaledValue * 100,
              ),
              fractionDigits: 2,
            ),
    );
    _multiplier = TextEditingController(
      text: settings.defaultProductMultiplier == null
          ? ''
          : ArgentineNumberFormatter.decimal(
              settings.defaultProductMultiplier!,
              fractionDigits: 3,
            ),
    );
    _minimumWholesale = TextEditingController(
      text: settings.minimumWholesaleAmount == null
          ? ''
          : ArgentineNumberFormatter.moneyAmount(
              settings.minimumWholesaleAmount!,
            ),
    );
  }

  @override
  void dispose() {
    _businessName.dispose();
    _currency.dispose();
    _waste.dispose();
    _thread.dispose();
    _retail.dispose();
    _multiplier.dispose();
    _minimumWholesale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600
              ? AppSpacing.md
              : AppSpacing.xl,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(isSaving: widget.controller.isSaving),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Datos del negocio',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ResponsiveFields(
                          children: [
                            TextFormField(
                              controller: _businessName,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del negocio',
                                prefixIcon: Icon(Icons.storefront_rounded),
                              ),
                              textInputAction: TextInputAction.next,
                              validator: _required,
                            ),
                            TextFormField(
                              controller: _currency,
                              decoration: const InputDecoration(
                                labelText: 'Moneda',
                                helperText:
                                    'Código de tres letras, por ejemplo ARS',
                                prefixIcon: Icon(Icons.payments_rounded),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 3,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  RegExp(r'^[A-Za-z]{3}$')
                                      .hasMatch(value?.trim() ?? '')
                                  ? null
                                  : 'Ingresá un código de tres letras',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.importController != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Importación inicial',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'Revisá e importá la planilla histórica de Manos Chacabuco sin reemplazar tus cambios locales.',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: const Key('open-historical-import'),
                              onPressed: _openImport,
                              icon: const Icon(Icons.table_view_rounded),
                              label: const Text('Importar planilla histórica'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Cálculos y precios',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Estos valores se proponen automáticamente. Más adelante '
                          'podrás cambiarlos en productos o presupuestos puntuales.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ResponsiveFields(
                          children: [
                            _PercentageField(
                              controller: _waste,
                              label: 'Desperdicio predeterminado',
                              helper: 'Valor inicial confirmado: 1,5 %',
                              validator: (value) => _percentageValidator(
                                value,
                                required: true,
                                max: 100,
                              ),
                            ),
                            _PercentageField(
                              controller: _thread,
                              label: 'Hilo sobre materia prima',
                              helper:
                                  'Se calcula sobre el costo de los materiales',
                              validator: (value) => _percentageValidator(
                                value,
                                required: true,
                                max: 100,
                              ),
                            ),
                            _PercentageField(
                              controller: _retail,
                              label: 'Porcentaje minorista predeterminado',
                              helper: 'Podés dejarlo vacío hasta definirlo',
                              validator: (value) => _percentageValidator(
                                value,
                                required: false,
                                max: 1000,
                              ),
                            ),
                            TextFormField(
                              controller: _multiplier,
                              decoration: const InputDecoration(
                                labelText:
                                    'Multiplicador inicial para productos',
                                helperText: 'Se usará como valor inicial. Después podrás cambiarlo en cada producto.',
                                prefixIcon: Icon(Icons.close_rounded),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.next,
                              validator: _multiplierValidator,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _minimumWholesale,
                          decoration: const InputDecoration(
                            labelText: 'Monto mínimo de compra mayorista',
                            helperText: 'Podés cambiarlo cuando quieras.',
                            prefixText: r'$ ',
                            prefixIcon: Icon(Icons.local_mall_rounded),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _save(),
                          validator: _moneyValidator,
                        ),
                      ],
                    ),
                  ),
                  if (widget.controller.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      widget.controller.errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: widget.controller.isSaving ? null : _save,
                      icon: widget.controller.isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        widget.controller.isSaving
                            ? 'Guardando…'
                            : 'Guardar cambios',
                      ),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final retail = _retail.text.trim().isEmpty
        ? null
        : DecimalValue.percent(
            ArgentineNumberParser.parseDecimal(_retail.text)
                .toDecimalString(fractionDigits: 6),
          );
    final multiplier = _multiplier.text.trim().isEmpty
        ? null
        : ArgentineNumberParser.parseDecimal(_multiplier.text);
    final minimum = _minimumWholesale.text.trim().isEmpty
        ? null
        : ArgentineNumberParser.parseMoney(
            _minimumWholesale.text,
            currency: _currency.text.trim().toUpperCase(),
          );
    final settings = AppSettings(
      businessName: _businessName.text.trim(),
      currency: _currency.text.trim().toUpperCase(),
      defaultWastePercentage: DecimalValue.percent(
        ArgentineNumberParser.parseDecimal(_waste.text)
            .toDecimalString(fractionDigits: 6),
      ),
      defaultThreadPercentage: DecimalValue.percent(
        ArgentineNumberParser.parseDecimal(_thread.text)
            .toDecimalString(fractionDigits: 6),
      ),
      defaultRetailPercentage: retail,
      defaultProductMultiplier: multiplier,
      minimumWholesaleAmount: minimum,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await widget.controller.save(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuración guardada.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.errorMessage ?? 'No se guardó.'),
        ),
      );
    }
  }

  Future<void> _openImport() async {
    final controller = widget.importController;
    if (controller == null) return;
    final openProducts = await showHistoricalImportScreen(
      context: context,
      controller: controller,
    );
    if (openProducts && mounted) widget.onOpenProducts?.call();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Este campo es necesario' : null;

  String? _percentageValidator(
    String? value, {
    required bool required,
    required int max,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Ingresá un porcentaje' : null;
    final parsed = ArgentineNumberParser.tryParseDecimal(text);
    if (parsed == null) return 'Ingresá un número válido, por ejemplo 1,5';
    if (parsed.scaledValue < 0 ||
        parsed.scaledValue > max * DecimalValue.scale) {
      return 'Ingresá un valor entre 0 y $max';
    }
    return null;
  }

  String? _multiplierValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = ArgentineNumberParser.tryParseDecimal(text);
    if (parsed == null) return 'Ingresá un número válido, por ejemplo 2,4';
    if (parsed.scaledValue <= 0 ||
        parsed.scaledValue > 100 * DecimalValue.scale) {
      return 'Ingresá un valor mayor que 0 y menor que 100';
    }
    return null;
  }

  String? _moneyValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = ArgentineNumberParser.tryParseMoney(text);
    if (parsed == null) return 'Ingresá un importe válido';
    return parsed.minorUnits < 0 ? 'El importe no puede ser negativo' : null;
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.isSaving});

  final bool isSaving;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('Ajustá las reglas generales de tu negocio.'),
          ],
        ),
      ),
      if (!isSaving)
        const Icon(Icons.cloud_done_rounded, color: AppColors.success),
    ],
  );
}

final class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 680) {
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
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final child in children)
            SizedBox(
              width: (constraints.maxWidth - AppSpacing.md) / 2,
              child: child,
            ),
        ],
      );
    },
  );
}

final class _PercentageField extends StatelessWidget {
  const _PercentageField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      suffixText: '%',
      prefixIcon: const Icon(Icons.percent_rounded),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    validator: validator,
  );
}
