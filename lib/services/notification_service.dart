import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../core/network/api_service.dart';

// Background message handler must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background execution
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Global key to handle navigation from anywhere
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<void> init() async {
    // 1. Request permissions (Required for iOS, Android 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted messaging permission');
    }

    // 2. Initialize Local Notifications for showing heads-up notifications in foreground
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 3. Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 4. Listen to foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      if (message.notification != null) {
        // FCM automatically hides notifications when app is in foreground
        // We use flutter_local_notifications to display it manually
        _showLocalNotification(message);
      }
    });

    // 5. App opened from a terminated state via notification tap
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageRoute(initialMessage.data);
    }

    // 6. App opened from background state via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessageRoute(message.data);
    });
  }

  // Display Local Notification when in Foreground
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'chat_messages_channel',
      'Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    // Serialize payload to pass it to the tap handler
    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title,
      body: message.notification?.body,
      notificationDetails: platformChannelSpecifics,
      payload: jsonEncode(message.data),
    );
  }

  // Trigger manual local notification
  Future<void> showForegroundNotification({
    required String title,
    required String body,
    required String chatId,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'chat_messages_channel',
      'Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: jsonEncode({'chatId': chatId}),
    );
  }

  // Handle tap on Foreground Local Notification
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      _handleMessageRoute(data);
    }
  }

  // Navigation Logic
  void _handleMessageRoute(Map<String, dynamic> data) {
    final chatId = data['chatId'];
    if (chatId != null && navigatorKey.currentState != null) {
      // Navigate to your Chat Screen
      // You may need to adapt this routing based on your app's navigation structure
      // navigatorKey.currentState!.pushNamed('/chat', arguments: {'chatId': chatId});
      debugPrint('Navigate to chat $chatId');
    }
  }

  // Get and Send Token to Backend
  Future<void> sendTokenToBackend(String userId, ApiService apiService) async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        debugPrint("FCM Token initialized: $token");
        await apiService.updateFcmToken(userId, token);
      }

      // Listen for token refresh in case the device token changes
      _fcm.onTokenRefresh.listen((newToken) async {
        debugPrint("FCM Token refreshed: $newToken");
        await apiService.updateFcmToken(userId, newToken);
      });
    } catch (e) {
      debugPrint("Error sending FCM token to backend: $e");
    }
  }
}
