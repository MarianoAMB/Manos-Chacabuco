import 'package:flutter/material.dart';

import '../../../core/design_system/app_tokens.dart';
import '../../../domain/geometry/geometry_models.dart';

Future<GeometryProfile?> showGeometryProfileEditorDialog({
  required BuildContext context,
  required List<String> measureNames,
  GeometryProfile? current,
}) => showDialog<GeometryProfile?>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _GeometryProfileEditor(measureNames: measureNames, current: current),
);

final class _GeometryProfileEditor extends StatefulWidget {
  const _GeometryProfileEditor({required this.measureNames, this.current});

  final List<String> measureNames;
  final GeometryProfile? current;

  @override
  State<_GeometryProfileEditor> createState() => _GeometryProfileEditorState();
}

final class _GeometryProfileEditorState extends State<_GeometryProfileEditor> {
  late GeometryShape _shape;
  late Set<GeometryComponent> _components;
  late GeometryLidType _lidType;
  late Map<String, String> _bindings;

  @override
  void initState() {
    super.initState();
    _shape = widget.current?.shape ?? GeometryShape.cylinder;
    _components = {...(widget.current?.components ?? _defaultsFor(_shape))};
    _lidType = widget.current?.lidType ?? GeometryLidType.none;
    _bindings = {...?widget.current?.dimensionBindings};
    _completeAutomaticBindings();
  }

  Set<GeometryComponent> _defaultsFor(GeometryShape shape) => switch (shape) {
    GeometryShape.circle => {GeometryComponent.base},
    GeometryShape.cylinder || GeometryShape.oval || GeometryShape.frustum => {
      GeometryComponent.base,
      GeometryComponent.lateral,
    },
    GeometryShape.other => <GeometryComponent>{},
  };

  GeometryProfile get _profile => GeometryProfile(
    shapeCode: _shape.code,
    components: _components,
    dimensionBindings: _bindings,
    lidType: _components.contains(GeometryComponent.lid)
        ? _lidType
        : GeometryLidType.none,
  );

  void _completeAutomaticBindings() {
    for (final parameter in GeometryParameters.requiredFor(_profile)) {
      if (widget.measureNames.contains(_bindings[parameter])) continue;
      final wanted = _normalized(GeometryParameters.label(parameter));
      final exact = widget.measureNames.where(
        (name) => _normalized(name) == wanted,
      );
      final semantic = widget.measureNames.where(
        (name) => _matchesParameter(parameter, _normalized(name)),
      );
      final match = exact.firstOrNull ?? semantic.firstOrNull;
      if (match != null) _bindings[parameter] = match;
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Forma para cálculo'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<GeometryShape>(
              key: const Key('geometry-shape'),
              initialValue: _shape,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Forma'),
              items: [
                for (final shape in GeometryShape.values)
                  DropdownMenuItem(value: shape, child: Text(shape.label)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _shape = value;
                  _components = _defaultsFor(value);
                  _lidType = GeometryLidType.none;
                  _bindings = {};
                  _completeAutomaticBindings();
                });
              },
            ),
            if (_shape == GeometryShape.other) ...[
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Podés guardar esta forma, pero el consumo deberá ingresarse manualmente hasta que exista una fórmula compatible.',
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Superficies',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final component in GeometryComponent.values)
                    FilterChip(
                      key: Key('geometry-component-${component.name}'),
                      label: Text(component.label),
                      selected: _components.contains(component),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _components.add(component);
                          if (component == GeometryComponent.lid &&
                              _lidType == GeometryLidType.none) {
                            _lidType = GeometryLidType.flat;
                          }
                        } else {
                          _components.remove(component);
                          if (component == GeometryComponent.lid) {
                            _lidType = GeometryLidType.none;
                          }
                        }
                        _completeAutomaticBindings();
                      }),
                    ),
                ],
              ),
              if (_components.contains(GeometryComponent.lid)) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<GeometryLidType>(
                  key: const Key('geometry-lid-type'),
                  initialValue: _lidType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo de tapa'),
                  items: [
                    for (final type in GeometryLidType.values.where(
                      (value) => value != GeometryLidType.none,
                    ))
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) => setState(() {
                    _lidType = value ?? GeometryLidType.flat;
                    _completeAutomaticBindings();
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'Vincular medidas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              if (widget.measureNames.isEmpty)
                const Text('Primero agregá las medidas del producto.'),
              for (final parameter in GeometryParameters.requiredFor(_profile))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: DropdownButtonFormField<String>(
                    key: Key('geometry-binding-$parameter'),
                    initialValue:
                        widget.measureNames.contains(_bindings[parameter])
                        ? _bindings[parameter]
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: GeometryParameters.label(parameter),
                    ),
                    items: [
                      for (final name in widget.measureNames)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (value) => setState(() {
                      if (value == null) {
                        _bindings.remove(parameter);
                      } else {
                        _bindings[parameter] = value;
                      }
                    }),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (widget.current != null)
        TextButton(
          key: const Key('remove-geometry-profile'),
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Quitar forma'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context, widget.current),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('save-geometry-profile'),
        onPressed: _save,
        child: const Text('Aceptar'),
      ),
    ],
  );

  void _save() {
    if (_shape != GeometryShape.other) {
      if (_components.isEmpty) {
        _message('Elegí al menos una superficie.');
        return;
      }
      final missing = GeometryParameters.requiredFor(_profile)
          .where((parameter) => !_bindings.containsKey(parameter));
      if (missing.isNotEmpty) {
        _message(
          'Vinculá ${GeometryParameters.label(missing.first).toLowerCase()}.',
        );
        return;
      }
    }
    Navigator.pop(context, _profile);
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  String _normalized(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _matchesParameter(String parameter, String name) => switch (parameter) {
    GeometryParameters.diameter => name.contains('diametro'),
    GeometryParameters.height =>
      name.contains('alto') || name.contains('altura'),
    GeometryParameters.length =>
      name.contains('largo') || name.contains('mayor'),
    GeometryParameters.width =>
      name.contains('ancho') || name.contains('menor'),
    GeometryParameters.bottomDiameter =>
      name.contains('inferior') || name.contains('base'),
    GeometryParameters.topDiameter => name.contains('superior'),
    GeometryParameters.lidBottomDiameter =>
      name.contains('tapainferior') || name.contains('tapabase'),
    GeometryParameters.lidTopDiameter => name.contains('tapasuperior'),
    GeometryParameters.lidHeight =>
      name.contains('tapaalto') || name.contains('tapaaltura'),
    _ => false,
  };
}
