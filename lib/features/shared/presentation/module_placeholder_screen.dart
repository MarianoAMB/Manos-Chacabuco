import 'package:flutter/material.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_card.dart';
import '../../../core/design_system/components/app_empty_state.dart';
import '../../../core/design_system/components/status_pill.dart';

final class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({required this.destination, super.key});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    final content = _moduleContent(destination);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppBreakpoints.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        destination.label,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const StatusPill(
                      label: 'Próxima etapa',
                      icon: Icons.schedule_rounded,
                      color: AppColors.warning,
                      backgroundColor: Color(0xFFFFEBCF),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: AppCard(
                    child: AppEmptyState(
                      icon: destination.icon,
                      title: content.title,
                      message: content.message,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({String title, String message}) _moduleContent(
    AppDestination destination,
  ) => switch (destination) {
    AppDestination.products => (
      title: 'Tus productos van a vivir acá',
      message:
          'La base ya contempla medidas, fotos opcionales, materiales por variante '
          'y reglas de precio. El alta y la edición llegarán en su fase específica.',
    ),
    AppDestination.materials => (
      title: 'Materias primas flexibles',
      message:
          'La estructura soporta peso, longitud, superficie, unidades y colores '
          'con precios propios. El próximo paso será crear su experiencia de gestión.',
    ),
    AppDestination.quotes => (
      title: 'Presupuestos claros y editables',
      message:
          'El modelo admite varios productos, cantidades y ajustes extraordinarios. '
          'La interfaz completa se construirá sin adelantar reglas no validadas.',
    ),
    AppDestination.calculator => (
      title: 'Una calculadora que aprende de lo real',
      message:
          'El motor acepta nuevas formas mediante estrategias. Las fórmulas se '
          'calibrarán con productos históricos y se mostrarán como estimaciones.',
    ),
    AppDestination.priceLists => (
      title: 'Listas mayorista y minorista',
      message:
          'Este espacio tendrá dos exportaciones independientes en PDF e imagen, '
          'listas para compartir desde Android.',
    ),
    _ => (
      title: 'Módulo preparado',
      message: 'La estructura está lista para la próxima etapa.',
    ),
  };
}
