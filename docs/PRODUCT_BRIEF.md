# Manos Chacabuco — definición de producto

## Propósito

Manos Chacabuco necesita reemplazar progresivamente su planilla de costos por una aplicación clara, confiable y usable desde Android y Windows. La aplicación debe acompañar el trabajo artesanal: reducir cálculos manuales, explicar de dónde surge cada precio y admitir excepciones sin convertir el producto en un ERP.

Este documento es la fuente de verdad funcional. Los cambios de reglas deben actualizarse aquí antes de implementarse.

## Usuaria y principios de experiencia

La usuaria principal es la emprendedora y no necesita conocer conceptos técnicos. Toda la interfaz se presenta en español y prioriza tareas frecuentes, resultados y lenguaje cotidiano.

- Mostrar costo total, precio mayorista y precio minorista antes del detalle de las fórmulas.
- Ofrecer "Ver detalle del cálculo" para conservar trazabilidad.
- Proponer valores predeterminados y permitir excepciones por producto o presupuesto.
- Evitar cálculos mentales, falsa precisión y terminología financiera innecesaria.
- Confirmar eliminaciones, conservar borradores cuando corresponda y crear estados vacíos orientativos.
- Mantener acciones cómodas para tacto en móvil y aprovechar el ancho de escritorio sin estirar layouts móviles.

## Plataformas y operación

- Una única aplicación Flutter para Android y Windows Desktop.
- Las dos plataformas permiten crear, consultar, modificar y eliminar todos los datos.
- La navegación es inferior en móvil y lateral en escritorio.
- El funcionamiento normal es offline-first: la base local es la fuente operativa de cada dispositivo.
- La sincronización opcional con Google Drive es un proceso separado del dominio y nunca bloquea el trabajo local.

## Alcance funcional del producto

### Materias primas

Una materia prima describe qué se compra y cómo se consume. Debe soportar peso, longitud, superficie y unidades; el catálogo de unidades puede ampliarse sin modificar las fórmulas centrales.

Datos principales: nombre, categoría, descripción, presentación de compra, cantidad comprada, precio, costo por unidad base, proveedor o marca, observaciones, estado y metadatos temporales.

Un material puede no tener variantes o tener variantes con precios propios, por ejemplo colores de un mismo cordón. El costo de una elaboración con varias variantes es la suma del consumo real de cada una; nunca se usa un promedio simple de sus precios.

### Productos

Un producto representa una pieza fabricada. Puede incluir categoría, descripción, foto opcional, una lista flexible de medidas (nombre, valor y unidad), perfil geométrico, consumos de materiales y variantes, avíos, observaciones y reglas de precio. Todos los datos importados o creados continúan siendo editables. El perfil geométrico enlaza parámetros como diámetro, alto o ejes con las medidas flexibles existentes: no crea un segundo juego de dimensiones.

Cada consumo se clasifica explícitamente como material principal o complementario y registra su origen como manual, estimado o real confirmado. Esto evita inferencias ambiguas y permite que cordones, cueros, cierres, mosquetones y otros avíos se representen con la misma estructura. Un producto histórico conserva referencias a materiales o variantes inactivas; las nuevas líneas ofrecen activos por defecto.

La foto es siempre opcional y se guarda localmente con una referencia relativa controlada por la aplicación. El desperdicio, el hilo y el porcentaje minorista usan el valor global salvo que el producto defina una excepción. El multiplicador de precio pertenece al producto, aunque se puede sugerir uno predeterminado al crearlo.

### Costos y precios

Valores iniciales configurables:

| Configuración | Valor inicial |
| --- | ---: |
| Desperdicio | 1,5 % |
| Hilo sobre materia prima | 6 % |
| Porcentaje minorista | Sin definir |
| Multiplicador sugerido | Opcional / sin definir |
| Monto mínimo mayorista | Sin definir |
| Moneda | ARS |
| Nombre del negocio | Manos Chacabuco |

Reglas conocidas:

1. El costo de materiales suma `consumo real de cada línea × costo unitario actual de su material o variante`. Esa suma es la fuente de verdad; nunca se promedian precios sin ponderar cantidades.
2. Hilo y desperdicio se calculan exclusivamente sobre el subtotal de materiales principales, usando sus porcentajes efectivos. Los complementarios y avíos se suman después y no reciben esos porcentajes.
3. `precio mayorista = costo total × multiplicador del producto`.
4. `precio minorista = precio mayorista × (1 + porcentaje minorista)`.
5. La mano de obra no es un costo separado; la clienta la contempla en el multiplicador.

