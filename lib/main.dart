import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/di/injection.dart';
import 'core/api/sync_engine.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/inactivity_lock_service.dart';
import 'features/auth/presentation/inactivity_lock_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize date formatting locales for intl
  try {
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('fr', null);
  } catch (e) {
    debugPrint('Date formatting initialization error: $e');
  }

  // Initialize dependency injection & Supabase safely
  try {
    await setupLocator();
  } catch (e, stack) {
    debugPrint('Setup locator initialization error: $e\n$stack');
  }

  // Start Offline Sync Engine and detect connectivity immediately
  try {
    if (locator.isRegistered<SyncEngine>()) {
      await locator<SyncEngine>().start();
    }
  } catch (e) {
    debugPrint('SyncEngine start error: $e');
  }

  // Initialize Mobile Push Notifications Service
  try {
    if (locator.isRegistered<MobilePushNotificationService>()) {
      await locator<MobilePushNotificationService>().initialize();
    }
  } catch (e) {
    debugPrint('Push notification service error: $e');
  }

  // Initialize Auto-Lock Inactivity Service (3 minutes timeout)
  try {
    if (locator.isRegistered<InactivityLockService>()) {
      await locator<InactivityLockService>().initialize();
    }
  } catch (e) {
    debugPrint('InactivityLockService error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'U.P.R',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return InactivityLockWrapper(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
