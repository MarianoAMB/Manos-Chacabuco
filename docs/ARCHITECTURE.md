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

La versión actual del esquema es **8**. La migración v2 agrega observaciones a variantes, índices para búsqueda y el catálogo inicial extensible de unidades y categorías de materias primas. La migración v3 agrega la excepción de hilo, el rol de cada consumo, índices de consulta y las categorías iniciales editables de productos. La migración v4 amplía presupuestos con duración de validez, tipo de precio, total, configuración productiva por ítem, snapshots serializados y ajustes asociados a ítems o al total. La migración v5 agrega el perfil geométrico serializado a productos e ítems de presupuesto y el origen manual, estimado o confirmado de cada consumo. La migración v6 agrega elegibilidad explícita para calibración, procedencia idempotente de la importación histórica e informes estructurados. La migración v7 agrega la referencia portable al logo y preferencias separadas para las listas minorista y mayorista. La migración v8 agrega estado de sincronización, revisiones, conflictos, cambios remotos procesados, cuenta vinculada, índices y triggers de outbox. No inserta datos de ejemplo y conserva los datos de las versiones anteriores.

`SqliteMaterialRepository` guarda material y variantes en una única transacción. `SqliteProductRepository` guarda el producto y toda su composición también de forma atómica. `SqliteQuoteRepository` guarda cabecera, ítems, recetas, snapshots y ajustes dentro de una transacción. Las eliminaciones operativas son lógicas. Una categoría solo se elimina si no está relacionada y ningún material o variante utilizado por un producto puede eliminarse: debe desactivarse. Una actualización de versión nunca borra ni recrea automáticamente la base de la usuaria.

## Importación histórica

La planilla “Precio Manos Chacabuco” es una fuente inicial de migración, no un backend. El XLSX se lee localmente mediante `XlsxWorkbookReader`; `HistoricalSheetAnalyzer` detecta los bloques por sus encabezados, aplica parsers limitados y produce un `ImportPreview` sin escribir. La pantalla de Configuración muestra conteos, problemas agrupados, posibles duplicados, referencias calibrables y diferencias de precio antes de habilitar la confirmación.

Las fórmulas admitidas se traducen de coordenadas de celdas a IDs reales de materiales. `SheetFormulaParser` reconoce el consumo principal por peso, avíos directos o multiplicados, longitudes proporcionales y sumas de esos términos. Una expresión fuera de ese repertorio no se evalúa: queda registrada para revisión.

Cada fila importada recibe una clave de procedencia estable con spreadsheet, hoja, sección, tipo y fila. `import_records` enlaza esa clave con el UUID local y permite que una reimportación trate el registro como ya importado. Por eso no se vuelven a crear productos, materiales ni relaciones y tampoco se reemplazan cambios manuales posteriores. Los registros locales previos se comparan por nombre normalizado y unidad; una coincidencia clara se reutiliza y una dudosa exige elegir usar el existente, crear otro u omitir.

La confirmación crea primero un backup con timestamp y luego guarda materiales, productos, consumos, procedencias e informe en una única transacción. Un error provoca rollback completo. La tabla `import_reports` conserva conteos, advertencias, filas omitidas y comparaciones App vs. Sheet para diagnóstico. Los presupuestos y sus snapshots no participan de esta operación.

Las medidas se extraen del nombre con reglas pequeñas por familia. Sólo maceteros y familias circulares explícitas reciben cilindro; un oval con tres medidas recibe perfil oval; círculos planos requieren una señal explícita; una bandeja conserva largo y ancho sin inventar forma. El resto guarda medidas genéricas y queda para revisión. Los consumos históricos conocidos se marcan como confirmados, pero sólo las relaciones principales con geometría compatible y distribución no ambigua tienen `calibration_eligible = 1`.

Los límites conocidos son deliberados: no se inventan variantes de color, no se reparte un peso multimaterial, no se crea un material ficticio para costos fijos, no se importan porcentajes históricos como configuración y no se mantienen referencias de Excel en el dominio. Modificar la planilla no modifica la app. La sincronización con Google Drive permanece separada de la importación.

