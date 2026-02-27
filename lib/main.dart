import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/auth/login_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for security
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const ProviderScope(child: SecureChatApp()));
}

class SecureChatApp extends ConsumerStatefulWidget {
  const SecureChatApp({super.key});

  @override
  ConsumerState<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends ConsumerState<SecureChatApp> {
  @override
  void initState() {
    super.initState();
    // Attempt auto-login from stored credentials
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).tryAutoLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SecureChat',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      // ── Dark Theme ────────────────────────────────────────────────────────
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF13132B),
        ),
        textTheme: GoogleFonts.cairoTextTheme(
          ThemeData.dark().textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF13132B),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // ── Light Theme ───────────────────────────────────────────────────────
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F4FF),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF3B82F6),
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.cairoTextTheme(
          ThemeData.light().textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: authState.isLoading
          ? const _SplashScreen()
          : authState.isLoggedIn
              ? const ChatListScreen()
              : const LoginScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D0D1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, color: Color(0xFF6C63FF), size: 64),
            SizedBox(height: 16),
            CircularProgressIndicator(
              color: Color(0xFF6C63FF),
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}
