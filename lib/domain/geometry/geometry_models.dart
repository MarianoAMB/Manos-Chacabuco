enum GeometryShape {
  circle('circle', 'Círculo plano'),
  cylinder('cylinder', 'Cilindro'),
  oval('oval', 'Oval'),
  frustum('frustum', 'Cono / tronco de cono'),
  other('other', 'Otra forma');

  const GeometryShape(this.code, this.label);

  final String code;
  final String label;

  static GeometryShape fromCode(String code) => values.firstWhere(
    (value) => value.code == code,
    orElse: () => GeometryShape.other,
  );
}

enum GeometryComponent { base, lateral, lid }

enum GeometryLidType { none, flat, frustum }

extension GeometryComponentLabel on GeometryComponent {
  String get label => switch (this) {
    GeometryComponent.base => 'Base',
    GeometryComponent.lateral => 'Laterales',
    GeometryComponent.lid => 'Tapa',
  };
}

extension GeometryLidTypeLabel on GeometryLidType {
  String get label => switch (this) {
    GeometryLidType.none => 'Sin tapa',
    GeometryLidType.flat => 'Tapa plana',
    GeometryLidType.frustum => 'Tapa cónica / tronco de cono',
  };
}

/// Describe qué geometría tiene una pieza y qué medida flexible alimenta cada
/// parámetro. Las áreas se recalculan siempre y no se persisten.
final class GeometryProfile {
  const GeometryProfile({
    required this.shapeCode,
    required this.components,
    required this.dimensionBindings,
    this.lidType = GeometryLidType.none,
  });

  final String shapeCode;
  final Set<GeometryComponent> components;
  final Map<String, String> dimensionBindings;
  final GeometryLidType lidType;

  GeometryShape get shape => GeometryShape.fromCode(shapeCode);

  String get compatibilityKey {
    final componentCodes = components.map((value) => value.name).toList()
      ..sort();
    return '$shapeCode|${componentCodes.join(',')}|${lidType.name}';
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'shapeCode': shapeCode,
    'components': components.map((value) => value.name).toList(),
    'dimensionBindings': dimensionBindings,
    'lidType': lidType.name,
  };

  factory GeometryProfile.fromJson(Map<String, Object?> json) =>
      GeometryProfile(
        shapeCode: json['shapeCode']! as String,
        components: {
          for (final value in json['components']! as List<Object?>)
            GeometryComponent.values.byName(value! as String),
        },
        dimensionBindings: Map<String, String>.from(
          json['dimensionBindings']! as Map,
        ),
        lidType: GeometryLidType.values.byName(
          (json['lidType'] as String?) ?? GeometryLidType.none.name,
        ),
      );
}

abstract final class GeometryParameters {
  static const diameter = 'diameter';
  static const height = 'height';
  static const length = 'length';
  static const width = 'width';
  static const bottomDiameter = 'bottomDiameter';
  static const topDiameter = 'topDiameter';
  static const lidBottomDiameter = 'lidBottomDiameter';
  static const lidTopDiameter = 'lidTopDiameter';
  static const lidHeight = 'lidHeight';

  static String label(String code) => switch (code) {
    diameter => 'Diámetro',
    height => 'Alto',
    length => 'Largo / diámetro mayor',
    width => 'Ancho / diámetro menor',
    bottomDiameter => 'Diámetro inferior',
    topDiameter => 'Diámetro superior',
    lidBottomDiameter => 'Diámetro inferior de tapa',
    lidTopDiameter => 'Diámetro superior de tapa',
    lidHeight => 'Altura de tapa',
    _ => code,
  };

  static List<String> requiredFor(GeometryProfile profile) {
    final result = switch (profile.shape) {
      GeometryShape.circle => <String>[diameter],
      GeometryShape.cylinder => <String>[
        diameter,
        if (profile.components.contains(GeometryComponent.lateral)) height,
      ],
      GeometryShape.oval => <String>[
        length,
        width,
        if (profile.components.contains(GeometryComponent.lateral)) height,
      ],
      GeometryShape.frustum => <String>[bottomDiameter, topDiameter, height],
      GeometryShape.other => <String>[],
    };
    if (profile.components.contains(GeometryComponent.lid) &&
        profile.lidType == GeometryLidType.frustum) {
      result.addAll([lidBottomDiameter, lidTopDiameter, lidHeight]);
    }
    return result;
  }
}
