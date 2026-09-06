import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_info.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_file_image.dart';
import '../../../core/design_system/components/status_pill.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../core/formatting/argentine_number_parser.dart';
import '../../../core/money/decimal_value.dart';
import '../../../core/money/money.dart';
import '../../../domain/settings/app_settings.dart';
import '../../../domain/sync/sync_models.dart';
import '../../importing/application/historical_import_controller.dart';
import '../../importing/presentation/historical_import_screen.dart';
import '../../sync/application/sync_controller.dart';
import '../application/settings_controller.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.controller,
    this.importController,
    this.onOpenProducts,
    this.syncController,
    super.key,
  });

  final SettingsController controller;
  final HistoricalImportController? importController;
  final VoidCallback? onOpenProducts;
  final SyncController? syncController;

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

final class SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessName;
  late final TextEditingController _currency;
  late final TextEditingController _waste;
  late final TextEditingController _thread;
  late final TextEditingController _retail;
  late final TextEditingController _multiplier;
  late final TextEditingController _minimumWholesale;
  bool _dirty = false;

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
    for (final controller in [
      _businessName,
      _currency,
      _waste,
      _thread,
      _retail,
      _multiplier,
      _minimumWholesale,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || !await confirmNavigation() || !mounted) return;
      if (Platform.isAndroid) await SystemNavigator.pop();
    },
    child: SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.controller,
          if (widget.syncController != null) widget.syncController!,
        ]),
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
                    _Header(
                      isSaving: widget.controller.isSaving,
                      hasUnsavedChanges: _dirty,
                    ),
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
                                key: const Key('business-name-field'),
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
                                textCapitalization:
                                    TextCapitalization.characters,
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
                          const SizedBox(height: AppSpacing.lg),
                          _BusinessLogoField(
                            imagePath: widget.controller.logoAbsolutePath,
                            isSaving: widget.controller.isSaving,
                            onSelect: _selectLogo,
                            onRemove: _removeLogo,
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
                                label: const Text(
                                  'Importar planilla histórica',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.syncController != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _SyncCard(
                        controller: widget.syncController!,
                        onConnect: _connectGoogle,
                        onChangeAccount: _changeGoogleAccount,
                        onDisconnect: _disconnectGoogle,
                        onReview: _reviewConflicts,
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
                                helper: 'Se calcula sobre las materias primas principales',
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
                    const SizedBox(height: AppSpacing.md),
                    const AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.terracottaDark,
                          ),
                          SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Acerca de',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: AppSpacing.xxs),
                                Text(
                                  '${AppInfo.name} · Versión ${AppInfo.version}',
                                ),
                              ],
                            ),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
      businessLogoPath: widget.controller.settings.businessLogoPath,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await widget.controller.save(settings);
      if (!mounted) return;
      setState(() => _dirty = false);
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

  Future<void> _connectGoogle() async {
    final controller = widget.syncController;
    if (controller == null) return;
    if (!controller.isConfigured) {
      final configured = await _configureGoogle(controller);
      if (!configured || !mounted) return;
    }
    await controller.connect();
    if (!mounted || controller.account.connected) return;
    if (controller.status == SyncConnectionStatus.error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.statusLabel)));
    }
  }

  Future<bool> _configureGoogle(SyncController controller) async {
    if (!controller.canConfigure) return false;
    final setupInput = await showDialog<String>(
      context: context,
      builder: (context) => _GoogleSetupDialog(isAndroid: Platform.isAndroid),
    );
    if (setupInput == null) return false;
    try {
      await controller.configure(setupInput);
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      final message = switch (error) {
        FormatException(:final message) => message,
        _ => 'No pudimos guardar la configuración de Google.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.toString())));
      return false;
    }
  }

  Future<void> _disconnectGoogle() async {
    final controller = widget.syncController;
    if (controller == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar Google Drive'),
        content: const Text(
          'Tus productos, materias primas y presupuestos seguirán guardados en '
          'este dispositivo. Solamente dejarán de sincronizarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.disconnect();
  }

  Future<void> _changeGoogleAccount() async {
    final controller = widget.syncController;
    if (controller == null || controller.isBusy) return;
    await controller.disconnect();
    if (mounted) await _connectGoogle();
  }

  Future<void> _reviewConflicts() async {
    final controller = widget.syncController;
    if (controller == null || controller.conflicts.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ConflictReviewDialog(controller: controller),
    );
  }

  Future<void> _selectLogo() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Imágenes',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        ),
      ],
    );
    if (file == null) return;
    try {
      await widget.controller.importLogo(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logo guardado.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar el logo.')),
      );
    }
  }

  Future<void> _removeLogo() async {
    try {
      await widget.controller.removeLogo();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logo eliminado.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos eliminar el logo.')),
      );
    }
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

  Future<bool> confirmNavigation() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Tenés cambios sin guardar'),
            content: const Text(
              'Si salís ahora, los cambios de Configuración no se guardarán.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Seguir editando'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Salir sin guardar',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

final class _GoogleSetupDialog extends StatefulWidget {
  const _GoogleSetupDialog({required this.isAndroid});

  final bool isAndroid;

  @override
  State<_GoogleSetupDialog> createState() => _GoogleSetupDialogState();
}

final class _GoogleSetupDialogState extends State<_GoogleSetupDialog> {
  static final _credentialsUri = Uri.parse(
    'https://console.cloud.google.com/apis/credentials',
  );
  final _clientId = TextEditingController();
  bool _openingFile = false;

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _openGoogleCloud() async {
    final opened = await launchUrl(
      _credentialsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened || !mounted) return;
  }

  Future<void> _chooseJson() async {
    if (_openingFile) return;
    setState(() => _openingFile = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Credencial de Google',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final contents = await File(file.path).readAsString();
      if (mounted) Navigator.pop(context, contents);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos leer ese archivo.')),
      );
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  void _continueWithClientId() {
    final value = _clientId.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Activar Google Drive'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Google pide identificar esta app antes del primer ingreso. '
              'Se hace una sola vez y no requiere tu contraseña.',
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.isAndroid) ...[
              const Text(
                'En Google Cloud, registrá la app Android y creá también una '
                'credencial de tipo “Aplicación web”. Después elegí su archivo '
                'JSON o pegá el Client ID.',
              ),
              const SizedBox(height: AppSpacing.xs),
              const SelectableText(
                'App Android: com.manoschacabuco.manos_chacabuco\n'
                'SHA-1: E9:46:4B:5E:AE:05:12:94:E6:3D:97:4C:65:D4:31:FC:8C:30:C9:D4',
                style: TextStyle(color: AppColors.mutedInk),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('google-web-client-id'),
                controller: _clientId,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Client ID de Aplicación web',
                  hintText: '…apps.googleusercontent.com',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _continueWithClientId(),
              ),
              const SizedBox(height: AppSpacing.sm),
            ] else ...[
              const Text(
                'En Google Cloud, creá una credencial de tipo “Aplicación de '
                'escritorio”, descargá su archivo JSON y elegilo acá.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: _openGoogleCloud,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Abrir Google Cloud'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _openingFile ? null : _chooseJson,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(
                    _openingFile ? 'Abriendo…' : 'Elegir archivo JSON',
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
      if (widget.isAndroid)
        FilledButton(
          onPressed: _clientId.text.trim().isEmpty
              ? null
              : _continueWithClientId,
          child: const Text('Continuar'),
        ),
    ],
  );
}

final class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.controller,
    required this.onConnect,
    required this.onChangeAccount,
    required this.onDisconnect,
    required this.onReview,
  });

  final SyncController controller;
  final Future<void> Function() onConnect;
  final Future<void> Function() onChangeAccount;
  final Future<void> Function() onDisconnect;
  final Future<void> Function() onReview;

  static final _privacyUri = Uri.parse(
    'https://manos-chacabuco.web.app/privacidad/',
  );

  @override
  Widget build(BuildContext context) {
    final connected = controller.account.connected;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_sync_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Sincronización',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Mantené tus datos actualizados entre Android y Windows con '
            'Google Drive. La app sigue funcionando normalmente sin Internet.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (!controller.isConfigured) ...[
            _SyncStatusLine(
              icon: Icons.info_outline_rounded,
              label: controller.configurationMessage ?? 'Falta configuración',
              color: AppColors.warning,
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('connect-google-drive'),
                onPressed: controller.isBusy ? null : onConnect,
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Conectar con Google'),
              ),
            ),
          ] else if (!connected) ...[
            _SyncStatusLine(
              icon: controller.status == SyncConnectionStatus.error
                  ? Icons.error_outline_rounded
                  : Icons.cloud_off_outlined,
              label: controller.status == SyncConnectionStatus.error
                  ? controller.statusLabel
                  : 'No hay una cuenta conectada',
              color: controller.status == SyncConnectionStatus.error
                  ? AppColors.danger
                  : AppColors.mutedInk,
            ),
            if (controller.pendingCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${controller.pendingCount} cambios locales se sincronizarán '
                'cuando conectes una cuenta.',
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('connect-google-drive'),
                onPressed: controller.isBusy ? null : onConnect,
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Conectar con Google'),
              ),
            ),
          ] else ...[
            _SyncDetail(
              label: 'Cuenta',
              value: controller.account.email ?? 'Google',
            ),
            _SyncDetail(
              label: 'Última sincronización',
              value: _syncDate(controller.account.lastSyncAt),
            ),
            _SyncDetail(label: 'Estado', value: controller.statusLabel),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Los cambios de todos los dispositivos se combinan '
              'automáticamente. Solo te pediremos elegir si el mismo dato '
              'se modificó en más de uno.',
              style: TextStyle(color: AppColors.mutedInk),
            ),
            const SizedBox(height: AppSpacing.md),
            _DevicesSection(controller: controller),
            if (controller.conflicts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('review-sync-conflicts'),
                onPressed: onReview,
                icon: const Icon(Icons.compare_arrows_rounded),
                label: Text(
                  '${controller.conflicts.length} '
                  '${controller.conflicts.length == 1 ? 'cambio necesita' : 'cambios necesitan'} revisión',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton.icon(
                  key: const Key('sync-now'),
                  onPressed: controller.isBusy ? null : controller.syncNow,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sincronizar ahora'),
                ),
                OutlinedButton.icon(
                  key: const Key('change-google-account'),
                  onPressed: controller.isBusy ? null : onChangeAccount,
                  icon: const Icon(Icons.switch_account_outlined),
                  label: const Text('Cambiar cuenta'),
                ),
                TextButton(
                  key: const Key('disconnect-google-drive'),
                  onPressed: controller.isBusy ? null : onDisconnect,
                  child: const Text('Desconectar'),
                ),
              ],
            ),
          ],
          if (!connected) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Al conectar, conservaremos tus datos locales y los combinaremos '
              'con los que ya existan en la cuenta.',
              style: TextStyle(color: AppColors.mutedInk),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('open-sync-privacy'),
              onPressed: () async {
                await launchUrl(
                  _privacyUri,
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Privacidad de la sincronización'),
            ),
          ),
        ],
      ),
    );
  }

  static String _syncDate(DateTime? value) {
    if (value == null) return 'Todavía no se sincronizó';
    return _exactDateTime(value);
  }
}

