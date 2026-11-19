import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';

void main() => runApp(const PortableAiApp());

enum AiMode { online, offline }

class ChatMessage {
  ChatMessage(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class PortableAiApp extends StatelessWidget {
  const PortableAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portable AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
          surface: const Color(0xFF111827),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const ChatScreen(),
      const ImageStudio(),
      const VideoStudio(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.image_outlined), selectedIcon: Icon(Icons.image), label: 'Bildstudio'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Videostudio'),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [
    ChatMessage('Hallo! Ich bin Portable AI. Nutze den Online-Modus mit einem KI-Anbieter oder die lokalen Basisfunktionen offline.', fromUser: false),
  ];
  AiMode _mode = AiMode.offline;
  bool _busy = false;
  String _baseUrl = 'https://api.openai.com/v1';
  String _model = 'gpt-4o-mini';
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _baseUrl = prefs.getString('baseUrl') ?? _baseUrl;
      _model = prefs.getString('model') ?? _model;
      _mode = prefs.getBool('onlineMode') == true ? AiMode.online : AiMode.offline;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', _baseUrl);
    await prefs.setString('model', _model);
    await prefs.setBool('onlineMode', _mode == AiMode.online);
  }

  Future<void> _openSettings() async {
    final url = TextEditingController(text: _baseUrl);
    final model = TextEditingController(text: _model);
    final key = TextEditingController(text: _apiKey);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Online-Einstellungen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Ein kompatibler Chat-Completions-Anbieter wird benötigt. API-Nutzung kann Kosten verursachen.'),
            const SizedBox(height: 14),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'API-Basisadresse')),
            const SizedBox(height: 10),
            TextField(controller: model, decoration: const InputDecoration(labelText: 'Modellname')),
            const SizedBox(height: 10),
            TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'API-Schlüssel')),
            const SizedBox(height: 8),
            const Text('Der Schlüssel bleibt in dieser App nur im Arbeitsspeicher und wird nicht dauerhaft gespeichert.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () async {
                setState(() {
                  _baseUrl = url.text.trim().replaceAll(RegExp(r'/+$'), '');
                  _model = model.text.trim();
                  _apiKey = key.text.trim();
                });
                await _saveSettings();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Speichern'),
            )),
          ]),
        ),
      ),
    );
    url.dispose(); model.dispose(); key.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() { _messages.add(ChatMessage(text, fromUser: true)); _busy = true; });
    _jumpToBottom();
    String answer;
    try {
      answer = _mode == AiMode.online ? await _askOnline(text) : _offlineReply(text);
    } catch (e) {
      answer = 'Online-Anfrage fehlgeschlagen: $e\nPrüfe Verbindung, API-Adresse, Modell und API-Schlüssel.';
    }
    if (!mounted) return;
    setState(() { _messages.add(ChatMessage(answer, fromUser: false)); _busy = false; });
    _jumpToBottom();
  }

  Future<String> _askOnline(String text) async {
    if (_apiKey.isEmpty) return 'Bitte öffne die Einstellungen und trage zuerst deinen API-Schlüssel ein.';
    final recent = _messages.length > 12 ? _messages.sublist(_messages.length - 12) : _messages;
    final history = recent.map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}).toList();
    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'},
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': 'Du bist Portable AI, ein hilfreicher Assistent. Antworte auf Deutsch, wenn der Nutzer Deutsch schreibt.'},
          ...history,
        ],
        'temperature': 0.7,
      }),
    ).timeout(const Duration(seconds: 60));
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = data is Map && data['error'] is Map ? (data['error']['message'] ?? response.body).toString() : response.body;
      throw Exception('HTTP ${response.statusCode}: $msg');
    }
    final content = data['choices']?[0]?['message']?['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    throw Exception('Keine lesbare Antwort vom Anbieter.');
  }

  String _offlineReply(String text) {
    final q = text.toLowerCase();
    if (q.contains('hallo') || q.contains('hi')) return 'Hallo! Schön, dass du Portable AI nutzt.';
    if (q.contains('datum') || q.contains('uhrzeit')) {
      final n = DateTime.now();
      return 'Auf deinem Gerät ist ${n.day}.${n.month}.${n.year}, ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')} Uhr.';
    }
    return 'Ich bin offline und habe noch kein lokales Sprachmodell geladen. Im Offline-Modus stehen derzeit einfache lokale Antworten bereit. Für ausführliche KI-Antworten aktiviere den Online-Modus.';
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() { _input.dispose(); _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final online = _mode == AiMode.online;
    return Column(children: [
      AppBar(
        title: const Row(children: [Icon(Icons.memory, color: Color(0xFF7DD3FC)), SizedBox(width: 9), Text('Portable AI', style: TextStyle(fontWeight: FontWeight.bold))]),
        actions: [
          PopupMenuButton<AiMode>(
            icon: Icon(online ? Icons.cloud_outlined : Icons.phone_android),
            onSelected: (m) async { setState(() => _mode = m); await _saveSettings(); },
            itemBuilder: (_) => const [PopupMenuItem(value: AiMode.online, child: Text('Online-Modus')), PopupMenuItem(value: AiMode.offline, child: Text('Offline-Modus'))],
          ),
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: online ? const Color(0xFF123047) : const Color(0xFF1E293B), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(online ? Icons.cloud_done_outlined : Icons.offline_bolt_outlined, size: 18),
          const SizedBox(width: 8), Expanded(child: Text(online ? 'Online · KI-Anbieter' : 'Offline · Basisfunktionen')),
          TextButton(onPressed: () async { setState(() => _mode = online ? AiMode.offline : AiMode.online); await _saveSettings(); }, child: Text(online ? 'Offline' : 'Online')),
        ]),
      ),
      Expanded(child: ListView.builder(
        controller: _scroll, padding: const EdgeInsets.all(16), itemCount: _messages.length + (_busy ? 1 : 0),
        itemBuilder: (context, i) {
          if (_busy && i == _messages.length) return const Padding(padding: EdgeInsets.all(12), child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Portable AI denkt nach...')]));
          final m = _messages[i];
          return Align(
            alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
              margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: m.fromUser ? const Color(0xFF075985) : const Color(0xFF1E293B), borderRadius: BorderRadius.circular(18)),
              child: SelectableText(m.text, style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          );
        },
      )),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 5, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Nachricht schreiben...', contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14)))),
          const SizedBox(width: 8),
          SizedBox(height: 52, width: 52, child: FilledButton(onPressed: _busy ? null : _send, style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder()), child: const Icon(Icons.send))),
        ]),
      ),
    ]);
  }
}

