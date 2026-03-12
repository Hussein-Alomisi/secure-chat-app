import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/app_providers.dart';
import '../../core/widgets/custom_avatar.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  File? _pickedImage;
  bool _isSavingImage = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pickedImage = File(picked.path);
      });
      _updateAvatar(File(picked.path));
    }
  }

  Future<void> _updateAvatar(File image) async {
    setState(() => _isSavingImage = true);

    try {
      final auth = ref.read(authProvider);
      await ref.read(authProvider.notifier).updateProfile(
            name: auth.userName ?? '',
            imagePath: image.path,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF4ADE80),
            content: Text('تم تحديث الصورة بنجاح',
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content:
                Text('فشل تحديث الصورة', style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingImage = false);
    }
  }

  void _showBiometricBottomSheet() async {
    final biometric = ref.read(biometricServiceProvider);
    final isAvailable = await biometric.isBiometricAvailable();
    final isEnabled = await biometric.isBiometricEnabled();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateBottomSheet) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                Icons.fingerprint_rounded,
                color: isEnabled
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFF6C63FF),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'تسجيل الدخول بالبصمة',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isAvailable
                    ? (isEnabled
                        ? 'البصمة مفعلة لتسجيل الدخول السريع'
                        : 'قم بتفعيل البصمة لتسجيل الدخول بأمان وسرعة')
                    : 'جهازك لا يدعم البصمة أو غير معدّة حالياً',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.color
                            ?.withOpacity(0.5) ??
                        Colors.white.withOpacity(0.5),
                    fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (isAvailable)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEnabled
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (isEnabled) {
                      await biometric.disableBiometric();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('تم إيقاف البصمة بنجاح')),
                        );
                      }
                    } else {
                      final authenticated = await biometric
                          .authenticate('قم بتأكيد البصمة لتفعيلها');
                      if (authenticated) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        _showPasswordPrompt();
                      }
                    }
                  },
                  child: Text(isEnabled ? 'إيقاف البصمة' : 'تفعيل البصمة',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordPrompt() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text('تأكيد كلمة المرور',
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.white)),
          content: TextField(
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            controller: passwordController,
            obscureText: true,
            style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color ??
                    Colors.white),
            decoration: InputDecoration(
              hintTextDirection: TextDirection.rtl,
              hintText: 'كلمة المرور الحالية',
              hintStyle: TextStyle(
                  color: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.color
                          ?.withOpacity(0.3) ??
                      Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF)),
              onPressed: () async {
                final pwd = passwordController.text.trim();
                if (pwd.isEmpty) return;

                final auth = ref.read(authProvider);
                final api = ref.read(apiServiceProvider);

                try {
                  final encService = ref.read(encryptionServiceProvider);
                  final publicKey = await encService.getPublicKeyBase64();

                  await api.login(
                    userId: auth.userId!,
                    password: pwd,
                    publicKey: publicKey,
                  );

                  await ref
                      .read(biometricServiceProvider)
                      .enableBiometric(auth.userId!, pwd);

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          backgroundColor:
                              Theme.of(context).appBarTheme.backgroundColor,
                          content: Text(
                            'تم تفعيل البصمة بنجاح',
                            style: TextStyle(
                                color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color ??
                                    Colors.white),
                          )),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('كلمة المرور غير صحيحة')),
                    );
                  }
                }
              },
              child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    Color myAvatarColor;
    try {
      myAvatarColor = Color(
          int.parse((auth.avatarColor ?? '#6C63FF').replaceFirst('#', '0xFF')));
    } catch (_) {
      myAvatarColor = const Color(0xFF6C63FF);
    }

    // CustomAvatar handles both local and network images

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          elevation: 0,
          title: Text(
            'الملف الشخصي',
            style: TextStyle(
                color: Theme.of(context).appBarTheme.titleTextStyle?.color ??
                    Colors.white),
          ),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: Theme.of(context).appBarTheme.iconTheme?.color ??
                  Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CustomAvatar(
                      radius: 60,
                      backgroundColor: myAvatarColor.withOpacity(0.2),
                      foregroundColor: myAvatarColor,
                      imageUrl: auth.fullAvatarUrl,
                      localImage: _pickedImage,
                      fallbackText: auth.userName ?? '?',
                      fontSizeFallback: 40,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF6C63FF),
                          shape: BoxShape.circle,
                        ),
                        child: _isSavingImage
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                auth.userName ?? 'مستخدم',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final isDark =
                          ref.watch(themeModeProvider) == ThemeMode.dark;
                      return ListTile(
                        leading: Icon(
                          isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          color: isDark
                              ? const Color(0xFFFFD600)
                              : const Color(0xFF5C6BC0),
                        ),
                        title: Text('المظهر',
                            style: TextStyle(
                                color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color ??
                                    Colors.white)),
                        trailing: Switch(
                          value: isDark,
                          onChanged: (val) => ref
                              .read(themeModeProvider.notifier)
                              .toggleTheme(),
                          activeColor: const Color(0xFF6C63FF),
                        ),
                      );
                    },
                  ),
                  Divider(
                    indent: 10,
                    endIndent: 10,
                    height: 1,
                    color: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.color
                        ?.withValues(alpha: 0.5),
                  ),
                  ListTile(
                    leading: const Icon(Icons.fingerprint_rounded,
                        color: Color(0xFF6C63FF)),
                    title: Text('إعداد البصمة',
                        style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                    Colors.white)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.grey),
                    onTap: _showBiometricBottomSheet,
                  ),
                  Divider(
                    indent: 10,
                    endIndent: 10,
                    height: 1,
                    color: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.color
                        ?.withValues(alpha: 0.5),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent),
                    title: const Text('تسجيل الخروج',
                        style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(context); // Close profile screen
                      ref.read(authProvider.notifier).logout();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