final class _DevicesSection extends StatelessWidget {
  const _DevicesSection({required this.controller});

  final SyncController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dispositivos sincronizados (${devices.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        const Text(
          'Las cantidades muestran qué tenía cada equipo en su última '
          'sincronización.',
          style: TextStyle(color: AppColors.mutedInk),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (devices.isEmpty)
          const Text(
            'Los dispositivos aparecerán acá después de sincronizar.',
            style: TextStyle(color: AppColors.mutedInk),
          )
        else
          for (final device in devices) ...[
            _DeviceCard(
              device: device,
              onRename: device.isCurrent && !controller.isBusy
                  ? () => _renameDevice(context, controller, device)
                  : null,
            ),
            if (device != devices.last) const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

final class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, this.onRename});

  final SyncDeviceSnapshot device;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.softSurface,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      border: Border.all(
        color: device.isCurrent ? AppColors.sage : AppColors.outline,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_platformIcon(device.platform), color: AppColors.sage),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (device.isCurrent)
                        const _CompactBadge(label: 'Este dispositivo'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${_platformLabel(device.platform)} · Última '
                    'sincronización: ${_nullableDateTime(device.lastSyncedAt)}',
                    style: const TextStyle(color: AppColors.mutedInk),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _summaryLabel(device.summary),
          key: Key('device-summary-${device.deviceId}'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            TextButton.icon(
              key: Key('view-device-changes-${device.deviceId}'),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => _DeviceChangesDialog(device: device),
                );
              },
              icon: const Icon(Icons.history_rounded),
              label: const Text('Ver cambios'),
            ),
            if (device.isCurrent)
              TextButton.icon(
                key: const Key('rename-current-device'),
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Cambiar nombre'),
              ),
          ],
        ),
      ],
    ),
  );
}

