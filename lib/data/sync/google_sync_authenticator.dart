// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/sync/sync_contracts.dart';
import 'google_drive_remote_sync_store.dart';
import 'google_oauth_configuration.dart';
import 'windows_protected_token_store.dart';

export 'google_oauth_configuration.dart' show GoogleSyncConfiguration;

final class GoogleSyncAuthenticator implements ConfigurableSyncAuthenticator {
  GoogleSyncAuthenticator({
    GoogleSyncConfiguration configuration = const GoogleSyncConfiguration(),
    GoogleOAuthConfigurationStore? configurationStore,
    DesktopTokenStore? desktopTokenStore,
  }) : _configuration = configuration,
       _configurationStore = configurationStore,
       _desktopTokenStore = desktopTokenStore ?? WindowsProtectedTokenStore();

  static Future<GoogleSyncAuthenticator> openDefault() async {
    final store = GoogleOAuthConfigurationStore();
    final saved = await store.read();
    final configuration = const GoogleSyncConfiguration().overlay(
      saved ?? const GoogleSyncConfiguration(),
    );
    return GoogleSyncAuthenticator(
      configuration: configuration,
      configurationStore: store,
    );
  }

  static const scopes = [GoogleDriveRemoteSyncStore.appDataScope];
  GoogleSyncConfiguration _configuration;
  final GoogleOAuthConfigurationStore? _configurationStore;
  final DesktopTokenStore _desktopTokenStore;
  bool _androidInitialized = false;

  @override
  bool get isConfigured => switch (Platform.operatingSystem) {
    'android' => _configuration.androidServerClientId.trim().isNotEmpty,
    'windows' => _configuration.desktopClientId.trim().isNotEmpty,
    _ => false,
  };

  @override
  String? get configurationMessage {
    if (isConfigured) return null;
    if (Platform.isAndroid) {
      return 'Google Drive necesita una configuración inicial de esta app.';
    }
    if (Platform.isWindows) {
      return 'Google Drive necesita una configuración inicial de esta app.';
    }
    return 'Google Drive está disponible solamente en Android y Windows.';
  }

  @override
  Future<void> configure(String setupInput) async {
    final store = _configurationStore;
    if (store == null) {
      throw StateError('Esta versión no permite guardar la configuración.');
    }
    _configuration = _configuration.withSetupInput(
      setupInput,
      platform: Platform.operatingSystem,
    );
    _androidInitialized = false;
    await store.write(_configuration);
  }

  @override
  Future<SyncAuthenticatedSession?> restore() async {
    if (!isConfigured) return null;
    if (Platform.isAndroid) {
      await _initializeAndroid();
      final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = attempt == null ? null : await attempt;
      return account == null
          ? null
          : _androidSession(account, interactive: false);
    }
    if (Platform.isWindows) {
      final encoded = await _desktopTokenStore.read();
      if (encoded == null) return null;
      final tokens = _DesktopTokens.fromJson(
        Map<String, Object?>.from(jsonDecode(encoded) as Map),
      );
      final manager = _DesktopTokenManager(
        tokens: tokens,
        configuration: _configuration,
        tokenStore: _desktopTokenStore,
      );
      await manager.ensureFresh();
      return _DesktopSession(tokens.email, manager);
    }
    return null;
  }

