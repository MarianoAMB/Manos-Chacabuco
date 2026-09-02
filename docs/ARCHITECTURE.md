# Arquitectura técnica

## Enfoque

La aplicación usa una arquitectura por capas, liviana y orientada por funcionalidades. Las dependencias apuntan hacia el dominio:

`presentation → domain ← data`

`app` compone las capas y `core` contiene infraestructura transversal. No se introduce un framework de inyección ni generación de código en esta fase; los objetos se construyen explícitamente y los contratos permiten reemplazarlos cuando el producto crezca.

## Capas

- `lib/app`: arranque, composición, destinos y shell adaptativo.
- `lib/features`: pantallas y estado de presentación agrupados por función.
- `lib/domain`: entidades, value objects, contratos de repositorio y motores puros.
- `lib/data`: adaptadores concretos de persistencia.
- `lib/core`: SQLite, dinero, sincronización transversal y design system.

Los widgets nunca calculan costos, precios, geometría ni calibraciones. `GeometryEngine`, `MaterialEstimationEngine`, `CostEngine`, `PricingEngine` y `QuoteEngine` reciben objetos del dominio y devuelven resultados puros.

## Estado y navegación

La navegación conserva estado local pequeño. `MaterialsController`, `ProductsController`, `QuotesController` y `SettingsController` coordinan los casos de uso asíncronos y notifican a la presentación sin introducir una dependencia adicional de state management. `ProductsController` escucha cambios de materiales y configuración para que los resultados derivados se actualicen sin copiar costos. `QuotesController` usa esos cálculos al editar, pero mantiene los importes históricos después de guardar. La composición explícita permite incorporar Riverpod, Bloc u otra solución si aparecen flujos más complejos sin modificar el dominio.

El shell cambia en el breakpoint de 800 px:

- compacto: barra inferior para las tareas frecuentes y hoja “Más” para las restantes;
- expandido: barra lateral persistente con todos los destinos;
- contenido: ancho máximo para conservar legibilidad en monitores grandes.

## Persistencia

SQLite es la fuente local. Android usa `sqflite` y Windows `sqflite_common_ffi`; ambos exponen el mismo contrato. `AppDatabase` controla el número de esquema, la configuración de claves foráneas y las migraciones.

El esquema inicial incluye configuración, categorías, materiales, variantes, productos, consumos, presupuestos, ítems, ajustes y una bandeja de sincronización. Tener tablas no implica que su CRUD ya esté habilitado.

Las migraciones son incrementales: nunca se edita una versión ya publicada; se agrega el siguiente paso y se prueba el upgrade.

La versión actual del esquema es **6**. La migración v2 agrega observaciones a variantes, índices para búsqueda y el catálogo inicial extensible de unidades y categorías de materiales. La migración v3 agrega el override de hilo, el rol de cada consumo, índices de consulta y las categorías iniciales editables de productos. La migración v4 amplía presupuestos con duración de validez, tipo de precio, total, configuración productiva por ítem, snapshots serializados y ajustes asociados a ítems o al total. La migración v5 agrega el perfil geométrico serializado a productos e ítems de presupuesto y el origen manual, estimado o confirmado de cada consumo. La migración v6 agrega elegibilidad explícita para calibración, procedencia idempotente de la importación histórica e informes estructurados. No inserta datos de ejemplo y conserva los datos de las versiones anteriores.

`SqliteMaterialRepository` guarda material y variantes en una única transacción. `SqliteProductRepository` guarda el producto y toda su composición también de forma atómica. `SqliteQuoteRepository` guarda cabecera, ítems, recetas, snapshots y ajustes dentro de una transacción. Las eliminaciones operativas son lógicas. Una categoría solo se elimina si no está relacionada y ningún material o variante utilizado por un producto puede eliminarse: debe desactivarse. Una actualización de versión nunca borra ni recrea automáticamente la base de la usuaria.

## Importación histórica