Future<void> _renameDevice(
  BuildContext context,
  SyncController controller,
  SyncDeviceSnapshot device,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _RenameDeviceDialog(initialName: device.name),
  );
  if (name == null || !context.mounted) return;
  try {
    await controller.renameCurrentDevice(name);
  } catch (error, stackTrace) {
    debugPrint(
      'No se pudo cambiar el nombre del dispositivo: $error\n$stackTrace',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo cambiar el nombre. Probá de nuevo.'),
      ),
    );
  }
}

final class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

final class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nombre de este dispositivo'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        key: const Key('device-name-field'),
        controller: _name,
        autofocus: true,
        maxLength: 50,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          helperText: 'Por ejemplo: Celular de Laura o PC del taller',
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Escribí un nombre para reconocerlo.'
            : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _name.text.trim());
  }
}

final class _DeviceChangesDialog extends StatelessWidget {
  const _DeviceChangesDialog({required this.device});

  final SyncDeviceSnapshot device;

  @override
  Widget build(BuildContext context) {
    final changes = [...device.recentChanges]
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final compact = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      title: Row(
        children: [
          Icon(_platformIcon(device.platform)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(device.name)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(_platformLabel(device.platform)),
                    if (device.isCurrent)
                      const _CompactBadge(label: 'Este dispositivo'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Última sincronización: '
                  '${_nullableDateTime(device.lastSyncedAt)}',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Datos disponibles',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                _DataSummaryPanel(summary: device.summary),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Cambios recientes (${changes.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (changes.isEmpty)
                  const Text(
                    'No hay cambios recientes registrados.',
                    style: TextStyle(color: AppColors.mutedInk),
                  )
                else
                  for (final change in changes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        change.operation == SyncOperation.delete
                            ? Icons.delete_outline_rounded
                            : Icons.edit_outlined,
                        color: change.operation == SyncOperation.delete
                            ? AppColors.danger
                            : AppColors.sage,
                      ),
                      title: Text(
                        change.label ?? _entityTypeLabel(change.entityType),
                      ),
                      subtitle: Text(
                        '${_operationLabel(change.operation)} · '
                        '${_exactDateTime(change.occurredAt)}',
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

final class _DataSummaryPanel extends StatelessWidget {
  const _DataSummaryPanel({required this.summary});

  final SyncDataSummary summary;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.sageSoft,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        _SummaryCount(value: summary.products, label: 'productos'),
        _SummaryCount(value: summary.materials, label: 'materias primas'),
        _SummaryCount(value: summary.quotes, label: 'presupuestos'),
      ],
    ),
  );
}

final class _SummaryCount extends StatelessWidget {
  const _SummaryCount({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$value $label',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: const TextStyle(color: AppColors.mutedInk)),
      ],
    ),
  );
}

final class _CompactBadge extends StatelessWidget {
  const _CompactBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: AppColors.sageSoft,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w800),
    ),
  );
}