Costos, subtotales y precios son valores derivados: no se copian dentro del producto. Si cambia el precio o la presentación de compra de una materia prima o variante, todo producto relacionado se recalcula con el valor actual. Los únicos valores persistidos son referencias, consumos, roles, reglas propias y el multiplicador.

Los importes se guardan en unidades monetarias menores enteras. Los porcentajes y multiplicadores usan valores decimales escalados; no se realizan operaciones de dinero con `Double`.

### Presupuestos personalizados

Un presupuesto tendrá cliente, fecha, vigencia, observaciones y múltiples ítems con cantidades y precios. Puede partir de un producto y cambiar tamaño, color, material o forma. También admite ajustes extraordinarios positivos o negativos con descripción.

Debe poder guardarse, editarse, duplicarse, eliminarse y convertir cualquiera de sus ítems personalizados en un producto nuevo. El monto mínimo mayorista es monetario, no una cantidad mínima de unidades.

La receta de cada ítem se mantiene separada del producto vivo usado como base. Mientras se edita se calculan costos con los materiales actuales; al guardar se conserva una copia histórica legible de materiales, variantes, consumos, reglas, costos y precios. Una variación posterior de una materia prima o del producto original no altera una oferta ya guardada. La actualización sólo ocurre mediante la acción explícita “Recalcular con precios actuales”, después de mostrar una comparación.

La validez se expresa principalmente como cantidad de días y conserva también fecha inicial y fecha final. Un presupuesto es vigente hasta incluir su fecha de vencimiento y pasa a vencido al día siguiente, sin perder ni modificar su precio. Al duplicar se conservan los días y la nueva fecha final se calcula desde la nueva fecha.

Los ajustes adicionales asociados a un ítem se suman o restan directamente de su precio final por unidad, sin recibir nuevamente el multiplicador. Los ajustes generales se aplican una vez sobre el total. Si el tipo de precio es mayorista se compara el total con el mínimo económico configurado y se advierte sin bloquear.

### Calculadora

La calculadora separa:

1. geometría;
2. superficie o longitud relevante;
3. comportamiento del material;
4. consumo estimado;
5. desperdicio;
6. costo;
7. precio sugerido.

El motor de formas usa estrategias registrables. Redonda, cilíndrica, ovalada, tronco de cono y tapa cónica son las primeras formas conocidas, no un listado cerrado. Base, lateral y tapa se eligen por separado para representar lo que realmente se fabrica.

Hay dos modos de uso. “Basado en un producto” escala físicamente toda la receta principal de una referencia elegida y conserva la distribución real entre variantes. “Pieza nueva” estima un material con productos históricos geométricamente compatibles, permite elegir la variante que define el costo, sumar avíos y usar un consumo manual cuando aún no existen referencias. Una forma “Otra” nunca inventa una fórmula: exige consumo manual.

La calibración normaliza consumos y medidas a unidades base, agrega las variantes del mismo material para hallar su consumo físico total y después mantiene cada variante separada para costearla con su precio real. Los consumos confirmados tienen prioridad sobre los manuales y los estimados. Con varias referencias se usa una mediana ponderada, se descartan valores atípicos por desviación absoluta mediana y se informa el rango retenido. La confianza es buena con al menos tres referencias coherentes, limitada con una o dos o con dispersión alta, e insuficiente cuando no queda ninguna referencia válida. Ningún resultado estimado se aplica a un producto o presupuesto sin confirmación explícita.

### Listas de precios e importación

Las listas minorista y mayorista se construyen con productos activos y precios vigentes. Permiten seleccionar categorías y productos, buscar, ordenar, agrupar, alternar fotos, medidas y material principal, mostrar fecha, mínimo mayorista y una nota opcional, y ver una previsualización antes de exportar. Generan PDF A4 multipágina o páginas PNG de 1080 × 1350; Android comparte los archivos mediante el sistema nativo y Windows permite elegir destino y abrir el resultado o su carpeta.

Son piezas comerciales, no presupuestos: no tienen cliente, cantidades, validez ni snapshot en la base. Nunca muestran costos internos, materias primas valorizadas, hilo, desperdicio, multiplicadores, márgenes o detalles de fabricación. Las preferencias guardan sólo opciones visuales y selección; el precio se vuelve a calcular desde el producto al preparar la próxima exportación.

La hoja "Precio Manos Chacabuco" será una fuente de datos inicial. Sus coordenadas y fórmulas no forman parte del modelo de la aplicación.

## Datos, identidad y sincronización

