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
            if (controller.conflicts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
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
    final local = value.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'Hoy $time';
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} $time';
  }
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

final class _ConflictReviewDialog extends StatelessWidget {
  const _ConflictReviewDialog({required this.controller});

  final SyncController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.conflicts.isEmpty) {
        return const AlertDialog(
          title: Text('Cambios revisados'),
          content: Text('Ya no quedan cambios pendientes de revisión.'),
        );
      }
      final conflict = controller.conflicts.first;
      return AlertDialog(
        title: Text('Cambios en ${conflict.entityLabel}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${conflict.title} fue modificado en los dos dispositivos. '
                  'Elegí cuál querés conservar.',
                ),
                const SizedBox(height: AppSpacing.md),
                _VersionPanel(
                  title: 'Versión de este dispositivo',
                  payload: conflict.localPayload,
                ),
                const SizedBox(height: AppSpacing.sm),
                _VersionPanel(
                  title: 'Versión del otro dispositivo',
                  payload: conflict.remoteEnvelope.payload,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Revisar después'),
          ),
          OutlinedButton(
            onPressed: () async {
              await controller.resolveConflict(
                conflict,
                SyncConflictResolution.useRemote,
              );
              if (context.mounted && controller.conflicts.isEmpty) {
                Navigator.pop(context);
              }
            },
            child: const Text('Usar la otra versión'),
          ),
          FilledButton(
            onPressed: () async {
              await controller.resolveConflict(
                conflict,
                SyncConflictResolution.useLocal,
              );
              if (context.mounted && controller.conflicts.isEmpty) {
                Navigator.pop(context);
              }
            },
            child: const Text('Usar esta versión'),
          ),
        ],
      );
    },
  );
}

final class _VersionPanel extends StatelessWidget {
  const _VersionPanel({required this.title, required this.payload});

  final String title;
  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final root = payload['root'];
    final values = root is Map ? root : const <Object?, Object?>{};
    final lines = <String>[
      if (values['name'] is String) 'Nombre: ${values['name']}',
      if (values['customer_name'] is String)
        'Cliente: ${values['customer_name']}',
      if (values['business_name'] is String)
        'Negocio: ${values['business_name']}',
      if (values['purchase_price_minor'] is int)
        'Precio de compra: ${ArgentineNumberFormatter.moneyAmount(Money(minorUnits: values['purchase_price_minor']! as int, currency: (values['currency'] as String?) ?? 'ARS'))}',
      if (values['total_minor'] is int)
        'Total: ${ArgentineNumberFormatter.moneyAmount(Money(minorUnits: values['total_minor']! as int, currency: (values['currency'] as String?) ?? 'ARS'))}',
      if (values['price_multiplier_scaled'] is int)
        'Multiplicador: ${ArgentineNumberFormatter.decimal(DecimalValue.scaled(values['price_multiplier_scaled']! as int), fractionDigits: 3)}',
      if (values['deleted_at'] != null) 'Estado: eliminado',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          for (final line in lines.take(4)) Text(line),
          if (lines.isEmpty) const Text('Cambio de configuración interna'),
        ],
      ),
    );
  }
}

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
