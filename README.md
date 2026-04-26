# SecureChat

A full-featured, privacy-focused real-time messaging application built with Flutter. SecureChat delivers a robust chatting experience combining seamless real-time communication with full offline capabilities, ensuring your messages are always accessible.

## Features

- **Real-Time Messaging**: Instant communication powered by Socket.io.
- **Offline Mode**: Local SQLite database integration ensures the app is fully functional without an internet connection.
- **Message Status**: Track whether messages are sent, delivered, or read.
- **Rich Messaging**: Support for replying to messages and message reactions.
- **Media Sharing & Viewer**: Share images, videos, files, and links. Includes a dedicated, immersive chat media viewer.
- **In-Chat Search**: Easily search through conversations with seamless next/previous navigation.
- **Intuitive UI**: Smooth scroll behavior inspired by WhatsApp, an unread message counter, and a "New Messages" divider.
- **Presence System**: Real-time online/offline status and typing indicators.
- **Profile Management**: Customizable user profiles with name and avatar management.
- **Privacy & Security**:
  - Biometric authentication (App lock via fingerprint).
  - Privacy mode (hides content when the app is in the background).
- **Personalization**: Emoji and sticker support, along with full Dark and Light theme capabilities.

## Screenshots

<p float="left">
  <img src="https://via.placeholder.com/250x500.png?text=Home+Screen" width="200" />
  <img src="https://via.placeholder.com/250x500.png?text=Chat+View" width="200" />
  <img src="https://via.placeholder.com/250x500.png?text=Media+Viewer" width="200" />
  <img src="https://via.placeholder.com/250x500.png?text=Settings+%26+Security" width="200" />
</p>

## Tech Stack

- **Frontend**: Flutter
- **Backend**: Node.js, Express, Socket.io
- **Local Database**: SQLite
- **Push Notifications**: Firebase Cloud Messaging (FCM)

## Architecture

This project follows a feature-based architecture pattern with a strong separation of concerns. The application logic is modularized to ensure scalability and maintainability:

- **Core**: Contains globally shared utilities, models, networking logic, and local database (SQLite) integrations.
- **Features**: Encapsulates specific application modules (e.g., Auth, Chat, Profile), making it easy to isolate functionality.
- **Services / Providers**: Handles state management and direct communication with external services (Node.js backend, Socket.io, Firebase).

## Folder Structure

```text
lib/
├── core/
│   ├── audio/           # Audio processing utilities
│   ├── auth/            # Core authentication logic (Biometrics, etc.)
│   ├── database/        # SQLite configuration and DAOs
│   ├── encryption/      # Local encryption algorithms
│   ├── models/          # Shared data models
│   ├── network/         # HTTP and Socket.io clients
│   ├── utils/           # Helpers and constants
│   └── widgets/         # Reusable UI components
├── features/
│   ├── auth/            # Login, registration, and onboarding UI
│   ├── chat/            # Chat listing, messaging UI, media viewer
│   └── profile/         # User profile and settings
├── providers/           # State management providers
├── services/            # Background and external services
├── firebase_options.dart
└── main.dart
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- Node.js & npm (for the backend environment)
- A physical device or emulator for testing biometric features

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/securechat.git
   cd securechat/flutter_app
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure the Environment:**
   Ensure you have your backend running locally or hosted, and update the base URLs in the `lib/core/network/` configurations.
   If using Firebase, add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS).

4. **Run the application:**
   ```bash
   flutter run
   ```

## Future Improvements

- **Voice Messages**: In-app recording and playback of voice notes.
- **End-to-End Encryption**: Upgrading from local-only encryption to full E2EE for maximum security.
- **Cloud Sync**: Securely sync chat history and media across multiple devices.
- **Group Chats**: Support for multi-user channels with admin controls.

---

*Designed and built with care for a seamless, private chatting experience.*
