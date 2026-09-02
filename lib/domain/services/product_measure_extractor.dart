import '../../core/money/decimal_value.dart';
import '../geometry/geometry_models.dart';

final class ExtractedProductMeasures {
  const ExtractedProductMeasures({
    required this.values,
    required this.geometryProfile,
    required this.semanticIsSafe,
  });

  final Map<String, DecimalValue> values;
  final GeometryProfile? geometryProfile;
  final bool semanticIsSafe;
}

final class ProductMeasureExtractor {
  const ProductMeasureExtractor();

  ExtractedProductMeasures extract(String productName) {
    final normalized = productName.toLowerCase();
    final matches = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)(?:\s*[x×]\s*(\d+(?:[.,]\d+)?))?',
      caseSensitive: false,
    ).allMatches(productName).toList();
    if (matches.length == 1) {
      final numbers = [
        for (var index = 1; index <= 3; index++)
          if (matches.single.group(index) != null)
            DecimalValue.parse(
              matches.single.group(index)!.replaceAll(',', '.'),
            ),
      ];
      if (_isOval(normalized) && numbers.length == 3) {
        return ExtractedProductMeasures(
          values: {
            'Largo': numbers[0],
            'Ancho': numbers[1],
            'Alto': numbers[2],
          },
          geometryProfile: const GeometryProfile(
            shapeCode: 'oval',
            components: {GeometryComponent.base, GeometryComponent.lateral},
            dimensionBindings: {
              GeometryParameters.length: 'Largo',
              GeometryParameters.width: 'Ancho',
              GeometryParameters.height: 'Alto',
            },
          ),
          semanticIsSafe: true,
        );
      }
      if (_isOpenCylinderFamily(normalized) && numbers.length == 2) {
        return ExtractedProductMeasures(
          values: {'Diámetro': numbers[0], 'Alto': numbers[1]},
          geometryProfile: const GeometryProfile(
            shapeCode: 'cylinder',
            components: {GeometryComponent.base, GeometryComponent.lateral},
            dimensionBindings: {
              GeometryParameters.diameter: 'Diámetro',
              GeometryParameters.height: 'Alto',
            },
          ),
          semanticIsSafe: true,
        );
      }
      if (normalized.contains('bandeja') && numbers.length == 2) {
        return ExtractedProductMeasures(
          values: {'Largo': numbers[0], 'Ancho': numbers[1]},
          geometryProfile: null,
          semanticIsSafe: true,
        );
      }
      return ExtractedProductMeasures(
        values: {
          for (var index = 0; index < numbers.length; index++)
            'Medida ${index + 1}': numbers[index],
        },
        geometryProfile: null,
        semanticIsSafe: false,
      );
    }

    if (matches.isEmpty && _isFlatCircle(normalized)) {
      final centimeter = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*cm',
        caseSensitive: false,
      ).firstMatch(productName);
      if (centimeter != null) {
        final diameter = DecimalValue.parse(
          centimeter.group(1)!.replaceAll(',', '.'),
        );
        return ExtractedProductMeasures(
          values: {'Diámetro': diameter},
          geometryProfile: const GeometryProfile(
            shapeCode: 'circle',
            components: {GeometryComponent.base},
            dimensionBindings: {GeometryParameters.diameter: 'Diámetro'},
          ),
          semanticIsSafe: true,
        );
      }
    }
    return const ExtractedProductMeasures(
      values: {},
      geometryProfile: null,
      semanticIsSafe: false,
    );
  }

  bool _isOval(String name) => name.contains('oval');

  bool _isOpenCylinderFamily(String name) =>
      name.contains('macetero') ||
      name.contains('centro de mesa') ||
      name.contains('contenedor infantil redond') ||
      name.contains('cesto gde');

  bool _isFlatCircle(String name) =>
      name.contains('bajo plato redondo') ||
      name.contains('bajoplato redondo') ||
      name.contains('posavasos redondo') ||
      name.contains('posafuente redondo');
}