La planilla “Precio Manos Chacabuco” es una fuente inicial de migración, no un backend. El XLSX se lee localmente mediante `XlsxWorkbookReader`; `HistoricalSheetAnalyzer` detecta los bloques por sus encabezados, aplica parsers limitados y produce un `ImportPreview` sin escribir. La pantalla de Configuración muestra conteos, problemas agrupados, posibles duplicados, referencias calibrables y diferencias de precio antes de habilitar la confirmación.

Las fórmulas admitidas se traducen de coordenadas de celdas a IDs reales de materiales. `SheetFormulaParser` reconoce el consumo principal por peso, avíos directos o multiplicados, longitudes proporcionales y sumas de esos términos. Una expresión fuera de ese repertorio no se evalúa: queda registrada para revisión.

Cada fila importada recibe una clave de procedencia estable con spreadsheet, hoja, sección, tipo y fila. `import_records` enlaza esa clave con el UUID local y permite que una reimportación trate el registro como ya importado. Por eso no se vuelven a crear productos, materiales ni relaciones y tampoco se reemplazan cambios manuales posteriores. Los registros locales previos se comparan por nombre normalizado y unidad; una coincidencia clara se reutiliza y una dudosa exige elegir usar el existente, crear otro u omitir.

La confirmación crea primero un backup con timestamp y luego guarda materiales, productos, consumos, procedencias e informe en una única transacción. Un error provoca rollback completo. La tabla `import_reports` conserva conteos, advertencias, filas omitidas y comparaciones App vs. Sheet para diagnóstico. Los presupuestos y sus snapshots no participan de esta operación.

Las medidas se extraen del nombre con reglas pequeñas por familia. Sólo maceteros y familias circulares explícitas reciben cilindro; un oval con tres medidas recibe perfil oval; círculos planos requieren una señal explícita; una bandeja conserva largo y ancho sin inventar forma. El resto guarda medidas genéricas y queda para revisión. Los consumos históricos conocidos se marcan como confirmados, pero sólo las relaciones principales con geometría compatible y distribución no ambigua tienen `calibration_eligible = 1`.

Los límites conocidos son deliberados: no se inventan variantes de color, no se reparte un peso multimaterial, no se crea un material ficticio para costos hardcodeados, no se importan porcentajes históricos como configuración y no se mantienen referencias de Excel en el dominio. Modificar el Sheet no modifica la app. La futura sincronización con Google Drive permanece separada.

## Presupuestos históricos

El ítem de presupuesto conserva dos capas. La configuración productiva contiene medidas, materiales, variantes, consumos por unidad, roles y reglas propias; sirve para editar, recalcular y convertir en producto sin tocar la referencia original. El snapshot comercial contiene nombres y unidades legibles, costos unitarios usados, desglose de costos, porcentajes efectivos, multiplicador y precios calculados en el momento de guardar. Por eso el detalle histórico no depende exclusivamente de entidades vivas.

`QuoteEngine` orquesta cantidades, ajustes, totales, mínimo mayorista, validez y comparación de recálculo. No reproduce las fórmulas de materiales o precios: la captura y el recálculo pasan por `ProductsController`, que a su vez reutiliza `CostEngine`, `PricingRulesResolver` y `PricingEngine`.

Los ajustes de ítem pertenecen al precio final de una unidad: `precio final unitario = precio calculado + ajustes`. El subtotal multiplica ese resultado por la cantidad comercial. Los ajustes generales se suman una sola vez después de los subtotales. No existe recálculo automático por vencimiento, por cambios del producto base ni por cambios de materias primas.

Las fotos se copian a `product_photos` dentro del directorio de soporte de la aplicación. SQLite guarda solamente un nombre de archivo relativo; el adaptador de almacenamiento resuelve la ruta de cada plataforma. Esto evita rutas absolutas frágiles y deja una frontera clara para sincronización futura.

## Dinero y decimales

`Money` guarda centavos en un `int` de 64 bits en las plataformas objetivo. `DecimalValue` guarda millonésimas para porcentajes, factores y cantidades. `PreciseUnitCost` conserva seis decimales de centavo al dividir una compra por su cantidad normalizada. Multiplicación y redondeo se realizan con enteros usando half-away-from-zero, centralizados y testeados.

