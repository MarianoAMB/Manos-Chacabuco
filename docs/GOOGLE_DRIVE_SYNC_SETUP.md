# Activar la sincronización privada con Google Drive

La app funciona completa sin Google. Esta configuración sólo es necesaria para
usar la misma información en Windows y Android. No se ingresan tokens a mano y
la app solicita únicamente acceso a su carpeta privada de Drive.

## 1. Preparar Google Cloud

1. Crear un único proyecto en Google Cloud para Manos Chacabuco.
2. Habilitar **Google Drive API**.
3. Configurar la pantalla de consentimiento OAuth y publicarla en producción.
   No distribuir una compilación conectada mientras el proyecto siga en modo
   de prueba: Google hace vencer esas autorizaciones a los siete días.
4. Declarar sólo el permiso
   `https://www.googleapis.com/auth/drive.appdata`.

Los clientes de Android y Windows deben pertenecer al mismo proyecto de Google
Cloud. Así ambos representan a la misma app y, al iniciar sesión con la misma
cuenta, ven el mismo espacio privado `appDataFolder`.

## 2. Credencial Android

1. Crear un cliente OAuth de tipo **Android**.
2. Usar el package name exacto
   `com.manoschacabuco.manos_chacabuco`.
3. Registrar los SHA-1 de los certificados usados para compilar: primero el de
   desarrollo y, antes de distribuir la app, también el de producción.
   En esta computadora, el SHA-1 de desarrollo ya verificado es
   `E9:46:4B:5E:AE:05:12:94:E6:3D:97:4C:65:D4:31:FC:8C:30:C9:D4`.
4. Crear además un cliente OAuth de tipo **Aplicación web** en el mismo
   proyecto. Copiar su Client ID como
   `MANOS_GOOGLE_ANDROID_SERVER_CLIENT_ID`.

No hace falta agregar `google-services.json` para esta implementación.

## 3. Credencial Windows

1. Crear un cliente OAuth de tipo **Aplicación de escritorio**.
2. Copiar su Client ID como `MANOS_GOOGLE_DESKTOP_CLIENT_ID`.
3. No copiar el `client_secret`: la app usa el flujo público de aplicaciones
   instaladas, protegido con PKCE.

Windows abre el navegador predeterminado y recibe la autorización en
`127.0.0.1` mediante un puerto local temporal. Usa PKCE y no pide copiar códigos
ni tokens.

## 4. Experiencia de la usuaria

En **Configuración > Sincronización**, pulsar **Conectar con Google**.

- En Windows y Android, la identificación pública de la app ya viene incluida
  en las versiones distribuidas.
- La usuaria sólo elige su cuenta y acepta el acceso privado de Manos Chacabuco.
- Nunca descarga, abre ni importa credenciales o archivos JSON.
- Para migrar a otro correo usa **Cambiar cuenta**, elige la cuenta nueva y la
  app copia automáticamente todos los datos locales actuales.

## 5. Configuración al compilar

1. Copiar `config/oauth.local.example.json` con el nombre
   `config/oauth.local.json`.
2. Reemplazar los textos `REEMPLAZAR` por los Client IDs obtenidos.
3. Compilar pasando:

   `--dart-define-from-file=config/oauth.local.json`

Ejemplos desde la carpeta del proyecto:

- Android: `flutter build apk --debug --dart-define-from-file=config/oauth.local.json`
- Windows: `flutter build windows --release --dart-define-from-file=config/oauth.local.json`

`config/oauth.local.json` está excluido de Git. Los refresh tokens de Windows
se cifran con DPAPI para el usuario actual de Windows, se guardan dentro de los
datos privados de la app y se eliminan al desconectar la cuenta.

## 6. Prueba cruzada recomendada

1. Conectar Windows, crear un producto y pulsar **Sincronizar ahora**.
2. Conectar Android con la misma cuenta y sincronizar; verificar el producto.
3. Editarlo en Android, sincronizar y volver a sincronizar Windows.
4. Hacer dos ediciones distintas del mismo producto sin sincronizar y luego
   sincronizar ambos; Configuración debe mostrar un conflicto para elegir qué
   versión conservar.

Desconectar Google no borra la base SQLite, las fotos ni los cambios pendientes
del dispositivo.

Si se elige otra cuenta, la app copia automáticamente toda la información local
actual a la cuenta nueva. La usuaria no descarga, abre ni mueve archivos JSON,
no completa una confirmación adicional y no necesita volver a iniciar sesión.
