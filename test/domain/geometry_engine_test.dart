import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/domain/geometry/geometry_models.dart';
import 'package:manos_chacabuco/domain/services/geometry_engine.dart';

void main() {
  final engine = GeometryEngine.standard();

  test('círculo de diámetro 20 calcula pi por radio al cuadrado', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.circle, {GeometryComponent.base}),
        valuesCm: const {GeometryParameters.diameter: 20},
      ),
    );

    expect(result.metadata['radius'], 10);
    expect(result.baseArea, closeTo(math.pi * 100, 0.000001));
    expect(result.totalEffectiveArea, closeTo(math.pi * 100, 0.000001));
  });

  test('cilindro abierto suma base y lateral', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.cylinder, {
          GeometryComponent.base,
          GeometryComponent.lateral,
        }),
        valuesCm: const {
          GeometryParameters.diameter: 20,
          GeometryParameters.height: 30,
        },
      ),
    );

    expect(result.baseArea, closeTo(math.pi * 100, 0.000001));
    expect(result.lateralArea, closeTo(2 * math.pi * 10 * 30, 0.000001));
    expect(result.lidArea, 0);
  });

  test('cilindro con tapa suma base, lateral y tapa', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.cylinder, {
          GeometryComponent.base,
          GeometryComponent.lateral,
          GeometryComponent.lid,
        }, lidType: GeometryLidType.flat),
        valuesCm: const {
          GeometryParameters.diameter: 20,
          GeometryParameters.height: 30,
        },
      ),
    );

    expect(result.lidArea, closeTo(math.pi * 100, 0.000001));
    expect(
      result.totalEffectiveArea,
      closeTo((2 * math.pi * 100) + (2 * math.pi * 10 * 30), 0.000001),
    );
  });

  test('oval plano usa el área de una elipse', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.oval, {GeometryComponent.base}),
        valuesCm: const {
          GeometryParameters.length: 30,
          GeometryParameters.width: 20,
        },
      ),
    );

    expect(result.baseArea, closeTo(math.pi * 15 * 10, 0.000001));
    expect(result.lateralArea, 0);
  });

  test('oval volumétrico usa Ramanujan para el lateral', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.oval, {
          GeometryComponent.base,
          GeometryComponent.lateral,
        }),
        valuesCm: const {
          GeometryParameters.length: 30,
          GeometryParameters.width: 20,
          GeometryParameters.height: 15,
        },
      ),
    );
    final perimeter =
        math.pi * (3 * 25 - math.sqrt((3 * 15 + 10) * (15 + 3 * 10)));

    expect(result.baseArea, closeTo(math.pi * 15 * 10, 0.000001));
    expect(result.lateralArea, closeTo(perimeter * 15, 0.000001));
  });

  test('tronco de cono usa generatriz y área lateral', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.frustum, {
          GeometryComponent.base,
          GeometryComponent.lateral,
        }),
        valuesCm: const {
          GeometryParameters.bottomDiameter: 30,
          GeometryParameters.topDiameter: 10,
          GeometryParameters.height: 20,
        },
      ),
    );
    final slant = math.sqrt(100 + 400);

    expect(result.metadata['slantHeight'], closeTo(slant, 0.000001));
    expect(result.lateralArea, closeTo(math.pi * 20 * slant, 0.000001));
    expect(result.baseArea, closeTo(math.pi * 225, 0.000001));
  });

  test('cono completo admite diámetro superior cero', () {
    final result = engine.calculate(
      GeometryInput(
        profile: _profile(GeometryShape.frustum, {
          GeometryComponent.base,
          GeometryComponent.lateral,
        }),
        valuesCm: const {
          GeometryParameters.bottomDiameter: 30,
          GeometryParameters.topDiameter: 0,
          GeometryParameters.height: 20,
        },
      ),
    );

    expect(result.totalEffectiveArea, greaterThan(0));
  });

  test('tapa cónica se calcula como componente independiente', () {
    final profile = GeometryProfile(
      shapeCode: GeometryShape.cylinder.code,
      components: const {
        GeometryComponent.base,
        GeometryComponent.lateral,
        GeometryComponent.lid,
      },
      dimensionBindings: const {},
      lidType: GeometryLidType.frustum,
    );
    final result = engine.calculate(
      GeometryInput(
        profile: profile,
        valuesCm: const {
          GeometryParameters.diameter: 30,
          GeometryParameters.height: 20,
          GeometryParameters.lidBottomDiameter: 30,
          GeometryParameters.lidTopDiameter: 10,
          GeometryParameters.lidHeight: 8,
        },
      ),
    );

    expect(result.lidArea, greaterThan(0));
    expect(result.metadata['lidSlantHeight'], isNotNull);
  });
}

GeometryProfile _profile(
  GeometryShape shape,
  Set<GeometryComponent> components, {
  GeometryLidType lidType = GeometryLidType.none,
}) => GeometryProfile(
  shapeCode: shape.code,
  components: components,
  dimensionBindings: const {},
  lidType: lidType,
);
