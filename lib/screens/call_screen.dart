import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

// ВСТАВЬ СВОЙ ID ТУТ
const String appId = "7b263560757645cda3219791aed6e579";

class CallScreen extends StatefulWidget {
  final String channelName;
  const CallScreen({super.key, required this.channelName});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int? _remoteUid;
  bool _localUserJoined = false;
  late RtcEngine _engine;

  @override
  void initState() {
    super.initState();
    initAgora();
  }

  Future<void> initAgora() async {
    // 1. Запрос разрешений
    await [Permission.microphone, Permission.camera].request();

    // 2. Создание движка
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    // 3. Обработка событий
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("Локальный пользователь зашел: ${connection.localUid}");
          setState(() => _localUserJoined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("Собеседник зашел: $remoteUid");
          setState(() => _remoteUid = remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("Собеседник вышел");
          setState(() => _remoteUid = null);
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          setState(() {
            _localUserJoined = false;
            _remoteUid = null;
          });
        },
      ),
    );

    // 4. Настройка видео
    await _engine.enableVideo();
    await _engine.startPreview();

    // 5. Вход в канал
    // ВАЖНО: Если в консоли Agora выбран "Testing Mode", то token оставляем null или ""
    await _engine.joinChannel(
      token: '',
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(),
    );
  }

  @override
  void dispose() {
    _disposeAgora();
    super.dispose();
  }

  Future<void> _disposeAgora() async {
    await _engine.leaveChannel();
    await _engine.release();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: _remoteVideo()),
          // Твое видео (превью)
          Positioned(
            right: 20,
            top: 50,
            child: SizedBox(
              width: 120,
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: _localUserJoined
                    ? AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                )
                    : Container(color: Colors.grey),
              ),
            ),
          ),
          _toolbar(),
        ],
      ),
    );
  }

  Widget _remoteVideo() {
    if (_remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.channelName),
        ),
      );
    } else {
      return const Text(
        'Ожидание психолога...',
        style: TextStyle(color: Colors.white, fontSize: 16),
      );
    }
  }

  Widget _toolbar() {
    return Container(
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RawMaterialButton(
            onPressed: () => Navigator.pop(context),
            shape: const CircleBorder(),
            fillColor: Colors.redAccent,
            padding: const EdgeInsets.all(15.0),
            child: const Icon(Icons.call_end, color: Colors.white, size: 35.0),
          ),
        ],
      ),
    );
  }
}