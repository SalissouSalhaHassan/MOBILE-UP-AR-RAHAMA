import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';
import '../auth/session_manager.dart';
import '../di/injection.dart';

class MobileApiConfig {
  static const String defaultBaseUrl = String.fromEnvironment(
    'EDUT_WEB_API_BASE_URL',
    defaultValue: 'https://web-up-ar-rahama.vercel.app',
  );

  static String _activeBaseUrl = defaultBaseUrl;

  static String get baseUrl => _activeBaseUrl;

  static void setBaseUrl(String url) {
    _activeBaseUrl = _normalize(url);
  }

  static String _normalize(String rawValue) {
    final value = rawValue.trim();
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}

class MobileApiException implements Exception {
  const MobileApiException(this.message, {this.isNetworkError = false});

  final String message;

  /// True only when the server could not be reached (timeout / no connection).
  /// Server-side rejections (4xx/5xx, business errors) are NOT network errors.
  final bool isNetworkError;

  @override
  String toString() => message;
}

class MobileApiProfile {
  const MobileApiProfile({
    required this.userId,
    required this.email,
    required this.role,
    required this.permissions,
    this.schoolId,
    this.employeeId,
    this.studentId,
    this.studentName,
    this.studentClass,
    this.educationalLevel,
  });

  final String userId;
  final String email;
  final String role;
  final List<String> permissions;
  final String? schoolId;
  final String? employeeId;
  final String? studentId;
  final String? studentName;
  final String? studentClass;
  final String? educationalLevel;

  factory MobileApiProfile.fromJson(Map<String, dynamic> json) {
    final student = json['student'] is Map
        ? Map<String, dynamic>.from(json['student'] as Map)
        : null;

    return MobileApiProfile(
      userId: json['userId']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'staff',
      schoolId: json['schoolId']?.toString(),
      employeeId: json['employeeId']?.toString(),
      permissions: List<String>.from(json['permissions'] ?? const []),
      studentId: student?['id']?.toString(),
      studentName: student?['name']?.toString(),
      studentClass: student?['className']?.toString(),
      educationalLevel: json['educationalLevel']?.toString() ??
          json['scope']?['educationalLevel']?.toString(),
    );
  }
}

class MobileApiClient {
  MobileApiClient({
    Dio? dio,
    SupabaseClient? supabaseClient,
    SessionManager? sessionManager,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: MobileApiConfig.baseUrl,
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 8),
              ),
            ),
        _supabaseClient = supabaseClient ?? SupabaseClientManager().client,
        _sessionManager = sessionManager ??
            (locator.isRegistered<SessionManager>()
                ? locator<SessionManager>()
                : SessionManager()) {
    _initBaseUrl();
  }

  final Dio _dio;
  final SupabaseClient _supabaseClient;
  final SessionManager _sessionManager;

  Future<void> _initBaseUrl() async {
    try {
      final custom = await _sessionManager.getCustomServerUrl();
      if (custom != null && custom.trim().isNotEmpty) {
        updateBaseUrl(custom.trim());
      }
    } catch (_) {}
  }

  void updateBaseUrl(String newUrl) {
    MobileApiConfig.setBaseUrl(newUrl);
    _dio.options.baseUrl = MobileApiConfig.baseUrl;
  }

