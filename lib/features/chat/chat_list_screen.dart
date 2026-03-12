import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../providers/app_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/database/local_database.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../../core/widgets/custom_avatar.dart';

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
                        CustomAvatar(
                          radius: 12,
                          backgroundColor: myAvatarColor.withOpacity(0.2),
                          foregroundColor: myAvatarColor,
                          imageUrl: auth.fullAvatarUrl,
                          fallbackText: auth.userName ?? '?',
                          fontSizeFallback: 10,
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
              icon: Icon(Icons.more_vert_rounded,
                  color: Theme.of(context).appBarTheme.iconTheme?.color ??
                      Colors.white54),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              tooltip: 'المزيد',
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
                    child: CustomAvatar(
                      radius: 100,
                      backgroundColor: avatarColor.withOpacity(0.2),
                      foregroundColor: avatarColor,
                      imageUrl: user.fullAvatarUrl,
                      fallbackText: user.initials,
                      fontSizeFallback: 60,
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
              child: CustomAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.2),
                foregroundColor: avatarColor,
                imageUrl: user.fullAvatarUrl,
                fallbackText: user.initials,
                fontSizeFallback: 16,
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
