import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/role_redirect.dart';
import '../../../core/di/injection.dart';
import '../../../core/utils/validators.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/services/inactivity_lock_service.dart';
import '../../../core/services/biometric_auth_service.dart';
import '../../../core/api/sync_engine.dart';
import '../data/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  final String? initialUsername;
  const LoginScreen({super.key, this.initialUsername});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _canCheckBiometric = false;
  String? _errorMessage;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    if (widget.initialUsername != null && widget.initialUsername!.trim().isNotEmpty) {
      _emailController.text = widget.initialUsername!.trim();
    } else {
      _loadCachedEmailIfEmpty();
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
  }

  Future<void> _loadCachedEmailIfEmpty() async {
    try {
      final session = locator<SessionManager>();
      final cachedEmail = await session.getCachedOfflineEmail();
      if (mounted && cachedEmail != null && cachedEmail.isNotEmpty && _emailController.text.isEmpty) {
        setState(() {
          _emailController.text = cachedEmail;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkBiometricAvailability() async {
    final bioService = locator<BiometricAuthService>();
    final available = await bioService.isBiometricAvailable();
    if (mounted) {
      setState(() => _canCheckBiometric = available);
    }
  }

  Future<void> _handleBiometricLogin() async {
    final bioService = locator<BiometricAuthService>();
    final didAuth = await bioService.authenticate(
      reason: 'Identifiez-vous par empreinte ou Face ID pour accéder à Edut',
    );

    if (didAuth) {
      final session = locator<SessionManager>();
      var email = await session.getEmail();
      var role = await session.getRole();

      // If active session is empty, try restoring from saved offline profile
      if (email == null || role == null || email.isEmpty) {
        final restored = await session.restoreSessionFromOfflineProfile();
        if (restored) {
          email = await session.getEmail();
          role = await session.getRole();
        }
      }

      if (email != null && role != null && email.isNotEmpty) {
        if (mounted) {
          locator<InactivityLockService>().unlock();
          locator<InactivityLockService>().recordActivity();
          context.go(getHomeRouteForRole(role));
        }
      } else {
        final typedEmail = _emailController.text.trim();
        final typedPassword = _passwordController.text;
        if (typedEmail.isNotEmpty && typedPassword.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔐 Empreinte validée ! Connexion et activation sur votre compte...'),
                backgroundColor: Color(0xFF4F46E5),
              ),
            );
            await _handleLogin();
          }
        } else {
          if (mounted) {
            _showBiometricHelpDialog();
          }
        }
      }
    }
  }

  void _showBiometricHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.fingerprint_rounded, color: Color(0xFF4F46E5), size: 28),
            SizedBox(width: 10),
            Text('Empreinte / Face ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Pour activer la connexion par Empreinte ou Face ID sur cet appareil, veuillez vous connecter une première fois avec votre identifiant et mot de passe.\n\nVotre compte sera ensuite automatiquement lié à votre empreinte pour vous connecter en 1 seul clic !',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final emailInput = _emailController.text.trim();
      final passwordInput = _passwordController.text;

      var result = await locator<AuthRepository>().login(
        email: emailInput,
        password: passwordInput,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => const LoginResult.failure(
          'Délai de connexion dépassé. Vérifiez votre connexion internet.',
        ),
      );

      // If online attempt failed due to network / timeout / server unreachable, try offline login!
      if (!result.success && result.message != null) {
        final msg = result.message!.toLowerCase();
        if (msg.contains('délai') ||
            msg.contains('connexion') ||
            msg.contains('réseau') ||
            msg.contains('internet') ||
            msg.contains('impossible de se connecter')) {
          final session = locator<SessionManager>();
          final offlineRes = await session.validateOfflineCredentialsDetailed(
            emailInput,
            passwordInput,
          );
          if (offlineRes == OfflineAuthResult.success) {
            result = const LoginResult.success();
          }
        }
      }

      if (mounted) {
        if (result.success) {
          locator<InactivityLockService>().unlock();
          locator<InactivityLockService>().recordActivity();
          final session = locator<SessionManager>();
          final hasPin = await session.hasOfflinePin();
          final role = await session.getRole() ?? 'staff';
          
          // Prime offline cache immediately in the background upon successful login
          try {
            locator<SyncEngine>().preloadAllOfflineData();
          } catch (_) {}

          if (!mounted) return;
          if (!hasPin) {
            // Suggest creating an offline PIN for seamless offline access
            context.go('/offline-pin?setup=true');
          } else {
            context.go(getHomeRouteForRole(role));
          }
        } else {
          setState(() {
            _errorMessage = result.message ?? 'Email ou mot de passe incorrect.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final emailInput = _emailController.text.trim();
        final passwordInput = _passwordController.text;
        final session = locator<SessionManager>();
        final offlineRes = await session.validateOfflineCredentialsDetailed(
          emailInput,
          passwordInput,
        );
        if (offlineRes == OfflineAuthResult.success) {
          locator<InactivityLockService>().unlock();
          locator<InactivityLockService>().recordActivity();
          final role = await session.getRole() ?? 'staff';
          if (!mounted) return;
          context.go(getHomeRouteForRole(role));
          return;
        }

        setState(() {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('socketexception') ||
              errStr.contains('clientexception') ||
              errStr.contains('failed host lookup') ||
              errStr.contains('no address associated') ||
              errStr.contains('network') ||
              errStr.contains('connection')) {
            _errorMessage =
                'Connexion Internet indisponible. Veuillez vérifier votre réseau.';
          } else {
            _errorMessage =
                'Erreur de connexion : ${e.toString().replaceAll('Exception:', '').trim()}';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showDemoSandboxDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.science_rounded, color: Color(0xFFD97706), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Environnement Démo Sandbox', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Choisissez un profil pour tester l\'application instantanément', style: TextStyle(color: Colors.black54, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _demoRoleTile(
              title: 'Directeur / Fondateur d\'école',
              email: 'admin@edut.app',
              role: 'school_admin',
              icon: Icons.admin_panel_settings_rounded,
              color: const Color(0xFF4F46E5),
            ),
            const SizedBox(height: 8),
            _demoRoleTile(
              title: 'Enseignant & Copilote Pédagogique',
              email: 'prof@edut.app',
              role: 'teacher',
              icon: Icons.school_rounded,
              color: const Color(0xFF059669),
            ),
            const SizedBox(height: 8),
            _demoRoleTile(
              title: 'Parent & Espace Famille',
              email: 'parent@edut.app',
              role: 'parent',
              icon: Icons.family_restroom_rounded,
              color: const Color(0xFFD97706),
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoRoleTile({
    required String title,
    required String email,
    required String role,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _emailController.text = email;
          _passwordController.text = 'edut1234';
        });
        _handleLogin();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(email, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Background ambient gradient blobs
          Positioned(
            top: -size.width * 0.35,
            right: -size.width * 0.25,
            child: Container(
              width: size.width * 0.95,
              height: size.width * 0.95,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4F46E5).withValues(alpha: 0.25),
                    const Color(0xFF818CF8).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: size.height * 0.35,
            left: -size.width * 0.3,
            child: Container(
              width: size.width * 0.8,
              height: size.width * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0D9488).withValues(alpha: 0.20),
                    const Color(0xFF34D399).withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Top Server switcher button (hidden - fixed single server)
          const SizedBox.shrink(),

          // Main scrollable content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // App Badge / Hero Header
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF4338CA), Color(0xFF3B82F6)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                                      blurRadius: 28,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(26),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Image.asset(
                                      'assets/images/app_icon.png',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.school_rounded,
                                            size: 44,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Title & Subtitle
                        const Center(
                          child: Text(
                            'U P AR-RAHAMA',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFC7D2FE)),
                            ),
                            child: const Text(
                              'Université Privée Ar-Rahma - Maradi',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4338CA),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Main Login Card
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4F46E5),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Connexion Sécurisée',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),

                                  // Email Input
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Identifiant / Adresse Email',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _emailController,
                                        keyboardType: TextInputType.emailAddress,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                        decoration: InputDecoration(
                                          hintText: 'Ex: nom@domaine.com ou votre matricule',
                                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          prefixIcon: const Icon(Icons.alternate_email_rounded, color: Color(0xFF6366F1), size: 20),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
                                          ),
                                          errorBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                                          ),
                                          focusedErrorBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'L\'adresse email ou identifiant est requis';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Password Input
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Mot de passe',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                        decoration: InputDecoration(
                                          hintText: '••••••••',
                                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF6366F1), size: 20),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                              color: const Color(0xFF64748B),
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscurePassword = !_obscurePassword;
                                              });
                                            },
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
                                          ),
                                          errorBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                                          ),
                                          focusedErrorBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
                                          ),
                                        ),
                                        validator: Validators.validatePassword,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Forgot Password
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => context.push('/forgot-password'),
                                      child: const Text(
                                        'Mot de passe oublié ?',
                                        style: TextStyle(
                                          color: Color(0xFF4F46E5),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Error message box
                                  if (_errorMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: const Color(0xFFFECACA)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: const TextStyle(
                                                    color: Color(0xFFB91C1C),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_errorMessage!.contains('associé à un autre compte') ||
                                              _errorMessage!.contains('autre compte')) ...[
                                            const SizedBox(height: 10),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  backgroundColor: const Color(0xFFFEE2E2),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () async {
                                                  final messenger = ScaffoldMessenger.of(context);
                                                  final session = locator<SessionManager>();
                                                  await session.purgeOfflineProfileAndAccounts();
                                                  setState(() {
                                                    _errorMessage = null;
                                                  });
                                                  messenger.showSnackBar(
                                                    const SnackBar(
                                                      content: Text("L'appareil a été dissocié avec succès. Vous pouvez maintenant vous connecter avec ce compte."),
                                                      backgroundColor: Color(0xFF059669),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(Icons.link_off_rounded, size: 14, color: Color(0xFFB91C1C)),
                                                label: const Text(
                                                  "Dissocier l'ancien compte de cet appareil",
                                                  style: TextStyle(
                                                    color: Color(0xFFB91C1C),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Gradient Login Button
                                  Container(
                                    height: 52,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF4338CA), Color(0xFF4F46E5), Color(0xFF3B82F6)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                                          blurRadius: 18,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: _isLoading ? null : _handleLogin,
                                        child: Center(
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child: CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2.5,
                                                  ),
                                                )
                                              : const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.login_rounded, color: Colors.white, size: 20),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Se connecter',
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w900,
                                                        color: Colors.white,
                                                        letterSpacing: 0.3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Biometric Login Button
                                  if (_canCheckBiometric) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: _handleBiometricLogin,
                                      icon: const Icon(Icons.fingerprint_rounded, color: Color(0xFF4F46E5), size: 22),
                                      label: const Text(
                                        'Connexion par Empreinte / Face ID',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF4F46E5),
                                          fontSize: 13,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Register Account Button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => context.push('/register'),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_add_alt_1_rounded, size: 18, color: Color(0xFF4F46E5)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Créer un compte (Élève / Enseignant)',
                                      style: TextStyle(
                                        color: Color(0xFF4F46E5),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Interactive Sandbox / Demo Mode Button
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _showDemoSandboxDialog,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.science_rounded, size: 18, color: Color(0xFFD97706)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Mode Démo / Sandbox Interactif',
                                      style: TextStyle(
                                        color: Color(0xFFB45309),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Fixed Production Server indicator (clean without dialog switcher)
                        const SizedBox.shrink(),


                        // Footer Security Badge
                        const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, size: 14, color: Color(0xFF94A3B8)),
                              SizedBox(width: 6),
                              Text(
                                'Plateforme Éducative Sécurisée • Edut Core',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
