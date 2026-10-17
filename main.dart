import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const TranscoderApp());

class TranscoderApp extends StatelessWidget {
  const TranscoderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frictionless Transcoder',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(primary: Colors.tealAccent),
      ),
      home: const TranscoderScreen(),
    );
  }
}

class TranscoderScreen extends StatefulWidget {
  const TranscoderScreen({super.key});

  @override
  State<TranscoderScreen> createState() => _TranscoderScreenState();
}

class _TranscoderScreenState extends State<TranscoderScreen> {
  late StreamSubscription _intentSub;
  File? _inputFile;
  bool _isProcessing = false;
  String _statusMessage = "Ready";

  @override
  void initState() {
    super.initState();
    _setupShareIntent();
  }

  void _setupShareIntent() {
    _intentSub = ReceiveSharingIntent.getMediaStream().listen((value) {
      if (value.isNotEmpty) setState(() => _inputFile = File(value.first.path));
    });
    ReceiveSharingIntent.getInitialMedia().then((value) {
      if (value.isNotEmpty) setState(() => _inputFile = File(value.first.path));
    });
  }

  @override
  void dispose() {
    _intentSub.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.media);
    if (result != null) setState(() => _inputFile = File(result.files.single.path!));
  }

  Future<void> _processMedia(String preset) async {
    if (_inputFile == null) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = "Processing locally on device...";
    });

    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final time = DateTime.now().millisecondsSinceEpoch;
    String out = '';
    String cmd = '';

    if (preset == "compress") {
      out = '${dir.path}/compressed_$time.mp4';
      cmd = '-i "${_inputFile!.path}" -vcodec libx264 -crf 28 -preset fast -c:a aac -b:a 128k "$out"';
    } else if (preset == "gif") {
      out = '${dir.path}/animation_$time.gif';
      cmd = '-i "${_inputFile!.path}" -vf "fps=15,scale=480:-1:flags=lanczos" -loop 0 "$out"';
    } else if (preset == "audio") {
      out = '${dir.path}/extracted_$time.mp3';
      cmd = '-i "${_inputFile!.path}" -q:a 0 -map a "$out"';
    }

    await FFmpegKit.executeAsync(cmd, (session) async {
      final code = await session.getReturnCode();
      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(code)) {
          _statusMessage = "Done! Saved to:\n$out";
        } else {
          _statusMessage = "Failed. Try a different file.";
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convert Media'), backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _isProcessing ? null : _pickFile,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.tealAccent, width: 2),
                ),
                child: Center(
                  child: Text(
                    _inputFile == null ? 'Tap to select file\nor share from gallery' : 'Selected:\n${_inputFile!.path.split('/').last}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_isProcessing) ...[
              const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
              const SizedBox(height: 16),
              Text(_statusMessage, textAlign: TextAlign.center),
            ] else if (_inputFile != null) ...[
              ElevatedButton.icon(
                onPressed: () => _processMedia("compress"),
                icon: const Icon(Icons.compress),
                label: const Text('Compress for Sharing'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _processMedia("gif"),
                icon: const Icon(Icons.gif_box),
                label: const Text('Turn into GIF'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _processMedia("audio"),
                icon: const Icon(Icons.audio_file),
                label: const Text('Extract Audio (MP3)'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
              const SizedBox(height: 24),
              Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.tealAccent)),
            ]
          ],
        ),
      ),
    );
  }
}
