<div align="center">
  <img src="https://via.placeholder.com/150x150.png?text=SecureChat+Logo" alt="SecureChat Logo" width="120" />

  # 🛡️ SecureChat

  **A High-Performance, Privacy-First Real-Time Messaging Application**

  [![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
  [![Node.js](https://img.shields.io/badge/Node.js-43853D?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
  [![Socket.io](https://img.shields.io/badge/Socket.io-010101?style=for-the-badge&logo=socket.io&logoColor=white)](https://socket.io/)
  [![SQLite](https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white)](https://sqlite.org/)

  *Seamless Communication • Offline-First Architecture • Enterprise-Grade Security*
</div>

---

## 📖 Overview

**SecureChat** is a production-ready messaging platform built to demonstrate advanced mobile development practices. It bridges the gap between instantaneous real-time communication and robust offline capabilities, offering a seamless UX regardless of network conditions. 

Designed with privacy and performance at its core, this project showcases clean architecture, complex state management, and real-time data synchronization.

---

## ✨ Key Technical Achievements

What makes this project stand out from typical chat applications:

- 🔄 **Offline-First Synchronization:** Built a robust local caching layer using **SQLite**. Users can read, search, and queue messages while fully offline. Messages automatically sync when the connection is restored.
- ⚡ **Real-Time Birectional Data:** Leveraged **Socket.io** for low-latency, instantaneous message delivery, typing indicators, and presence tracking.
- 📱 **Native-Grade Fluid UI/UX:** Engineered a custom WhatsApp-style scroll behavior, seamless "jump-to" in-chat search navigation, and immersive media viewing without dropping frames.
- 🔒 **Privacy by Design:** Implemented hardware-backed **Biometric Authentication** (Fingerprint/FaceID) and an App-Background Privacy Mode to prevent sensitive content from appearing in the OS app switcher.

---

## 📱 Feature Showcase

### 💬 Messaging Experience
* **Rich Messaging:** Text, emoji, sticker support, message reactions, and threaded replies.
* **Granular Status Tracking:** Real-time visual indicators for *Sent*, *Delivered*, and *Read* receipts.
* **Smart Navigation:** "New Messages" divider and dynamic unread counters.

### 🖼️ Media & Search
* **Media Handling:** Seamless sharing of images, videos, documents, and links.
* **Immersive Viewer:** Dedicated in-app gallery viewer for high-res media exploration.
* **Deep Search:** Instantly search through thousands of local messages with keyword highlighting and previous/next navigation.

### 👤 Profile & Personalization
* **Presence System:** Live Online/Offline status and dynamic typing indicators.
* **Customization:** Full user profile management and complete support for dynamically switching between **Dark & Light Themes**.

---

## 📸 Screenshots

<div align="center">
  <img src="https://via.placeholder.com/250x500.png?text=Home+Screen" width="22%" />&nbsp;
  <img src="https://via.placeholder.com/250x500.png?text=Chat+Interface" width="22%" />&nbsp;
  <img src="https://via.placeholder.com/250x500.png?text=Media+Viewer" width="22%" />&nbsp;
  <img src="https://via.placeholder.com/250x500.png?text=Security+Lock" width="22%" />
</div>

---

## 🏗️ Architecture & Code Quality

This project strictly adheres to **Clean Architecture** principles to ensure the codebase remains scalable, testable, and maintainable.

```text
lib/
├── core/            # Global utilities, network clients (Socket.io), DAOs, models
├── features/        # Isolated feature modules (Auth, Chat, Profile)
├── providers/       # State Management handling
└── services/        # Background processes and Firebase integration
```

* **Separation of Concerns:** UI code is completely decoupled from business logic and data fetching.
* **Modular Features:** The `features/` directory isolates distinct parts of the app, preventing spaghetti code and allowing for easy scaling.

---

## 🚀 Getting Started

### Prerequisites
* [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0.0+)
* Node.js & npm (for local backend setup)
* Physical device or Emulator with Biometrics enabled

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/securechat.git
   cd securechat/flutter_app
   ```

2. **Fetch dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Environment**
   * Start your local Node.js server.
   * Update the `baseUrl` in `lib/core/network/` to point to your local backend.
   * *(Optional)* Add your Firebase `google-services.json` / `GoogleService-Info.plist` for push notifications.

4. **Run the App**
   ```bash
   flutter run
   ```

---

## 🔮 Roadmap & Future Scope

Demonstrating a vision for continuous improvement:
- [ ] **End-to-End Encryption (E2EE):** Implementing Signal Protocol for absolute privacy.
- [ ] **Voice Notes:** In-app audio recording with waveform visualization.
- [ ] **Group Channels:** Expanding architecture to support multi-user chat rooms.
- [ ] **Cloud Backup:** Securely syncing local SQLite data to encrypted cloud storage.

---

<div align="center">
  <b>Built with ❤️ by <a href="https://github.com/yourusername">Your Name</a></b><br>
  <i>A portfolio piece demonstrating modern mobile development, state management, and real-time networking.</i>
</div>
