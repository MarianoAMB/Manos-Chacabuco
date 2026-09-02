import 'dart:math' as math;

import '../geometry/geometry_models.dart';

final class GeometryInput {
  const GeometryInput({required this.profile, required this.valuesCm});

  final GeometryProfile profile;
  final Map<String, double> valuesCm;

  double requirePositive(String parameter) {
    final value = valuesCm[parameter];
    if (value == null || !value.isFinite || value <= 0) {
      throw GeometryValidationException(
        'Completá ${GeometryParameters.label(parameter).toLowerCase()} con un valor mayor que cero.',
      );
    }
    return value;
  }

  double requireNonNegative(String parameter) {
    final value = valuesCm[parameter];
    if (value == null || !value.isFinite || value < 0) {
      throw GeometryValidationException(
        'Completá ${GeometryParameters.label(parameter).toLowerCase()} con un valor válido.',
      );
    }
    return value;
  }
}

final class GeometryResult {
  const GeometryResult({
    required this.shapeCode,
    required this.baseArea,
    required this.lateralArea,
    required this.lidArea,
    this.otherArea = 0,
    this.metadata = const {},
  });

  final String shapeCode;
  final double baseArea;
  final double lateralArea;
  final double lidArea;
  final double otherArea;
  final Map<String, double> metadata;

  double get totalEffectiveArea => baseArea + lateralArea + lidArea + otherArea;
}

final class GeometryValidationException implements Exception {
  const GeometryValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class GeometryStrategy {
  String get shapeCode;
  GeometryResult calculate(GeometryInput input);
}

final class GeometryEngine {
  GeometryEngine(Iterable<GeometryStrategy> strategies)
    : _strategies = {
        for (final strategy in strategies) strategy.shapeCode: strategy,
      };

  factory GeometryEngine.standard() => GeometryEngine(const [
    CircleGeometryStrategy(),
    CylinderGeometryStrategy(),
    OvalGeometryStrategy(),
    FrustumGeometryStrategy(),
  ]);

  final Map<String, GeometryStrategy> _strategies;

  GeometryResult calculate(GeometryInput input) {
    final strategy = _strategies[input.profile.shapeCode];
    if (strategy == null) {
      throw UnsupportedError(
        'Todavía no tenemos una fórmula para esta forma. Ingresá el consumo manualmente.',
      );
    }
    final body = strategy.calculate(input);
    if (!input.profile.components.contains(GeometryComponent.lid) ||
        input.profile.lidType != GeometryLidType.frustum) {
      return body;
    }
    final bottom = input.requirePositive(GeometryParameters.lidBottomDiameter);
    final top = input.requireNonNegative(GeometryParameters.lidTopDiameter);
    final height = input.requirePositive(GeometryParameters.lidHeight);
    final lid = _frustumSurface(
      bottomDiameter: bottom,
      topDiameter: top,
      height: height,
      includeBase: false,
      includeTop: top > 0,
      includeLateral: true,
    );
    return GeometryResult(
      shapeCode: body.shapeCode,
      baseArea: body.baseArea,
      lateralArea: body.lateralArea,
      lidArea: lid.lateral + lid.top,
      otherArea: body.otherArea,
      metadata: {...body.metadata, 'lidSlantHeight': lid.slant},
    );
  }
}

final class CircleGeometryStrategy implements GeometryStrategy {
  const CircleGeometryStrategy();

  @override
  String get shapeCode => GeometryShape.circle.code;

  @override
  GeometryResult calculate(GeometryInput input) {
    final radius = input.requirePositive(GeometryParameters.diameter) / 2;
    final area = math.pi * radius * radius;
    return GeometryResult(
      shapeCode: shapeCode,
      baseArea: input.profile.components.contains(GeometryComponent.base)
          ? area
          : 0,
      lateralArea: 0,
      lidArea: 0,
      metadata: {'radius': radius},
    );
  }
}

final class CylinderGeometryStrategy implements GeometryStrategy {
  const CylinderGeometryStrategy();

