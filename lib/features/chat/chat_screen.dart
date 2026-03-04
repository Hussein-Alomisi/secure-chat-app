import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';
import '../../providers/app_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/audio/voice_recorder_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final AppUserModel peer;
  const ChatScreen({super.key, required this.peer});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;
  // ignore: prefer_final_fields
  bool _peerIsTyping = false;

  // ─── Voice recording state ─────────────────────────────────────────────────
  final _voiceRecorder = VoiceRecorderService();
  bool _isRecording = false; // true while recording is active
  bool _isSlidingToCancel = false; // true during hold + slide left
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  double _dragOffset = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const double _cancelThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider(widget.peer.id).notifier).initialize();
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _pulseController.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await ref.read(chatProvider(widget.peer.id).notifier).sendText(text);
    _scrollToBottom();
  }

  // ─── Voice recording logic ─────────────────────────────────────────────────

  Future<void> _onMicLongPressStart(LongPressStartDetails details) async {
    final hasPermission = await _voiceRecorder.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يتطلب الوصول إلى الميكروفون للإرسال الصوتي'),
            backgroundColor: Color(0xFF6C63FF),
          ),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();
    await _voiceRecorder.start();

    setState(() {
      _isRecording = true;
      _isSlidingToCancel = false;
      _recordingSeconds = 0;
      _dragOffset = 0;
    });

    _pulseController.repeat(reverse: true);
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds++);
    });
  }

  /// Called while the user is still holding – track slide-left gesture.
  void _onMicLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    final dx = -details.localOffsetFromOrigin.dx; // positive = dragged left
    setState(() {
      _dragOffset = dx.clamp(0.0, _cancelThreshold + 20);
      _isSlidingToCancel = dx > _cancelThreshold;
    });
  }

  /// Called when the user lifts their finger.
  /// If they slid to cancel → cancel immediately.
  /// Otherwise → keep recording; the UI now shows Send / Cancel buttons.
  Future<void> _onMicLongPressEnd(LongPressEndDetails details) async {
    if (!_isRecording) return;

    if (_isSlidingToCancel) {
      await _cancelRecording();
    } else {
      // Reset drag visual but DO NOT stop recording.
      // The user can now tap Send or Cancel in the recording bar.
      setState(() {
        _dragOffset = 0;
        _isSlidingToCancel = false;
      });
    }
  }

  /// Tapped the ✅ Send button in the recording bar.
  Future<void> _sendRecording() async {
    if (!_isRecording) return;
    _stopRecordingTimer();

    if (_recordingSeconds < 1) {
      await _cancelRecording();
      return;
    }

    final path = await _voiceRecorder.stop();
    setState(() {
      _isRecording = false;
      _dragOffset = 0;
    });

    if (path != null && mounted) {
      await ref.read(chatProvider(widget.peer.id).notifier).sendVoice(
            filePath: path,
            durationSeconds: _recordingSeconds,
          );
      _scrollToBottom();
    }
  }

  /// Tapped the ❌ Cancel button or slid past threshold.
  Future<void> _cancelRecording() async {
    _stopRecordingTimer();
    await _voiceRecorder.cancel();
    HapticFeedback.lightImpact();
    setState(() {
      _isRecording = false;
      _isSlidingToCancel = false;
      _dragOffset = 0;
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _pulseController.stop();
    _pulseController.reset();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── File picking ──────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    await ref.read(chatProvider(widget.peer.id).notifier).sendFile(
          filePath: file.path!,
          fileName: file.name,
          fileType: _getMimeType(file.extension ?? ''),
        );
    _scrollToBottom();
  }

  Future<void> _pickImage({bool isCamera = false}) async {
    final picker = ImagePicker();
    final picked = isCamera
        ? await picker.pickImage(source: ImageSource.camera, imageQuality: 80)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (picked == null) return;

    await ref.read(chatProvider(widget.peer.id).notifier).sendFile(
          filePath: picked.path,
          fileName: picked.name,
          fileType: 'image/jpeg',
        );
    _scrollToBottom();
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    await ref.read(chatProvider(widget.peer.id).notifier).sendFile(
          filePath: picked.path,
          fileName: picked.name,
          fileType: 'video/mp4',
        );
    _scrollToBottom();
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13132B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                  icon: Icons.image_outlined,
                  label: 'الصور',
                  color: const Color(0xFF6C63FF),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage();
                  }),
              _AttachOption(
                  icon: Icons.camera_alt_outlined,
                  label: 'الكاميرا',
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(isCamera: true);
                  }),
              _AttachOption(
                  icon: Icons.videocam_outlined,
                  label: 'فيديو',
                  color: const Color(0xFFF59E0B),
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideo();
                  }),
              _AttachOption(
                  icon: Icons.folder_outlined,
                  label: 'ملف',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile();
                  }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final messages = ref.watch(chatProvider(widget.peer.id));
    final usersAsync = ref.watch(usersProvider);
    final myId = auth.userId ?? '';

    final currentPeer = usersAsync.maybeWhen(
      data: (users) => users.firstWhere((u) => u.id == widget.peer.id,
          orElse: () => widget.peer),
      orElse: () => widget.peer,
    );

    ref.listen<List<ChatMessage>>(chatProvider(widget.peer.id), (prev, next) {
      if (prev != null && next.length > prev.length) {
        _scrollToBottom();
      }
    });

    Color peerColor;
    try {
      peerColor =
          Color(int.parse(widget.peer.avatarColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      peerColor = const Color(0xFF6C63FF);
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF13132B),
          elevation: 0,
          leadingWidth: 36,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: peerColor.withOpacity(0.2),
                child: Text(
                  widget.peer.initials,
                  style: TextStyle(
                    color: peerColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peer.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text(
                    _peerIsTyping
                        ? 'يكتب...'
                        : currentPeer.isOnline
                            ? 'متصل'
                            : (currentPeer.lastSeen != null
                                ? 'آخر ظهور ${currentPeer.lastSeen}'
                                : 'غير متصل'),
                    style: TextStyle(
                      color: _peerIsTyping || currentPeer.isOnline
                          ? const Color(0xFF4ADE80)
                          : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // Message list
            Expanded(
              child: messages.isEmpty
                  ? _EmptyConversation(peerName: widget.peer.name)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = messages[i];
                        final isMe = msg.senderId == myId;
                        return _MessageBubble(
                          message: msg,
                          isMe: isMe,
                          onDownload: msg.localFilePath == null &&
                                  msg.fileId != null
                              ? () => ref
                                  .read(chatProvider(widget.peer.id).notifier)
                                  .downloadFile(msg)
                              : null,
                        );
                      },
                    ),
            ),

            // Input bar
            Container(
              color: const Color(0xFF13132B),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: SafeArea(
                top: false,
                child: _isRecording
                    ? _buildRecordingBar()
                    : _buildNormalInputBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Normal input bar ───────────────────────────────────────────────────────

  Widget _buildNormalInputBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.attach_file_rounded, color: Colors.white54),
          onPressed: _showAttachmentMenu,
        ),
        Expanded(
          child: TextField(
            controller: _textController,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            minLines: 1,
            onChanged: (val) {
              final typing = val.isNotEmpty;
              if (typing != _isTyping) {
                setState(() => _isTyping = typing);
                final socket = ref.read(socketServiceProvider);
                typing
                    ? socket.sendTypingStart(widget.peer.id)
                    : socket.sendTypingStop(widget.peer.id);
              }
            },
            decoration: InputDecoration(
              hintText: 'اكتب رسالة...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _isTyping
            ? _SendButton(onTap: _sendText)
            : _MicButton(
                pulseAnimation: _pulseAnimation,
                onLongPressStart: _onMicLongPressStart,
                onLongPressMoveUpdate: _onMicLongPressMoveUpdate,
                onLongPressEnd: _onMicLongPressEnd,
              ),
      ],
    );
  }

  // ─── Recording bar ──────────────────────────────────────────────────────────

  Widget _buildRecordingBar() {
    final isSlidingNow = _isSlidingToCancel && _dragOffset > 0;
    final slideHintOpacity =
        (1.0 - (_dragOffset / _cancelThreshold)).clamp(0.0, 1.0);

    return Row(
      children: [
        // ❌ Cancel button
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _cancelRecording,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.12),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Pulsing mic + timer
        ScaleTransition(
          scale: _pulseAnimation,
          child: Icon(
            Icons.mic_rounded,
            color: isSlidingNow ? Colors.red : const Color(0xFF6C63FF),
            size: 20,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _formatDuration(_recordingSeconds),
          style: TextStyle(
            color: isSlidingNow ? Colors.redAccent : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),

        // Slide-to-cancel hint or "release to cancel" text
        Expanded(
          child: isSlidingNow
              ? const Center(
                  child: Text(
                    'حرر للإلغاء',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Opacity(
                    opacity: slideHintOpacity,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back_ios_rounded,
                            color: Colors.white38, size: 13),
                        SizedBox(width: 2),
                        Text(
                          'اسحب للإلغاء',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
        ),

        // Animated waveform
        _AnimatedWaveform(isActive: !isSlidingNow),
        const SizedBox(width: 8),

        // ✅ Send button
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _sendRecording,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                ),
              ),
              child:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      default:
        return 'application/octet-stream';
    }
  }
}

// ─── Send Button ────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── Mic Button ─────────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  final Animation<double> pulseAnimation;
  final void Function(LongPressStartDetails) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final void Function(LongPressEndDetails) onLongPressEnd;

  const _MicButton({
    required this.pulseAnimation,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd,
      child: ScaleTransition(
        scale: pulseAnimation,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// ─── Animated Waveform ───────────────────────────────────────────────────────

class _AnimatedWaveform extends StatefulWidget {
  final bool isActive;
  const _AnimatedWaveform({required this.isActive});

  @override
  State<_AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<_AnimatedWaveform>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  static const _barCount = 5;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _barCount,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + i * 80),
      )..repeat(reverse: true),
    );
    _animations = _controllers
        .map((c) => Tween<double>(begin: 4.0, end: 18.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (_, __) => Container(
              width: 3,
              height: widget.isActive ? _animations[i].value : 4,
              decoration: BoxDecoration(
                color:
                    widget.isActive ? const Color(0xFF6C63FF) : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onDownload;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF5B52E5)],
                )
              : null,
          color: isMe ? null : const Color(0xFF1E1E38),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.decryptedText ?? '🔒',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 4),
              _TimeAndStatus(message: message, isMe: isMe),
            ],
          ),
        );

      case MessageType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.localFilePath != null)
              GestureDetector(
                onTap: () => _openImage(context, message.localFilePath!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(message.localFilePath!),
                    width: 220,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              _MediaPlaceholder(
                icon: Icons.image_rounded,
                label: message.fileName ?? 'صورة',
                onDownload: onDownload,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 6),
              child: _TimeAndStatus(message: message, isMe: isMe),
            ),
          ],
        );

      case MessageType.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.localFilePath != null)
              _VideoThumbnail(path: message.localFilePath!)
            else
              _MediaPlaceholder(
                icon: Icons.videocam_rounded,
                label: message.fileName ?? 'فيديو',
                onDownload: onDownload,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 6),
              child: _TimeAndStatus(message: message, isMe: isMe),
            ),
          ],
        );

      case MessageType.file:
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.insert_drive_file_rounded,
                        color: Colors.white70, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.fileName ?? 'ملف',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (message.fileSize != null)
                          Text(
                            _formatFileSize(message.fileSize!),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (message.localFilePath != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded,
                          color: Colors.white70, size: 18),
                      onPressed: () => OpenFilex.open(message.localFilePath!),
                    )
                  else if (onDownload != null)
                    IconButton(
                      icon: const Icon(Icons.download_rounded,
                          color: Colors.white70, size: 18),
                      onPressed: onDownload,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _TimeAndStatus(message: message, isMe: isMe),
            ],
          ),
        );

      case MessageType.audio:
        return _AudioBubble(
          message: message,
          isMe: isMe,
          onDownload: onDownload,
        );
    }
  }

  void _openImage(BuildContext context, String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black),
          body: PhotoView(imageProvider: FileImage(File(path))),
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─── Audio Bubble ─────────────────────────────────────────────────────────────

