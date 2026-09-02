import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../domain/materials/material_models.dart';
import '../application/materials_controller.dart';

extension MeasurementDimensionLabel on MeasurementDimension {
  String get label => switch (this) {
    MeasurementDimension.weight => 'Peso',
    MeasurementDimension.length => 'Longitud',
    MeasurementDimension.area => 'Superficie',
    MeasurementDimension.count => 'Unidades',
  };

  String get question => switch (this) {
    MeasurementDimension.weight => 'Se compra por peso',
    MeasurementDimension.length => 'Se compra por longitud',
    MeasurementDimension.area => 'Se compra por superficie',
    MeasurementDimension.count => 'Se compra por cantidad',
  };
}

String presentationLabel(
  PurchasePresentation purchase,
  MaterialsController controller,
) {
  final unit = controller.unitById(purchase.quantity.unitId);
  if (unit == null) return 'Presentación no disponible';
  return '${ArgentineNumberFormatter.decimal(purchase.quantity.amount)} '
      '${unit.symbol} · ${ArgentineNumberFormatter.money(purchase.price)}';
}

String unitCostLabel(
  PurchasePresentation purchase,
  String displayUnitId,
  MaterialsController controller,
) {
  final displayUnit = controller.unitById(displayUnitId);
  if (displayUnit == null) return 'Costo pendiente';
  return ArgentineNumberFormatter.unitCost(
    controller.unitCost(purchase),
    displayUnit,
  );
}