  @override
  Future<SyncAuthenticatedSession> connect() async {
    if (!isConfigured) {
      throw StateError(configurationMessage ?? 'OAuth no está configurado.');
    }
    if (Platform.isAndroid) {
      await _initializeAndroid();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: scopes,
      );
      final session = await _androidSession(account, interactive: true);
      if (session == null) {
        throw StateError('Google no autorizó el acceso privado de la app.');
      }
      return session;
    }
    if (Platform.isWindows) return _connectDesktop();
    throw UnsupportedError('Plataforma no compatible con Google Drive.');
  }

  @override
  Future<void> disconnect() async {
    if (Platform.isAndroid && _androidInitialized) {
      await GoogleSignIn.instance.disconnect();
      return;
    }
    if (Platform.isWindows) {
      final encoded = await _desktopTokenStore.read();
      await _desktopTokenStore.delete();
      if (encoded == null) return;
      try {
        final tokens = _DesktopTokens.fromJson(
          Map<String, Object?>.from(jsonDecode(encoded) as Map),
        );
        final token = tokens.refreshToken ?? tokens.accessToken;
        await http.post(
          Uri.https('oauth2.googleapis.com', '/revoke'),
          headers: const {'content-type': 'application/x-www-form-urlencoded'},
          body: {'token': token},
        );
      } catch (_) {
        // La desconexión local debe completarse aunque Google esté sin conexión.
      }
    }
  }

  Future<void> _initializeAndroid() async {
    if (_androidInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _configuration.androidServerClientId,
    );
    _androidInitialized = true;
  }

  Future<SyncAuthenticatedSession?> _androidSession(
    GoogleSignInAccount account, {
    required bool interactive,
  }) async {
    final clientAuthorization =
        await account.authorizationClient.authorizationForScopes(scopes) ??
        (interactive
            ? await account.authorizationClient.authorizeScopes(scopes)
            : null);
    if (clientAuthorization == null) return null;
    final client = clientAuthorization.authClient(scopes: scopes);
    return _GoogleSession(account.email, client);
  }

  Future<SyncAuthenticatedSession> _connectDesktop() async {
    final random = Random.secure();
    final verifier = _randomUrlSafe(random, 64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomUrlSafe(random, 32);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    final authorizationUri = Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      {
        'client_id': _configuration.desktopClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email ${scopes.join(' ')}',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );
    if (!await launchUrl(
      authorizationUri,
      mode: LaunchMode.externalApplication,
    )) {
      await server.close(force: true);
      throw StateError('No pudimos abrir Google en el navegador.');
    }

    try {
      final request = await server.first.timeout(const Duration(minutes: 3));
      final query = request.uri.queryParameters;
      final valid = query['state'] == state && query['code'] != null;
      request.response
        ..statusCode = valid ? HttpStatus.ok : HttpStatus.badRequest
        ..headers.contentType = ContentType.html
        ..write(
          valid
              ? '<html><body><h2>Cuenta conectada</h2><p>Ya podés cerrar esta ventana y volver a Manos Chacabuco.</p></body></html>'
              : '<html><body><h2>No se pudo conectar</h2><p>Volvé a Manos Chacabuco e intentá nuevamente.</p></body></html>',
        );
      await request.response.close();
      if (!valid) throw StateError('Google no autorizó la conexión.');
      final response = await http.post(
        Uri.https('oauth2.googleapis.com', '/token'),
        headers: const {'content-type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _configuration.desktopClientId,
          'code': query['code']!,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Google rechazó la autorización.');
      }
      final json = Map<String, Object?>.from(jsonDecode(response.body) as Map);
      final email = _emailFromIdToken(json['id_token']! as String);
      final tokens = _DesktopTokens(
        accessToken: json['access_token']! as String,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.now().toUtc().add(
          Duration(seconds: json['expires_in']! as int),
        ),
        email: email,
      );
      await _desktopTokenStore.write(jsonEncode(tokens.toJson()));
      return _DesktopSession(
        email,
        _DesktopTokenManager(
          tokens: tokens,
          configuration: _configuration,
          tokenStore: _desktopTokenStore,
        ),
      );
    } finally {
      await server.close(force: true);
    }
  }

  String _randomUrlSafe(Random random, int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _emailFromIdToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw StateError('Google no devolvió la cuenta.');
    final payload = Map<String, Object?>.from(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map,
    );
    final email = payload['email'];
    if (email is! String || email.isEmpty) {
      throw StateError('Google no devolvió el email de la cuenta.');
    }
    return email;
  }
}

final class _GoogleSession implements SyncAuthenticatedSession {
  _GoogleSession(this.email, this._client)
    : remoteStore = GoogleDriveRemoteSyncStore(_client);

  @override
  final String email;
  final http.Client _client;

  @override
  final RemoteSyncStore remoteStore;

  @override
  Future<void> close() async => _client.close();
}

final class _DesktopSession implements SyncAuthenticatedSession {
  _DesktopSession._(this.email, this._client)
    : remoteStore = GoogleDriveRemoteSyncStore(_client);

  factory _DesktopSession(String email, _DesktopTokenManager manager) {
    final client = _RefreshingClient(manager);
    return _DesktopSession._(email, client);
  }

  @override
  final String email;
  final http.Client _client;

  @override
  final RemoteSyncStore remoteStore;

  @override
  Future<void> close() async => _client.close();
}

final class _RefreshingClient extends http.BaseClient {
  _RefreshingClient(this._manager);

  final _DesktopTokenManager _manager;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _manager.accessToken();
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

final class _DesktopTokenManager {
  _DesktopTokenManager({
    required _DesktopTokens tokens,
    required GoogleSyncConfiguration configuration,
    required DesktopTokenStore tokenStore,
  }) : _tokens = tokens,
       _configuration = configuration,
       _tokenStore = tokenStore;

  _DesktopTokens _tokens;
  final GoogleSyncConfiguration _configuration;
  final DesktopTokenStore _tokenStore;
  Future<void>? _refreshing;

  Future<String> accessToken() async {
    await ensureFresh();
    return _tokens.accessToken;
  }

  Future<void> ensureFresh() async {
    if (_tokens.expiresAt.isAfter(
      DateTime.now().toUtc().add(const Duration(minutes: 2)),
    )) {
      return;
    }
    final existing = _refreshing;
    if (existing != null) return existing;
    final future = _refresh();
    _refreshing = future;
    try {
      await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _refresh() async {
    final refreshToken = _tokens.refreshToken;
    if (refreshToken == null) {
      throw StateError(
        'La sesión de Google venció. Volvé a conectar la cuenta.',
      );
    }
    final response = await http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: const {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _configuration.desktopClientId,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'La sesión de Google venció. Volvé a conectar la cuenta.',
      );
    }
    final json = Map<String, Object?>.from(jsonDecode(response.body) as Map);
    _tokens = _DesktopTokens(
      accessToken: json['access_token']! as String,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: json['expires_in']! as int),
      ),
      email: _tokens.email,
    );
    await _tokenStore.write(jsonEncode(_tokens.toJson()));
  }
}

final class _DesktopTokens {
  const _DesktopTokens({
    required this.accessToken,
    required this.expiresAt,
    required this.email,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String email;

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'email': email,
  };

  factory _DesktopTokens.fromJson(Map<String, Object?> json) => _DesktopTokens(
    accessToken: json['accessToken']! as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
    email: json['email']! as String,
  );
}