final class _SyncStatusLine extends StatelessWidget {
  const _SyncStatusLine({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color),
      const SizedBox(width: AppSpacing.xs),
      Expanded(child: Text(label)),
    ],
  );
}

final class _SyncDetail extends StatelessWidget {
  const _SyncDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(label, style: const TextStyle(color: AppColors.mutedInk)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

final class _ConflictReviewDialog extends StatefulWidget {
  const _ConflictReviewDialog({required this.controller});

  final SyncController controller;

  @override
  State<_ConflictReviewDialog> createState() => _ConflictReviewDialogState();
}

final class _ConflictReviewDialogState extends State<_ConflictReviewDialog> {
  String? _selectedChoice;
  bool _resolving = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.conflicts.isEmpty) {
        return const AlertDialog(
          title: Text('Cambios revisados'),
          content: Text('Ya no quedan cambios pendientes de revisión.'),
        );
      }
      final conflict = widget.controller.conflicts.first;
      final choices = _choices(conflict);
      final validSelection = choices.any(
        (choice) => choice.key == _selectedChoice,
      );
      final compact = MediaQuery.sizeOf(context).width < 600;
      return AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        title: Text('Elegí qué versión conservar'),
        content: SizedBox(
          width: 680,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.64,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${conflict.title} tiene ${choices.length} versiones para '
                    'comparar. Revisá el dispositivo y la fecha antes de '
                    'elegir.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RadioGroup<String>(
                    groupValue: validSelection ? _selectedChoice : null,
                    onChanged: (value) {
                      if (value == null || _resolving) return;
                      setState(() => _selectedChoice = value);
                    },
                    child: Column(
                      children: [
                        for (final choice in choices) ...[
                          _ConflictVersionCard(
                            choice: choice,
                            selected: choice.key == _selectedChoice,
                            enabled: !_resolving,
                            onSelected: () {
                              setState(() => _selectedChoice = choice.key);
                            },
                          ),
                          if (choice != choices.last)
                            const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _resolving ? null : () => Navigator.pop(context),
            child: const Text('Decidir después'),
          ),
          FilledButton(
            key: const Key('keep-selected-sync-version'),
            onPressed: !validSelection || _resolving
                ? null
                : () => _resolve(conflict, choices),
            child: Text(
              _resolving ? 'Guardando…' : 'Conservar versión seleccionada',
            ),
          ),
        ],
      );
    },
  );