Las entidades sincronizables usan UUID estable, `createdAt`, `updatedAt` y `deletedAt` para borrado lógico. La base mantiene una bandeja de cambios locales. El diseño implementado es:

`base local ↔ motor de sincronización ↔ Google Drive ↔ motor de sincronización ↔ base local`

El repositorio de sincronización y la resolución de conflictos son fronteras explícitas. La falta de conexión o de Drive no impide trabajar.

## Módulos principales

- Inicio
- Productos
- Materias primas
- Presupuestos
- Calculadora
- Listas de precios
- Configuración

## Estado por fases

### Fase fundacional

Incluye documentación, arquitectura, proyecto Flutter Android/Windows, sistema visual, shell adaptativo, dashboard demo, modelos esenciales, contratos de repositorio, base SQLite versionada, configuración inicial, utilidades monetarias y pruebas de infraestructura.

### Fase 2 — materias primas y configuración

Incluye el CRUD completo de materias primas, variantes opcionales y categorías; unidades extensibles de peso, longitud, superficie y cantidad; costo unitario preciso; búsqueda y filtros; activación y borrado lógico; configuración general editable; dashboard con datos reales; y persistencia SQLite en Android y Windows. La base comienza sin materiales demo y conserva solamente los catálogos iniciales editables.

Quedan deliberadamente pendientes para fases posteriores: productos completos, calculadora calibrada, presupuestos, exportaciones, compartir, sincronización Drive, importación de la planilla, stock, CRM, pedidos, ventas y analítica avanzada.

### Fase 3 — productos y motor real de costos

Incluye categorías de productos editables; CRUD completo con búsqueda y filtros; medidas flexibles; múltiples líneas de material y variantes; rol principal o complementario explícito; validación de unidades; cálculo con costos actuales; reglas generales y excepciones por producto; mayorista y minorista; desglose comprensible; duplicación; fotos locales opcionales; activación; protecciones referenciales; dashboard actualizado; y persistencia transaccional en SQLite.

Quedan deliberadamente pendientes para fases posteriores: calculadora geométrica, presupuestos, exportaciones, compartir, sincronización Drive, importación de la planilla, stock, CRM, pedidos, ventas y analítica avanzada.

### Fase 4 — presupuestos personalizados

Incluye creación guiada con cliente, fecha, validez en días y vencimiento editable; tipo minorista o mayorista; múltiples ítems y cantidades; personalización desde productos existentes o desde cero; medidas y consumos manuales; materiales, variantes y roles; ajustes por unidad y generales; detalle comercial con cálculo progresivo; búsqueda, filtros, edición, duplicación, vencimiento, borrado lógico y advertencia de mínimo mayorista.

Cada ítem guarda su configuración productiva y un snapshot comercial autónomo. El precio histórico sólo cambia al editar una configuración que afecta importes o al confirmar “Recalcular con precios actuales”. La duplicación conserva la duración de validez y calcula un nuevo vencimiento desde la fecha nueva. Un ítem puede abrirse como producto nuevo para revisión; nunca copia cliente, vigencia, cantidad comercial, snapshot ni ajustes monetarios.

La calculadora geométrica y la estimación automática de consumo se incorporan en la fase 5. Continúan fuera de alcance exportaciones PDF/imagen, compartir, sincronización Drive, importación de la planilla, stock, CRM, pedidos, ventas y analítica avanzada.

### Fase 5 — calculadora geométrica y estimación calibrada

Incluye una calculadora operativa accesible desde la navegación y el inicio; modos por producto de referencia y pieza nueva; fórmulas puras para círculo, cilindro, óvalo y tronco de cono; selección independiente de base, lateral y tapa plana o cónica; calibración con productos históricos compatibles; prioridad por origen del consumo; rechazo robusto de valores atípicos; rango y confianza visibles; consumo manual seguro cuando faltan referencias; costeo ponderado por variantes; avíos; desperdicio, hilo, costo y precios mediante los motores existentes; y creación de un producto nuevo para revisión.

La misma estimación puede proponerse al editar un producto o personalizar un ítem de presupuesto. Cambiar medidas sólo muestra una advertencia; el consumo se modifica únicamente al pulsar “Estimar consumo”, revisar la propuesta y confirmarla. En presupuestos se modifica exclusivamente la receta del ítem y su snapshot se invalida para el recálculo normal, sin tocar el producto original.

Quedan deliberadamente pendientes para la fase siguiente: importación real de la planilla “Precio Manos Chacabuco”. También continúan fuera de alcance exportaciones PDF/imagen, compartir, sincronización Drive, stock, CRM, pedidos, ventas y analítica avanzada.