  Future<MobileApiProfile> getCurrentProfile({String? accessToken}) async {
    var token =
        accessToken ?? _supabaseClient.auth.currentSession?.accessToken;

    if (token == null || token.isEmpty) {
      try {
        token = await _sessionManager.getToken();
      } catch (_) {}
    }

    if (token == null || token.isEmpty) {
      throw const MobileApiException('Session mobile absente.');
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '/api/mobile/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final body = response.data;
    if (body == null || body['success'] != true || body['profile'] is! Map) {
      throw const MobileApiException('Profil Edut mobile invalide.');
    }

    return MobileApiProfile.fromJson(
      Map<String, dynamic>.from(body['profile'] as Map),
    );
  }

  Future<MobileApiProfile?> getMeProfile(String token) async {
    try {
      return await getCurrentProfile(accessToken: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> register({
    required String role,
    required String schoolSlug,
    required String matriculeOrEmail,
    required String username,
    required String fullName,
    required String password,
    required String activationPin,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/mobile/register',
        data: {
          'role': role,
          'schoolSlug': schoolSlug,
          'matriculeOrEmail': matriculeOrEmail,
          'username': username,
          'fullName': fullName,
          'password': password,
          'activationPin': activationPin,
        },
      );
      final body = response.data;
      if (body == null || body['success'] != true) {
        throw MobileApiException(body?['error']?.toString() ?? 'Erreur lors de l\'inscription.');
      }
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error']?.toString() ?? 'Erreur lors de l\'inscription.';
      throw MobileApiException(errorMsg);
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String role,
    required String schoolSlug,
    required String matriculeOrEmail,
    required String verificationCodeOrPhone,
    String? newPassword,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/mobile/forgot-password',
        data: {
          'role': role,
          'schoolSlug': schoolSlug,
          'matriculeOrEmail': matriculeOrEmail,
          'verificationCodeOrPhone': verificationCodeOrPhone,
          if (newPassword != null && newPassword.isNotEmpty) 'newPassword': newPassword,
        },
      );
      final body = response.data;
      if (body == null || body['success'] != true) {
        throw MobileApiException(body?['error']?.toString() ?? 'Erreur lors de la réinitialisation.');
      }
      return Map<String, dynamic>.from(body['data'] as Map);
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error']?.toString() ?? 'Erreur lors de la réinitialisation.';
      throw MobileApiException(errorMsg);
    }
  }

  Future<Map<String, dynamic>> loginWithApi({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'username': username,
          'password': password,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = response.data;
      if (data == null) {
        throw const MobileApiException('Réponse du serveur vide.');
      }

      if (data['success'] != true) {
        final errorMsg = data['error']?.toString() ??
            'Identifiant ou mot de passe incorrect.';
        throw MobileApiException(errorMsg);
      }

      return data;
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  MobileApiException _handleDioException(DioException e) {
    final responseData = e.response?.data;
    if (responseData is Map) {
      final errorMsg = responseData['error']?.toString() ??
          responseData['message']?.toString();
      if (errorMsg != null && errorMsg.trim().isNotEmpty) {
        return MobileApiException(errorMsg.trim());
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const MobileApiException('Connexion indisponible pour le moment.', isNetworkError: true);
    }
    return MobileApiException(e.message ?? 'Erreur de communication réseau.');
  }

  Future<String?> _resolveValidAccessToken({bool forceRefresh = false}) async {
    var session = _supabaseClient.auth.currentSession;

    // 1. If session is null, attempt recovery via saved refreshToken
    if (session == null || forceRefresh) {
      try {
        final savedRefreshToken = await _sessionManager.getRefreshToken();
        if (savedRefreshToken != null && savedRefreshToken.isNotEmpty) {
          final res = await _supabaseClient.auth.setSession(savedRefreshToken);
          session = res.session ?? session;
          if (res.session?.accessToken != null) {
            await _sessionManager.updateAccessToken(
              res.session!.accessToken,
              res.session?.refreshToken,
            );
          }
        }
      } catch (e) {
        // Fallback: continue checking if currentSession exists
      }
    }

    // 2. If session is present and expired or near expiry (or forceRefresh requested)
    if (session != null) {
      final expiresAt = session.expiresAt;
      final isNearExpiry = expiresAt != null &&
          DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
              .isBefore(DateTime.now().add(const Duration(minutes: 5)));

      if (session.isExpired || isNearExpiry || forceRefresh) {
        try {
          final refreshRes = await _supabaseClient.auth.refreshSession();
          session = refreshRes.session ?? session;
          if (refreshRes.session?.accessToken != null) {
            await _sessionManager.updateAccessToken(
              refreshRes.session!.accessToken,
              refreshRes.session?.refreshToken,
            );
          }
        } catch (_) {}
      }
    }

    // 3. Priority: Check saved session token first (issued by active server API)
    var token = await _sessionManager.getToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }

    return session?.accessToken ?? _supabaseClient.auth.currentSession?.accessToken;
  }

  Future<Options> _authOptions() async {
    final token = await _resolveValidAccessToken();
    if (token == null || token.isEmpty) {
      throw const MobileApiException('Session mobile absente.');
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<Map<String, dynamic>> _executeWithAuthRetry(
    Future<Response<Map<String, dynamic>>> Function(Options options) requestFn,
  ) async {
    final options = await _authOptions();
    try {
      final response = await requestFn(options);
      return _parseBody(response.data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final errorData = e.response?.data;
      final errorMsg = (errorData is Map ? errorData['error']?.toString() : '') ?? '';
      final isAuthError = statusCode == 401 ||
          errorMsg.contains('Session mobile invalide') ||
          errorMsg.contains('Token mobile') ||
          errorMsg.contains('jwt expired');

      if (isAuthError) {
        // Attempt an immediate token refresh and retry the request once
        try {
          final newToken = await _resolveValidAccessToken(forceRefresh: true);
          if (newToken != null && newToken.isNotEmpty) {
            final retryResponse = await requestFn(
              Options(headers: {'Authorization': 'Bearer $newToken'}),
            );
            return _parseBody(retryResponse.data);
          }
        } catch (retryErr) {
          if (retryErr is DioException) {
            throw _handleDioException(retryErr);
          }
        }
      }
      throw _handleDioException(e);
    }
  }

  Future<Map<String, dynamic>> getJson(String path) {
    return _executeWithAuthRetry((options) => _dio.get<Map<String, dynamic>>(path, options: options));
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) {
    return _executeWithAuthRetry((options) => _dio.post<Map<String, dynamic>>(path, data: data, options: options));
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) {
    return _executeWithAuthRetry((options) => _dio.put<Map<String, dynamic>>(path, data: data, options: options));
  }

  Future<Map<String, dynamic>> patchJson(
    String path, [
    Map<String, dynamic>? data,
  ]) {
    return _executeWithAuthRetry((options) => _dio.patch<Map<String, dynamic>>(path, data: data, options: options));
  }

  Future<Map<String, dynamic>> deleteJson(String path) {
    return _executeWithAuthRetry((options) => _dio.delete<Map<String, dynamic>>(path, options: options));
  }

  Future<Map<String, dynamic>> get(String path) => getJson(path);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, Map<String, dynamic>? data}) =>
      postJson(path, body ?? data ?? const {});

  Map<String, dynamic> _parseBody(Map<String, dynamic>? body) {
    if (body == null) {
      throw const MobileApiException('Reponse Edut mobile vide.');
    }
    if (body['success'] == false) {
      throw MobileApiException(
        body['error']?.toString() ?? 'Erreur API Edut mobile.',
      );
    }
    return body;
  }
}