class ImageStudio extends StatefulWidget {
  const ImageStudio({super.key});
  @override
  State<ImageStudio> createState() => _ImageStudioState();
}

class _ImageStudioState extends State<ImageStudio> {
  final _picker = ImagePicker();
  final _prompt = TextEditingController();
  File? _original;
  File? _edited;
  bool _working = false;
  String _status = 'Wähle ein Foto oder beschreibe ein neues Bild.';
  // Configure a secure server endpoint that accepts multipart fields:
  // image (optional), prompt, and returns either { "image_url": "https://..." }
  // or { "image_base64": "..." }.
  String _imageServiceUrl = '';

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) return;
    setState(() {
      _original = File(picked.path);
      _edited = null;
      _status = 'Bild geladen. Beschreibe deine gewünschte Änderung oder nutze einen lokalen Effekt.';
    });
  }

  Future<void> _configureService() async {
    final controller = TextEditingController(text: _imageServiceUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bild-KI verbinden'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Eigene Server-Adresse',
            hintText: 'https://dein-server.example/api/image',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              setState(() => _imageServiceUrl = controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _applyLocalEffect(String effect) async {
    if (_original == null || _working) return;
    setState(() { _working = true; _status = 'Bild wird lokal bearbeitet...'; });
    try {
      final bytes = await _original!.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Bildformat konnte nicht gelesen werden.');
      final result = effect == 'Schwarz-Weiß' ? img.grayscale(decoded) : img.sepia(decoded);
      final out = File('${Directory.systemTemp.path}/portable_ai_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(result, quality: 92));
      if (!mounted) return;
      setState(() { _edited = out; _status = '$effect-Effekt angewendet.'; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Bearbeitung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _runImageAi() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _working) {
      setState(() => _status = 'Bitte beschreibe zuerst, welches Bild du erstellen oder wie du das Foto verändern möchtest.');
      return;
    }
    if (_imageServiceUrl.isEmpty) {
      setState(() => _status = 'Noch kein Bild-KI-Server verbunden. Tippe oben rechts auf das Server-Symbol und trage die Adresse deines sicheren Bild-KI-Backends ein.');
      return;
    }
    setState(() { _working = true; _status = 'Anfrage wird an deinen Bild-KI-Dienst gesendet...'; });
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_imageServiceUrl));
      request.fields['prompt'] = prompt;
      if (_original != null) {
        request.files.add(await http.MultipartFile.fromPath('image', _original!.path));
      }
      final streamed = await request.send().timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server antwortete mit HTTP ${response.statusCode}: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      File output;
      if (data['image_base64'] is String) {
        final raw = (data['image_base64'] as String).replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '');
        output = File('${Directory.systemTemp.path}/portable_ai_ai_${DateTime.now().millisecondsSinceEpoch}.png');
        await output.writeAsBytes(base64Decode(raw));
      } else if (data['image_url'] is String) {
        final imageResponse = await http.get(Uri.parse(data['image_url'] as String)).timeout(const Duration(minutes: 2));
        if (imageResponse.statusCode < 200 || imageResponse.statusCode >= 300) {
          throw Exception('Das Ergebnisbild konnte nicht geladen werden.');
        }
        output = File('${Directory.systemTemp.path}/portable_ai_ai_${DateTime.now().millisecondsSinceEpoch}.png');
        await output.writeAsBytes(imageResponse.bodyBytes);
      } else {
        throw Exception('Antwortformat nicht erkannt. Erwartet werden image_url oder image_base64.');
      }
      if (!mounted) return;
      setState(() { _edited = output; _status = 'KI-Ergebnis empfangen.'; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Bild-KI fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _edited ?? _original;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildstudio', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _configureService, icon: const Icon(Icons.cloud_outlined), tooltip: 'Bild-KI-Server einstellen'),
          IconButton(onPressed: _pickImage, icon: const Icon(Icons.add_photo_alternate_outlined), tooltip: 'Foto auswählen'),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Dein Foto. Deine Ideen.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Nutze lokale Effekte oder verbinde einen Bild-KI-Dienst für generative Bearbeitung.', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        if (shown != null)
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(shown, fit: BoxFit.contain, height: 300, errorBuilder: (_, __, ___) => const SizedBox(height: 180, child: Center(child: Text('Bild konnte nicht angezeigt werden.')))))
        else
          Container(height: 230, decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(18)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.auto_awesome, size: 58, color: Color(0xFF7DD3FC)), SizedBox(height: 12), Text('Bild auswählen oder neu beschreiben')])),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: _working ? null : _pickImage, icon: const Icon(Icons.photo_library_outlined), label: const Text('Foto aus Galerie auswählen')),
        const SizedBox(height: 14),
        TextField(
          controller: _prompt,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Was soll die KI machen?',
            hintText: 'Zum Beispiel: Verwandle das Foto in eine farbenfrohe Comic-Illustration...',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _working ? null : _runImageAi,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Mit Bild-KI bearbeiten / erstellen'),
        ),
        const SizedBox(height: 12),
        const Text('Lokale Effekte (funktionieren ohne Internet)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _working || _original == null ? null : () => _applyLocalEffect('Schwarz-Weiß'), child: const Text('Schwarz-Weiß'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: _working || _original == null ? null : () => _applyLocalEffect('Sepia'), child: const Text('Vintage / Sepia'))),
        ]),
        if (_edited != null)
          TextButton(onPressed: () => setState(() { _edited = null; _status = 'Originalbild wird angezeigt.'; }), child: const Text('Original anzeigen')),
        if (_working) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
        Text(_status, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        const Text('Die KI-Funktion benötigt einen eigenen Server, der Bildanfragen an einen Anbieter weiterleitet. Der API-Schlüssel gehört auf den Server und nicht in die APK. Ohne Server funktionieren die lokalen Effekte weiterhin.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}

class VideoStudio extends StatefulWidget {
  const VideoStudio({super.key});
  @override
  State<VideoStudio> createState() => _VideoStudioState();
}

class _VideoStudioState extends State<VideoStudio> {
  final _picker = ImagePicker();
  final _prompt = TextEditingController();
  VideoPlayerController? _controller;
  File? _sourceVideo;
  bool _working = false;
  String _status = 'Wähle einen Clip oder beschreibe eine Videoidee.';
  // Configure a secure backend that accepts multipart fields:
  // prompt, optional video; returns { "video_url": "https://..." }
  // or { "video_base64": "...", "mime_type": "video/mp4" }.
  String _videoServiceUrl = '';

  @override
  void dispose() {
    _prompt.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _configureService() async {
    final controller = TextEditingController(text: _videoServiceUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video-KI verbinden'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Eigene Server-Adresse',
            hintText: 'https://dein-server.example/api/video',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              setState(() => _videoServiceUrl = controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _controller?.dispose();
    _controller = null;
    _sourceVideo = File(picked.path);
    await _loadVideo(_sourceVideo!);
  }

  Future<void> _loadVideo(File file) async {
    final controller = VideoPlayerController.file(file);
    setState(() { _controller = controller; _status = 'Video wird geladen...'; });
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _status = 'Video bereit. Tippe auf Wiedergabe.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Video konnte nicht geöffnet werden: $e');
    }
  }

  Future<void> _generateOrEditVideo() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _working) {
      setState(() => _status = 'Bitte beschreibe zuerst deine Videoidee oder die gewünschte Änderung.');
      return;
    }
    if (_videoServiceUrl.isEmpty) {
      setState(() => _status = 'Noch kein Video-KI-Server verbunden. Tippe oben rechts auf das Server-Symbol und trage die Adresse deines sicheren Video-KI-Backends ein.');
      return;
    }
    setState(() { _working = true; _status = 'Videoanfrage wird gesendet. Je nach Anbieter kann das einige Minuten dauern...'; });
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_videoServiceUrl));
      request.fields['prompt'] = prompt;
      if (_sourceVideo != null) {
        request.files.add(await http.MultipartFile.fromPath('video', _sourceVideo!.path));
      }
      final streamed = await request.send().timeout(const Duration(minutes: 10));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server antwortete mit HTTP ${response.statusCode}: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      late final File generatedFile;
      if (data['video_base64'] is String) {
        final bytes = base64Decode(data['video_base64'] as String);
        final ext = (data['mime_type'] as String? ?? 'video/mp4').contains('webm') ? 'webm' : 'mp4';
        generatedFile = File('${Directory.systemTemp.path}/portable_ai_video_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await generatedFile.writeAsBytes(bytes);
      } else if (data['video_url'] is String) {
        final videoResponse = await http.get(Uri.parse(data['video_url'] as String)).timeout(const Duration(minutes: 5));
        if (videoResponse.statusCode < 200 || videoResponse.statusCode >= 300) {
          throw Exception('Das Ergebnisvideo konnte nicht geladen werden.');
        }
        generatedFile = File('${Directory.systemTemp.path}/portable_ai_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await generatedFile.writeAsBytes(videoResponse.bodyBytes);
      } else {
        throw Exception('Antwortformat nicht erkannt. Erwartet werden video_url oder video_base64.');
      }
      if (!mounted) return;
      await _controller?.dispose();
      await _loadVideo(generatedFile);
      if (mounted) setState(() => _status = 'KI-Video empfangen und geladen.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Video-KI fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videostudio', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _configureService, icon: const Icon(Icons.cloud_outlined), tooltip: 'Video-KI-Server einstellen')],
      ),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Bewegtbild. Neue Ideen.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Wähle einen Clip zur Vorschau oder verbinde einen Video-KI-Dienst für generative Bearbeitung.', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        if (c != null && c.value.isInitialized)
          ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
        else
          Container(height: 220, decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(18)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_library_outlined, size: 58, color: Color(0xFF7DD3FC)), SizedBox(height: 12), Text('Noch kein Video ausgewählt')])),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _working ? null : _pickVideo, icon: const Icon(Icons.video_library), label: const Text('Video aus Galerie auswählen')),
        if (c != null && c.value.isInitialized) ...[
          const SizedBox(height: 8),
          Row(children: [
            IconButton.filled(onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()), icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow)),
            const SizedBox(width: 10),
            Expanded(child: VideoProgressIndicator(c, allowScrubbing: true)),
          ]),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _prompt,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Was soll im Video passieren?',
            hintText: 'Zum Beispiel: Erzeuge einen kurzen animierten Clip mit einer futuristischen Stadt bei Nacht...',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _working ? null : _generateOrEditVideo,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Mit Video-KI erstellen / bearbeiten'),
        ),
        if (_working) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
        Text(_status, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        const Text('Die Video-KI-Schaltfläche benötigt einen eigenen Server, der Videoanfragen an einen Anbieter weiterleitet. Dieser Quellcode enthält keinen gehosteten Video-KI-Dienst. Die Galerie-Auswahl und Wiedergabe funktionieren unabhängig davon.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