## Listas de precios

Los productos siguen siendo la única fuente de verdad. `PriceListsController` toma los productos y la configuración actuales, reutiliza el cálculo de `ProductsController` —y por lo tanto `CostEngine` y `PricingEngine`— y prepara entradas comerciales con el precio minorista o mayorista efectivo. Cada apertura y cada exportación vuelve a leer ese estado; una lista no congela precios ni modifica productos o presupuestos.

`PriceListDataBuilder` filtra productos activos, seleccionados y con precio válido, aplica categorías, orden y opciones visuales, y produce un `PriceListDocument` neutral. Ese modelo client-facing contiene solamente nombre, categoría, foto local, medidas, material principal, precio y datos de encabezado/pie. No puede transportar costo, hilo, desperdicio, multiplicador, margen, notas internas ni desglose productivo. `ProductCommercialFormatter` resume medidas y materiales principales sin mostrar avíos complementarios.

Los exportadores reciben el documento ya resuelto y nunca consultan SQLite ni calculan precios. `PdfPriceListExporter` crea páginas A4 reales con fuentes Unicode embebidas, cards indivisibles y paginado determinista. `PngPriceListExporter` crea páginas independientes de 1080 × 1350 px; decodifica y reduce las fotos según el tamaño de destino, aplica recorte `cover` y usa un placeholder si falta el archivo. El paginador limita la cantidad de productos por página según el modo con o sin fotos para evitar imágenes verticales enormes y cortes de contenido.

`ShareService` mantiene la plataforma fuera del dominio. En Android, `NativeShareService` entrega el PDF o todas las páginas PNG al share sheet del sistema con MIME correcto; no integra una aplicación específica. En Windows, `PriceListFileService` usa selector de archivo para PDF, selector de carpeta para varias imágenes y permite abrir el archivo o su carpeta. Si no se solicita destino usa una carpeta visible `Manos Chacabuco` dentro de Descargas o Documentos.

Las preferencias visuales de cada tipo se guardan en `price_list_preferences` como configuración, nunca con productos o precios copiados. El logo opcional se copia a `business_assets` dentro del directorio de soporte y SQLite conserva sólo el nombre relativo, igual que la estrategia de fotografías. El logo puede cambiarse o eliminarse; si no existe o su archivo se perdió, encabezados y exportadores usan el nombre del negocio sin fabricar una marca gráfica.

Las limitaciones deliberadas de esta fase son: no hay historial de exportaciones, orden manual por arrastre, impresión nativa, sincronización con Drive ni catálogo web. Las apps receptoras disponibles dependen de lo instalado en Android; Windows prioriza guardar y abrir archivos.

## Presupuestos históricos

El ítem de presupuesto conserva dos capas. La configuración productiva contiene medidas, materiales, variantes, consumos por unidad, roles y reglas propias; sirve para editar, recalcular y convertir en producto sin tocar la referencia original. El snapshot comercial contiene nombres y unidades legibles, costos unitarios usados, desglose de costos, porcentajes efectivos, multiplicador y precios calculados en el momento de guardar. Por eso el detalle histórico no depende exclusivamente de entidades vivas.

`QuoteEngine` orquesta cantidades, ajustes, totales, mínimo mayorista, validez y comparación de recálculo. No reproduce las fórmulas de materiales o precios: la captura y el recálculo pasan por `ProductsController`, que a su vez reutiliza `CostEngine`, `PricingRulesResolver` y `PricingEngine`.

Los ajustes de ítem pertenecen al precio final de una unidad: `precio final unitario = precio calculado + ajustes`. El subtotal multiplica ese resultado por la cantidad comercial. Los ajustes generales se suman una sola vez después de los subtotales. No existe recálculo automático por vencimiento, por cambios del producto base ni por cambios de materias primas.