### Fase 6 — importación histórica inicial

Incluye lectura local del XLSX real con valores y fórmulas; detección semántica de los bloques Deco y Accesorios; preview sin escritura; clasificación de confianza; importación transaccional de materiales, productos, consumos principales y complementarios; pesos confirmados; multiplicadores por producto; medidas y perfiles geométricos prudentes; comparación de costos históricos con los motores actuales; resolución explícita de duplicados; backup automático; procedencia idempotente; informe local y referencias elegibles para la Calculadora.

La importación es de una sola vía y la app pasa a ser la fuente de verdad. Reimportar sólo detecta datos nuevos o conflictos y nunca sobrescribe silenciosamente una edición local. Los porcentajes de desperdicio y minorista observados en la planilla permanecen como contexto histórico: los defaults confirmados siguen siendo 1,5 % de desperdicio y 6 % de hilo.

Continúan fuera de alcance exportaciones PDF/imagen, compartir, sincronización con Google Drive, stock, CRM, pedidos, ventas y analítica avanzada.

### Fase 7 — listas de precios comerciales

Incluye listas independientes minorista y mayorista basadas en productos activos y precios efectivos actuales; selección por categoría y producto; búsqueda; cuatro órdenes deterministas; presentación con o sin fotos; medidas y material principal opcionales; agrupación; mínimo mayorista; fecha y nota al pie; preview adaptativo; PDF A4 multipágina; PNG paginado de 1080 × 1350; nombres de archivo legibles; share sheet nativo de Android; guardado, apertura de archivo y apertura de carpeta en Windows; logo opcional portable; y preferencias visuales por tipo de lista.

La salida usa un modelo comercial limitado que no transporta costos, hilo, desperdicio, multiplicador, margen, notas internas ni desglose de fabricación. Exportar no modifica productos, no crea snapshots y no toca presupuestos históricos. Continúan fuera de alcance Google Drive Sync, historial de exportaciones, orden manual por arrastre, impresión nativa, stock, CRM, ventas, pedidos, ecommerce, catálogo web público y analítica avanzada.

### Fase 8 — export editorial y sincronización privada

Exportar comienza eligiendo **Con fotos** o **Sin fotos** y después PDF,
imágenes o compartir cuando la plataforma lo permite. Con fotos conserva el
catálogo visual. Sin fotos usa un diseño propio de dos columnas de productos por
página, sin tarjetas fotográficas ni placeholders; mantiene encabezado,
categorías, precio, medidas, material y pie con cortes deterministas. El preview
muestra exactamente el modo elegido y las preferencias se recuerdan por tipo de
lista. Ambos modos continúan usando exclusivamente datos comerciales.

La sincronización opcional replica con Google Drive la base operativa entre
Windows y Android sin reemplazar SQLite. Guarda primero en local, mantiene una
cola transaccional y sincroniza incrementalmente configuraciones, catálogos,
materiales, productos, recetas, geometría, presupuestos, snapshots, preferencias
de lista y metadatos de importación. Fotos y logo viajan como assets deduplicados
por hash. Los PDFs/PNGs exportados nunca se suben automáticamente.

La misma cuenta de Google accede al espacio privado de la app. Los cambios en
entidades distintas se combinan; una edición concurrente de la misma entidad
queda visible para elegir versión local o remota, sin sobrescritura silenciosa.
El borrado usa tombstones, los snapshots de presupuesto se trasladan sin
recalcular y desconectar Google no borra datos locales. La app conserva toda su
funcionalidad sin cuenta o sin Internet.

### Fase 9 — cierre de V1

La versión 1.0.0 consolida los módulos existentes sin ampliar el alcance. Agrega
protección consistente ante cambios sin guardar, feedback de acciones,
recuperación visual para imágenes faltantes o dañadas, arranque con estado de
carga, nombre correcto en ambas plataformas, sección Acerca de, revisión
responsive y documentación de uso y entrega. La base continúa en SQLite v8 y
las migraciones existentes se conservan sin recrear datos.

## Criterios de aceptación transversales

- La lógica de negocio no vive en widgets.
- Los cálculos son deterministas y testeables.
- El dominio no depende de SQLite, Flutter ni Google Drive.
- Las eliminaciones operativas se modelan como borrado lógico para sincronización.
- Los nuevos módulos respetan los tokens y componentes visuales compartidos.
- Formatter, analizador y pruebas deben quedar verdes antes de cada entrega.
