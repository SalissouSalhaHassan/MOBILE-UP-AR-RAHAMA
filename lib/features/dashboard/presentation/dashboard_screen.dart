import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/auth/role_redirect.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sync_status_banner.dart';
import '../../../core/widgets/connectivity_widgets.dart';
import '../../../core/api/sync_engine.dart';
import '../../auth/data/auth_repository.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../academics/data/academics_repository.dart';
import '../../exams/data/exams_repository.dart';
import '../data/dashboard_stats_repository.dart';
import '../../messaging/data/messaging_repository.dart';
import '../../teacher/presentation/teacher_cockpit_widget.dart';
import '../../teacher/presentation/classroom_tools_modal.dart';
import 'dart:async';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/educational_level_helper.dart';
import '../../../core/utils/type_converters.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<Map<String, dynamic>>? _pushSubscription;
  String _userEmail = '';
  String _userRole = 'staff';
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _isDarkMode = false;
  bool _hasFinanceAccess = false;
  bool _hasOwnerAccess = false;
  bool _hasStudentsAccess = false;
  bool _hasStudentPromotionAccess = false;
  bool _hasHostelAccess = false;
  bool _hasHrAccess = false;
  Map<String, dynamic> _dashboardStats = {};
  int _unreadNotificationsCount = 0;

  /// Returns true if the current user is a teacher
  bool get _isTeacher {
    final r = _userRole.toLowerCase().trim();
    return r == 'teacher' ||
        r == 'enseignant' ||
        r == 'professeur' ||
        r.contains('teacher') ||
        r.contains('enseignant') ||
        r.contains('professeur');
  }

  /// Returns true if the current user has super admin / management rights
  bool get _isSuperAdmin {
    final r = _userRole.toLowerCase().trim();
    return r == 'super_admin' ||
        r == 'owner' ||
        r == 'admin' ||
        r.contains('super') ||
        r.contains('admin') ||
        r.contains('owner') ||
        r.contains('director') ||
        r.contains('directeur');
  }

  /// Returns true if the user can manage finances (admin, director, accountant, secretary, super_admin, finance)
  // ignore: unused_element
  bool get _canManageFinance {
    final r = _userRole.toLowerCase().trim();
    return r == 'admin' ||
        r == 'owner' ||
        r == 'super_admin' ||
        r == 'director' ||
        r == 'accountant' ||
        r == 'comptable' ||
        r == 'secretary' ||
        r == 'secretaire' ||
        r == 'secrétaire' ||
        r == 'finance' ||
        r.contains('admin') ||
        r.contains('director') ||
        r.contains('comptable') ||
        r.contains('accountant') ||
        r.contains('finance');
  }

  // ignore: unused_element
  bool get _canAccessOwnerSpace {
    final r = _userRole.toLowerCase().trim();
    return r == 'owner' ||
        r == 'super_admin' ||
        r == 'admin' ||
        r.contains('owner') ||
        r.contains('admin');
  }

  /// Returns a human-readable label for the role
  String _getRoleLabel(String role) {
    final r = role.toLowerCase().trim();
    if (r.isEmpty || r == 'staff') {
      return 'Rôle non défini';
    }
    if (r == 'super_admin') {
      return 'Super Admin';
    }
    if (r == 'admin') {
      return 'Administrateur';
    }
    if (r == 'owner' ||
        r == 'proprietaire' ||
        r == 'propriétaire' ||
        r.contains('owner') ||
        r.contains('proprietaire') ||
        r.contains('propriétaire')) {
      return 'Proprietaire';
    }
    if (r == 'director' ||
        r == 'general_director' ||
        r == 'school_director' ||
        r == 'level_director' ||
        r == 'directeur' ||
        r.contains('director') ||
        r.contains('directeur')) {
      return 'Directeur';
    }
    if (r == 'teacher' ||
        r == 'enseignant' ||
        r == 'professeur' ||
        r.contains('teacher') ||
        r.contains('enseignant') ||
        r.contains('professeur')) {
      return 'Professeur';
    }
    if (r == 'student' ||
        r == 'eleve' ||
        r == 'élève' ||
        r.contains('student') ||
        r.contains('eleve') ||
        r.contains('élève')) {
      return 'Élève';
    }
    if (r == 'parent' || r.contains('parent')) {
      return 'Parent';
    }
    if (r == 'accountant' ||
        r == 'comptable' ||
        r == 'finance' ||
        r == 'financier' ||
        r == 'caissier' ||
        r == 'tresorier' ||
        r == 'trésorier' ||
        r == 'daf' ||
        r.contains('comptab') ||
        r.contains('account') ||
        r.contains('financ') ||
        r.contains('caiss') ||
        r.contains('tresor') ||
        r.contains('trésor') ||
        r.contains('daf') ||
        r.contains('محاسب') ||
        r.contains('مالي') ||
        r.contains('صندوق') ||
        r.contains('خزينة')) {
      return 'Finance / Comptabilité';
    }
    if (r == 'secretary' ||
        r == 'secretaire' ||
        r == 'secrétaire' ||
        r.contains('secretaire') ||
        r.contains('secretary')) {
      return 'Secrétaire';
    }
    if (r == 'personnel' || r.contains('personnel')) {
      return 'Personnel';
    }
    if (role.length > 1) {
      return role[0].toUpperCase() + role.substring(1);
    }
    return role.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _subscribeToPushNotifications();
  }

  void _subscribeToPushNotifications() {
    try {
      final pushService = locator<MobilePushNotificationService>();
      _pushSubscription = pushService.onNotificationReceived.listen((notification) {
        if (mounted) {
          MobilePushNotificationService.showInAppPushBanner(context, notification);
          setState(() {
            _unreadNotificationsCount++;
          });
        }
      });
    } catch (e) {
      debugPrint('Error subscribing to push notifications in Dashboard: $e');
    }
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final session = locator<SessionManager>();
    final permissionService = locator<PermissionService>();
    final email = await session.getEmail();
    final role = await session.getRole();
    final profile = await permissionService.getCurrentProfile();
    Map<String, dynamic> dashboardStats = {};
    int unreadNotificationsCount = 0;

    try {
      dashboardStats = await locator<DashboardStatsRepository>().getSummary();
      await locator<SyncEngine>().updateLastSyncTime();
    } catch (e) {
      debugPrint('Dashboard stats unavailable: $e');
    }

    try {
      final notifs = await locator<MessagingRepository>().getNotifications();
      unreadNotificationsCount = (notifs['unreadCount'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('Failed to load notifications count: $e');
    }

    if (mounted) {
      if (email == null || email.isEmpty) {
        context.go('/login');
        return;
      }
      final normalizedRole = (role ?? 'staff').toLowerCase().trim();
      if (normalizedRole == 'student' ||
          normalizedRole == 'parent' ||
          normalizedRole == 'owner') {
        context.go(getHomeRouteForRole(normalizedRole));
        return;
      }
      final hasFinance =
          await permissionService.hasPermission(AppPermissions.financeView);
      final hasOwner = await permissionService.hasPermission(
        AppPermissions.ownerPlatformView,
      );
      final hasStudents =
          await permissionService.hasPermission(AppPermissions.studentsView);
      final hasStudentPromotion = await permissionService.hasPermission(
        AppPermissions.studentsPromote,
      );
      final hasHostel =
          await permissionService.hasPermission(AppPermissions.hostelView);
      final hasHr =
          await permissionService.hasPermission(AppPermissions.hrView);

      if (mounted) {
        setState(() {
          _userEmail = email;
          _userRole = profile.role;
          _hasFinanceAccess = hasFinance;
          _hasOwnerAccess = hasOwner;
          _hasStudentsAccess = hasStudents;
          _hasStudentPromotionAccess = hasStudentPromotion;
          _hasHostelAccess = hasHostel;
          _hasHrAccess = hasHr;
          _dashboardStats = dashboardStats;
          _unreadNotificationsCount = unreadNotificationsCount;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    await locator<AuthRepository>().logout();
    if (mounted) {
      context.go('/login');
    }
  }

  Future<void> _handleStudentRollAction() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final session = locator<SessionManager>();
    final employeeIdStr = await session.getEmployeeId();
    final employeeId = int.tryParse(employeeIdStr ?? '');
    final role = await session.getRole() ?? 'staff';
    final userEducationalLevel = await session.getEducationalLevel();

    final roleStr = role.toLowerCase().trim();
    final isTeacher =
        roleStr == 'teacher' ||
        roleStr == 'enseignant' ||
        roleStr == 'professeur' ||
        roleStr.contains('teacher') ||
        roleStr.contains('enseignant') ||
        roleStr.contains('professeur');
    List<Map<String, dynamic>> classes = [];

    try {
      if (isTeacher) {
        if (employeeId != null) {
          classes = await locator<AttendanceRepository>()
              .getTeacherClassesAndSubjects(employeeId);
        }
      } else {
        final formOpts = await locator<ExamsRepository>().getExamFormOptions();
        final classList = formOpts['classes'] ?? [];
        if (classList.isNotEmpty) {
          classes = classList
              .map(
                (c) => {
                  'class_id': c['id'],
                  'subject_id': null,
                  'school_classes': {
                    'class_name': c['class_name'],
                    'educational_level': c['educational_level'],
                    'section_name': c['section_name'],
                  },
                  'school_subjects': null,
                },
              )
              .toList();
        } else {
          final schoolIdStr = await session.getSchoolId();
          final schoolId = int.tryParse(schoolIdStr ?? '');
          if (schoolId != null) {
            classes = await locator<AcademicsRepository>()
                .getAllClassesAndSubjects(schoolId);
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading classes for roll: $e");
    }

    // Scoping for Level Director (e.g. University, Primary, College, Lycee)
    if (!isTeacher &&
        userEducationalLevel != null &&
        !EducationalLevelHelper.hasAllEducationalLevels(userEducationalLevel)) {
      final filtered = classes.where((item) {
        final className = item['school_classes']?['class_name']?.toString() ??
            item['class_name']?.toString();
        final educationalLevel = item['school_classes']?['school_sections']?['educational_level']?.toString() ??
            item['school_classes']?['educational_level']?.toString() ??
            item['educational_level']?.toString();
        final sectionName = item['school_classes']?['school_sections']?['section_name']?.toString() ??
            item['school_classes']?['section_name']?.toString() ??
            item['section_name']?.toString();
        final filiere = item['school_classes']?['filiere']?.toString() ??
            item['filiere']?.toString();

        return EducationalLevelHelper.isStudentInEducationalLevel(
          educationalLevel: educationalLevel,
          className: className,
          sectionName: sectionName,
          filiere: filiere,
          activeLevel: userEducationalLevel,
        );
      }).toList();

      if (filtered.isNotEmpty) {
        classes = filtered;
      }
    }

    if (mounted) {
      Navigator.pop(context); // Close loading dialog

      if (classes.isEmpty) {
        final errorMsg = isTeacher
            ? 'Aucune classe ou matière n’est assignée à ce compte enseignant.'
            : 'Aucune classe disponible pour votre niveau.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMsg)));
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          String searchQuery = '';
          return StatefulBuilder(
            builder: (context, setModalState) {
              final filteredClasses = classes.where((item) {
                if (searchQuery.trim().isEmpty) return true;
                final q = searchQuery.trim().toLowerCase();
                final className = (item['school_classes']?['class_name'] ?? item['class_name'] ?? '').toString().toLowerCase();
                final subjectName = (item['school_subjects']?['subject_name'] ?? item['subject_name'] ?? '').toString().toLowerCase();
                return className.contains(q) || subjectName.contains(q);
              }).toList();

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.slate300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          "Sélectionner une classe",
                          style: AppTextStyles.heading3,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          autofocus: false,
                          decoration: InputDecoration(
                            hintText: "Rechercher une classe...",
                            hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: AppColors.slate400, size: 20),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18, color: AppColors.slate400),
                                    onPressed: () {
                                      setModalState(() {
                                        searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.45,
                          ),
                          child: filteredClasses.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 40, color: AppColors.slate300),
                                      SizedBox(height: 8),
                                      Text(
                                        "Aucune classe trouvée",
                                        style: TextStyle(color: AppColors.slate400, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: filteredClasses.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  itemBuilder: (context, index) {
                                    final item = filteredClasses[index];
                                    final classId = TypeConverters.safeInt(item['class_id']);
                                    final className =
                                        item['school_classes']?['class_name']?.toString() ?? 'Classe';
                                    final subjectId = item['subject_id'] != null
                                        ? TypeConverters.safeInt(item['subject_id'])
                                        : null;
                                    final subjectName =
                                        item['school_subjects']?['subject_name']?.toString();

                                    return ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: AppColors.primaryLight,
                                        child: Icon(
                                          Icons.class_,
                                          color: AppColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(className, style: AppTextStyles.bodyBold),
                                      subtitle: subjectName != null
                                          ? Text(subjectName)
                                          : const Text("Appel Général Journée"),
                                      onTap: () {
                                        Navigator.pop(context);
                                        context.push(
                                          '/attendance/student-roll',
                                          extra: {
                                            'classId': classId,
                                            'className': className,
                                            'subjectId': subjectId,
                                            'subjectName': subjectName,
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }
  }

  Future<void> _handleAcademicsAction({required bool isDevoirs}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final session = locator<SessionManager>();
    final employeeIdStr = await session.getEmployeeId();
    final employeeId = int.tryParse(employeeIdStr ?? '');
    final role = await session.getRole() ?? 'staff';
    final userEducationalLevel = await session.getEducationalLevel();

    final roleStr2 = role.toLowerCase().trim();
    final isTeacher =
        roleStr2 == 'teacher' ||
        roleStr2 == 'enseignant' ||
        roleStr2 == 'professeur' ||
        roleStr2.contains('teacher') ||
        roleStr2.contains('enseignant') ||
        roleStr2.contains('professeur');
    List<Map<String, dynamic>> classes = [];
    final schoolId = int.tryParse(await session.getSchoolId() ?? '');

    try {
      if (isTeacher) {
        if (employeeId != null) {
          classes = await locator<AttendanceRepository>()
              .getTeacherClassesAndSubjects(employeeId);
        }
      } else {
        if (schoolId != null) {
          classes = await locator<AcademicsRepository>()
              .getAllClassesAndSubjects(schoolId);
        }
      }
    } catch (e) {
      debugPrint("Error loading classes for academics: $e");
    }

    // Scoping for Level Director
    if (!isTeacher &&
        userEducationalLevel != null &&
        !EducationalLevelHelper.hasAllEducationalLevels(userEducationalLevel)) {
      final filtered = classes.where((item) {
        final className = item['school_classes']?['class_name']?.toString() ??
            item['class_name']?.toString();
        final educationalLevel = item['school_classes']?['school_sections']?['educational_level']?.toString() ??
            item['school_classes']?['educational_level']?.toString() ??
            item['educational_level']?.toString();
        final sectionName = item['school_classes']?['school_sections']?['section_name']?.toString() ??
            item['school_classes']?['section_name']?.toString() ??
            item['section_name']?.toString();
        final filiere = item['school_classes']?['filiere']?.toString() ??
            item['filiere']?.toString();

        return EducationalLevelHelper.isStudentInEducationalLevel(
          educationalLevel: educationalLevel,
          className: className,
          sectionName: sectionName,
          filiere: filiere,
          activeLevel: userEducationalLevel,
        );
      }).toList();

      if (filtered.isNotEmpty) {
        classes = filtered;
      }
    }

    if (mounted) {
      Navigator.pop(context); // Close loading dialog

      final validClasses = classes
          .where((c) => c['subject_id'] != null)
          .toList();

      if (validClasses.isEmpty) {
        final errorMsg = isTeacher
            ? 'Aucune classe ou matière n’est assignée à ce compte enseignant.'
            : 'Aucune classe/matière disponible pour votre niveau.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMsg)));
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          String searchQuery = '';
          return StatefulBuilder(
            builder: (context, setModalState) {
              final filteredClasses = validClasses.where((item) {
                if (searchQuery.trim().isEmpty) return true;
                final q = searchQuery.trim().toLowerCase();
                final className = (item['school_classes']?['class_name'] ?? item['class_name'] ?? '').toString().toLowerCase();
                final subjectName = (item['school_subjects']?['subject_name'] ?? item['subject_name'] ?? '').toString().toLowerCase();
                return className.contains(q) || subjectName.contains(q);
              }).toList();

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.slate300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          "Sélectionner Classe & Matière",
                          style: AppTextStyles.heading3,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          autofocus: false,
                          decoration: InputDecoration(
                            hintText: "Rechercher classe ou matière...",
                            hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: AppColors.slate400, size: 20),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18, color: AppColors.slate400),
                                    onPressed: () {
                                      setModalState(() {
                                        searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.45,
                          ),
                          child: filteredClasses.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 40, color: AppColors.slate300),
                                      SizedBox(height: 8),
                                      Text(
                                        "Aucune classe ou matière trouvée",
                                        style: TextStyle(color: AppColors.slate400, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: filteredClasses.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  itemBuilder: (context, index) {
                                    final item = filteredClasses[index];
                                    final classId = TypeConverters.safeInt(item['class_id']);
                                    final className =
                                        item['school_classes']?['class_name'] ?? 'Classe';
                                    final subjectId = TypeConverters.safeInt(item['subject_id']);
                                    final subjectName =
                                        item['school_subjects']?['subject_name']
                                            as String? ??
                                        'Matière';

                                    return ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: AppColors.primaryLight,
                                        child: Icon(
                                          Icons.class_,
                                          color: AppColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(className, style: AppTextStyles.bodyBold),
                                      subtitle: Text(subjectName),
                                      onTap: () {
                                        Navigator.pop(context);
                                        final path = isDevoirs
                                            ? '/academics/gestion-devoirs'
                                            : '/academics/saisie-notes';
                                        context.push(
                                          path,
                                          extra: {
                                            'classId': classId,
                                            'className': className,
                                            'subjectId': subjectId,
                                            'subjectName': subjectName,
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }
  }

  // Drawers list
  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            accountName: Text(
              _userEmail.split('@')[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(_userEmail),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.dashboard,
                    color: Color(0xFF6D28D9),
                  ),
                  title: const Text('Tableau de bord'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentIndex = 0);
                  },
                ),
                if (_hasOwnerAccess)
                  ListTile(
                    leading: const Icon(
                      Icons.workspace_premium,
                      color: Color(0xFF7C3AED),
                    ),
                    title: const Text('PROPRIÉTAIRE'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/owner/dashboard');
                    },
                  ),
                if (_hasOwnerAccess)
                  ListTile(
                    leading: const Icon(
                      Icons.admin_panel_settings,
                      color: Color(0xFF4F46E5),
                    ),
                    title: const Text('Permissions'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/owner/permissions');
                    },
                  ),
                if (_hasStudentsAccess)
                  ListTile(
                    leading: const Icon(Icons.school, color: Color(0xFF4F46E5)),
                    title: const Text('Gestion des etudiants'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/students');
                    },
                  ),
                if (_hasStudentPromotionAccess)
                  ListTile(
                    leading: const Icon(
                      Icons.arrow_upward,
                      color: Color(0xFF059669),
                    ),
                    title: const Text('Promotion des etudiants'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/students/promotion');
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.assignment_turned_in,
                    color: Color(0xFFF59E0B),
                  ),
                  title: const Text("Faire l'appel"),
                  onTap: () {
                    Navigator.pop(context);
                    _handleStudentRollAction();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.qr_code_scanner,
                    color: Color(0xFF4F46E5),
                  ),
                  title: const Text('Scanner QR Code'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/attendance/qr-scan');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.grade, color: Color(0xFF9333EA)),
                  title: const Text('Saisie des Notes'),
                  onTap: () {
                    Navigator.pop(context);
                    _handleAcademicsAction(isDevoirs: false);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.fact_check,
                    color: Color(0xFF4338CA),
                  ),
                  title: const Text('Examens & Resultats'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/exams');
                  },
                ),
                if (_hasHostelAccess)
                  ListTile(
                    leading: const Icon(
                      Icons.home_work_outlined,
                      color: Color(0xFF0D9488),
                    ),
                    title: const Text('Internat & Dortoirs'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/hostel');
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Color(0xFF1E293B),
                  ),
                  title: const Text('QG Direction & Approbations', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Validation demandes & Suivi bida', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/admin/director-cockpit');
                  },
                ),
                if (_hasHrAccess)
                  ListTile(
                    leading: const Icon(
                      Icons.badge_outlined,
                      color: Color(0xFF7C3AED),
                    ),
                    title: const Text('Ressources Humaines'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/hr');
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.school_rounded,
                    color: Color(0xFF6366F1),
                  ),
                  title: const Text('E-Learning & LMS'),
                  subtitle: const Text('Cours, Lives, Quiz, Certificats'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/lms');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.assignment,
                    color: Color(0xFF2563EB),
                  ),
                  title: const Text('Devoirs & DS'),
                  onTap: () {
                    Navigator.pop(context);
                    _handleAcademicsAction(isDevoirs: true);
                  },
                ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFF2563EB),
                    ),
                    title: const Text('Générateur d\'Examens IA'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/teacher/ai-exam-generator');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.assignment_turned_in,
                      color: Color(0xFF0D9488),
                    ),
                    title: const Text('Fiche Pédagogique APC (IA)'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/teacher/ai-fiche-pedagogique');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.analytics,
                      color: Color(0xFF4F46E5),
                    ),
                    title: const Text('Diagnostic & Remédiation IA'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/teacher/ai-remediation');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.star_rounded,
                      color: Color(0xFF10B981),
                    ),
                    title: const Text('Live Discipline & Mérites'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/teacher/live-discipline');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.badge_outlined,
                      color: Color(0xFF0F766E),
                    ),
                    title: const Text('Mon Espace RH & Paie'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/teacher/self-service-hr');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF334155),
                    ),
                    title: const Text('Protection DND & Réponses'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/teacher/comm-protection');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.menu_book,
                      color: Color(0xFF0D9488),
                    ),
                    title: const Text('Cahier de textes'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/pedagogie/cahier-textes');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.event_note,
                      color: Color(0xFF0D9488),
                    ),
                    title: const Text('Planification'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/pedagogie/planification');
                    },
                  ),
                if (_isTeacher || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.insert_chart,
                      color: Color(0xFF7C3AED),
                    ),
                    title: const Text('Progression'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/pedagogie/progression');
                    },
                  ),
                if (_hasFinanceAccess)
                  ListTile(
                    leading: const Icon(
                      Icons.account_balance_wallet,
                      color: Color(0xFF10B981),
                    ),
                    title: const Text('Gestion Financière'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/finance/dashboard');
                    },
                  ),
                if (_hasFinanceAccess || _isSuperAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.mark_chat_unread_rounded,
                      color: Color(0xFF0F766E),
                    ),
                    title: const Text('Relances Frais WhatsApp & SMS', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Rappels impayés multilingues', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/finance/fee-reminders');
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.insert_chart,
                    color: Color(0xFF0D9488),
                  ),
                  title: const Text('Rapports HR'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/attendance/teacher-reports');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.local_library_rounded,
                    color: Color(0xFF0284C7),
                  ),
                  title: const Text('Bibliothèque & Centre Doc.', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Fonds physiques & E-books numériques', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/library');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.sync_lock_rounded,
                    color: Color(0xFF0284C7),
                  ),
                  title: const Text('Mode Hors-Ligne & Synchro', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Gestion du cache et file d\'attente', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/offline-sync');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.phonelink_lock_rounded,
                    color: Color(0xFF0F4C81),
                  ),
                  title: const Text('Appareils Connectés', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Téléphone unique & Sessions', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/security/connected-devices');
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text('Déconnexion'),
                  onTap: () {
                    Navigator.pop(context);
                    _handleLogout();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'EDUT PRO SCOLAIRE v1.0.0',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Welcome card inside dashboard
  num _statNumber(String key) {
    final value = _dashboardStats[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _statBool(String key) => _dashboardStats[key] == true;

  String _statCount(String key) => _statNumber(key).round().toString();

  String _statPercent(String key, {String? hasDataKey}) {
    if (hasDataKey != null && !_statBool(hasDataKey)) return '0%';
    return '${_statNumber(key).toStringAsFixed(1)}%';
  }

  String _statHours(String key) => '${_statNumber(key).round()}h';

  String _statAverage(String key) {
    if (!_statBool('hasGradeData')) return '0 / 20';
    return '${_statNumber(key).toStringAsFixed(1)} / 20';
  }

  double _progressFromPercent(String key, {String? hasDataKey}) {
    if (hasDataKey != null && !_statBool(hasDataKey)) return 0;
    final value = _statNumber(key).toDouble() / 100;
    return value.clamp(0, 1);
  }

  Widget _buildWelcomeCard() {
    final isTeacher = _isTeacher;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D28D9).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bienvenue,',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userEmail.split('@')[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _getRoleLabel(_userRole),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: isTeacher
                ? [
                    _buildStatItem(
                      Icons.check_circle_outline,
                      _statPercent(
                        'studentAttendanceRate',
                        hasDataKey: 'hasStudentAttendanceData',
                      ),
                      'Présences',
                    ),
                    _buildStatItem(
                      Icons.timer_outlined,
                      _statHours('plannedHours'),
                      'Planifiées',
                    ),
                    _buildStatItem(
                      Icons.class_,
                      _statCount('classesCount'),
                      'Classes Actives',
                    ),
                    _buildStatItem(
                      Icons.assignment,
                      _statCount('examsCount'),
                      'Examens',
                    ),
                  ]
                : [
                    _buildStatItem(
                      Icons.people_outline,
                      _statCount('activeStudents'),
                      'Élèves Actifs',
                    ),
                    _buildStatItem(
                      Icons.analytics_outlined,
                      _statPercent(
                        'teacherAttendanceRate',
                        hasDataKey: 'hasTeacherAttendanceData',
                      ),
                      'Présence Ens.',
                    ),
                    _buildStatItem(
                      Icons.class_,
                      _statCount('classesCount'),
                      'Classes Actives',
                    ),
                    _buildStatItem(
                      Icons.assignment,
                      _statCount('examsCount'),
                      'Examens',
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String subtitle) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6D28D9), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF0F0E26),
          selectedItemColor: const Color(0xFF8B5CF6),
          unselectedItemColor: Colors.white38,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'Analyses',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Paramètres',
            ),
          ],
        ),
      ),
    );
  }

  // Accueil tab view
  Widget _buildAccueilView() {
    final isTeacher = _isTeacher;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CacheStatusChip(),
          const SizedBox(height: 12),
          if (isTeacher) ...[
            const TeacherCockpitWidget(),
            const SizedBox(height: 28),
          ] else ...[
            _buildWelcomeCard(),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => context.push('/admin/director-cockpit'),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF312E81).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFDE047), size: 26),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QG Direction & Approbations',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Approbations 1-Clic • Suivi Bida • Présence Ens.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],

          _buildSectionTitle('Actions & Outils', Icons.grid_view_rounded),
          const SizedBox(height: 16),

          _buildQuickActionsGrid(isTeacher),
          const SizedBox(height: 28),

          _buildSectionTitle('Aperçu global', Icons.analytics_outlined),
          const SizedBox(height: 16),

          isTeacher ? _buildTeacherOverview() : _buildAdminOverview(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(bool isTeacher) {
    final List<Widget> quickActions = [
      _buildQuickActionCard(
        title: "E-Learning & LMS",
        description: "Cours, Lives, Quiz, Devoirs",
        icon: Icons.school_rounded,
        color: const Color(0xFF4F46E5),
        onTap: () => context.push('/lms'),
      ),
      if (!isTeacher)
        _buildQuickActionCard(
          title: 'QG Direction',
          description: 'Approbations & Suivi Bida',
          icon: Icons.admin_panel_settings_rounded,
          color: const Color(0xFF1E1B4B),
          onTap: () => context.push('/admin/director-cockpit'),
        ),
      if (isTeacher) ...[
        _buildQuickActionCard(
          title: 'Examens IA',
          description: 'Génération quiz & devoirs',
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF2563EB),
          onTap: () => context.push('/teacher/ai-exam-generator'),
        ),
        _buildQuickActionCard(
          title: 'Fiche APC IA',
          description: 'Préparation de leçon',
          icon: Icons.assignment_turned_in_rounded,
          color: const Color(0xFF0D9488),
          onTap: () => context.push('/teacher/ai-fiche-pedagogique'),
        ),
        _buildQuickActionCard(
          title: 'Diagnostic IA',
          description: 'Remédiation élèves',
          icon: Icons.analytics_rounded,
          color: const Color(0xFF4F46E5),
          onTap: () => context.push('/teacher/ai-remediation'),
        ),
        _buildQuickActionCard(
          title: 'Outils Classe',
          description: 'Tirage & Chronomètre',
          icon: Icons.casino_rounded,
          color: const Color(0xFF6D28D9),
          onTap: () => ClassroomToolsModal.show(context),
        ),
      ],
      if (_hasStudentsAccess)
        _buildQuickActionCard(
          title: 'Etudiants',
          description: 'Liste et suivi des profils',
          icon: Icons.school_outlined,
          color: const Color(0xFF4338CA),
          onTap: () => context.push('/students'),
        ),
      if (_hasStudentPromotionAccess)
        _buildQuickActionCard(
          title: 'Promotion',
          description: 'Passage classe suivante',
          icon: Icons.arrow_upward_outlined,
          color: const Color(0xFF059669),
          onTap: () => context.push('/students/promotion'),
        ),
      _buildQuickActionCard(
        title: 'Scanner QR Code',
        description: 'Présence Classe',
        icon: Icons.qr_code_scanner,
        color: const Color(0xFF4F46E5),
        onTap: () => context.push('/attendance/qr-scan'),
      ),
      _buildQuickActionCard(
        title: isTeacher ? 'Mon Calendrier' : 'Rapports HR',
        description: isTeacher ? 'Emploi du temps' : 'Présences Enseignants',
        icon: isTeacher ? Icons.calendar_today : Icons.insert_chart_outlined,
        color: const Color(0xFF0D9488),
        onTap: () => context.push('/attendance/teacher-reports'),
      ),
      _buildQuickActionCard(
        title: "Faire l'appel",
        description: "Présence des élèves",
        icon: Icons.assignment_turned_in_outlined,
        color: const Color(0xFFF59E0B),
        onTap: _handleStudentRollAction,
      ),
      _buildQuickActionCard(
        title: "Saisie des Notes",
        description: "Moy. Classe & Examens",
        icon: Icons.grade_outlined,
        color: const Color(0xFF9333EA),
        onTap: () => _handleAcademicsAction(isDevoirs: false),
      ),
      _buildQuickActionCard(
        title: "Examens",
        description: "Epreuves & resultats",
        icon: Icons.fact_check_outlined,
        color: const Color(0xFF4338CA),
        onTap: () => context.push('/exams'),
      ),
      if (_hasHostelAccess)
        _buildQuickActionCard(
          title: "Internat",
          description: "Chambres & residents",
          icon: Icons.home_work_outlined,
          color: const Color(0xFF0D9488),
          onTap: () => context.push('/hostel'),
        ),
      if (_hasHrAccess)
        _buildQuickActionCard(
          title: "RH",
          description: "Employes, paie, rapports",
          icon: Icons.badge_outlined,
          color: const Color(0xFF7C3AED),
          onTap: () => context.push('/hr'),
        ),
      _buildQuickActionCard(
        title: "Devoirs & DS",
        description: "Devoirs & Distributions",
        icon: Icons.assignment_outlined,
        color: const Color(0xFF2563EB),
        onTap: () => _handleAcademicsAction(isDevoirs: true),
      ),
      _buildQuickActionCard(
        title: "Bibliothèque",
        description: "Fonds doc. & E-books",
        icon: Icons.local_library_outlined,
        color: const Color(0xFF0284C7),
        onTap: () => context.push('/library'),
      ),
      if (_isTeacher || _isSuperAdmin)
        _buildQuickActionCard(
          title: 'Cahier de textes',
          description: 'Séances & leçons',
          icon: Icons.menu_book_outlined,
          color: const Color(0xFF0D9488),
          onTap: () => context.push('/pedagogie/cahier-textes'),
        ),
      if (_isTeacher || _isSuperAdmin)
        _buildQuickActionCard(
          title: 'Planification',
          description: 'Plans pédagogiques',
          icon: Icons.event_note_outlined,
          color: const Color(0xFF0D9488),
          onTap: () => context.push('/pedagogie/planification'),
        ),
      if (_isTeacher || _isSuperAdmin)
        _buildQuickActionCard(
          title: 'Progression',
          description: 'Suivi & avancement',
          icon: Icons.insert_chart_outlined,
          color: const Color(0xFF7C3AED),
          onTap: () => context.push('/pedagogie/progression'),
        ),
    ];

    if (_hasFinanceAccess) {
      quickActions.add(
        _buildQuickActionCard(
          title: 'Finances',
          description: 'Frais & Recouvrements',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF10B981),
          onTap: () => context.push('/finance/dashboard'),
        ),
      );
    }

    if (_hasOwnerAccess) {
      quickActions.insert(
        0,
        _buildQuickActionCard(
          title: 'PROPRIÉTAIRE',
          description: 'Pilotage central',
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFF6D28D9),
          onTap: () => context.push('/owner/dashboard'),
        ),
      );
      quickActions.insert(
        1,
        _buildQuickActionCard(
          title: 'Permissions',
          description: 'Roles et acces',
          icon: Icons.admin_panel_settings_outlined,
          color: const Color(0xFF4F46E5),
          onTap: () => context.push('/owner/permissions'),
        ),
      );
    }

    quickActions.add(
      _buildQuickActionCard(
        title: 'Messages',
        description: 'Communications internes',
        icon: Icons.chat_bubble_outline,
        color: const Color(0xFFF43F5E),
        onTap: () => context.push('/messaging'),
      ),
    );

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.25,
      children: quickActions,
    );
  }

  Widget _buildTeacherOverview() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildMiniOverviewCard(
          Icons.check_circle_outline,
          _statPercent(
            'studentAttendanceRate',
            hasDataKey: 'hasStudentAttendanceData',
          ),
          'Présence',
          const Color(0xFF10B981),
        ),
        _buildMiniOverviewCard(
          Icons.timer_outlined,
          _statHours('plannedHours'),
          'Planifiées',
          const Color(0xFF3B82F6),
        ),
        _buildMiniOverviewCard(
          Icons.class_,
          _statCount('classesCount'),
          'Classes',
          const Color(0xFF8B5CF6),
        ),
        _buildMiniOverviewCard(
          Icons.assignment,
          _statCount('examsCount'),
          'Examens',
          const Color(0xFFEF4444),
        ),
      ],
    );
  }

  Widget _buildAdminOverview() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildMiniOverviewCard(
          Icons.people_outline,
          _statCount('activeStudents'),
          'Élèves Actifs',
          const Color(0xFF4F46E5),
        ),
        _buildMiniOverviewCard(
          Icons.analytics_outlined,
          _statPercent(
            'teacherAttendanceRate',
            hasDataKey: 'hasTeacherAttendanceData',
          ),
          'Présence Ens.',
          const Color(0xFFF59E0B),
        ),
        _buildMiniOverviewCard(
          Icons.class_,
          _statCount('classesCount'),
          'Classes Actives',
          const Color(0xFF10B981),
        ),
        _buildMiniOverviewCard(
          Icons.assignment,
          _statCount('examsCount'),
          'Examens En cours',
          const Color(0xFFEF4444),
        ),
      ],
    );
  }

  Widget _buildMiniOverviewCard(
    IconData icon,
    String value,
    String title,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  // Analyses tab view
  Widget _buildAnalysesView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Analyses de l'établissement",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Rapports de performance globale",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildAnalyticCard(
            "Taux de présence global",
            _statPercent(
              'studentAttendanceRate',
              hasDataKey: 'hasStudentAttendanceData',
            ),
            _progressFromPercent(
              'studentAttendanceRate',
              hasDataKey: 'hasStudentAttendanceData',
            ),
            Colors.green,
          ),
          _buildAnalyticCard(
            "Moyenne des évaluations",
            _statAverage('averageGrade'),
            (_statNumber('averageGrade').toDouble() / 20).clamp(0, 1),
            Colors.blue,
          ),
          _buildAnalyticCard(
            "Devoirs suivis",
            _statCount('homeworkCount'),
            _progressFromPercent('homeworkOnTimeRate'),
            Colors.amber,
          ),
          _buildAnalyticCard(
            "Alertes absence / retard",
            '${_statCount('absenceAlerts')} / ${_statCount('lateAlerts')}',
            0,
            Colors.purple,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.slate100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Activités Extrascolaires",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Clubs actifs"),
                    Text(
                      _statNumber('clubsCount') > 0
                          ? _statCount('clubsCount')
                          : 'Aucune donnée',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Événements planifiés"),
                    Text(
                      _statNumber('eventsCount') > 0
                          ? '${_statNumber('eventsCount').round()} ce mois-ci'
                          : 'Aucune donnée',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticCard(
    String title,
    String value,
    double percent,
    Color progressColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: progressColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // Paramètres tab view
  Widget _buildParametresView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Mon Profil & Parametres",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.slate100),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFF8B5CF6),
                  child: Icon(Icons.person, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userEmail.split('@')[0].toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Role: ${_userRole.toUpperCase()}",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _userEmail,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Preferences",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.slate100),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Mode Sombre"),
                  secondary: const Icon(
                    Icons.dark_mode,
                    color: Color(0xFF6D28D9),
                  ),
                  value: _isDarkMode,
                  onChanged: (val) {
                    setState(() {
                      _isDarkMode = val;
                    });
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language, color: Color(0xFF6D28D9)),
                  title: const Text("Langue"),
                  trailing: const Text(
                    "Francais",
                    style: TextStyle(color: Colors.grey),
                  ),
                  onTap: () => context.push('/notifications'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.cloud_done_rounded,
                    color: Color(0xFF10B981),
                  ),
                  title: const Text("Serveur Cloud Officiel"),
                  subtitle: const Text(
                    "web-up-ar-rahama.vercel.app (U P AR-RAHAMA)",
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Text(
                      "Connecté",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text(
              "Se deconnecter",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              "EDUT PRO SCOLAIRE - Version 1.0.0",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'EDUT PRO SCOLAIRE',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 1.0,
          ),
        ),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'Menu',
            );
          },
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.white),
                onPressed: () async {
                  await context.push('/notifications');
                  _loadUserInfo();
                },
                tooltip: 'Notifications',
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_unreadNotificationsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            onPressed: _handleLogout,
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          SyncStatusBanner(onRefresh: _loadUserInfo),
          Expanded(
            child: SafeArea(
              top: false,
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _buildAccueilView(),
                  _buildAnalysesView(),
                  _buildParametresView(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }
}