Las fotos se copian a `product_photos` dentro del directorio de soporte de la aplicación. SQLite guarda solamente un nombre de archivo relativo; el adaptador de almacenamiento resuelve la ruta de cada plataforma. Esto evita rutas absolutas frágiles y mantiene una frontera clara para la sincronización.

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

## Sincronización privada offline-first

SQLite sigue siendo la única fuente operativa. La migración v8 crea el estado de
sincronización, conflictos, cambios remotos procesados y cuenta vinculada. Los
triggers escriben cada cambio de negocio y su outbox dentro de la misma
transacción, y las pantallas nunca esperan a Google Drive para guardar.

Cada cambio remoto es un sobre inmutable y versionado con ID de dispositivo,
ID estable de entidad, operación, hash de contenido, revisión base, revisión
nueva y referencias de assets. Los agregados de material, producto y presupuesto
incluyen sus hijos para respetar dependencias. Fotos y logo son archivos
separados, identificados por SHA-256 y descargados de forma atómica. Los exports
PDF/PNG, builds, temporales y logs quedan fuera.

`SyncEngine` primero incorpora cambios desconocidos y después publica el
outbox. Cambios independientes se combinan; las ramas sobre la misma revisión
crean un conflicto explícito y el resto continúa. Un conflicto conserva todas
las versiones remotas recibidas para la entidad, junto con su dispositivo y
fecha, en filas existentes de `sync_conflicts`. No se usa la hora como
last-write-wins. La versión elegida genera una nueva revisión de unión con todas
las revisiones descartadas en `resolvedRevisions`; de ese modo, cada dispositivo
reconoce el mismo resultado y el conflicto no reaparece. Las eliminaciones
viajan como tombstones y no se purgan automáticamente.

La identidad local estable continúa en `sync_state`, igual que el cache JSON de
los dispositivos conocidos. Esto mantiene el esquema SQLite en **v8** y permite
actualizar sin alterar productos, fotos, presupuestos ni cambios pendientes.
Una compilación anterior todavía puede abrir la base, pero no debe usarse para
resolver un conflicto multidispositivo iniciado por esta versión. Cada sobre
agrega de forma opcional el nombre, la plataforma, la versión de app y los
conteos activos del equipo que lo creó; los lectores anteriores ignoran estos
campos.

Google Drive es sólo el transporte. Usa `appDataFolder` con el scope mínimo
`drive.appdata`; Android autentica con Google Sign-In y Windows usa OAuth de app
nativa con navegador, loopback en `127.0.0.1`, state y PKCE S256. Los refresh
tokens de Windows quedan cifrados con DPAPI para el usuario actual. La configuración externa se
documenta en `docs/GOOGLE_DRIVE_SYNC_SETUP.md`.

Los resúmenes de dispositivos se publican en archivos independientes
`mc-device-*`. No reemplazan ni eliminan los cambios inmutables `mc-change-*` o
los assets `mc-asset-*`, y una versión anterior los ignora porque consulta otro
prefijo. Cada dispositivo actualiza exclusivamente su propio manifiesto después
de una sincronización exitosa; las fechas se guardan en UTC y los conteos se
calculan desde las entidades locales activas. El nombre del equipo se puede
cambiar desde la app. Android excluye la base, los archivos y las preferencias
de Auto Backup y de la transferencia directa: así dos teléfonos no heredan el
mismo `device_id`; Google Drive recompone los datos comerciales.

El inicio local no depende de OAuth ni de red. La sincronización se intenta al
iniciar con una cuenta previa, al recuperar conectividad, al volver al frente,
después de cambios con debounce y manualmente. No requiere un servicio
permanente en segundo plano. El diseño evita un lock remoto global: los cambios
son inmutables e idempotentes y SQLite serializa sus transacciones locales.

## Decisiones diferidas

- Flujo de borradores persistentes ante cierre forzado.
- Política comercial final de redondeo y valores aún no definidos.
- Retención/purga manual de historiales remotos y tombstones.
