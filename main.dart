import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const TranscoderApp());

class TranscoderApp extends StatelessWidget {
  const TranscoderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro Media Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.teal,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const TranscoderScreen(),
    );
  }
}

class PresetItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String extension;
  final String Function(String input, String output) buildCommand;

  PresetItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.extension,
    required this.buildCommand,
  });
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
  String _statusMessage = "Select a media file to begin";
  String? _lastOutputPath;

  // All 99 Official Whisper AI Supported World Languages + Same-as-Audio option
  final Map<String, String> _worldLanguages = {
    "Same as Video Audio (No Translation)": "same",
    "English": "en",
    "Arabic (العربية)": "ar",
    "German (Deutsch)": "de",
    "French (Français)": "fr",
    "Spanish (Español)": "es",
    "Turkish (Türkçe)": "tr",
    "Russian (Русский)": "ru",
    "Chinese (中文)": "zh-CN",
    "Hindi (हिन्दी)": "hi",
    "Urdu (اردو)": "ur",
    "Portuguese (Português)": "pt",
    "Italian (Italiano)": "it",
    "Japanese (日本語)": "ja",
    "Korean (한국어)": "ko",
    "Dutch (Nederlands)": "nl",
    "Polish (Polski)": "pl",
    "Persian (فارسی)": "fa",
    "Indonesian (Bahasa Indonesia)": "id",
    "Vietnamese (Tiếng Việt)": "vi",
    "Thai (ไทย)": "th",
    "Ukrainian (Українська)": "uk",
    "Greek (Ελληνικά)": "el",
    "Swedish (Svenska)": "sv",
    "Czech (Čeština)": "cs",
    "Romanian (Română)": "ro",
    "Hungarian (Magyar)": "hu",
    "Danish (Dansk)": "da",
    "Finnish (Suomi)": "fi",
    "Norwegian (Norsk)": "no",
    "Hebrew (עברית)": "iw",
    "Malay (Bahasa Melayu)": "ms",
    "Tagalog / Filipino": "tl",
    "Swahili (Kiswahili)": "sw",
    "Bengali (বাংলা)": "bn",
    "Tamil (தமிழ்)": "ta",
    "Telugu (తెలుగు)": "te",
    "Punjabi (پنجابی)": "pa",
    "Marathi (मराठी)": "mr",
    "Gujarati (ગુજરાતી)": "gu",
    "Kannada (ಕನ್ನಡ)": "kn",
    "Malayalam (മലയാളം)": "ml",
    "Nepali (नेपाली)": "ne",
    "Sinhala (සිංහල)": "si",
    "Assamese (অসমীয়া)": "as",
    "Sindhi (سنڌي)": "sd",
    "Sanskrit (संस्कृतम्)": "sa",
    "Pashto (پښتو)": "ps",
    "Tajik (Тоҷикӣ)": "tg",
    "Turkmen (Türkmençe)": "tk",
    "Uzbek (Oʻzbek)": "uz",
    "Kazakh (Қазақ тілі)": "kk",
    "Tatar (Татарча)": "tt",
    "Bashkir (Башҡортса)": "ba",
    "Mongolian (Монгол)": "mn",
    "Tibetan (བོད་ཡིག)": "bo",
    "Myanmar / Burmese (မြန်မာ)": "my",
    "Khmer (ខ្មែរ)": "km",
    "Lao (ລາວ)": "lo",
    "Javanese (Basa Jawa)": "jw",
    "Sundanese (Basa Sunda)": "su",
    "Maori (Māori)": "mi",
    "Hawaiian (ʻŌlelo Hawaiʻi)": "haw",
    "Somali (Soomaali)": "so",
    "Amharic (አማርኛ)": "am",
    "Hausa": "ha",
    "Yoruba": "yo",
    "Shona (ChiShona)": "sn",
    "Lingala (Lingála)": "ln",
    "Malagasy": "mg",
    "Afrikaans": "af",
    "Albanian (Shqip)": "sq",
    "Armenian (Հայերեն)": "hy",
    "Azerbaijani (Azərbaycan)": "az",
    "Belarusian (Беларуская)": "be",
    "Bosnian (Bosanski)": "bs",
    "Bulgarian (Български)": "bg",
    "Catalan (Català)": "ca",
    "Croatian (Hrvatski)": "hr",
    "Estonian (Eesti)": "et",
    "Faroese (Føroyskt)": "fo",
    "Galician (Galego)": "gl",
    "Georgian (ქართული)": "ka",
    "Icelandic (Íslenska)": "is",
    "Latvian (Latviešu)": "lv",
    "Lithuanian (Lietuvių)": "lt",
    "Luxembourgish (Lëtzebuergesch)": "lb",
    "Macedonian (Македонски)": "mk",
    "Maltese (Malti)": "mt",
    "Serbian (Српски)": "sr",
    "Slovak (Slovenčina)": "sk",
    "Slovenian (Slovenščina)": "sl",
    "Welsh (Cymraeg)": "cy",
    "Breton (Brezhoneg)": "br",
    "Basque (Euskara)": "eu",
    "Occitan": "oc",
    "Latin (Latina)": "la",
    "Yiddish (ייִדיש)": "yi",
    "Haitian Creole (Kreyòl Ayisyen)": "ht",
    "Cantonese (粵語)": "yue",
  };

  final Map<String, List<PresetItem>> _categories = {
    "Resolution & Quality": [
      PresetItem(
        title: "4K Ultra HD",
        subtitle: "3840x2160 • High Bitrate MP4",
        icon: Icons.four_k_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -vf "scale=3840:-2" -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k "$o"',
      ),
      PresetItem(
        title: "1080p Full HD",
        subtitle: "1920x1080 • Crisp Standard HD",
        icon: Icons.hd_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -vf "scale=1920:-2" -c:v libx264 -preset fast -crf 21 -c:a aac -b:a 160k "$o"',
      ),
      PresetItem(
        title: "720p HD Ready",
        subtitle: "1280x720 • Balanced Size & Quality",
        icon: Icons.sd_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -vf "scale=1280:-2" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k "$o"',
      ),
      PresetItem(
        title: "Small Share Size",
        subtitle: "480p • Best for Discord & WhatsApp",
        icon: Icons.compress,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -vf "scale=854:-2" -c:v libx264 -preset veryfast -crf 28 -c:a aac -b:a 96k "$o"',
      ),
    ],
    "Speed, FPS & GIF": [
      PresetItem(
        title: "Smooth 60 FPS",
        subtitle: "Convert framerate to 60fps",
        icon: Icons.speed,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -r 60 -c:v libx264 -preset fast -crf 22 -c:a copy "$o"',
      ),
      PresetItem(
        title: "2x Fast Forward",
        subtitle: "Double video & audio speed",
        icon: Icons.fast_forward_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -filter_complex "[0:v]setpts=0.5*PTS[v];[0:a]atempo=2.0[a]" -map "[v]" -map "[a]" -c:v libx264 -preset fast "$o"',
      ),
      PresetItem(
        title: "0.5x Slow Motion",
        subtitle: "Half speed smooth playback",
        icon: Icons.slow_motion_video,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -filter_complex "[0:v]setpts=2.0*PTS[v];[0:a]atempo=0.5[a]" -map "[v]" -map "[a]" -c:v libx264 -preset fast "$o"',
      ),
      PresetItem(
        title: "High-Quality GIF",
        subtitle: "480px • 15 FPS Animated GIF",
        icon: Icons.gif_box_outlined,
        extension: "gif",
        buildCommand: (i, o) => '-y -i "$i" -vf "fps=15,scale=480:-1:flags=lanczos" "$o"',
      ),
    ],
    "Subtitles & Transcribe": [
      PresetItem(
        title: "AI Auto-Subtitles (Burn-In)",
        subtitle: "Transcribe speech & auto-translate into 99 languages",
        icon: Icons.auto_awesome,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "AI Auto-Transcribe (.SRT File Only)",
        subtitle: "Generate & translate .srt file in 99 languages",
        icon: Icons.description_outlined,
        extension: "srt",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "Burn External .SRT into Video",
        subtitle: "Pick an existing .srt file on your phone & burn it in",
        icon: Icons.closed_caption_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "Extract Embedded Subtitles",
        subtitle: "Extract existing soft subtitles (.srt)",
        icon: Icons.subtitles_outlined,
        extension: "srt",
        buildCommand: (i, o) => '-y -i "$i" -map 0:s:0 "$o"',
      ),
      PresetItem(
        title: "Extract WebVTT (.vtt)",
        subtitle: "WebVTT subtitle format export",
        icon: Icons.closed_caption_outlined,
        extension: "vtt",
        buildCommand: (i, o) => '-y -i "$i" -map 0:s:0 "$o"',
      ),
      PresetItem(
        title: "Strip Subtitles (Clean Video)",
        subtitle: "Remove subtitle tracks completely",
        icon: Icons.leak_remove_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -c:v copy -c:a copy -sn "$o"',
      ),
    ],
    "Audio & Formats": [
      PresetItem(
        title: "Extract MP3 Audio",
        subtitle: "320kbps High-Bitrate MP3",
        icon: Icons.audiotrack_outlined,
        extension: "mp3",
        buildCommand: (i, o) => '-y -i "$i" -vn -acodec libmp3lame -b:a 320k "$o"',
      ),
      PresetItem(
        title: "Extract WAV Audio",
        subtitle: "Uncompressed Lossless Audio",
        icon: Icons.graphic_eq,
        extension: "wav",
        buildCommand: (i, o) => '-y -i "$i" -vn "$o"',
      ),
      PresetItem(
        title: "Mute Video",
        subtitle: "Remove audio track completely",
        icon: Icons.volume_off_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -c:v copy -an "$o"',
      ),
      PresetItem(
        title: "Boost Volume 200%",
        subtitle: "Fix quiet audio in videos",
        icon: Icons.volume_up_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -vcodec copy -af "volume=2.0" "$o"',
      ),
      PresetItem(
        title: "Remux to MKV",
        subtitle: "Instant container swap (Lossless)",
        icon: Icons.video_file_outlined,
        extension: "mkv",
        buildCommand: (i, o) => '-y -i "$i" -c copy "$o"',
      ),
      PresetItem(
        title: "Remux to MOV",
        subtitle: "Apple QuickTime format",
        icon: Icons.movie_creation_outlined,
        extension: "mov",
        buildCommand: (i, o) => '-y -i "$i" -c copy "$o"',
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    FFmpegKitConfig.setFontDirectoryList(["/system/fonts", "/system/font"], {});
    _setupShareIntent();
  }

  void _setupShareIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        setState(() {
          _inputFile = File(value.first.path);
          _statusMessage = "Loaded from Share Menu";
        });
      }
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        setState(() {
          _inputFile = File(value.first.path);
          _statusMessage = "Loaded from Share Menu";
        });
      }
    });
  }

  @override
  void dispose() {
    _intentSub.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.media);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _inputFile = File(result.files.single.path!);
        _statusMessage = "Ready to transcode";
        _lastOutputPath = null;
      });
    }
  }

  Future<String> _getOutputFilePath(String presetTitle, String ext) async {
    final cleanTitle = presetTitle.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final downloadDir = Directory('/storage/emulated/0/Download');
    if (await downloadDir.exists()) {
      return '${downloadDir.path}/Transcoded_${cleanTitle}_$timestamp.$ext';
    }
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    return '${dir.path}/Transcoded_${cleanTitle}_$timestamp.$ext';
  }

  String _formatDurationToSrt(Duration d) {
    final String hrs = d.inHours.toString().padLeft(2, '0');
    final String mins = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    final String ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hrs:$mins:$secs,$ms';
  }

  // Free keyless translation helper so ANY spoken language can be translated into ANY subtitle language
  Future<String> _translateTextFree(String text, String targetLang) async {
    if (targetLang == "same" || text.trim().isEmpty) return text;
    try {
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$targetLang&dt=t&q=${Uri.encodeComponent(text)}',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List sentences = decoded[0];
        final StringBuffer translated = StringBuffer();
        for (final s in sentences) {
          if (s[0] != null) translated.write(s[0]);
        }
        return translated.toString().trim();
      }
    } catch (_) {}
    return text;
  }

  Future<String?> _showSearchableLanguageDialog() async {
    String searchQuery = "";

    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredEntries = _worldLanguages.entries
                .where((e) => e.key.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text("Select Target Subtitle Language", style: TextStyle(color: Colors.tealAccent)),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Search 99 languages...",
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Colors.tealAccent),
                        filled: true,
                        fillColor: const Color(0xFF121212),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (val) => setModalState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredEntries.length,
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          return ListTile(
                            title: Text(entry.key, style: const TextStyle(color: Colors.white)),
                            trailing: Text(entry.value.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            onTap: () => Navigator.pop(context, entry.value),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _burnExternalSrt() async {
    FilePickerResult? srtResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass'],
    );
    if (srtResult == null || srtResult.files.single.path == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Burning external subtitles into video...";
      _lastOutputPath = null;
    });

    final tempDir = await getTemporaryDirectory();
    final safeSrtFile = File('${tempDir.path}/clean_subs.srt');
    await File(srtResult.files.single.path!).copy(safeSrtFile.path);

    final outPath = await _getOutputFilePath("Burned_Subs", "mp4");
    final cmd = '-y -i "${_inputFile!.path}" -vf "subtitles=${safeSrtFile.path}:fontsdir=/system/fonts:force_style=\'FontSize=18,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2\'" -c:v libx264 -preset veryfast -crf 22 -c:a copy "$outPath"';

    await FFmpegKit.execute(cmd).then((session) async {
      final returnCode = await session.getReturnCode();
      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(returnCode)) {
          _statusMessage = "Success! Subtitled video saved to Downloads";
          _lastOutputPath = outPath;
        } else {
          _statusMessage = "Subtitle burn failed (Code: ${returnCode?.getValue()})";
        }
      });
    });
  }

  Future<void> _handleOfflineWhisperSubtitles({required bool burnIntoVideo}) async {
    final targetLangCode = await _showSearchableLanguageDialog();
    if (targetLangCode == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Step 1/4: Extracting 16kHz speech audio...";
      _lastOutputPath = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final tempWavPath = '${tempDir.path}/whisper_input.wav';
      final tempSrtPath = '${tempDir.path}/whisper_subs.srt';

      final wavCmd = '-y -i "${_inputFile!.path}" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$tempWavPath"';
      final wavSession = await FFmpegKit.execute(wavCmd);
      if (!ReturnCode.isSuccess(await wavSession.getReturnCode())) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Failed to prepare 16kHz WAV audio.";
        });
        return;
      }

      setState(() {
        _statusMessage = "Step 2/4: Transcribing true speech with Offline Whisper AI...";
      });

      final whisper = Whisper(
        model: WhisperModel.base,
        downloadHost: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
      );

      // CRITICAL FIX: Always use language: "auto" so Whisper accurately transcribes the actual spoken language in the video instead of hallucinating!
      final res = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: tempWavPath,
          language: "auto",
          isTranslate: false,
          isNoTimestamps: false,
          splitOnWord: false,
        ),
      );

      final segments = res.segments;
      final StringBuffer srtBuffer = StringBuffer();

      if (segments != null && segments.isNotEmpty) {
        setState(() {
          _statusMessage = targetLangCode == "same"
              ? "Step 3/4: Formatting subtitle timestamps..."
              : "Step 3/4: Translating ${segments.length} subtitle lines to ${targetLangCode.toUpperCase()}...";
        });

        for (int i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final originalText = seg.text.trim();
          if (originalText.isEmpty) continue;

          final finalLine = await _translateTextFree(originalText, targetLangCode);

          srtBuffer.writeln('${i + 1}');
          srtBuffer.writeln('${_formatDurationToSrt(seg.fromTs)} --> ${_formatDurationToSrt(seg.toTs)}');
          srtBuffer.writeln(finalLine);
          srtBuffer.writeln();
        }
      } else if (res.text.trim().isNotEmpty) {
        final finalLine = await _translateTextFree(res.text.trim(), targetLangCode);
        srtBuffer.writeln('1');
        srtBuffer.writeln('00:00:00,000 --> 00:05:00,000');
        srtBuffer.writeln(finalLine);
        srtBuffer.writeln();
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = "No speech detected in audio.";
        });
        return;
      }

      await File(tempSrtPath).writeAsString(srtBuffer.toString());

      if (!burnIntoVideo) {
        final outSrtPath = await _getOutputFilePath("Whisper_Subtitles_$targetLangCode", "srt");
        await File(tempSrtPath).copy(outSrtPath);
        setState(() {
          _isProcessing = false;
          _statusMessage = "Success! Accurate .SRT saved to Downloads";
          _lastOutputPath = outSrtPath;
        });
        return;
      }

      setState(() => _statusMessage = "Step 4/4: Burning Subtitles into Video...");
      final outVideoPath = await _getOutputFilePath("Subtitled_$targetLangCode", "mp4");

      final burnCmd = '-y -i "${_inputFile!.path}" -vf "subtitles=$tempSrtPath:fontsdir=/system/fonts:force_style=\'FontSize=18,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2\'" -c:v libx264 -preset veryfast -crf 22 -c:a copy "$outVideoPath"';

      final burnSession = await FFmpegKit.execute(burnCmd);
      final burnCode = await burnSession.getReturnCode();

      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(burnCode)) {
          _statusMessage = "Success! Burned Video saved to Downloads";
          _lastOutputPath = outVideoPath;
        } else {
          _statusMessage = "Subtitle burn failed (Code: ${burnCode?.getValue()})";
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Whisper Error: $e";
      });
    }
  }

  Future<void> _runPreset(PresetItem preset) async {
    if (_inputFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a video first!")),
      );
      return;
    }

    if (preset.title == "AI Auto-Subtitles (Burn-In)") {
      await _handleOfflineWhisperSubtitles(burnIntoVideo: true);
      return;
    }
    if (preset.title == "AI Auto-Transcribe (.SRT File Only)") {
      await _handleOfflineWhisperSubtitles(burnIntoVideo: false);
      return;
    }
    if (preset.title == "Burn External .SRT into Video") {
      await _burnExternalSrt();
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Running: ${preset.title}...";
      _lastOutputPath = null;
    });

    final outPath = await _getOutputFilePath(preset.title, preset.extension);
    final cmd = preset.buildCommand(_inputFile!.path, outPath);

    await FFmpegKit.execute(cmd).then((session) async {
      final returnCode = await session.getReturnCode();
      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(returnCode)) {
          _statusMessage = "Success! Saved to Downloads";
          _lastOutputPath = outPath;
        } else {
          _statusMessage = "Conversion failed (Code: ${returnCode?.getValue()})";
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _inputFile?.path.split('/').last ?? "Tap to Pick Media File";

    return DefaultTabController(
      length: _categories.keys.length,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF181818),
          elevation: 0,
          title: const Text("Pro Media Studio", style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.white60,
            tabs: _categories.keys.map((cat) => Tab(text: cat)).toList(),
          ),
        ),
        body: Column(
          children: [
            GestureDetector(
              onTap: _isProcessing ? null : _pickFile,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _inputFile != null ? Colors.tealAccent : Colors.white24,
                    width: 1.8,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.upload_file_outlined,
                      color: Colors.tealAccent,
                      size: 34,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _inputFile != null ? "Selected File:" : "No File Selected",
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fileName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isProcessing) ...[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Flexible(
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (_lastOutputPath != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _lastOutputPath!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: _categories.values.map((presets) {
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: presets.length,
                    itemBuilder: (context, index) {
                      final p = presets[index];
                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          enabled: !_isProcessing,
                          leading: CircleAvatar(
                            backgroundColor: Colors.tealAccent.withOpacity(0.12),
                            child: Icon(p.icon, color: Colors.tealAccent),
                          ),
                          title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(p.subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          trailing: const Icon(Icons.play_arrow_rounded, color: Colors.tealAccent),
                          onTap: () => _runPreset(p),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
