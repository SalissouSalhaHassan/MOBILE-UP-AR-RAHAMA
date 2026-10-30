import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/mobile_api_client.dart';
import '../../../core/api/offline_store_manager.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/di/injection.dart';

class ServerConfigDialog extends StatefulWidget {
  const ServerConfigDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ServerConfigDialog(),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  final _controller = TextEditingController();
  final _sessionManager = locator<SessionManager>();
  String _currentActiveUrl = MobileApiConfig.baseUrl;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSaving = false;

  // Test connection state
  bool? _testSuccess;
  int? _testLatencyMs;
  String? _testMessage;

  final List<Map<String, dynamic>> _presets = [
    {
      'label': 'Production Principale (U P AR-RAHAMA)',
      'url': 'https://web-ces-bourja.vercel.app',
      'tag': 'Live Prod',
      'badgeColor': const Color(0xFF10B981),
      'description': 'Serveur Vercel officiel actif (U P AR-RAHAMA)',
    },
    {
      'label': 'Serveur Web Standard (Edut-Web)',
      'url': 'https://edut-web.vercel.app',
      'tag': 'Vercel',
      'badgeColor': const Color(0xFF6366F1),
      'description': 'Domaine Vercel principal standard',
    },
    {
      'label': 'Émulateur Android (PC Local)',
      'url': 'http://10.0.2.2:3000',
      'tag': 'Localhost',
      'badgeColor': const Color(0xFFF59E0B),
      'description': 'Serveur Next.js local sur machine de développement',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final customUrl = await _sessionManager.getCustomServerUrl();
    if (mounted) {
      final active = (customUrl != null && customUrl.trim().isNotEmpty)
          ? customUrl.trim()
          : MobileApiConfig.baseUrl;
      setState(() {
        _currentActiveUrl = _cleanAndNormalizeUrl(active);
        _controller.text = _currentActiveUrl;
        _isLoading = false;
      });
    }
  }

  /// Intelligently formats, fixes and normalizes URLs
  /// - Prepends https:// if protocol missing
  /// - Trims spaces, trailing slashes
  /// - Strips accidental paths like /dashboard, /login, /api
  static String _cleanAndNormalizeUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return MobileApiConfig.defaultBaseUrl;

    // Handle missing protocol
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.startsWith('10.0.2.2') || url.startsWith('localhost') || url.startsWith('192.168.')) {
        url = 'http://$url';
      } else {
        url = 'https://$url';
      }
    }

    try {
      final uri = Uri.parse(url);
      // Keep only scheme, host and port (remove accidental paths like /dashboard, /fr, etc.)
      var portPart = (uri.hasPort && uri.port != 80 && uri.port != 443) ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$portPart';
    } catch (_) {
      // Fallback: strip trailing slashes
      while (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      return url;
    }
  }

  /// Test connectivity and latency with the target server
  Future<void> _testConnection(String rawUrl) async {
    final normalized = _cleanAndNormalizeUrl(rawUrl);
    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testLatencyMs = null;
      _testMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    try {
      // Test the endpoint (health check or root HEAD)
      final response = await dio.get('$normalized/api/health').catchError((_) {
        // Fallback to checking root or options if health isn't present
        return dio.get(normalized);
      });
      stopwatch.stop();

      if (mounted) {
        setState(() {
          _isTesting = false;
          _testSuccess = true;
          _testLatencyMs = stopwatch.elapsedMilliseconds;
          _testMessage = 'Connexion réussie (${response.statusCode})';
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testSuccess = false;
          _testLatencyMs = stopwatch.elapsedMilliseconds;
          _testMessage = 'Impossible de joindre le serveur';
        });
      }
    }
  }

  Future<void> _saveServerUrl(String rawUrl) async {
    final url = _cleanAndNormalizeUrl(rawUrl);

    setState(() {
      _isSaving = true;
    });

    try {
      // 1. Save in storage
      if (url == MobileApiConfig.defaultBaseUrl) {
        await _sessionManager.setCustomServerUrl(null);
      } else {
        await _sessionManager.setCustomServerUrl(url);
      }

      // 2. Update active client
      locator<MobileApiClient>().updateBaseUrl(url);

      // 3. Clear offline cache to avoid mixing data between different servers
      try {
        if (locator.isRegistered<OfflineStoreManager>()) {
          await locator<OfflineStoreManager>().clearAllData();
        }
      } catch (e) {
        debugPrint('Cache clear warning: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Serveur activé : $url\nCache local réinitialisé.',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sauvegarde : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuration Serveur',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Connexion API & Environnements Vercel',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                // Presets Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SERVEURS DISPONIBLES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Actif: ${_currentActiveUrl.replaceFirst('https://', '').replaceFirst('http://', '')}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Presets List
                ..._presets.map((preset) {
                  final isSelected = _cleanAndNormalizeUrl(_controller.text) == _cleanAndNormalizeUrl(preset['url'] as String);
                  final badgeColor = preset['badgeColor'] as Color;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _controller.text = preset['url'] as String;
                        _currentActiveUrl = preset['url'] as String;
                        _testSuccess = null;
                        _testMessage = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            size: 20,
                            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        preset['label'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                          color: isSelected ? const Color(0xFF1E1B4B) : const Color(0xFF1E293B),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        preset['tag'] as String,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset['url'] as String,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isSelected ? const Color(0xFF4338CA) : const Color(0xFF64748B),
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 12),

                // Custom URL Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SAISIE DIRECTE OU VERCEL URL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data != null && data.text != null && data.text!.isNotEmpty) {
                          setState(() {
                            _controller.text = _cleanAndNormalizeUrl(data.text!);
                          });
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.content_paste_rounded, size: 13, color: Color(0xFF6366F1)),
                            SizedBox(width: 4),
                            Text(
                              'Coller',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // URL Input Field
                TextFormField(
                  controller: _controller,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'ex: web-ces-bourja.vercel.app',
                    hintStyle: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    prefixIcon: const Icon(
                      Icons.link_rounded,
                      color: Color(0xFF6366F1),
                      size: 20,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              setState(() {
                                _controller.clear();
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFF64748B),
                            size: 20,
                          ),
                          tooltip: 'Réinitialiser au défaut',
                          onPressed: () {
                            setState(() {
                              _controller.text = MobileApiConfig.defaultBaseUrl;
                            });
                          },
                        ),
                      ],
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF4F46E5),
                        width: 1.6,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Quick Action: Test Connection Ping
                InkWell(
                  onTap: _isTesting ? null : () => _testConnection(_controller.text),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        if (_isTesting)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                          )
                        else
                          Icon(
                            _testSuccess == null
                                ? Icons.network_check_rounded
                                : (_testSuccess! ? Icons.check_circle_rounded : Icons.error_rounded),
                            size: 16,
                            color: _testSuccess == null
                                ? const Color(0xFF4F46E5)
                                : (_testSuccess! ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isTesting
                                ? 'Test de connexion en cours...'
                                : (_testMessage != null
                                    ? '$_testMessage (${_testLatencyMs ?? 0} ms)'
                                    : 'Tester la connexion maintenant'),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: _testSuccess == null
                                  ? const Color(0xFF475569)
                                  : (_testSuccess! ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
                            ),
                          ),
                        ),
                        if (!_isTesting)
                          const Text(
                            'Ping',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        child: const Text(
                          'Annuler',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () => _saveServerUrl(_controller.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Appliquer',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