class _AudioBubble extends ConsumerWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onDownload;

  const _AudioBubble({
    required this.message,
    required this.isMe,
    this.onDownload,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the singleton manager – rebuilds this widget whenever its state
    // changes (position tick, play/pause toggle, completion reset).
    final manager = ref.watch(audioPlaybackManagerProvider);

    final hasFile = message.localFilePath != null;
    final msgId = message.id;

    final isActive = manager.isActive(msgId);
    final isPlaying = manager.isPlayingMessage(msgId);

    // Use live position/total only for the active track; otherwise show saved
    // audioDuration so the duration label is always populated.
    final position = isActive ? manager.position : Duration.zero;
    final total = isActive && manager.total > Duration.zero
        ? manager.total
        : Duration(seconds: message.audioDuration ?? 0);

    final progress = total.inMilliseconds > 0
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final iconColor = isMe ? Colors.white : const Color(0xFF6C63FF);
    final trackColor = isMe ? Colors.white.withOpacity(0.3) : Colors.white24;
    final activeColor = isMe ? Colors.white : const Color(0xFF6C63FF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play / Pause / Download button
              SizedBox(
                width: 38,
                height: 38,
                child: Material(
                  color: isMe
                      ? Colors.white.withOpacity(0.15)
                      : const Color(0xFF6C63FF).withOpacity(0.15),
                  shape: const CircleBorder(),
                  child: !hasFile && onDownload != null
                      ? IconButton(
                          icon: Icon(Icons.download_rounded,
                              color: iconColor, size: 20),
                          onPressed: onDownload,
                          padding: EdgeInsets.zero,
                        )
                      : IconButton(
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: iconColor,
                            size: 22,
                          ),
                          onPressed: hasFile
                              ? () => manager.togglePlay(
                                    msgId,
                                    message.localFilePath!,
                                  )
                              : null,
                          padding: EdgeInsets.zero,
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // Progress bar + time label
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.toDouble(),
                        backgroundColor: trackColor,
                        valueColor: AlwaysStoppedAnimation(activeColor),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total > Duration.zero
                        ? '${_fmt(position)} / ${_fmt(total)}'
                        : '🎤 رسالة صوتية',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          _TimeAndStatus(message: message, isMe: isMe),
        ],
      ),
    );
  }
}