  List<_ConflictChoice> _choices(SyncConflict conflict) {
    final current = widget.controller.devices
        .where((device) => device.isCurrent)
        .firstOrNull;
    final result = <_ConflictChoice>[
      _ConflictChoice(
        key: 'local:${conflict.id}',
        isLocal: true,
        entityType: conflict.entityType,
        name: current?.name ?? 'Este dispositivo',
        platform: current?.platform ?? Platform.operatingSystem,
        occurredAt:
            conflict.localOccurredAt ??
            _payloadUpdatedAt(conflict.localPayload) ??
            conflict.createdAt,
        payload: conflict.localPayload,
        isCurrent: true,
      ),
    ];
    for (final envelope in conflict.remoteEnvelopes) {
      final snapshot = widget.controller.deviceById(envelope.deviceId);
      final platform =
          envelope.devicePlatform ?? snapshot?.platform ?? 'unknown';
      result.add(
        _ConflictChoice(
          key: 'remote:${envelope.revision}',
          isLocal: false,
          entityType: conflict.entityType,
          remoteRevision: envelope.revision,
          name:
              envelope.deviceName ??
              snapshot?.name ??
              _fallbackDeviceName(platform, envelope.deviceId),
          platform: platform,
          occurredAt: envelope.occurredAt,
          payload: envelope.payload,
          isCurrent: snapshot?.isCurrent ?? false,
        ),
      );
    }
    return result;
  }

  Future<void> _resolve(
    SyncConflict conflict,
    List<_ConflictChoice> choices,
  ) async {
    final selected = choices
        .where((choice) => choice.key == _selectedChoice)
        .firstOrNull;
    if (selected == null) return;
    setState(() => _resolving = true);
    try {
      await widget.controller.resolveConflict(
        conflict,
        selected.isLocal
            ? SyncConflictResolution.useLocal
            : SyncConflictResolution.useRemote,
        remoteRevision: selected.remoteRevision,
      );
      if (!mounted) return;
      if (widget.controller.conflicts.isEmpty) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _selectedChoice = null;
        _resolving = false;
      });
    } catch (error, stackTrace) {
      debugPrint('No se pudo resolver el conflicto: $error\n$stackTrace');
      if (!mounted) return;
      if (widget.controller.conflicts.isEmpty) {
        Navigator.pop(context);
        return;
      }
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar la elección. Probá de nuevo.'),
        ),
      );
    }
  }
}

final class _ConflictChoice {
  const _ConflictChoice({
    required this.key,
    required this.isLocal,
    required this.entityType,
    required this.name,
    required this.platform,
    required this.occurredAt,
    required this.payload,
    required this.isCurrent,
    this.remoteRevision,
  });

  final String key;
  final bool isLocal;
  final String entityType;
  final String? remoteRevision;
  final String name;
  final String platform;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
  final bool isCurrent;
}

