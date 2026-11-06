/// App 入口：初始化 Supabase 与本地通知，按登录态分流到登录页或主页。
///
/// 路由：
/// - `/` → AuthGate：未登录显示登录页，已登录显示主页；
/// - `/home` → 主页（HomeScreen，未传资料时自己再查一次）。
library;

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'models/models.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  await NotificationService().initLocal();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      routes: <String, WidgetBuilder>{
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

/// 登录门：查当前用户资料，有资料进主页，没资料进登录页。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: SupabaseService().currentProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }
        final profile = snapshot.data;
        if (profile != null) {
          return HomeScreen(profile: profile);
        }
        return const AuthScreen();
      },
    );
  }
}