  @override
  String get shapeCode => GeometryShape.cylinder.code;

  @override
  GeometryResult calculate(GeometryInput input) {
    final radius = input.requirePositive(GeometryParameters.diameter) / 2;
    final circle = math.pi * radius * radius;
    final hasLateral = input.profile.components.contains(
      GeometryComponent.lateral,
    );
    final height = hasLateral
        ? input.requirePositive(GeometryParameters.height)
        : 0.0;
    return GeometryResult(
      shapeCode: shapeCode,
      baseArea: input.profile.components.contains(GeometryComponent.base)
          ? circle
          : 0,
      lateralArea: hasLateral ? 2 * math.pi * radius * height : 0,
      lidArea:
          input.profile.components.contains(GeometryComponent.lid) &&
              input.profile.lidType == GeometryLidType.flat
          ? circle
          : 0,
      metadata: {'radius': radius},
    );
  }
}

final class OvalGeometryStrategy implements GeometryStrategy {
  const OvalGeometryStrategy();

  @override
  String get shapeCode => GeometryShape.oval.code;

  @override
  GeometryResult calculate(GeometryInput input) {
    final a = input.requirePositive(GeometryParameters.length) / 2;
    final b = input.requirePositive(GeometryParameters.width) / 2;
    final ellipse = math.pi * a * b;
    final perimeter =
        math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)));
    final hasLateral = input.profile.components.contains(
      GeometryComponent.lateral,
    );
    final height = hasLateral
        ? input.requirePositive(GeometryParameters.height)
        : 0.0;
    return GeometryResult(
      shapeCode: shapeCode,
      baseArea: input.profile.components.contains(GeometryComponent.base)
          ? ellipse
          : 0,
      lateralArea: hasLateral ? perimeter * height : 0,
      lidArea:
          input.profile.components.contains(GeometryComponent.lid) &&
              input.profile.lidType == GeometryLidType.flat
          ? ellipse
          : 0,
      metadata: {'semiMajor': a, 'semiMinor': b, 'perimeter': perimeter},
    );
  }
}

final class FrustumGeometryStrategy implements GeometryStrategy {
  const FrustumGeometryStrategy();

  @override
  String get shapeCode => GeometryShape.frustum.code;

  @override
  GeometryResult calculate(GeometryInput input) {
    final bottom = input.requirePositive(GeometryParameters.bottomDiameter);
    final top = input.requireNonNegative(GeometryParameters.topDiameter);
    final height = input.requirePositive(GeometryParameters.height);
    final areas = _frustumSurface(
      bottomDiameter: bottom,
      topDiameter: top,
      height: height,
      includeBase: input.profile.components.contains(GeometryComponent.base),
      includeTop:
          input.profile.components.contains(GeometryComponent.lid) &&
          input.profile.lidType == GeometryLidType.flat &&
          top > 0,
      includeLateral: input.profile.components.contains(
        GeometryComponent.lateral,
      ),
    );
    return GeometryResult(
      shapeCode: shapeCode,
      baseArea: areas.base,
      lateralArea: areas.lateral,
      lidArea: areas.top,
      metadata: {'slantHeight': areas.slant},
    );
  }
}

({double base, double lateral, double slant, double top}) _frustumSurface({
  required double bottomDiameter,
  required double topDiameter,
  required double height,
  required bool includeBase,
  required bool includeTop,
  required bool includeLateral,
}) {
  final bigRadius = bottomDiameter / 2;
  final smallRadius = topDiameter / 2;
  final slant = math.sqrt(
    math.pow(bigRadius - smallRadius, 2) + math.pow(height, 2),
  );
  return (
    base: includeBase ? math.pi * bigRadius * bigRadius : 0,
    lateral: includeLateral ? math.pi * (bigRadius + smallRadius) * slant : 0,
    slant: slant,
    top: includeTop ? math.pi * smallRadius * smallRadius : 0,
  );
}
