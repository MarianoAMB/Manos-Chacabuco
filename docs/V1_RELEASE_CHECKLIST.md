# Checklist de entrega — V1

Versión de aplicación: **1.0.0+1**  
Versión de SQLite: **8**

## Producto

- [x] Inicio con accesos útiles y orientación cuando no hay datos.
- [x] Materias primas, variantes, categorías y unidades.
- [x] Productos, fotos, composición, costos y precios.
- [x] Presupuestos con snapshots, ajustes, duplicación y recálculo explícito.
- [x] Calculadora geométrica y estimación con nivel de confianza.
- [x] Importación histórica con preview, backup e idempotencia.
- [x] Listas minorista y mayorista.
- [x] PDF e imágenes con fotos.
- [x] PDF e imágenes editoriales sin fotos y en dos columnas.
- [x] Funcionamiento local sin Internet.
- [x] Sincronización incremental y resolución de conflictos.
- [x] Advertencia de cambios sin guardar en formularios principales.
- [x] Mensajes de carga, guardado y error comprensibles.
- [x] Sección Acerca de con versión visible.

## Calidad y datos

- [x] Migración desde SQLite v7 a v8 cubierta por pruebas.
- [x] Claves foráneas activadas.
- [x] Integridad y relaciones de las bases locales encontradas verificadas sobre copias.
- [x] CostEngine y PricingEngine cubiertos por pruebas.
- [x] Snapshot histórico de presupuestos cubierto por pruebas.
- [x] Exports sin información interna cubiertos por regresión.
- [x] Fotos faltantes o dañadas tienen reemplazo visual.
- [x] No se incluyen datos demo en la base inicial.
- [x] Builds, temporales, exports y credenciales locales están ignorados por Git.
- [ ] Importar y revisar en la base de entrega los 46 productos seguros detectados en la planilla real; actualmente las bases personales encontradas no contienen ese catálogo.

## Builds

- [x] Ejecutar el cierre final de analyzer y todos los tests.
- [x] Generar APK debug de prueba.
- [x] Generar APK release de validación.
- [x] Generar el APK privado final y verificar su firma.
- [x] Generar Windows Release.
- [x] Probar el ejecutable Windows desde su carpeta Release completa y con datos aislados.
- [x] Preparar ZIP de la carpeta Windows completa para entrega.

## Configuración externa pendiente

- [x] Crear y configurar el proyecto OAuth según `GOOGLE_DRIVE_SYNC_SETUP.md`.
- [x] Publicar OAuth en producción con página de inicio, privacidad y términos.
- [ ] Ejecutar una sincronización real Windows ↔ Android con la misma cuenta.
- [x] Registrar en Google la misma firma incluida en el APK privado.
- [ ] Reemplazar el ícono predeterminado cuando exista un logo cuadrado aprobado.

## Limitaciones conocidas de V1

- La estimación depende de referencias históricas compatibles y no muestra falsa precisión.
- Formas especiales pueden requerir consumo manual.
- La planilla histórica contiene casos incompletos que necesitan revisión humana.
- Google Drive tiene clientes OAuth de Windows y Android incorporados y el
  proyecto está publicado en producción.
- El APK se distribuye de forma privada, fuera de Play Store. Las futuras
  actualizaciones deben conservar la misma firma Android.
- No hay stock, ventas, pedidos, CRM, ecommerce, facturación ni contabilidad.
- Los tombstones y el historial remoto no tienen todavía una limpieza manual.

## Posibles mejoras para V2 — no implementadas

- Stock, clientes, pedidos e historial de ventas.
- Estadísticas comerciales.
- Catálogo web.
- Nuevas geometrías y política comercial de redondeo.
- Backup avanzado y limpieza administrada del historial remoto.
