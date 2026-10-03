import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';

class CallScreen extends StatefulWidget {
  final String slotId;
  final ApiClient apiClient;

  const CallScreen({
    super.key,
    required this.slotId,
    required this.apiClient,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isLoading = true;
  String? _errorMessage;
  String? _channelName;

  bool _isMuted = false;
  bool _isVideoDisabled = false;

  RtcEngine? _engine;

  final Color accentPurple = const Color(0xFF7862D6);
  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color warmWhite = const Color(0xFFF6F8FD);

  @override
  void initState() {
    super.initState();
    _startCallSession();
  }

  Future<void> _startCallSession() async {
    try {
      final statuses = await [Permission.microphone, Permission.camera].request();
      if (statuses[Permission.microphone] != PermissionStatus.granted ||
          statuses[Permission.camera] != PermissionStatus.granted) {
        if (mounted) {
          setState(() {
            _errorMessage = "Для совершения звонка необходим доступ к камере и микрофону";
            _isLoading = false;
          });
        }
        return;
      }

      final response = await widget.apiClient.dio.post('/calls/${widget.slotId}/join');

      final String fetchedAppId = response.data['appId'];
      final String token = response.data['token'];
      final int uid = response.data['uid'] ?? 0;
      _channelName = response.data['channelName'];

      await _initAgora(fetchedAppId, token, uid, _channelName!);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Ошибка подключения к сессии: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initAgora(String appId, String token, int uid, String channelName) async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (mounted) {
            setState(() {
              _localUserJoined = true;
              _isLoading = false;
            });
          }
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          if (mounted) {
            setState(() => _remoteUid = remoteUid);
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          if (mounted) {
            setState(() => _remoteUid = null);
          }
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          if (mounted) {
            setState(() {
              _localUserJoined = false;
              _remoteUid = null;
            });
          }
        },
      ),
    );

    await _engine!.enableVideo();
    await _engine!.startPreview();

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  void _onToggleMute() {
    if (_engine == null) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    _engine!.muteLocalAudioStream(_isMuted);
  }

  void _onToggleVideo() {
    if (_engine == null) return;
    setState(() {
      _isVideoDisabled = !_isVideoDisabled;
    });
    _engine!.muteLocalVideoStream(_isVideoDisabled);
  }

  void _onSwitchCamera() {
    _engine?.switchCamera();
  }

  void _onCallEnd() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _disposeAgora();
    super.dispose();
  }

  Future<void> _disposeAgora() async {
    if (_engine != null) {
      if (_localUserJoined) {
        await _engine!.leaveChannel();
      }
      await _engine!.release();
    }

    // Обязательное уведомление бэкенда о завершении участия
    try {
      await widget.apiClient.dio.post('/calls/${widget.slotId}/leave');
    } catch (e) {
      debugPrint('Ошибка при выходе из слота: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E1C2A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: accentPurple),
              const SizedBox(height: 20),
              Text(
                "Подключение к защищённой сессии...",
                style: TextStyle(color: warmWhite.withOpacity(0.8), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E1C2A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.redAccent.shade100),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: warmWhite, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                  child: Text("Вернуться", style: TextStyle(color: warmWhite, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF14131D),
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _buildRemoteVideo()),
            Positioned(
              right: 20,
              top: 20,
              child: _buildLocalVideoPreview(),
            ),
            Positioned(
              left: 20,
              top: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: warmWhite.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _remoteUid != null ? Colors.greenAccent : Colors.orangeAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _remoteUid != null ? "Консультация" : "Соединение...",
                      style: TextStyle(color: warmWhite, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildControlsToolbar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteVideo() {
    if (_remoteUid != null && _engine != null && _channelName != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine!,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: _channelName!),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: accentPurple.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.psychology, size: 64, color: deepPurple),
            ),
            const SizedBox(height: 24),
            Text(
              "Ожидание подключения психолога...",
              style: TextStyle(color: warmWhite, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Сессия начнётся автоматически, как только специалист войдет в комнату",
              style: TextStyle(color: warmWhite.withOpacity(0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildLocalVideoPreview() {
    return Container(
      width: 110,
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF2A283A),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: warmWhite.withOpacity(0.15), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _localUserJoined && !_isVideoDisabled && _engine != null
            ? AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: _engine!,
            canvas: const VideoCanvas(uid: 0),
          ),
        )
            : Center(
          child: Icon(
            _isVideoDisabled ? Icons.videocam_off : Icons.person,
            color: warmWhite.withOpacity(0.4),
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildControlsToolbar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 30, left: 24, right: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF232133).withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: warmWhite.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            isActive: !_isMuted,
            onPressed: _onToggleMute,
          ),
          _buildActionButton(
            icon: _isVideoDisabled ? Icons.videocam_off : Icons.videocam,
            isActive: !_isVideoDisabled,
            onPressed: _onToggleVideo,
          ),
          _buildActionButton(
            icon: Icons.cameraswitch,
            isActive: true,
            onPressed: _onSwitchCamera,
          ),
          _buildActionButton(
            icon: Icons.call_end,
            isEndCall: true,
            onPressed: _onCallEnd,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    bool isActive = true,
    bool isEndCall = false,
    required VoidCallback onPressed,
  }) {
    Color buttonBg = isEndCall
        ? Colors.redAccent
        : (isActive ? warmWhite.withOpacity(0.15) : Colors.redAccent.withOpacity(0.2));

    Color iconColor = isEndCall
        ? Colors.white
        : (isActive ? warmWhite : Colors.redAccent);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: buttonBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
    );
  }
}