final class _ConflictVersionCard extends StatelessWidget {
  const _ConflictVersionCard({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final _ConflictChoice choice;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final lines = _versionLines(choice.entityType, choice.payload);
    return Semantics(
      selected: selected,
      button: true,
      label: 'Versión de ${choice.name}',
      child: Material(
        color: selected ? AppColors.terracottaSoft : AppColors.softSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: BorderSide(
            color: selected ? AppColors.terracotta : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onSelected : null,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Radio<String>(value: choice.key, enabled: enabled),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            _platformIcon(choice.platform),
                            size: 20,
                            color: AppColors.sage,
                          ),
                          Text(
                            choice.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (choice.isCurrent)
                            const _CompactBadge(label: 'Este dispositivo'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '${_platformLabel(choice.platform)} · '
                        'Modificado: ${_exactDateTime(choice.occurredAt)}',
                        style: const TextStyle(color: AppColors.mutedInk),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final line in lines) Text(line),
                      if (lines.isEmpty)
                        const Text('Esta versión no tiene detalles visibles.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<String> _versionLines(String entityType, Map<String, Object?> payload) {
  final root = payload['root'];
  if (root is! Map) return const ['Estado: eliminado'];
  final values = Map<String, Object?>.from(root);
  final currency = (values['currency'] as String?) ?? 'ARS';
  final lines = <String>[];

  void addText(String label, Object? raw) {
    if (raw case final String value when value.trim().isNotEmpty) {
      lines.add('$label: ${value.trim()}');
    }
  }

  switch (entityType) {
    case 'appSettings':
      lines.add('Moneda: $currency');
      lines.add(
        'Desperdicio predeterminado: '
        '${_optionalPercent(values['default_waste_scaled'])}',
      );
      lines.add(
        'Hilo predeterminado: '
        '${_optionalPercent(values['default_thread_scaled'])}',
      );
      lines.add(
        'Recargo minorista: '
        '${_optionalPercent(values['default_retail_scaled'])}',
      );
      lines.add(
        'Multiplicador predeterminado: '
        '${_optionalDecimal(values['default_multiplier_scaled'])}',
      );
      lines.add(
        'Mínimo mayorista: '
        '${_optionalMoney(values['minimum_wholesale_minor'], currency)}',
      );
      lines.add(
        'Logo: ${_hasText(values['business_logo_path']) ? 'incluido' : 'sin logo'}',
      );
    case 'material':
      addText('Nombre', values['name']);
      addText('Descripción', values['description']);
      addText('Marca o proveedor', values['brand_or_supplier']);
      if (values['purchase_quantity_scaled'] case final int value) {
        lines.add(
          'Cantidad de compra: ${_scaledDecimal(value)}'
          '${_unitSuffix(values['purchase_unit_id'])}',
        );
      }
      if (values['purchase_price_minor'] case final int value) {
        lines.add(
          'Precio de compra: '
          '${ArgentineNumberFormatter.money(Money(minorUnits: value, currency: currency))}',
        );
      }
      lines.add(
        'Unidad de consumo: ${_unitLabel(values['consumption_unit_id'])}',
      );
      if (payload['variants'] case final List<Object?> variants) {
        lines.add(_payloadListSummary('Variantes', variants));
      }
      addText('Notas', values['notes']);
    case 'product':
      addText('Nombre', values['name']);
      addText('Descripción', values['description']);
      if (values['shape_code'] case final String value when value.isNotEmpty) {
        lines.add('Forma: ${_shapeLabel(value)}');
      }
      if (_dimensionsSummary(values['dimensions_json']) case final summary?) {
        lines.add('Medidas: $summary');
      }
      lines.add(
        'Desperdicio: ${_optionalPercent(values['waste_override_scaled'], fallback: 'usa el valor general')}',
      );
      lines.add(
        'Hilo: ${_optionalPercent(values['thread_override_scaled'], fallback: 'usa el valor general')}',
      );
      lines.add(
        'Recargo minorista: ${_optionalPercent(values['retail_override_scaled'], fallback: 'usa el valor general')}',
      );
      lines.add(
        'Multiplicador: ${_optionalDecimal(values['price_multiplier_scaled'])}',
      );
      if (payload['usages'] case final List<Object?> usages) {
        lines.add('Materias primas utilizadas: ${_activePayloadCount(usages)}');
      }
      lines.add(
        'Foto: ${_hasText(values['photo_path']) ? 'incluida' : 'sin foto'}',
      );
      addText('Notas', values['notes']);
    case 'quote':
      addText('Cliente', values['customer_name']);
      lines.add('Fecha: ${_storedDate(values['quote_date'])}');
      lines.add('Válido hasta: ${_storedDate(values['valid_until'])}');
      if (values['validity_days'] case final int value) {
        lines.add('Vigencia: $value días');
      }
      lines.add('Tipo de precio: ${_priceTypeLabel(values['price_type'])}');
      if (values['total_minor'] case final int value) {
        lines.add(
          'Total: '
          '${ArgentineNumberFormatter.money(Money(minorUnits: value, currency: currency))}',
        );
      }
      if (payload['items'] case final List<Object?> items) {
        lines.add(_payloadListSummary('Productos', items));
      }
      if (payload['adjustments'] case final List<Object?> adjustments) {
        lines.add(_payloadListSummary('Ajustes', adjustments));
      }
      addText('Notas', values['notes']);
    case 'measurementUnit':
      addText('Nombre', values['name']);
      addText('Símbolo', values['symbol']);
      addText('Código', values['code']);
      addText('Tipo de medida', values['dimension']);
    case 'priceListPreference':
      lines.add('Lista: ${_priceTypeLabel(values['price_type'])}');
      lines.addAll(_priceListPreferenceLines(values['config_json']));
    default:
      addText('Nombre', values['name']);
      addText('Descripción', values['description']);
      addText('Cliente', values['customer_name']);
  }

  if (values['deleted_at'] != null) {
    lines.add('Estado: eliminado');
  } else if (values['is_active'] case final int value) {
    lines.add('Estado: ${value == 1 ? 'activo' : 'inactivo'}');
  }
  return lines;
}

String _optionalPercent(Object? raw, {String fallback = 'sin definir'}) =>
    raw is int
    ? '${ArgentineNumberFormatter.decimal(DecimalValue.scaled(raw * 100), fractionDigits: 2)}%'
    : fallback;

String _optionalDecimal(Object? raw, {String fallback = 'sin definir'}) =>
    raw is int
    ? ArgentineNumberFormatter.decimal(
        DecimalValue.scaled(raw),
        fractionDigits: 3,
      )
    : fallback;

String _optionalMoney(Object? raw, String currency) => raw is int
    ? ArgentineNumberFormatter.money(Money(minorUnits: raw, currency: currency))
    : 'sin definir';

String _scaledDecimal(int value) => ArgentineNumberFormatter.decimal(
  DecimalValue.scaled(value),
  fractionDigits: 3,
);

bool _hasText(Object? value) => value is String && value.trim().isNotEmpty;

String _unitSuffix(Object? unitId) {
  final label = _unitLabel(unitId);
  return label == 'otra unidad' ? '' : ' $label';
}

String _unitLabel(Object? unitId) => switch (unitId) {
  'd8a885bb-55c2-4fb3-b430-933781c3f8c0' => 'g',
  '696f7d11-937d-47cc-9e4c-8e46f5caa706' => 'kg',
  'e2a6fd75-1f02-41ea-bd51-14e8535ddad5' => 'm',
  'b59af36e-bb0c-4533-a4a8-48ec2cead406' => 'cm',
  '35258dd4-0b31-45dd-b06e-1992d96757d9' => 'm²',
  '44df27a1-a71f-447c-b6ee-02e75b6d6238' => 'cm²',
  '2bf70ea7-4bb8-4249-b009-f57f55aa1a85' => 'unidades',
  _ => 'otra unidad',
};

String _shapeLabel(String value) => switch (value) {
  'circle' => 'Círculo plano',
  'cylinder' => 'Cilindro',
  'oval' => 'Oval',
  'frustum' => 'Cono / tronco de cono',
  _ => 'Otra forma',
};

String? _dimensionsSummary(Object? encoded) {
  if (encoded is! String || encoded.isEmpty) return null;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return null;
    final parts = <String>[];
    for (final entry in decoded.entries) {
      if (entry.value is! Map) continue;
      final value = entry.value as Map;
      final amount = value['amount'];
      if (amount is! int) continue;
      parts.add(
        '${_dimensionLabel(entry.key.toString())}: ${_scaledDecimal(amount)}'
        '${_unitSuffix(value['unit'])}',
      );
    }
    return parts.isEmpty ? null : parts.join(' · ');
  } on FormatException {
    return 'configuradas';
  }
}

String _dimensionLabel(String code) => switch (code) {
  'diameter' => 'Diámetro',
  'height' => 'Alto',
  'length' => 'Largo',
  'width' => 'Ancho',
  'bottomDiameter' => 'Diámetro inferior',
  'topDiameter' => 'Diámetro superior',
  'lidBottomDiameter' => 'Diámetro inferior de tapa',
  'lidTopDiameter' => 'Diámetro superior de tapa',
  'lidHeight' => 'Altura de tapa',
  _ => code,
};

String _storedDate(Object? raw) {
  if (raw is! String || raw.length < 10) return 'sin definir';
  final date = raw.substring(0, 10).split('-');
  return date.length == 3 ? '${date[2]}/${date[1]}/${date[0]}' : raw;
}

String _priceTypeLabel(Object? value) => switch (value) {
  'retail' => 'Minorista',
  'wholesale' => 'Mayorista',
  _ => 'Sin definir',
};

String _payloadListSummary(String label, List<Object?> values) {
  final active = values
      .where((item) {
        return item is Map && item['deleted_at'] == null;
      })
      .toList(growable: false);
  final names = <String>[
    for (final item in active)
      if (item case final Map value)
        if ((value['name'] ?? value['description']) case final String name
            when name.trim().isNotEmpty)
          name.trim(),
  ];
  if (names.isEmpty) return '$label: ${active.length}';
  final visible = names.take(3).join(', ');
  final remaining = names.length - 3;
  return '$label (${active.length}): $visible'
      '${remaining > 0 ? ' y $remaining más' : ''}';
}

List<String> _priceListPreferenceLines(Object? encoded) {
  if (encoded is! String || encoded.isEmpty) return const [];
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return const [];
    final products = decoded['selectedProductIds'];
    return [
      'Productos seleccionados: ${products is List ? products.length : 0}',
      'Fotos: ${decoded['showPhotos'] == false ? 'no' : 'sí'}',
      'Agrupar por categoría: '
          '${decoded['groupByCategory'] == false ? 'no' : 'sí'}',
      if (decoded['footerNote'] case final String value
          when value.trim().isNotEmpty)
        'Nota al pie: ${value.trim()}',
    ];
  } on FormatException {
    return const ['Preferencias guardadas'];
  }
}

int _activePayloadCount(List<Object?> values) => values.where((item) {
  if (item is! Map) return false;
  return item['deleted_at'] == null;
}).length;

DateTime? _payloadUpdatedAt(Map<String, Object?> payload) {
  final root = payload['root'];
  if (root is! Map || root['updated_at'] is! String) return null;
  return DateTime.tryParse(root['updated_at']! as String);
}

String _summaryLabel(SyncDataSummary summary) =>
    '${summary.products} productos · ${summary.materials} materias primas · '
    '${summary.quotes} presupuestos';

String _nullableDateTime(DateTime? value) =>
    value == null ? 'Todavía no se sincronizó' : _exactDateTime(value);

String _exactDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} · $hour:$minute';
}

String _platformLabel(String platform) => switch (platform.toLowerCase()) {
  'windows' => 'Windows',
  'android' => 'Android',
  _ => 'Dispositivo',
};

IconData _platformIcon(String platform) => switch (platform.toLowerCase()) {
  'windows' => Icons.computer_rounded,
  'android' => Icons.smartphone_rounded,
  _ => Icons.devices_other_rounded,
};

String _fallbackDeviceName(String platform, String deviceId) {
  final suffix = deviceId.length <= 4
      ? deviceId.toUpperCase()
      : deviceId.substring(deviceId.length - 4).toUpperCase();
  return '${_platformLabel(platform)} · $suffix';
}

String _entityTypeLabel(String type) => switch (type) {
  'product' => 'Producto',
  'material' => 'Materia prima',
  'quote' => 'Presupuesto',
  'appSettings' => 'Configuración',
  'productCategory' => 'Categoría de producto',
  'materialCategory' => 'Categoría de materia prima',
  'priceListPreference' => 'Lista de precios',
  _ => 'Dato de la aplicación',
};

String _operationLabel(SyncOperation operation) => switch (operation) {
  SyncOperation.upsert => 'Guardado',
  SyncOperation.delete => 'Eliminado',
};

final class _BusinessLogoField extends StatelessWidget {
  const _BusinessLogoField({
    required this.imagePath,
    required this.isSaving,
    required this.onSelect,
    required this.onRemove,
  });

  final String? imagePath;
  final bool isSaving;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && File(imagePath!).existsSync();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: SizedBox.square(
              dimension: 72,
              child: hasImage
                  ? AppFileImage(
                      path: imagePath,
                      cacheWidth: 160,
                      cacheHeight: 160,
                      semanticLabel: 'Logo del negocio',
                    )
                  : const ColoredBox(
                      color: Colors.white,
                      child: Icon(
                        Icons.storefront_rounded,
                        color: AppColors.terracotta,
                      ),
                    ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logo del negocio',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text('Opcional. Se mostrará en las listas comerciales.'),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: isSaving ? null : onSelect,
            icon: const Icon(Icons.image_outlined),
            label: Text(hasImage ? 'Cambiar' : 'Elegir imagen'),
          ),
          if (hasImage)
            TextButton.icon(
              onPressed: isSaving ? null : onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Eliminar'),
            ),
        ],
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.isSaving, required this.hasUnsavedChanges});

  final bool isSaving;
  final bool hasUnsavedChanges;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configuración',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text('Ajustá las reglas generales de tu negocio.'),
      ],
    );
    final status = StatusPill(
      label: isSaving
          ? 'Guardando…'
          : hasUnsavedChanges
          ? 'Cambios sin guardar'
          : 'Guardado en este equipo',
      icon: isSaving
          ? Icons.sync_rounded
          : hasUnsavedChanges
          ? Icons.edit_note_rounded
          : Icons.check_circle_outline_rounded,
      color: hasUnsavedChanges ? AppColors.warning : AppColors.success,
      backgroundColor: hasUnsavedChanges
          ? AppColors.terracottaSoft
          : AppColors.sageSoft,
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 560
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: AppSpacing.sm),
                status,
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                status,
              ],
            ),
    );
  }
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