Esta decisión evita errores binarios de `Double` y permite evolucionar la política de redondeo sin recorrer las pantallas.

## Geometría y calibración

`GeometryEngine` es un registro de estrategias puras identificadas por código. Las estrategias incluidas calculan áreas en centímetros cuadrados para círculo, cilindro, óvalo y tronco de cono. Cada resultado separa base, lateral y tapa; una tapa plana reutiliza el área de la base y una tapa cónica usa su propia generatriz. Agregar una forma nueva requiere implementar otra estrategia, no modificar costos, presupuestos ni pantallas existentes.

Las fórmulas aplicadas son:

- círculo: `π × radio²`;
- cilindro: base `π × radio²` y lateral `2 × π × radio × alto`;
- óvalo: base `π × semieje mayor × semieje menor` y lateral `perímetro aproximado de Ramanujan × alto`;
- tronco de cono: base `π × radio inferior²` y lateral `π × (radio inferior + radio superior) × generatriz`, donde la generatriz es `√(alto² + (radio inferior - radio superior)²)`;
- tapa cónica o truncada: la misma fórmula lateral del tronco, calculada con el radio exterior, el radio superior y el alto propios de la tapa.

La **superficie efectiva** es la suma exclusiva de los componentes elegidos —base, lateral y tapa— y funciona como denominador físico de la calibración. No incluye desperdicio ni hilo: esos porcentajes se aplican una sola vez después, mediante `CostEngine`, para evitar duplicarlos.

`GeometryProfile` persiste la forma, componentes, tipo de tapa y el enlace semántico entre parámetros geométricos y medidas flexibles. `ProductsController` convierte longitudes mediante `UnitConverter`, invoca geometría y prepara referencias compatibles sin duplicar fórmulas.

`MaterialEstimationEngine` trabaja en unidades base. Primero prioriza consumos reales confirmados; si no existen, admite registros manuales y por último históricos estimados. Para múltiples referencias calcula predicciones por densidad superficial, descarta atípicos mediante desviación absoluta mediana y usa una mediana ponderada por calidad de fuente y cercanía geométrica. El rango mínimo–máximo se deriva sólo de referencias retenidas. Una única referencia produce un valor puntual sin fingir un intervalo; ninguna referencia produce confianza insuficiente y obliga a intervención manual.

Las variantes se agregan únicamente para calibrar el consumo físico total de un material. Al proyectar una receta existente se preserva su proporción y cada línea vuelve a `CostEngine` con su variante, por lo que el costo sigue siendo una suma ponderada real. Los avíos permanecen complementarios y no reciben hilo ni desperdicio. Las estimaciones guardadas quedan marcadas como tales hasta que la usuaria las cambie a reales confirmadas.

## Defaults y overrides

`AppSettings` guarda reglas globales. El producto usa `PricingOverrides` para desperdicio, hilo y minorista; un campo nulo significa “heredar el valor global”. El multiplicador queda fijado en cada producto desde su creación. Un resolver construye las reglas efectivas antes de invocar `CostEngine` y `PricingEngine`.

`CostEngine` resuelve el costo unitario vigente de cada referencia, normaliza unidades, suma consumos reales y aplica hilo/desperdicio sólo al subtotal principal. `PricingEngine` recibe el costo total derivado, aplica el multiplicador y calcula el minorista únicamente cuando existe porcentaje efectivo. Los resultados estructurados no se persisten como fuente de verdad.

## Preparación para sincronización

Las entidades usan `SyncMetadata`. Las escrituras futuras deben guardar el cambio de negocio y su entrada de outbox en la misma transacción. `SyncGateway` representa el transporte remoto y `SyncRepository` la cola local; Google Drive será un adaptador, no una dependencia del dominio.

La resolución de conflictos se definirá con los casos reales. Hasta entonces no se presupone que “última escritura gana” sea correcto para todos los datos.

## Decisiones diferidas

- Política de conflicto y formato remoto en Drive.
- Flujo de borradores persistentes ante cierre forzado.
- Política comercial final de redondeo y valores aún no definidos.
- Formato remoto de fotos y exportaciones.
