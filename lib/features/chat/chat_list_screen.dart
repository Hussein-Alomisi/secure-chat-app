import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../providers/app_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/database/local_database.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final usersAsync = ref.watch(usersProvider);

    Color myAvatarColor;
    try {
      myAvatarColor = Color(
          int.parse((auth.avatarColor ?? '#6C63FF').replaceFirst('#', '0xFF')));
    } catch (_) {
      myAvatarColor = const Color(0xFF6C63FF);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'محادثة آمنة',
                style: TextStyle(
                  color: Theme.of(context).appBarTheme.titleTextStyle?.color ??
                      Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: myAvatarColor.withOpacity(0.2),
                          backgroundImage: auth.fullAvatarUrl != null
                              ? NetworkImage(auth.fullAvatarUrl!)
                              : null,
                          child: auth.fullAvatarUrl == null
                              ? Text(
                                  auth.userName?.isNotEmpty == true
                                      ? auth.userName![0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: myAvatarColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          auth.userName ?? '',
                          style: TextStyle(
                            color: Theme.of(context)
                                    .appBarTheme
                                    .titleTextStyle
                                    ?.color ??
                                Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.fingerprint_rounded,
                  color: Color(0xFF6C63FF)),
              onPressed: () => _showBiometricBottomSheet(context, ref),
              tooltip: 'إعداد البصمة',
            ),
            // IconButton(
            //   icon: const Icon(Icons.shield_outlined, color: Color(0xFF6C63FF)),
            //   onPressed: () => _showSecurityInfo(context),
            //   tooltip: 'معلومات الأمان',
            // ),
            Consumer(
              builder: (context, ref, _) {
                final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                return IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      key: ValueKey(isDark),
                      color: isDark
                          ? const Color(0xFFFFD600)
                          : const Color(0xFF5C6BC0),
                    ),
                  ),
                  tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                  onPressed: () {
                    ref.read(themeModeProvider.notifier).toggleTheme();
                  },
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.logout_rounded,
                  color: Theme.of(context).appBarTheme.iconTheme?.color ??
                      Colors.white54),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        body: usersAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary),
          ),
          error: (err, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded,
                    color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.38) ??
                        Colors.white38,
                    size: 48),
                const SizedBox(height: 12),
                Text('تعذر تحميل جهات الاتصال',
                    style: TextStyle(
                        color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withOpacity(0.5) ??
                            Colors.white.withOpacity(0.5))),
              ],
            ),
          ),
          data: (users) {
            // Filter out current user
            final contacts = users.where((u) => u.id != auth.userId).toList();
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: contacts.length,
              itemBuilder: (ctx, i) {
                final user = contacts[i];
                return _ContactTile(
                  user: user,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: user),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showSecurityInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
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
            const Icon(Icons.shield_rounded,
                color: Color(0xFF6C63FF), size: 48),
            const SizedBox(height: 12),
            Text(
              'حماية عالية المستوى',
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ...[
              ('🔑', 'X25519 ECDH', 'تبادل المفاتيح بأمان كامل'),
              ('🔒', 'AES-256-GCM', 'تشفير الرسائل والملفات'),
              ('🔐', 'Forward Secrecy', 'مفتاح مختلف لكل جلسة'),
              ('🗑️', 'تدمير ذاتي', 'الملفات تُحذف من السيرفر فور التسليم'),
              ('💾', 'تخزين محلي', 'كل البيانات على جهازك فقط'),
            ].map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(item.$1, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$2,
                              style: TextStyle(
                                  color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color ??
                                      Colors.white,
                                  fontWeight: FontWeight.w600)),
                          Text(item.$3,
                              style: TextStyle(
                                  color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color
                                          ?.withOpacity(0.5) ??
                                      Colors.white.withOpacity(0.5),
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showBiometricBottomSheet(BuildContext context, WidgetRef ref) async {
    final biometric = ref.read(biometricServiceProvider);
    final isAvailable = await biometric.isBiometricAvailable();
    final isEnabled = await biometric.isBiometricEnabled();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
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
                        _showPasswordPrompt(context, ref);
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

  void _showPasswordPrompt(BuildContext context, WidgetRef ref) {
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

                // We need to locally check via api login or somehow if password is correct.
                // Since we don't hold the plain password anywhere, we make a quick validation call to ensure it's not a fake password
                // before persisting it as our 'fast login' password!
                try {
                  // We use the already stored public key (we could fetch it again but let's assume valid)
                  final encService = ref.read(encryptionServiceProvider);
                  final publicKey = await encService.getPublicKeyBase64();

                  // Show loading indicator here or just do it in the background
                  await api.login(
                    userId: auth.userId!,
                    password: pwd,
                    publicKey: publicKey,
                  );

                  // If this point is reached, the password is correct!
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
}

class _ContactTile extends ConsumerWidget {
  final AppUserModel user;
  final VoidCallback onTap;

  const _ContactTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Parse avatar color
    Color avatarColor;
    try {
      avatarColor = Color(
        int.parse(user.avatarColor.replaceFirst('#', '0xFF')),
      );
    } catch (_) {
      avatarColor = const Color(0xFF6C63FF);
    }

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: 'profile_pic_${user.id}',
                    child: CircleAvatar(
                      radius: 100,
                      backgroundColor: avatarColor.withOpacity(0.2),
                      backgroundImage: user.fullAvatarUrl != null
                          ? NetworkImage(user.fullAvatarUrl!)
                          : null,
                      child: user.fullAvatarUrl == null
                          ? Text(
                              user.initials,
                              style: TextStyle(
                                color: avatarColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 60,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.name,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color ??
                          Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Stack(
          children: [
            Hero(
              tag: 'profile_pic_${user.id}',
              child: CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.2),
                backgroundImage: user.fullAvatarUrl != null
                    ? NetworkImage(user.fullAvatarUrl!)
                    : null,
                child: user.fullAvatarUrl == null
                    ? Text(
                        user.initials,
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
            ),
            if (user.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        user.name,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: FutureBuilder<String>(
        future:
            ref.read(localDatabaseProvider).getOrCreateConversation(user.id),
        builder: (context, convIdSnapshot) {
          if (!convIdSnapshot.hasData) {
            return const SizedBox.shrink();
          }
          final convId = convIdSnapshot.data!;
          return StreamBuilder<List<Message>>(
            stream: ref.watch(localDatabaseProvider).watchMessages(convId),
            builder: (context, msgSnapshot) {
              if (msgSnapshot.hasData && msgSnapshot.data!.isNotEmpty) {
                final lastMsg = msgSnapshot.data!.last;
                String preview = lastMsg.decryptedText ?? '';
                if (lastMsg.type == 'audio') preview = '🎤 رسالة صوتية';
                if (lastMsg.type == 'image') preview = '🖼️ صورة';
                if (lastMsg.type == 'video') preview = '📹 فيديو';
                if (lastMsg.type == 'file') preview = '📎 ملف';

                if (lastMsg.isDeleted) preview = '🚫 رسالة محذوفة';

                return Text(
                  preview,
                  style: TextStyle(
                    color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.6) ??
                        Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              }
              return Text(
                'ابدأ المحادثة...',
                style: TextStyle(
                  color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withOpacity(0.4) ??
                      Colors.white.withOpacity(0.4),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              );
            },
          );
        },
      ),
      trailing: FutureBuilder<String>(
        future:
            ref.read(localDatabaseProvider).getOrCreateConversation(user.id),
        builder: (context, convIdSnapshot) {
          if (!convIdSnapshot.hasData) {
            return const SizedBox.shrink();
          }
          final convId = convIdSnapshot.data!;

          final unreadCountStream = convIdSnapshot.data != null
              ? (ref
                  .watch(localDatabaseProvider)
                  .watchConversations()
                  .map((list) {
                  try {
                    return list.firstWhere((c) => c.id == convId);
                  } catch (_) {
                    return null;
                  }
                }))
              : Stream.value(null);

          return StreamBuilder<Conversation?>(
              stream: unreadCountStream,
              builder: (context, convSnapshot) {
                final count = convSnapshot.data?.unreadCount ?? 0;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      user.isOnline
                          ? 'متصل'
                          : user.lastSeen != null
                              ? 'آخر ظهور ${timeago.format(DateTime.tryParse(user.lastSeen!) ?? DateTime.now(), locale: 'ar')}'
                              : 'غير متصل',
                      style: TextStyle(
                        color: user.isOnline
                            ? const Color(0xFF4ADE80)
                            : Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withOpacity(0.5) ??
                                Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontWeight:
                            user.isOnline ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (count > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        child: Text(
                          count > 99 ? '99+' : count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                );
              });
        },
      ),
    );
  }
}