// ─── Shared sub-widgets ──────────────────────────────────────────────────────

class _TimeAndStatus extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _TimeAndStatus({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('HH:mm').format(message.timestamp),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 10,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          Icon(
            message.status == MessageStatus.read
                ? Icons.done_all_rounded
                : message.status == MessageStatus.delivered
                    ? Icons.done_all_rounded
                    : Icons.done_rounded,
            size: 14,
            color: message.status == MessageStatus.read
                ? const Color(0xFF4ADE80)
                : Colors.white38,
          ),
        ],
      ],
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onDownload;

  const _MediaPlaceholder(
      {required this.icon, required this.label, this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white38, size: 36),
          const SizedBox(height: 8),
          Text(label,
              style:
                  TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (onDownload != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('تنزيل', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  final String path;
  const _VideoThumbnail({required this.path});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _VideoPlayerScreen(path: path),
        ),
      ),
      child: Container(
        width: 220,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.play_circle_fill_rounded,
                color: Colors.white.withOpacity(0.8), size: 52),
            Positioned(
              bottom: 8,
              right: 10,
              child: Text('فيديو',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerScreen extends StatefulWidget {
  final String path;
  const _VideoPlayerScreen({required this.path});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: _controller.value.isInitialized
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.deepPurpleAccent,
                      bufferedColor: Colors.grey,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        }),
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  final String peerName;
  const _EmptyConversation({required this.peerName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6C63FF).withOpacity(0.1),
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Color(0xFF6C63FF),
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'محادثة مع $peerName',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'الرسائل مشفرة من طرف إلى طرف 🔒',
            style:
                TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
