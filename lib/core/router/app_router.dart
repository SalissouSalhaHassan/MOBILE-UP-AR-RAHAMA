import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../api/mobile_api_client.dart';
import '../utils/type_converters.dart';
import '../auth/role_redirect.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/offline_pin_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/family/presentation/family_dashboard_screen.dart';
import '../../features/family/presentation/family_finance_screen.dart';
import '../../features/family/presentation/family_transport_screen.dart';
import '../../features/family/presentation/family_hostel_screen.dart';
import '../../features/family/presentation/digital_student_id_screen.dart';
import '../../features/ai/presentation/ai_tutor_screen.dart';
import '../../features/students/presentation/students_management_screen.dart';
import '../../features/students/presentation/student_details_screen.dart';
import '../../features/students/presentation/student_form_screen.dart';
import '../../features/students/presentation/student_promotion_screen.dart';
import '../../features/attendance/presentation/qr_scan_screen.dart';
import '../../features/attendance/presentation/teacher_attendance_screen.dart';
import '../../features/attendance/presentation/student_attendance_screen.dart';
import '../../features/academics/presentation/saisie_notes_screen.dart';
import '../../features/academics/presentation/gestion_devoirs_screen.dart';
import '../../features/academics/presentation/student_homework_screen.dart';
import '../../features/academics/presentation/ai_timetable_generator_sheet.dart';
import '../../features/library/presentation/past_exams_screen.dart';
import '../../features/library/presentation/e_library_screen.dart';
import '../../features/academics/presentation/qcm_scanner_screen.dart';
import '../../features/finance/presentation/finance_dashboard_screen.dart';
import '../../features/finance/presentation/journal_de_caisse_screen.dart';
import '../../features/finance/presentation/cashflow_forecast_screen.dart';
import '../../features/finance/presentation/student_fee_details_screen.dart';
import '../../features/finance/presentation/record_payment_screen.dart';
import '../../features/finance/presentation/unified_financial_report_screen.dart';
import '../../features/ministry/presentation/benchmarking_screen.dart';
import '../../features/exams/presentation/exams_dashboard_screen.dart';
import '../../features/exams/presentation/exam_results_screen.dart';
import '../../features/exams/presentation/exam_form_screen.dart';
import '../../features/hostel/presentation/hostel_dashboard_screen.dart';
import '../../features/hr/presentation/hr_dashboard_screen.dart';
import '../../features/owner/presentation/owner_dashboard_screen.dart';
import '../../features/owner/presentation/owner_platform_admin_screen.dart';
import '../../features/owner/presentation/owner_audit_screen.dart';
import '../../features/owner/presentation/owner_subscription_screen.dart';
import '../../features/owner/presentation/owner_legacy_console_screen.dart';
import '../../features/owner/presentation/owner_register_school_screen.dart';
import '../../features/owner/presentation/owner_permissions_screen.dart';
import '../../features/messaging/presentation/messaging_screen.dart';
import '../../features/messaging/presentation/notifications_screen.dart';
import '../../features/messaging/presentation/direct_chat_screen.dart';
import '../../features/ministry/presentation/ministry_dashboard_screen.dart';
import '../di/injection.dart';
import '../auth/session_manager.dart';
import '../../features/pedagogie/presentation/cahier_textes_screen.dart';
import '../../features/pedagogie/presentation/planification_screen.dart';
import '../../features/pedagogie/presentation/progression_screen.dart';
import '../../features/health/presentation/school_clinic_screen.dart';
import '../../features/teacher/presentation/teacher_cockpit_screen.dart';
import '../../features/teacher/presentation/ai_exam_generator_screen.dart';
import '../../features/teacher/presentation/ai_fiche_pedagogique_screen.dart';
import '../../features/teacher/presentation/ai_remediation_screen.dart';
import '../../features/teacher/presentation/live_discipline_screen.dart';
import '../../features/teacher/presentation/teacher_self_service_hr_screen.dart';
import '../../features/teacher/presentation/teacher_comm_protection_screen.dart';
import '../../features/hr/presentation/director_cockpit_screen.dart';
import '../../features/ai/presentation/exam_predictor_screen.dart';
import '../../features/finance/presentation/smart_fee_reminders_screen.dart';
import '../../features/sync/presentation/offline_sync_screen.dart';
import '../../features/security/presentation/connected_devices_screen.dart';
import '../../features/security/presentation/gate_scanner_screen.dart';
import '../permissions/permission_service.dart';
import 'guarded_screen.dart';
import '../../features/lms/presentation/lms_home_screen.dart';
import '../../features/finance/presentation/smart_bourses_echeanciers_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final initialUsername = (state.extra as Map<String, dynamic>?)?['username'] as String? ??
              state.uri.queryParameters['username'];
          return LoginScreen(initialUsername: initialUsername);
        },
      ),
      GoRoute(
        path: '/offline-pin',
        builder: (context, state) {
          final isSetting = state.uri.queryParameters['setup'] == 'true';
          return OfflinePinScreen(isSettingPin: isSetting);
        },
      ),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/ministry/dashboard',
        builder: (context, state) => const MinistryDashboardScreen(),
      ),
      GoRoute(
        path: '/owner/dashboard',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerPlatformView,
          child: OwnerDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/owner/platform-admin',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerPlatformView,
          child: OwnerPlatformAdminScreen(),
        ),
      ),
      GoRoute(
        path: '/owner/audit',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerPlatformView,
          child: OwnerAuditScreen(),
        ),
      ),
      GoRoute(
        path: '/owner/subscription',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerPlatformView,
          child: OwnerSubscriptionScreen(),
        ),
      ),
      GoRoute(
        path: '/owner/legacy-console',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerPlatformView,
          child: OwnerLegacyConsoleScreen(),
        ),
      ),
      GoRoute(
        path: '/owner/register-school',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerSchoolsManage,
          child: OwnerRegisterSchoolScreen(),
        ),
      ),
      GoRoute(
        path: '/owner/permissions',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.ownerPlatformView,
          child: OwnerPermissionsScreen(),
        ),
      ),
      GoRoute(
        path: '/family/dashboard',
        builder: (context, state) => const FamilyDashboardScreen(),
      ),
      GoRoute(
        path: '/family/finance',
        builder: (context, state) => const FamilyFinanceScreen(),
      ),
      GoRoute(
        path: '/family/transport',
        builder: (context, state) => const FamilyTransportScreen(),
      ),
      GoRoute(
        path: '/family/library',
        builder: (context, state) => const ELibraryScreen(),
      ),
      GoRoute(
        path: '/family/homework',
        builder: (context, state) => const StudentHomeworkScreen(),
      ),
      GoRoute(
        path: '/library/past-exams',
        builder: (context, state) => const PastExamsScreen(),
      ),
      GoRoute(
        path: '/academics/ai-timetable-scheduler',
        builder: (context, state) => const Scaffold(
          body: SafeArea(child: AiTimetableGeneratorSheet()),
        ),
      ),
      GoRoute(
        path: '/family/hostel',
        builder: (context, state) => const FamilyHostelScreen(),
      ),
      GoRoute(
        path: '/family/student-id',
        builder: (context, state) => const DigitalStudentIdScreen(),
      ),
      GoRoute(
        path: '/ai/tutor',
        builder: (context, state) => const AiTutorScreen(),
      ),
      GoRoute(
        path: '/students',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.studentsView,
          child: StudentsManagementScreen(),
        ),
      ),
      GoRoute(
        path: '/students/details',
        builder: (context, state) {
          final studentId = state.extra as int;
          return GuardedScreen(
            permission: AppPermissions.studentsView,
            child: StudentDetailsScreen(studentId: studentId),
          );
        },
      ),
      GoRoute(
        path: '/students/form',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return GuardedScreen(
            permission: AppPermissions.studentsEdit,
            child: StudentFormScreen(initialData: extra),
          );
        },
      ),
      GoRoute(
        path: '/students/promotion',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.studentsPromote,
          child: StudentPromotionScreen(),
        ),
      ),
      GoRoute(
        path: '/attendance/qr-scan',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.attendanceManage,
          child: QRScanScreen(),
        ),
      ),
      GoRoute(
        path: '/attendance/teacher-reports',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.attendanceView,
          child: TeacherAttendanceScreen(),
        ),
      ),
      GoRoute(
        path: '/attendance',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final classId = extra['classId'] as int? ??
              int.tryParse(state.uri.queryParameters['classId'] ?? '') ?? 1;
          final className = extra['className'] as String? ??
              state.uri.queryParameters['className'] ??
              state.uri.queryParameters['class'] ?? '3ème B';
          final subjectId = extra['subjectId'] as int? ??
              int.tryParse(state.uri.queryParameters['subjectId'] ?? '');
          final subjectName = extra['subjectName'] as String? ??
              state.uri.queryParameters['subjectName'] ??
              state.uri.queryParameters['subject'];
          final initialDateStr = extra['initialDateStr'] as String? ??
              state.uri.queryParameters['initialDateStr'];

          return GuardedScreen(
            permission: AppPermissions.attendanceView,
            child: StudentAttendanceScreen(
              classId: classId,
              className: className,
              subjectId: subjectId,
              subjectName: subjectName,
              initialDateStr: initialDateStr,
            ),
          );
        },
      ),
      GoRoute(
        path: '/attendance/student-roll',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final classId = TypeConverters.safeInt(
            extra['classId'],
            int.tryParse(state.uri.queryParameters['classId'] ?? '') ?? 1,
          );
          final className = extra['className']?.toString() ??
              state.uri.queryParameters['className'] ??
              state.uri.queryParameters['class'] ?? '3ème B';
          final subjectId = extra['subjectId'] != null
              ? TypeConverters.safeInt(extra['subjectId'])
              : int.tryParse(state.uri.queryParameters['subjectId'] ?? '');
          final subjectName = extra['subjectName']?.toString() ??
              state.uri.queryParameters['subjectName'] ??
              state.uri.queryParameters['subject'];
          final initialDateStr = extra['initialDateStr']?.toString() ??
              state.uri.queryParameters['initialDateStr'];

          return GuardedScreen(
            permission: AppPermissions.attendanceView,
            child: StudentAttendanceScreen(
              classId: classId,
              className: className,
              subjectId: subjectId,
              subjectName: subjectName,
              initialDateStr: initialDateStr,
            ),
          );
        },
      ),
      GoRoute(
        path: '/academics/saisie-notes',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final classId = TypeConverters.safeInt(extra['classId'], 1);
          final className = extra['className']?.toString() ?? 'Classe';
          final subjectId = TypeConverters.safeInt(extra['subjectId'], 1);
          final subjectName = extra['subjectName']?.toString() ?? 'Matière';

          return GuardedScreen(
            permission: AppPermissions.saisieNotesView,
            child: SaisieNotesScreen(
              classId: classId,
              className: className,
              subjectId: subjectId,
              subjectName: subjectName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/academics/gestion-devoirs',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final classId = TypeConverters.safeInt(extra['classId'], 1);
          final className = extra['className']?.toString() ?? 'Classe';
          final subjectId = TypeConverters.safeInt(extra['subjectId'], 1);
          final subjectName = extra['subjectName']?.toString() ?? 'Matière';

          return GuardedScreen(
            permission: AppPermissions.gestionDevoirsView,
            child: GestionDevoirsScreen(
              classId: classId,
              className: className,
              subjectId: subjectId,
              subjectName: subjectName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/academics/qcm-scanner',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final subjectName = extra['subjectName'] as String? ?? 'Évaluation';
          final className = extra['className'] as String? ?? 'Classe';
          final studentName = extra['studentName'] as String?;

          return QcmScannerScreen(
            subjectName: subjectName,
            className: className,
            studentName: studentName,
          );
        },
      ),
      GoRoute(
        path: '/health/clinic',
        builder: (context, state) => const SchoolClinicScreen(),
      ),
      GoRoute(
        path: '/library/past-exams',
        builder: (context, state) => const PastExamsScreen(),
      ),
      GoRoute(
        path: '/lms',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final studentId = extra['studentId'] as int? ??
              int.tryParse(state.uri.queryParameters['studentId'] ?? '');
          final studentName = extra['studentName'] as String? ??
              state.uri.queryParameters['studentName'];
          return LmsHomeScreen(
            studentId: studentId,
            studentName: studentName,
          );
        },
      ),
      GoRoute(
        path: '/finance/dashboard',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.financeView,
          child: FinanceDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/finance/bourses-echeanciers',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.financeView,
          child: SmartBoursesEcheanciersScreen(),
        ),
      ),
      GoRoute(
        path: '/finance/unified-report',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.financeView,
          child: UnifiedFinancialReportScreen(),
        ),
      ),
      GoRoute(
        path: '/finance/journal',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.financeView,
          child: JournalDeCaisseScreen(),
        ),
      ),
      GoRoute(
        path: '/exams',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.examsView,
          child: ExamsDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/exams/results',
        builder: (context, state) {
          final exam = state.extra as Map<String, dynamic>;
          return GuardedScreen(
            permission: AppPermissions.examsView,
            child: ExamResultsScreen(exam: exam),
          );
        },
      ),
      GoRoute(
        path: '/exams/form',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return GuardedScreen(
            permission: AppPermissions.examsManage,
            child: ExamFormScreen(initialData: extra),
          );
        },
      ),
      GoRoute(
        path: '/hostel',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.hostelView,
          child: HostelDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/hr',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.hrView,
          child: HrDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/finance/fee-details',
        builder: (context, state) {
          final fee = state.extra as Map<String, dynamic>;
          return GuardedScreen(
            permission: AppPermissions.financeView,
            child: StudentFeeDetailsScreen(feeData: fee),
          );
        },
      ),
      GoRoute(
        path: '/finance/record-payment',
        builder: (context, state) {
          final fee = state.extra as Map<String, dynamic>;
          return GuardedScreen(
            permission: AppPermissions.financeCollect,
            child: RecordPaymentScreen(feeData: fee),
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/messaging',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.messagingView,
          child: MessagingScreen(),
        ),
      ),
      GoRoute(
        path: '/messaging/chat',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final recipientId = extra['recipientId'] as int? ?? 0;
          final recipientName = extra['recipientName'] as String? ?? 'Discussion';
          final recipientRole = extra['recipientRole'] as String?;
          return DirectChatScreen(
            recipientId: recipientId,
            recipientName: recipientName,
            recipientRole: recipientRole,
          );
        },
      ),
      GoRoute(
        path: '/pedagogie/cahier-textes',
        builder: (context, state) => const CahierTextesScreen(),
      ),
      GoRoute(
        path: '/pedagogie/planification',
        builder: (context, state) => const PlanificationScreen(),
      ),
      GoRoute(
        path: '/finance/forecast',
        builder: (context, state) => const GuardedScreen(
          permission: AppPermissions.financeView,
          child: CashflowForecastScreen(),
        ),
      ),
      GoRoute(
        path: '/ministry/dashboard',
        builder: (context, state) => const MinistryDashboardScreen(),
      ),
      GoRoute(
        path: '/ministry/benchmarking',
        builder: (context, state) => const BenchmarkingScreen(),
      ),
      GoRoute(
        path: '/pedagogie/progression',
        builder: (context, state) => const ProgressionScreen(),
      ),
      GoRoute(
        path: '/teacher/cockpit',
        builder: (context, state) => const TeacherCockpitScreen(),
      ),
      GoRoute(
        path: '/teacher/ai-exam-generator',
        builder: (context, state) => AiExamGeneratorScreen(
          initialClass: state.uri.queryParameters['class'],
          initialSubject: state.uri.queryParameters['subject'],
        ),
      ),
      GoRoute(
        path: '/teacher/ai-fiche-pedagogique',
        builder: (context, state) => AiFichePedagogiqueScreen(
          initialClass: state.uri.queryParameters['class'],
          initialSubject: state.uri.queryParameters['subject'],
        ),
      ),
      GoRoute(
        path: '/teacher/ai-remediation',
        builder: (context, state) => AiRemediationScreen(
          initialClass: state.uri.queryParameters['class'],
          initialSubject: state.uri.queryParameters['subject'],
        ),
      ),
      GoRoute(
        path: '/teacher/live-discipline',
        builder: (context, state) {
          final cls = state.uri.queryParameters['class'];
          return LiveDisciplineScreen(initialClass: cls);
        },
      ),
      GoRoute(
        path: '/teacher/self-service-hr',
        builder: (context, state) => const TeacherSelfServiceHrScreen(),
      ),
      GoRoute(
        path: '/teacher/comm-protection',
        builder: (context, state) => const TeacherCommProtectionScreen(),
      ),
      GoRoute(
        path: '/admin/director-cockpit',
        builder: (context, state) => const DirectorCockpitScreen(),
      ),
      GoRoute(
        path: '/director/cockpit',
        builder: (context, state) => const DirectorCockpitScreen(),
      ),
      GoRoute(
        path: '/family/exam-predictor',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final sId = extra['studentId'] as int? ?? int.tryParse(state.uri.queryParameters['studentId'] ?? '');
          final sName = extra['studentName'] as String? ?? state.uri.queryParameters['studentName'];
          final sClass = extra['studentClass'] as String? ?? state.uri.queryParameters['studentClass'];
          return ExamPredictorScreen(
            studentId: sId,
            studentName: sName,
            studentClass: sClass,
          );
        },
      ),
      GoRoute(
        path: '/ai/exam-predictor',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final sId = extra['studentId'] as int? ?? int.tryParse(state.uri.queryParameters['studentId'] ?? '');
          final sName = extra['studentName'] as String? ?? state.uri.queryParameters['studentName'];
          final sClass = extra['studentClass'] as String? ?? state.uri.queryParameters['studentClass'];
          return ExamPredictorScreen(
            studentId: sId,
            studentName: sName,
            studentClass: sClass,
          );
        },
      ),
      GoRoute(
        path: '/family/transport',
        builder: (context, state) => const FamilyTransportScreen(),
      ),
      GoRoute(
        path: '/transport',
        builder: (context, state) => const FamilyTransportScreen(),
      ),
      GoRoute(
        path: '/finance/fee-reminders',
        builder: (context, state) => const SmartFeeRemindersScreen(),
      ),
      GoRoute(
        path: '/admin/fee-reminders',
        builder: (context, state) => const SmartFeeRemindersScreen(),
      ),
      GoRoute(
        path: '/sync',
        builder: (context, state) => const OfflineSyncScreen(),
      ),
      GoRoute(
        path: '/offline-sync',
        builder: (context, state) => const OfflineSyncScreen(),
      ),
      GoRoute(
        path: '/security/connected-devices',
        builder: (context, state) => const ConnectedDevicesScreen(),
      ),
      GoRoute(
        path: '/connected-devices',
        builder: (context, state) => const ConnectedDevicesScreen(),
      ),
      GoRoute(
        path: '/security/gate-scanner',
        builder: (context, state) => const GateScannerScreen(),
      ),
      GoRoute(
        path: '/gate-scanner',
        builder: (context, state) => const GateScannerScreen(),
      ),
      GoRoute(
        path: '/library',
        builder: (context, state) => const ELibraryScreen(),
      ),
      GoRoute(
        path: '/e-library',
        builder: (context, state) => const ELibraryScreen(),
      ),
      GoRoute(
        path: '/e-learning',
        builder: (context, state) => const ELibraryScreen(),
      ),
    ],
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _sessionCheckTimer;

  @override
  void initState() {
    super.initState();
    _sessionCheckTimer = Timer(const Duration(seconds: 2), _checkSession);
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSession() async {
    final sessionManager = locator<SessionManager>();
    final isLoggedIn = await sessionManager.isLoggedIn();
    if (!mounted) return;
    if (isLoggedIn) {
      // Proactively verify if the user account is still valid and not deleted
      try {
        final token = await sessionManager.getToken();
        if (token != null && token.isNotEmpty) {
          final profile = await locator<MobileApiClient>()
              .getCurrentProfile(accessToken: token)
              .timeout(const Duration(seconds: 3));

          await sessionManager.saveSession(
            token: token,
            email: profile.email,
            role: profile.role,
            employeeId: profile.employeeId ?? '',
            userId: profile.userId,
            schoolId: profile.schoolId,
            studentId: profile.studentId,
            studentName: profile.studentName,
            studentClass: profile.studentClass,
            permissions: profile.permissions,
          );
        }
      } on MobileApiException catch (e) {
        if (e.message.contains("Compte non relié") ||
            e.message.contains("supprimé") ||
            e.message.contains("invalide")) {
          debugPrint("[SplashScreen] User account was deleted on server. Clearing session.");
          await sessionManager.clearSession();
          if (!mounted) return;
          context.go('/login');
          return;
        }
      } catch (e) {
        debugPrint("[SplashScreen] Background profile verification: $e");
      }

      if (!mounted) return;
      final role = await sessionManager.getRole() ?? 'staff';
      context.go(getHomeRouteForRole(role));
    } else {
      // Check if user has an offline PIN configured on this device
      final hasPin = await sessionManager.hasOfflinePin();
      final hasOfflineProfile = await sessionManager.getCachedOfflineEmail();
      if (!mounted) return;
      if (hasPin || (hasOfflineProfile != null && hasOfflineProfile.isNotEmpty)) {
        context.go('/offline-pin');
      } else {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school, size: 80, color: Colors.indigo),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
