# Manos Chacabuco

Aplicación offline-first de costos, precios y presupuestos para Android y Windows, construida con Flutter.

La definición funcional vive en [`docs/PRODUCT_BRIEF.md`](docs/PRODUCT_BRIEF.md) y las decisiones técnicas en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Probar la app sin herramientas de desarrollo

La carpeta exacta del proyecto en esta computadora es:

`C:\Users\Flaco\Documents\Codex\2026-09-01\files-pasted-by-the-user-quiero`

Para probarla en Windows, abrir con doble clic:

`C:\Users\Flaco\Documents\Codex\2026-09-01\files-pasted-by-the-user-quiero\build\windows\x64\runner\Release\manos_chacabuco.exe`

El ejecutable necesita los demás archivos que están en su carpeta `Release`, por lo que no hay que mover solamente el `.exe` al Escritorio. Se puede crear un acceso directo si se desea.

Para instalar la versión de prueba en Android, copiar al teléfono y abrir:

`C:\Users\Flaco\Documents\Codex\2026-09-01\files-pasted-by-the-user-quiero\build\app\outputs\flutter-apk\app-debug.apk`

Android puede pedir permiso para instalar aplicaciones desde esa fuente. Los comandos de las secciones siguientes son sólo para desarrollo y no son necesarios para probar estos archivos ya compilados.

## Requisitos

- Flutter 3.47.2 estable (Dart 3.13.2) o una versión compatible con `pubspec.yaml`.
- Android Studio/SDK para Android.
- Visual Studio con **Desktop development with C++** para Windows.
- En Windows, Modo desarrollador habilitado para que Flutter pueda crear symlinks de plugins.

## Ejecutar

```powershell
flutter pub get
flutter run -d android
```

Para Windows:

```powershell
flutter run -d windows
```

## Calidad

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

La base local se crea en el directorio de soporte de la aplicación bajo el nombre `manos_chacabuco.db`.
