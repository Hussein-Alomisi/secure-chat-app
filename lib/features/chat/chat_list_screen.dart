import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../providers/app_providers.dart';
import '../../core/models/chat_message.dart';
import '../chat/chat_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final usersAsync = ref.watch(usersProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF13132B),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'محادثة آمنة',
                style: TextStyle(
                  color: Colors.white,
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
                  const SizedBox(width: 4),
                  Text(
                    auth.userName ?? '',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.shield_outlined, color: Color(0xFF6C63FF)),
              onPressed: () => _showSecurityInfo(context),
              tooltip: 'معلومات الأمان',
            ),
            // Consumer(
            //   builder: (context, ref, _) {
            //     final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
            //     return IconButton(
            //       icon: AnimatedSwitcher(
            //         duration: const Duration(milliseconds: 300),
            //         transitionBuilder: (child, anim) => RotationTransition(
            //           turns: anim,
            //           child: FadeTransition(opacity: anim, child: child),
            //         ),
            //         child: Icon(
            //           isDark
            //               ? Icons.light_mode_rounded
            //               : Icons.dark_mode_rounded,
            //           key: ValueKey(isDark),
            //           color: isDark
            //               ? const Color(0xFFFFD600)
            //               : const Color(0xFF5C6BC0),
            //         ),
            //       ),
            //       tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
            //       onPressed: () {
            //         ref.read(themeModeProvider.notifier).state =
            //             isDark ? ThemeMode.light : ThemeMode.dark;
            //       },
            //     );
            //   },
            // ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white54),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        body: usersAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
          ),
          error: (err, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    color: Colors.white38, size: 48),
                const SizedBox(height: 12),
                Text('تعذر تحميل جهات الاتصال',
                    style: TextStyle(color: Colors.white.withOpacity(0.5))),
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
      backgroundColor: const Color(0xFF13132B),
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
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.shield_rounded,
                color: Color(0xFF6C63FF), size: 48),
            const SizedBox(height: 12),
            const Text(
              'حماية عالية المستوى',
              style: TextStyle(
                  color: Colors.white,
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
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          Text(item.$3,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
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
}

class _ContactTile extends StatelessWidget {
  final AppUserModel user;
  final VoidCallback onTap;

  const _ContactTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: avatarColor.withOpacity(0.2),
            child: Text(
              user.initials,
              style: TextStyle(
                color: avatarColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
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
                  border: Border.all(color: const Color(0xFF0D0D1A), width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        user.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        user.isOnline
            ? 'متصل الآن'
            : user.lastSeen != null
                ? 'آخر ظهور ${timeago.format(DateTime.tryParse(user.lastSeen!) ?? DateTime.now(), locale: 'ar')}'
                : 'غير متصل',
        style: TextStyle(
          color: user.isOnline
              ? const Color(0xFF4ADE80)
              : Colors.white.withOpacity(0.35),
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.white.withOpacity(0.2),
      ),
    );
  }
}
