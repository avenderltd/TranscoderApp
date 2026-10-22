import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
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

class _DubSegment {
  int startMs;
  int endMs;
  String text;
  _DubSegment({required this.startMs, required this.endMs, required this.text});
}

class ChatMessage {
  final String sender; // "user" or "ai"
  final String text;
  final String? attachmentPath;
  ChatMessage({required this.sender, required this.text, this.attachmentPath});
}

class AiModelOption {
  final String id;
  final String friendlyName;
  final String technicalName;
  final String sizeLabel;
  final int minValidBytes;
  final String badgeText;
  final String whatItDoes;
  final String howItHelpsYou;
  final String downloadUrl;
  final String fileName;
  final int minCoresRecommended;

  AiModelOption({
    required this.id,
    required this.friendlyName,
    required this.technicalName,
    required this.sizeLabel,
    required this.minValidBytes,
    required this.badgeText,
    required this.whatItDoes,
    required this.howItHelpsYou,
    required this.downloadUrl,
    required this.fileName,
    required this.minCoresRecommended,
  });
}

class TranscoderScreen extends StatefulWidget {
  const TranscoderScreen({super.key});

  @override
  State<TranscoderScreen> createState() => _TranscoderScreenState();
}

class _TranscoderScreenState extends State<TranscoderScreen> {
  late StreamSubscription _intentSub;
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _chatScrollController = ScrollController();
  File? _inputFile;
  bool _isProcessing = false;
  String _statusMessage = "Analyzing hardware profile...";
  String _hardwareTierBadge = "Detecting specs...";
  String? _lastOutputPath;
  String _lastGeneratedTranscript = "";

  // Hardware Profiler Settings
  int _deviceCores = 4;
  int _optimalThreads = 4;
  String _optimalPreset = "superfast";
  String _recommendedModel = "Option 2 (1.5B) or Option 3 (3B)";

  // Local AI Chat & Model Downloader State
  final TextEditingController _chatController = TextEditingController();
  bool _webSearchEnabled = true;
  bool _isAiGenerating = false;
  File? _loadedGgufModel;
  String _activeAiModelTitle = "Option 2: DeepSeek-R1 Smart Logic & Coding (1.5B)";
  bool _isDownloadingModel = false;
  double _modelDownloadProgress = 0.0;
  String _downloadingModelName = "";
  File? _attachedVisionFile;

  final List<AiModelOption> _aiModelCatalog = [
    AiModelOption(
      id: "qwen_05b",
      friendlyName: "Option 1: Qwen Ultra-Fast Everyday AI (0.5B)",
      technicalName: "Qwen 2.5 (0.5B • Ultra-Light GGUF)",
      sizeLabel: "398 MB",
      minValidBytes: 350 * 1024 * 1024,
      badgeText: "⚡ Fastest • Works on ANY Android Phone",
      whatItDoes:
          "A super-lightweight AI brain that downloads quickly, uses almost zero battery, and replies fast in any language.",
      howItHelpsYou:
          "Perfect if you want quick answers, video title ideas, email writing, grammar fixes, or fast summaries of your video subtitles without slowing down your phone.",
      downloadUrl:
          "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
      fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
      minCoresRecommended: 2,
    ),
    AiModelOption(
      id: "deepseek_15b",
      friendlyName: "Option 2: DeepSeek-R1 Smart Logic & Coding (1.5B)",
      technicalName: "DeepSeek-R1 Distill Qwen (1.5B GGUF)",
      sizeLabel: "1.12 GB",
      minValidBytes: 950 * 1024 * 1024,
      badgeText: "⭐ #1 Best Balance for Modern Phones & Laptops",
      whatItDoes:
          "A reasoning AI that 'thinks step-by-step' before answering. It understands all world languages, programming, math, and complex questions deeply.",
      howItHelpsYou:
          "Best for writing and fixing code (Flutter, Python, FFmpeg), solving tough problems, analyzing long video transcripts, and answering in any language.",
      downloadUrl:
          "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
      fileName: "DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
      minCoresRecommended: 6,
    ),
    AiModelOption(
      id: "qwen_3b",
      friendlyName: "Option 3: Qwen Creator & Deep Analysis (3B)",
      technicalName: "Qwen 2.5 Instruct (3B • High-Intelligence GGUF)",
      sizeLabel: "1.93 GB",
      minValidBytes: 1700 * 1024 * 1024,
      badgeText: "🎨 Great for Flagship Phones (8GB+ RAM) & Laptops",
      whatItDoes:
          "Doubles the brain size for richer storytelling, multilingual translation nuances, advanced coding, and detailed media/photo inspection.",
      howItHelpsYou:
          "Ideal for content creators and developers who want full YouTube scripts, professional business emails, multi-language assistance, and deeper code architecture.",
      downloadUrl:
          "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf",
      fileName: "qwen2.5-3b-instruct-q4_k_m.gguf",
      minCoresRecommended: 7,
    ),
    AiModelOption(
      id: "deepseek_7b",
      friendlyName: "Option 4: DeepSeek-R1 Workstation Master (7B)",
      technicalName: "DeepSeek-R1 Distill Qwen (7B • Desktop Grade GGUF)",
      sizeLabel: "4.68 GB",
      minValidBytes: 4100 * 1024 * 1024,
      badgeText: "💻 Best for Laptops, PCs & 12GB+ RAM Ultra Devices",
      whatItDoes:
          "A massive desktop-class AI model that rivals paid cloud subscriptions while running privately on your own hardware.",
      howItHelpsYou:
          "Gives you maximum intelligence for full software engineering, complex legal/business document drafting, and deep research in any language.",
      downloadUrl:
          "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
      fileName: "DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
      minCoresRecommended: 8,
    ),
  ];

  final List<ChatMessage> _messages = [
    ChatMessage(
      sender: "ai",
      text:
          "Hello! مرحباً! Hallo! Bonjour! 👋\n\nAsk me anything in Arabic, English, German, French, or any language! When 'Google & Web' is ON, I can check live weather for any country/city, search the web, write code, or analyze media attached with 📷.",
    )
  ];

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
        title: "4K Ultra HD (Cinema Remaster)",
        subtitle: "Fast 3840x2160 • Hardware-Optimized Upscale & Stereo",
        icon: Icons.four_k_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -vf "scale=3840:-2:flags=bicubic,unsharp=3:3:1.2:3:3:0.0,eq=contrast=1.08:saturation=1.14:brightness=0.01" -c:v libx264 -preset superfast -threads 0 -crf 22 -maxrate 12M -bufsize 24M -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 192k -max_muxing_queue_size 9999 -movflags +faststart "$o"',
      ),
      PresetItem(
        title: "1080p Full HD (Crisp Remaster)",
        subtitle: "Fast 1920x1080 • Balanced Edge Sharpening & Stereo",
        icon: Icons.hd_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -vf "scale=1920:-2:flags=bicubic,unsharp=3:3:1.0:3:3:0.0,eq=contrast=1.06:saturation=1.10" -c:v libx264 -preset superfast -threads 0 -crf 21 -maxrate 6M -bufsize 12M -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 192k -max_muxing_queue_size 9999 -movflags +faststart "$o"',
      ),
      PresetItem(
        title: "720p HD Ready",
        subtitle: "1280x720 • Fast Encoding, Crisp Detail & Stereo Audio",
        icon: Icons.sd_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -vf "scale=1280:-2:flags=bicubic,unsharp=3:3:0.6:3:3:0.0" -c:v libx264 -preset superfast -threads 0 -crf 22 -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 160k -max_muxing_queue_size 9999 -movflags +faststart "$o"',
      ),
      PresetItem(
        title: "480p SD Compact",
        subtitle: "854x480 • Fast Mobile & Storage Saver",
        icon: Icons.compress,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -vf "scale=854:-2:flags=bicubic" -c:v libx264 -preset superfast -threads 0 -crf 23 -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 128k -max_muxing_queue_size 9999 -movflags +faststart "$o"',
      ),
      PresetItem(
        title: "Exact <10MB Fit (Discord/Email)",
        subtitle: "Guaranteed under 10MB with clear video & stereo audio",
        icon: Icons.fit_screen_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "Exact <16MB Fit (WhatsApp)",
        subtitle: "Guaranteed under 16MB with clear video & stereo audio",
        icon: Icons.send_to_mobile_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
    ],
    "Viral & Creator": [
      PresetItem(
        title: "Auto-Cut Dead Silence (Jump-Cut)",
        subtitle: "AI removes awkward pauses & silent gaps automatically",
        icon: Icons.content_cut_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "9:16 Viral Vertical (TikTok/Reels)",
        subtitle: "Converts horizontal video to 1080x1920 with blurred BG",
        icon: Icons.stay_current_portrait_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -filter_complex "[0:v:0]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:10[bg];[0:v:0]scale=1080:1920:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2[vout]" -map "[vout]" -map 0:a? -c:v libx264 -preset superfast -threads 0 -crf 21 -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 160k -max_muxing_queue_size 9999 "$o"',
      ),
      PresetItem(
        title: "Privacy Shield (Strip GPS & Data)",
        subtitle: "Instantly removes hidden GPS location & phone metadata",
        icon: Icons.shield_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '-y -i "$i" -map_metadata -1 -c:v copy -c:a aac -ac 2 -b:a 192k "$o"',
      ),
    ],
    "Subtitles & Dubbing": [
      PresetItem(
        title: "AI Auto-Dub Video (Voiceover)",
        subtitle: "100% Offline-First Continuous Dub • Male/Female • 15%/0% BG",
        icon: Icons.record_voice_over_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "AI Auto-Dub + Burn Subtitles",
        subtitle: "100% Offline-First Voiceover AND burned subtitles together",
        icon: Icons.spatial_audio_off_outlined,
        extension: "mp4",
        buildCommand: (i, o) => '',
      ),
      PresetItem(
        title: "AI Auto-Subtitles (Burn-In)",
        subtitle: "Transcribe speech & offline/auto-translate into 99 languages",
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
        buildCommand: (i, o) => '-y -i "$i" -c:v copy -c:a aac -ac 2 -b:a 192k -sn "$o"',
      ),
    ],
    "Speed, FPS & GIF": [
      PresetItem(
        title: "Smooth 60 FPS",
        subtitle: "Convert framerate to smooth 60fps",
        icon: Icons.speed,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -r 60 -c:v libx264 -preset superfast -threads 0 -crf 21 -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 160k "$o"',
      ),
      PresetItem(
        title: "2x Fast Forward",
        subtitle: "Double video & audio speed",
        icon: Icons.fast_forward_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -vf "setpts=0.5*PTS" -af "atempo=2.0,aresample=async=1" -c:v libx264 -preset superfast -threads 0 -crf 21 -pix_fmt yuv420p -c:a aac -ac 2 -ar 44100 -b:a 160k "$o"',
      ),
      PresetItem(
        title: "0.5x Slow Motion",
        subtitle: "Half speed smooth playback",
        icon: Icons.slow_motion_video,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -fflags +genpts -i "$i" -vf "setpts=2.0*PTS" -af "atempo=0.5,aresample=async=1" -c:v libx264 -preset superfast -threads 0 -crf 21 -pix_fmt yuv420p -c:a aac -ac 2 -ar 44100 -b:a 160k "$o"',
      ),
      PresetItem(
        title: "High-Quality GIF",
        subtitle: "480px • 15 FPS Animated GIF",
        icon: Icons.gif_box_outlined,
        extension: "gif",
        buildCommand: (i, o) => '-y -i "$i" -vf "fps=15,scale=480:-1:flags=lanczos" "$o"',
      ),
    ],
    "Audio & Formats": [
      PresetItem(
        title: "Studio Mic Enhancer (Denoise)",
        subtitle: "Remove background noise & boost vocal clarity",
        icon: Icons.mic_external_on_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -i "$i" -c:v copy -af "highpass=f=80,lowpass=f=12000,afftdn=nf=-25,acompressor=threshold=-18dB:ratio=3:attack=5:release=50,volume=1.4,aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 192k "$o"',
      ),
      PresetItem(
        title: "Karaoke Mode (Vocal Remover)",
        subtitle: "Cancel out center-panned vocals from music videos",
        icon: Icons.music_note_outlined,
        extension: "mp4",
        buildCommand: (i, o) =>
            '-y -i "$i" -c:v copy -af "stereotools=mlev=0.015625,aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 192k "$o"',
      ),
      PresetItem(
        title: "Extract MP3 Audio",
        subtitle: "320kbps High-Bitrate Stereo MP3",
        icon: Icons.audiotrack_outlined,
        extension: "mp3",
        buildCommand: (i, o) => '-y -i "$i" -vn -acodec libmp3lame -ac 2 -ar 44100 -b:a 320k "$o"',
      ),
      PresetItem(
        title: "Extract WAV Audio",
        subtitle: "Uncompressed Lossless Stereo Audio",
        icon: Icons.graphic_eq,
        extension: "wav",
        buildCommand: (i, o) => '-y -i "$i" -vn -ac 2 -ar 44100 "$o"',
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
        buildCommand: (i, o) =>
            '-y -i "$i" -c:v copy -af "volume=2.0,aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 192k "$o"',
      ),
      PresetItem(
        title: "Remux to MKV",
        subtitle: "Instant container swap (Lossless)",
        icon: Icons.video_file_outlined,
        extension: "mkv",
        buildCommand: (i, o) => '-y -i "$i" -c:v copy -c:a aac -ac 2 -b:a 192k "$o"',
      ),
      PresetItem(
        title: "Remux to MOV",
        subtitle: "Apple QuickTime format",
        icon: Icons.movie_creation_outlined,
        extension: "mov",
        buildCommand: (i, o) => '-y -i "$i" -c:v copy -c:a aac -ac 2 -b:a 192k "$o"',
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    FFmpegKitConfig.setFontDirectoryList(["/system/fonts", "/system/font"], {});
    _analyzeDeviceHardware();
    _checkAlreadyDownloadedModels();
    _setupShareIntent();
  }

  Future<void> _analyzeDeviceHardware() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final int cores = Platform.numberOfProcessors;
      _deviceCores = cores;

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        final bool isHighEnd = cores >= 7 && androidInfo.version.sdkInt >= 33;
        setState(() {
          _optimalThreads = isHighEnd ? 6 : 4;
          _optimalPreset = "superfast";
          _hardwareTierBadge = isHighEnd
              ? "Pro Mobile (${androidInfo.model} • $cores Cores)"
              : "Balanced Mobile (${androidInfo.model} • $cores Cores)";
          _recommendedModel = isHighEnd
              ? "Option 2 (1.5B) or Option 3 (3B)"
              : "Option 1 (0.5B) or Option 2 (1.5B)";
          _statusMessage = "Ready • Hardware Profile Active";
        });
      } else {
        setState(() {
          _optimalThreads = (cores > 4) ? cores - 2 : 4;
          _optimalPreset = "fast";
          _hardwareTierBadge = "Laptop / PC Studio ($cores Cores)";
          _recommendedModel = "Option 3 (3B) or Option 4 (7B Master)";
          _statusMessage = "Ready • Desktop Multi-Core Profile Active";
        });
      }
    } catch (_) {
      setState(() {
        _hardwareTierBadge = "Standard Profile";
        _statusMessage = "Ready to transcode";
      });
    }
  }

  Future<void> _checkAlreadyDownloadedModels() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final opt in _aiModelCatalog) {
        final f = File('${dir.path}/${opt.fileName}');
        if (await f.exists()) {
          final int len = await f.length();
          if (len >= opt.minValidBytes) {
            setState(() {
              _loadedGgufModel = f;
              _activeAiModelTitle = opt.friendlyName;
            });
            break;
          }
        }
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _cleanMarkdownFormatting(String raw) {
    return raw
        .replaceAll('**', '')
        .replaceAll('### ', '')
        .replaceAll('## ', '')
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>'), '')
        .trim();
  }

  String _decodeHtmlEntities(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _downloadAndActivateAiModel(AiModelOption option, StateSetter? modalSetState) async {
    if (_isDownloadingModel) return;

    setState(() {
      _isDownloadingModel = true;
      _modelDownloadProgress = 0.01;
      _downloadingModelName = option.friendlyName;
    });
    if (modalSetState != null) modalSetState(() {});

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveFile = File('${dir.path}/${option.fileName}');

      if (await saveFile.exists() && await saveFile.length() >= option.minValidBytes) {
        setState(() {
          _isDownloadingModel = false;
          _loadedGgufModel = saveFile;
          _activeAiModelTitle = option.friendlyName;
          _messages.add(ChatMessage(
            sender: "ai",
            text: "✅ Switched to ${option.friendlyName}!\n\nHow it helps you: ${option.howItHelpsYou}",
          ));
        });
        if (modalSetState != null) modalSetState(() {});
        _scrollToBottom();
        return;
      }

      int existingBytes = await saveFile.exists() ? await saveFile.length() : 0;
      int totalExpectedBytes = option.minValidBytes;

      for (int attempt = 0; attempt < 12; attempt++) {
        existingBytes = await saveFile.exists() ? await saveFile.length() : 0;
        if (existingBytes >= option.minValidBytes) break;

        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(option.downloadUrl));
          if (existingBytes > 0) {
            request.headers['Range'] = 'bytes=$existingBytes-';
          }

          final response = await client.send(request).timeout(const Duration(seconds: 25));
          if (response.statusCode == 200 && existingBytes > 0) {
            await saveFile.writeAsBytes([]);
            existingBytes = 0;
          }

          final int contentLen = response.contentLength ?? option.minValidBytes;
          totalExpectedBytes = existingBytes + contentLen;

          final IOSink sink = saveFile.openWrite(
            mode: existingBytes > 0 ? FileMode.append : FileMode.write,
          );

          await for (final chunk in response.stream.timeout(const Duration(seconds: 25))) {
            sink.add(chunk);
            existingBytes += chunk.length;
            final double prog = (existingBytes / totalExpectedBytes).clamp(0.01, 0.99);
            setState(() {
              _modelDownloadProgress = prog;
            });
            if (modalSetState != null) modalSetState(() {});
          }

          await sink.flush();
          await sink.close();
          client.close();

          if (existingBytes >= option.minValidBytes) {
            break;
          }
        } catch (_) {
          client.close();
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      final int finalBytes = await saveFile.exists() ? await saveFile.length() : 0;
      if (finalBytes >= option.minValidBytes) {
        setState(() {
          _isDownloadingModel = false;
          _modelDownloadProgress = 1.0;
          _loadedGgufModel = saveFile;
          _activeAiModelTitle = option.friendlyName;
          _messages.add(ChatMessage(
            sender: "ai",
            text:
                "🎉 Download 100% Complete! Activated ${option.friendlyName} (${(finalBytes / (1024 * 1024)).toStringAsFixed(0)} MB verified on storage).",
          ));
        });
      } else {
        setState(() {
          _isDownloadingModel = false;
          _messages.add(ChatMessage(
            sender: "ai",
            text:
                "⏸️ Download paused at ${(finalBytes / (1024 * 1024)).toStringAsFixed(0)} MB due to network drop. Tap 'Download Offline' again to resume right where it left off!",
          ));
        });
      }
      if (modalSetState != null) modalSetState(() {});
      _scrollToBottom();
    } catch (_) {
      setState(() {
        _isDownloadingModel = false;
        _messages.add(ChatMessage(
          sender: "ai",
          text: "⏸️ Network connection paused. Tap 'Download Offline' again to auto-resume.",
        ));
      });
      if (modalSetState != null) modalSetState(() {});
      _scrollToBottom();
    }
  }

  Future<void> _showAiModelRecommendationDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Choose Your Local AI Brain",
                    style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Device: $_hardwareTierBadge\nRecommended: $_recommendedModel",
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 460,
                child: Column(
                  children: [
                    if (_isDownloadingModel) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.tealAccent),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "Downloading $_downloadingModelName... ${(_modelDownloadProgress * 100).toStringAsFixed(1)}%",
                              style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "Auto-resume enabled • Safe to keep open",
                              style: TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _modelDownloadProgress,
                              color: Colors.tealAccent,
                              backgroundColor: Colors.white12,
                            ),
                          ],
                        ),
                      ),
                    ],
                    Expanded(
                      child: ListView.builder(
                        itemCount: _aiModelCatalog.length,
                        itemBuilder: (context, index) {
                          final opt = _aiModelCatalog[index];
                          final bool isBestForHardware = _deviceCores >= opt.minCoresRecommended;
                          final bool isCurrentlyActive = _activeAiModelTitle == opt.friendlyName;

                          return Card(
                            color: const Color(0xFF242424),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isCurrentlyActive
                                    ? Colors.tealAccent
                                    : (isBestForHardware ? Colors.teal.withOpacity(0.6) : Colors.white12),
                                width: isCurrentlyActive ? 2.0 : 1.0,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          opt.friendlyName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.tealAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          opt.sizeLabel,
                                          style: const TextStyle(
                                            color: Colors.tealAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${opt.badgeText} • ${opt.technicalName}",
                                    style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                                  ),
                                  const Divider(color: Colors.white12, height: 14),
                                  Text(
                                    "📖 What it is:\n${opt.whatItDoes}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "💡 How it helps you:\n${opt.howItHelpsYou}",
                                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() => _activeAiModelTitle = opt.friendlyName);
                                          Navigator.pop(context);
                                        },
                                        child: const Text(
                                          "Use Now",
                                          style: TextStyle(color: Colors.tealAccent, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal.shade700,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.download_rounded, size: 16),
                                        label: Text(
                                          isCurrentlyActive && _loadedGgufModel != null
                                              ? "Downloaded ✓"
                                              : "Download Offline",
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: _isDownloadingModel
                                            ? null
                                            : () => _downloadAndActivateAiModel(opt, setModalState),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.folder_open, color: Colors.tealAccent, size: 18),
                  label: const Text("Load .GGUF File", style: TextStyle(color: Colors.tealAccent)),
                  onPressed: () {
                    Navigator.pop(context);
                    _pickGgufModelFile();
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    );
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
    _chatController.dispose();
    _chatScrollController.dispose();
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

  Future<double> _getMediaDurationSeconds(String path, {double fallback = 0.0}) async {
    try {
      final infoSession = await FFprobeKit.getMediaInformation(path);
      final info = infoSession.getMediaInformation();
      final d = double.tryParse(info?.getDuration() ?? "");
      if (d != null && d > 0.05) return d;
    } catch (_) {}
    return fallback;
  }

  TranslateLanguage? _mapToMlKitLang(String code) {
    final String clean = code.split('-').first.toLowerCase();
    for (final lang in TranslateLanguage.values) {
      if (lang.bcpCode.toLowerCase() == clean) {
        return lang;
      }
    }
    if (clean == 'iw') return TranslateLanguage.hebrew;
    return null;
  }

  Future<Map<String, String>> _detectLanguageAndTranslateToEnglish(String text) async {
    try {
      final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': 'auto',
        'tl': 'en',
        'dt': 't',
        'q': text,
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
      }).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List sentences = decoded[0];
        final StringBuffer translated = StringBuffer();
        for (final s in sentences) {
          if (s[0] != null) translated.write(s[0]);
        }
        final String detectedLang = (decoded.length > 2 && decoded[2] != null) ? decoded[2].toString() : "en";
        return {
          'enText': translated.toString().trim(),
          'lang': detectedLang,
        };
      }
    } catch (_) {}
    return {'enText': text, 'lang': 'en'};
  }

  Future<List<String>> _translateBatchLines(List<String> lines, String targetLang) async {
    if (targetLang == "same" || lines.isEmpty) return lines;
    final List<String> results = List<String>.from(lines);

    final TranslateLanguage? targetMl = _mapToMlKitLang(targetLang);
    if (targetMl != null) {
      try {
        final modelManager = OnDeviceTranslatorModelManager();
        final bool isTargetDownloaded = await modelManager.isModelDownloaded(targetMl.bcpCode);
        if (!isTargetDownloaded) {
          setState(() {
            _statusMessage = "Downloading 30MB Offline ${targetLang.toUpperCase()} Dictionary (One-Time)...";
          });
          await modelManager.downloadModel(targetMl.bcpCode, isWifiRequired: false);
        }

        final onDeviceTranslator = OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.english,
          targetLanguage: targetMl,
        );

        bool allOfflineSucceeded = true;
        for (int i = 0; i < lines.length; i++) {
          final String translated = await onDeviceTranslator.translateText(lines[i]);
          if (translated.trim().isNotEmpty) {
            results[i] = translated.trim();
          } else {
            allOfflineSucceeded = false;
          }
        }
        await onDeviceTranslator.close();
        if (allOfflineSucceeded) return results;
      } catch (_) {}
    }

    const int batchSize = 12;
    for (int start = 0; start < lines.length; start += batchSize) {
      final int end = (start + batchSize < lines.length) ? start + batchSize : lines.length;
      final List<String> chunk = lines.sublist(start, end);
      final String joinedPayload = chunk.map((s) => s.replaceAll('\n', ' ').trim()).join('\n');

      bool translatedBatchOk = false;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
            'client': 'gtx',
            'sl': 'auto',
            'tl': targetLang,
            'dt': 't',
            'q': joinedPayload,
          });
          final response = await http.get(uri, headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
          }).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes));
            final List sentences = decoded[0];
            final StringBuffer fullTranslated = StringBuffer();
            for (final s in sentences) {
              if (s[0] != null) fullTranslated.write(s[0]);
            }
            final List<String> splitLines = fullTranslated.toString().split('\n');
            if (splitLines.length == chunk.length) {
              for (int j = 0; j < chunk.length; j++) {
                results[start + j] = splitLines[j].trim();
              }
              translatedBatchOk = true;
              break;
            }
          }
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }

      if (!translatedBatchOk) {
        for (int j = 0; j < chunk.length; j++) {
          results[start + j] = await _translateSingleLineWithRetry(chunk[j], targetLang);
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    return results;
  }

  Future<String> _translateSingleLineWithRetry(String text, String targetLang) async {
    if (targetLang == "same" || text.trim().isEmpty) return text;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
          'client': 'gtx',
          'sl': 'auto',
          'tl': targetLang,
          'dt': 't',
          'q': text,
        });
        final response = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
        }).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          final List sentences = decoded[0];
          final StringBuffer translated = StringBuffer();
          for (final s in sentences) {
            if (s[0] != null) translated.write(s[0]);
          }
          final res = translated.toString().trim();
          if (res.isNotEmpty) return res;
        }
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
    return text;
  }

  Future<bool> _generateVerifiedSpeechFile({
    required String text,
    required String langCode,
    required String voiceGender,
    required String outRawPath,
    required int segmentIndex,
  }) async {
    final String cleanLang = langCode == "same" ? "en" : langCode;

    try {
      final Completer<bool> ttsCompleter = Completer<bool>();
      _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) ttsCompleter.complete(true);
      });
      _flutterTts.setErrorHandler((msg) {
        if (!ttsCompleter.isCompleted) ttsCompleter.complete(false);
      });

      await _flutterTts.setLanguage(cleanLang);
      await _flutterTts.setPitch(voiceGender == "male" ? 0.82 : 1.04);
      await _flutterTts.setSpeechRate(0.5);

      await _flutterTts.synthesizeToFile(text, outRawPath);
      await ttsCompleter.future.timeout(const Duration(seconds: 7), onTimeout: () => false);

      await Future.delayed(const Duration(milliseconds: 120));
      if (await File(outRawPath).exists() && await File(outRawPath).length() > 350) {
        final double dur = await _getMediaDurationSeconds(outRawPath);
        if (dur > 0.12) return true;
      }
    } catch (_) {}

    final List<String> words = text.trim().split(RegExp(r'\s+'));
    final List<String> chunks = [];
    StringBuffer currentChunk = StringBuffer();

    for (final w in words) {
      if (currentChunk.length + w.length + 1 > 165) {
        if (currentChunk.isNotEmpty) chunks.add(currentChunk.toString().trim());
        currentChunk = StringBuffer(w);
      } else {
        if (currentChunk.isNotEmpty) currentChunk.write(' ');
        currentChunk.write(w);
      }
    }
    if (currentChunk.isNotEmpty) chunks.add(currentChunk.toString().trim());

    final List<String> clients = ['gtx', 'tw-ob', 'dict-chrome-ex'];
    final List<int> combinedMp3Bytes = [];
    bool allChunksDownloaded = true;

    for (int cIdx = 0; cIdx < chunks.length; cIdx++) {
      final String chunk = chunks[cIdx];
      if (chunk.isEmpty) continue;

      bool chunkOk = false;
      for (int attempt = 0; attempt < 3; attempt++) {
        final String clientParam = clients[(segmentIndex + attempt) % clients.length];
        try {
          await Future.delayed(Duration(milliseconds: 120 + (attempt * 180)));
          final Uri uri = Uri.https('translate.googleapis.com', '/translate_tts', {
            'ie': 'UTF-8',
            'client': clientParam,
            'tl': cleanLang,
            'q': chunk,
          });

          final response = await http.get(uri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          }).timeout(const Duration(seconds: 6));
          if (response.statusCode == 200 && response.bodyBytes.length > 250) {
            combinedMp3Bytes.addAll(response.bodyBytes);
            chunkOk = true;
            break;
          }
        } catch (_) {}
      }
      if (!chunkOk) {
        allChunksDownloaded = false;
        break;
      }
    }

    if (allChunksDownloaded && combinedMp3Bytes.length > 250) {
      await File(outRawPath).writeAsBytes(combinedMp3Bytes);
      final double dur = await _getMediaDurationSeconds(outRawPath);
      if (dur > 0.12) return true;
    }

    return false;
  }

  Future<void> _compressToExactTargetSizeMB(double targetMB) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Measuring duration for <${targetMB.toInt()}MB fit...";
      _lastOutputPath = null;
    });

    try {
      final double durationSec = (await _getMediaDurationSeconds(_inputFile!.path, fallback: 60.0)).clamp(1.0, 14400.0);
      final double safeTargetKilobits = targetMB * 8192.0 * 0.93;
      final int totalKbps = (safeTargetKilobits / durationSec).floor();
      final int audioKbps = totalKbps > 450 ? 128 : (totalKbps > 220 ? 96 : 64);
      final int videoKbps = (totalKbps - audioKbps).clamp(95, 8000);

      String targetWidth = "1280";
      if (videoKbps < 260) {
        targetWidth = "480";
      } else if (videoKbps < 520) {
        targetWidth = "640";
      } else if (videoKbps < 1050) {
        targetWidth = "854";
      }

      setState(() {
        _statusMessage = "Encoding at ${videoKbps}kbps (${targetWidth}p + Stereo) using $_optimalThreads threads...";
      });

      final outPath = await _getOutputFilePath("Fit_${targetMB.toInt()}MB", "mp4");
      final cmd =
          '-y -fflags +genpts -i "${_inputFile!.path}" -vf "scale=\'min($targetWidth,iw)\':-2:flags=bicubic" -c:v libx264 -preset $_optimalPreset -threads $_optimalThreads -b:v ${videoKbps}k -maxrate ${videoKbps}k -bufsize ${videoKbps * 2}k -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a ${audioKbps}k -max_muxing_queue_size 9999 -movflags +faststart "$outPath"';

      final session = await FFmpegKit.execute(cmd);
      final code = await session.getReturnCode();

      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(code)) {
          _statusMessage = "Success! <${targetMB.toInt()}MB video saved!";
          _lastOutputPath = outPath;
        } else {
          _statusMessage = "Target size compression failed (Code: ${code?.getValue()})";
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Size Fit Error: $e";
      });
    }
  }

  Future<void> _handleAutoCutSilence() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Step 1/3: Scanning speech timestamps with Offline Whisper AI...";
      _lastOutputPath = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final tempWavPath = '${tempDir.path}/whisper_jumpcut.wav';

      final wavCmd = '-y -i "${_inputFile!.path}" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$tempWavPath"';
      final wavSession = await FFmpegKit.execute(wavCmd);
      if (!ReturnCode.isSuccess(await wavSession.getReturnCode())) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Failed to extract audio for silence detection.";
        });
        return;
      }

      final whisper = Whisper(
        model: WhisperModel.base,
        downloadHost: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
      );

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
      if (segments == null || segments.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "No speech segments found to jump-cut.";
        });
        return;
      }

      setState(() {
        _statusMessage = "Step 2/3: Cutting silent pauses across ${segments.length} clips...";
      });

      final StringBuffer filterComplex = StringBuffer();
      final StringBuffer concatInputs = StringBuffer();
      int validCount = 0;

      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        if (seg.text.trim().isEmpty) continue;
        final double start = (seg.fromTs.inMilliseconds / 1000.0).clamp(0.0, 99999.0);
        final double end = (seg.toTs.inMilliseconds / 1000.0) + 0.12;
        if (end <= start) continue;

        filterComplex.write(
          '[0:v:0]trim=start=${start.toStringAsFixed(2)}:end=${end.toStringAsFixed(2)},setpts=PTS-STARTPTS[v$validCount];',
        );
        filterComplex.write(
          '[0:a:0]atrim=start=${start.toStringAsFixed(2)}:end=${end.toStringAsFixed(2)},asetpts=PTS-STARTPTS[a$validCount];',
        );
        concatInputs.write('[v$validCount][a$validCount]');
        validCount++;
      }

      if (validCount == 0) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "No valid dialogue segments found.";
        });
        return;
      }

      filterComplex.write('${concatInputs.toString()}concat=n=$validCount:v=1:a=1[outv][outa]');

      setState(() {
        _statusMessage = "Step 3/3: Stitching fast-paced Jump-Cut video...";
      });

      final outVideoPath = await _getOutputFilePath("JumpCut_NoSilence", "mp4");
      final cutCmd =
          '-y -i "${_inputFile!.path}" -filter_complex "${filterComplex.toString()}" -map "[outv]" -map "[outa]" -c:v libx264 -preset $_optimalPreset -threads $_optimalThreads -crf 21 -pix_fmt yuv420p -c:a aac -ac 2 -ar 44100 -b:a 160k "$outVideoPath"';

      final cutSession = await FFmpegKit.execute(cutCmd);
      final cutCode = await cutSession.getReturnCode();

      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(cutCode)) {
          _statusMessage = "Success! Jump-Cut video saved to Downloads";
          _lastOutputPath = outVideoPath;
        } else {
          _statusMessage = "Jump-Cut failed (Code: ${cutCode?.getValue()})";
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Jump-Cut Error: $e";
      });
    }
  }

  Future<String?> _showSearchableLanguageDialog({String title = "Select Target Language"}) async {
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
              title: Text(title, style: const TextStyle(color: Colors.tealAccent)),
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

  Future<Map<String, dynamic>?> _showDubbingOptionsDialog() async {
    String searchQuery = "";
    bool keepBackgroundAudio = true;
    String voiceGender = "female";

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredEntries = _worldLanguages.entries
                .where((e) => e.key.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text("AI Dubbing Studio Settings", style: TextStyle(color: Colors.tealAccent, fontSize: 18)),
              content: SizedBox(
                width: double.maxFinite,
                height: 490,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: SwitchListTile(
                        activeColor: Colors.tealAccent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        title: Text(
                          keepBackgroundAudio ? "Original Audio: 15%" : "Original Audio: Muted (0%)",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          keepBackgroundAudio
                              ? "Keeps faint background music & effects"
                              : "Completely mutes original video audio",
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        value: keepBackgroundAudio,
                        onChanged: (val) => setModalState(() => keepBackgroundAudio = val),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("👩 Natural Female"),
                            selected: voiceGender == "female",
                            selectedColor: Colors.tealAccent.withOpacity(0.25),
                            labelStyle: TextStyle(
                              color: voiceGender == "female" ? Colors.tealAccent : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            onSelected: (_) => setModalState(() => voiceGender = "female"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("👨 Natural Male"),
                            selected: voiceGender == "male",
                            selectedColor: Colors.tealAccent.withOpacity(0.25),
                            labelStyle: TextStyle(
                              color: voiceGender == "male" ? Colors.tealAccent : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            onSelected: (_) => setModalState(() => voiceGender = "male"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredEntries.length,
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          return ListTile(
                            title: Text(entry.key, style: const TextStyle(color: Colors.white)),
                            trailing: Text(entry.value.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            onTap: () => Navigator.pop(context, {
                              'lang': entry.value,
                              'keepBg': keepBackgroundAudio,
                              'gender': voiceGender,
                            }),
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
    final cmd =
        '-y -fflags +genpts -i "${_inputFile!.path}" -vf "subtitles=${safeSrtFile.path}:fontsdir=/system/fonts:force_style=\'FontSize=18,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2\'" -c:v libx264 -preset $_optimalPreset -threads $_optimalThreads -crf 22 -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 160k "$outPath"';

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

  Future<void> _handleAiAutoDubbing({required bool alsoBurnSubtitles}) async {
    final dubChoice = await _showDubbingOptionsDialog();
    if (dubChoice == null) return;

    final String targetLangCode = dubChoice['lang'];
    final bool keepBackgroundAudio = dubChoice['keepBg'];
    final String voiceGender = dubChoice['gender'] ?? "female";

    setState(() {
      _isProcessing = true;
      _statusMessage = "Step 1/5: Extracting speech audio for AI...";
      _lastOutputPath = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final tempWavPath = '${tempDir.path}/whisper_dub_input.wav';
      final tempSrtPath = '${tempDir.path}/whisper_dub_subs.srt';
      final masterDubWavPath = '${tempDir.path}/master_dub_track.wav';

      final wavCmd = '-y -i "${_inputFile!.path}" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$tempWavPath"';
      final wavSession = await FFmpegKit.execute(wavCmd);
      if (!ReturnCode.isSuccess(await wavSession.getReturnCode())) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Failed to extract audio from video.";
        });
        return;
      }

      setState(() {
        _statusMessage = "Step 2/5: Recognizing speech with Offline Whisper AI...";
      });

      final whisper = Whisper(
        model: WhisperModel.base,
        downloadHost: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
      );

      final res = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: tempWavPath,
          language: "auto",
          isTranslate: false,
          isNoTimestamps: false,
          splitOnWord: false,
        ),
      );

      final rawSegments = res.segments;
      if (rawSegments == null || rawSegments.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "No spoken dialogue detected to dub.";
        });
        return;
      }

      final List<_DubSegment> mergedSegments = [];
      for (final s in rawSegments) {
        final String clean = s.text.trim();
        if (clean.isEmpty) continue;
        final int sStart = s.fromTs.inMilliseconds;
        final int sEnd = s.toTs.inMilliseconds;

        if (mergedSegments.isNotEmpty) {
          final prev = mergedSegments.last;
          final int gap = sStart - prev.endMs;
          final int combinedDuration = sEnd - prev.startMs;
          if (gap <= 300 && combinedDuration <= 7500 && !prev.text.endsWith('.') && !prev.text.endsWith('?')) {
            prev.endMs = sEnd;
            prev.text = "${prev.text} $clean";
            continue;
          }
        }
        mergedSegments.add(_DubSegment(startMs: sStart, endMs: sEnd, text: clean));
      }

      final List<String> originalTexts = mergedSegments.map((s) => s.text).toList();

      setState(() {
        _statusMessage = "Step 3/5: Offline/Batch-translating ${mergedSegments.length} sentences...";
      });

      final List<String> translatedLines = await _translateBatchLines(originalTexts, targetLangCode);

      final StringBuffer srtBuffer = StringBuffer();
      final List<String> sequentialWavParts = [];
      int currentTimelineMs = 0;

      for (int i = 0; i < mergedSegments.length; i++) {
        final seg = mergedSegments[i];
        final String translatedLine = translatedLines[i].trim();
        if (translatedLine.isEmpty) continue;

        srtBuffer.writeln('${i + 1}');
        srtBuffer.writeln(
          '${_formatDurationToSrt(Duration(milliseconds: seg.startMs))} --> ${_formatDurationToSrt(Duration(milliseconds: seg.endMs))}',
        );
        srtBuffer.writeln(translatedLine);
        srtBuffer.writeln();

        setState(() {
          _statusMessage = "Step 4/5: Generating voice (${i + 1}/${mergedSegments.length}) on $_hardwareTierBadge...";
        });

        final rawTtsPath = '${tempDir.path}/tts_raw_$i.wav';
        final ok = await _generateVerifiedSpeechFile(
          text: translatedLine,
          langCode: targetLangCode,
          voiceGender: voiceGender,
          outRawPath: rawTtsPath,
          segmentIndex: i,
        );
        if (!ok || !await File(rawTtsPath).exists()) continue;

        final int segStartMs = seg.startMs;
        final int nextSegStartMs = (i + 1 < mergedSegments.length)
            ? mergedSegments[i + 1].startMs
            : seg.endMs + 4000;

        if (segStartMs > currentTimelineMs) {
          final double gapSec = (segStartMs - currentTimelineMs) / 1000.0;
          if (gapSec >= 0.04) {
            final gapWavPath = '${tempDir.path}/seq_gap_$i.wav';
            final gapSess = await FFmpegKit.execute(
              '-y -f lavfi -i anullsrc=r=24000:cl=mono -t ${gapSec.toStringAsFixed(3)} -ar 24000 -ac 1 -c:a pcm_s16le "$gapWavPath"',
            );
            if (ReturnCode.isSuccess(await gapSess.getReturnCode()) && await File(gapWavPath).exists()) {
              sequentialWavParts.add(gapWavPath);
              currentTimelineMs = segStartMs;
            }
          }
        }

        final double rawTtsSec = await _getMediaDurationSeconds(rawTtsPath, fallback: 2.2);
        final double naturalSlotSec = ((nextSegStartMs - segStartMs) / 1000.0).clamp(1.2, 25.0);
        final double remainingSlotSec = ((nextSegStartMs - currentTimelineMs) / 1000.0).clamp(1.0, 25.0);
        final double targetSlotSec = remainingSlotSec < naturalSlotSec * 0.6 ? naturalSlotSec * 0.75 : remainingSlotSec;

        final double pitchShift = voiceGender == "male" ? 0.86 : 1.03;
        final double pitchedDurationSec = rawTtsSec / pitchShift;

        double targetTempo = 1.06;
        if (pitchedDurationSec > targetSlotSec) {
          targetTempo = (pitchedDurationSec / targetSlotSec).clamp(1.06, 1.75);
        }

        final int pitchedRate = (24000 * pitchShift).round();
        final String filterChain =
            'aresample=24000,asetrate=$pitchedRate,aresample=24000,atempo=${targetTempo.toStringAsFixed(2)},volume=1.5';

        final segWavPath = '${tempDir.path}/seq_voice_$i.wav';
        final voiceSess = await FFmpegKit.execute(
          '-y -i "$rawTtsPath" -af "$filterChain" -ar 24000 -ac 1 -c:a pcm_s16le "$segWavPath"',
        );

        if (ReturnCode.isSuccess(await voiceSess.getReturnCode()) && await File(segWavPath).exists()) {
          final double actualSec = await _getMediaDurationSeconds(segWavPath, fallback: targetSlotSec);
          if (actualSec > 0.1) {
            sequentialWavParts.add(segWavPath);
            currentTimelineMs += (actualSec * 1000).round();
          }
        } else {
          final fallbackSess = await FFmpegKit.execute(
            '-y -i "$rawTtsPath" -ar 24000 -ac 1 -c:a pcm_s16le "$segWavPath"',
          );
          if (ReturnCode.isSuccess(await fallbackSess.getReturnCode()) && await File(segWavPath).exists()) {
            final double actualSec = await _getMediaDurationSeconds(segWavPath, fallback: rawTtsSec);
            if (actualSec > 0.1) {
              sequentialWavParts.add(segWavPath);
              currentTimelineMs += (actualSec * 1000).round();
            }
          }
        }

        if (await File(rawTtsPath).exists()) await File(rawTtsPath).delete();
      }

      if (sequentialWavParts.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Failed to generate dubbing audio clips.";
        });
        return;
      }

      _lastGeneratedTranscript = srtBuffer.toString();
      await File(tempSrtPath).writeAsString(_lastGeneratedTranscript);

      final concatListFile = File('${tempDir.path}/concat_list.txt');
      final StringBuffer concatText = StringBuffer();
      for (final wavPart in sequentialWavParts) {
        concatText.writeln("file '$wavPart'");
      }
      await concatListFile.writeAsString(concatText.toString());

      final concatSession = await FFmpegKit.execute(
        '-y -f concat -safe 0 -i "${concatListFile.path}" -ar 24000 -ac 1 -c:a pcm_s16le "$masterDubWavPath"',
      );

      for (final wavPart in sequentialWavParts) {
        final f = File(wavPart);
        if (await f.exists()) await f.delete();
      }

      if (!ReturnCode.isSuccess(await concatSession.getReturnCode())) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Failed to assemble master dubbing timeline.";
        });
        return;
      }

      setState(() {
        _statusMessage = keepBackgroundAudio
            ? "Step 5/5: Mixing video + ${voiceGender.toUpperCase()} voice (15% background)..."
            : "Step 5/5: Mixing video + pure ${voiceGender.toUpperCase()} voice (0% background)...";
      });

      final outVideoPath = await _getOutputFilePath(
        alsoBurnSubtitles ? "Dubbed_Subtitled_${voiceGender}_$targetLangCode" : "Dubbed_${voiceGender}_$targetLangCode",
        "mp4",
      );

      String videoMappingAndCodec;
      if (alsoBurnSubtitles) {
        videoMappingAndCodec =
            '-map 0:v:0 -vf "subtitles=$tempSrtPath:fontsdir=/system/fonts:force_style=\'FontSize=18,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2\'" -c:v libx264 -preset $_optimalPreset -threads $_optimalThreads -crf 22 -pix_fmt yuv420p';
      } else {
        videoMappingAndCodec = '-map 0:v:0 -c:v copy';
      }

      String dubCmd;
      if (keepBackgroundAudio) {
        dubCmd =
            '-y -fflags +genpts -i "${_inputFile!.path}" -i "$masterDubWavPath" -filter_complex "[0:a]aresample=async=1,volume=0.15[bg];[1:a]apad,volume=2.0[dub];[bg][dub]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[aout]" $videoMappingAndCodec -map "[aout]" -c:a aac -ac 2 -ar 44100 -b:a 192k "$outVideoPath"';
      } else {
        dubCmd =
            '-y -fflags +genpts -i "${_inputFile!.path}" -i "$masterDubWavPath" -filter_complex "[1:a]apad,volume=1.8[aout]" $videoMappingAndCodec -map "[aout]" -c:a aac -ac 2 -ar 44100 -b:a 192k -shortest "$outVideoPath"';
      }

      final dubSession = await FFmpegKit.execute(dubCmd);
      final dubCode = await dubSession.getReturnCode();

      setState(() {
        _isProcessing = false;
        if (ReturnCode.isSuccess(dubCode)) {
          _statusMessage = "Success! Offline-Ready Dubbed Video saved!";
          _lastOutputPath = outVideoPath;
        } else {
          _statusMessage = "Dubbing mix failed (Code: ${dubCode?.getValue()})";
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Dubbing Error: $e";
      });
    }
  }

  Future<void> _handleOfflineWhisperSubtitles({required bool burnIntoVideo}) async {
    final targetLangCode = await _showSearchableLanguageDialog(title: "Select Target Subtitle Language");
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

      final res = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: tempWavPath,
          language: "auto",
          isTranslate: false,
          isNoTimestamps: false,
          splitOnWord: false,
        ),
      );

      final rawSegments = res.segments;
      final StringBuffer srtBuffer = StringBuffer();

      if (rawSegments != null && rawSegments.isNotEmpty) {
        final validSegments = rawSegments.where((s) => s.text.trim().isNotEmpty).toList();
        final List<String> originalTexts = validSegments.map((s) => s.text.trim()).toList();

        setState(() {
          _statusMessage = targetLangCode == "same"
              ? "Step 3/4: Formatting subtitle timestamps..."
              : "Step 3/4: Offline/Batch-translating ${validSegments.length} lines...";
        });

        final List<String> translatedLines = await _translateBatchLines(originalTexts, targetLangCode);

        for (int i = 0; i < validSegments.length; i++) {
          final seg = validSegments[i];
          srtBuffer.writeln('${i + 1}');
          srtBuffer.writeln('${_formatDurationToSrt(seg.fromTs)} --> ${_formatDurationToSrt(seg.toTs)}');
          srtBuffer.writeln(translatedLines[i]);
          srtBuffer.writeln();
        }
      } else if (res.text.trim().isNotEmpty) {
        final finalLine = await _translateSingleLineWithRetry(res.text.trim(), targetLangCode);
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

      _lastGeneratedTranscript = srtBuffer.toString();
      await File(tempSrtPath).writeAsString(_lastGeneratedTranscript);

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

      final burnCmd =
          '-y -fflags +genpts -i "${_inputFile!.path}" -vf "subtitles=$tempSrtPath:fontsdir=/system/fonts:force_style=\'FontSize=18,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2\'" -c:v libx264 -preset $_optimalPreset -threads $_optimalThreads -crf 22 -pix_fmt yuv420p -af "aresample=async=1" -c:a aac -ac 2 -ar 44100 -b:a 160k "$outVideoPath"';

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

    if (preset.title == "Exact <10MB Fit (Discord/Email)") {
      await _compressToExactTargetSizeMB(10.0);
      return;
    }
    if (preset.title == "Exact <16MB Fit (WhatsApp)") {
      await _compressToExactTargetSizeMB(16.0);
      return;
    }
    if (preset.title == "Auto-Cut Dead Silence (Jump-Cut)") {
      await _handleAutoCutSilence();
      return;
    }
    if (preset.title == "AI Auto-Dub Video (Voiceover)") {
      await _handleAiAutoDubbing(alsoBurnSubtitles: false);
      return;
    }
    if (preset.title == "AI Auto-Dub + Burn Subtitles") {
      await _handleAiAutoDubbing(alsoBurnSubtitles: true);
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
      _statusMessage = "Running: ${preset.title} on $_hardwareTierBadge...";
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

  Future<void> _pickGgufModelFile() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res != null && res.files.single.path != null) {
      final f = File(res.files.single.path!);
      setState(() {
        _loadedGgufModel = f;
        _activeAiModelTitle = f.path.split('/').last;
        _messages.add(ChatMessage(
          sender: "ai",
          text:
              "✅ Loaded custom GGUF model: $_activeAiModelTitle\nConfigured with $_optimalThreads CPU threads for $_hardwareTierBadge.",
        ));
      });
      _scrollToBottom();
    }
  }

  Future<void> _pickVisionAttachment() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.media);
    if (res != null && res.files.single.path != null) {
      setState(() {
        _attachedVisionFile = File(res.files.single.path!);
      });
    }
  }

  // Country-to-Capital & Coordinates Smart Resolver (Prevents "Germany" from matching a tiny town in Ohio, USA!)
  Map<String, dynamic>? _resolveKnownCountryOrRegion(String locationQuery) {
    final String q = locationQuery.toLowerCase().trim();
    final Map<String, Map<String, dynamic>> knownCountries = {
      'germany': {'name': 'Germany (Berlin / Central)', 'lat': 51.51, 'lon': 7.46},
      'deutschland': {'name': 'Deutschland', 'lat': 51.51, 'lon': 7.46},
      'ألمانيا': {'name': 'ألمانيا (Germany)', 'lat': 51.51, 'lon': 7.46},
      'المانيا': {'name': 'ألمانيا (Germany)', 'lat': 51.51, 'lon': 7.46},
      'france': {'name': 'France (Paris)', 'lat': 48.85, 'lon': 2.35},
      'فرنسا': {'name': 'فرنسا (France)', 'lat': 48.85, 'lon': 2.35},
      'uk': {'name': 'United Kingdom (London)', 'lat': 51.50, 'lon': -0.12},
      'united kingdom': {'name': 'United Kingdom (London)', 'lat': 51.50, 'lon': -0.12},
      'england': {'name': 'England (London)', 'lat': 51.50, 'lon': -0.12},
      'بريطانيا': {'name': 'بريطانيا (UK)', 'lat': 51.50, 'lon': -0.12},
      'usa': {'name': 'United States (New York)', 'lat': 40.71, 'lon': -74.00},
      'united states': {'name': 'United States', 'lat': 40.71, 'lon': -74.00},
      'أمريكا': {'name': 'الولايات المتحدة (USA)', 'lat': 40.71, 'lon': -74.00},
      'turkey': {'name': 'Turkey (Istanbul)', 'lat': 41.00, 'lon': 28.97},
      'تركيا': {'name': 'تركيا (Turkey)', 'lat': 41.00, 'lon': 28.97},
      'spain': {'name': 'Spain (Madrid)', 'lat': 40.41, 'lon': -3.70},
      'إسبانيا': {'name': 'إسبانيا (Spain)', 'lat': 40.41, 'lon': -3.70},
      'italy': {'name': 'Italy (Rome)', 'lat': 41.90, 'lon': 12.49},
      'إيطاليا': {'name': 'إيطاليا (Italy)', 'lat': 41.90, 'lon': 12.49},
      'lebanon': {'name': 'Lebanon (Beirut)', 'lat': 33.89, 'lon': 35.50},
      'لبنان': {'name': 'لبنان ( بيروت )', 'lat': 33.89, 'lon': 35.50},
      'syria': {'name': 'Syria (Damascus)', 'lat': 33.51, 'lon': 36.29},
      'سوريا': {'name': 'سوريا (دمشق)', 'lat': 33.51, 'lon': 36.29},
      'egypt': {'name': 'Egypt (Cairo)', 'lat': 30.04, 'lon': 31.23},
      'مصر': {'name': 'مصر (القاهرة)', 'lat': 30.04, 'lon': 31.23},
      'saudi arabia': {'name': 'Saudi Arabia (Riyadh)', 'lat': 24.71, 'lon': 46.67},
      'السعودية': {'name': 'السعودية (الرياض)', 'lat': 24.71, 'lon': 46.67},
      'uae': {'name': 'UAE (Dubai)', 'lat': 25.20, 'lon': 55.27},
      'الإمارات': {'name': 'الإمارات (دبي)', 'lat': 25.20, 'lon': 55.27},
    };

    for (final entry in knownCountries.entries) {
      if (q == entry.key || q.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  // FIXED SMART WEATHER & WEB SEARCH AGGREGATOR:
  // 1. If it's a weather question, it ONLY fetches accurate weather (using highest-population city/country match so "Germany" never matches a village in Ohio!) and does NOT pollute with random Wikipedia articles!
  // 2. If it's a general web search, it fetches the top 3 cleanest snippets so the AI never chokes or dumps raw text!
  Future<Map<String, String>> _fetchSmartWebOrWeatherContext(
    String rawQuery,
    String englishQuery,
    String detectedLang,
  ) async {
    final String lowerEn = englishQuery.toLowerCase();
    final String lowerRaw = rawQuery.toLowerCase();

    final bool isWeatherQuery = lowerEn.contains("weather") ||
        lowerEn.contains("temperature") ||
        lowerEn.contains("forecast") ||
        lowerEn.contains("rain") ||
        lowerRaw.contains("طقس") ||
        lowerRaw.contains("الطقس") ||
        lowerRaw.contains("جو") ||
        lowerRaw.contains("حرارة") ||
        lowerRaw.contains("wetter") ||
        lowerRaw.contains("météo") ||
        lowerRaw.contains("clima") ||
        lowerRaw.contains("hava");

    if (isWeatherQuery) {
      String targetLocation = "";
      final RegExp inMatch = RegExp(r'\b(?:in|at|for|of)\s+([a-zA-Z\s]{2,25})', caseSensitive: false);
      final match = inMatch.firstMatch(englishQuery);
      if (match != null && match.group(1) != null) {
        targetLocation = match.group(1)!
            .replaceAll(RegExp(r'\b(today|now|tomorrow|right now|currently|please|the)\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
      }

      try {
        double lat = 51.61;
        double lon = 7.20;
        String resolvedPlaceName = targetLocation.isNotEmpty ? targetLocation : "Germany";

        // First check if the user named a known country (like Germany / ألمانيا) so it never picks a US town!
        final knownCountry = _resolveKnownCountryOrRegion(targetLocation.isNotEmpty ? targetLocation : rawQuery);
        if (knownCountry != null) {
          lat = knownCountry['lat'];
          lon = knownCountry['lon'];
          resolvedPlaceName = knownCountry['name'];
        } else if (targetLocation.isNotEmpty) {
          // Fetch top 10 matches and pick the one with the LARGEST population!
          final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
            'name': targetLocation,
            'count': '10',
            'language': detectedLang,
            'format': 'json',
          });
          final geoResp = await http.get(geoUri).timeout(const Duration(seconds: 4));
          if (geoResp.statusCode == 200) {
            final geoData = jsonDecode(utf8.decode(geoResp.bodyBytes));
            final List? results = geoData['results'];
            if (results != null && results.isNotEmpty) {
              Map<String, dynamic> bestMatch = results[0];
              int maxPop = (bestMatch['population'] as int?) ?? 0;
              for (final r in results) {
                final int pop = (r['population'] as int?) ?? 0;
                final String fCode = (r['feature_code'] ?? '').toString();
                if (fCode.startsWith('PPLC') || fCode.startsWith('PCLI') || pop > maxPop) {
                  bestMatch = r;
                  if (pop > maxPop) maxPop = pop;
                }
              }
              lat = (bestMatch['latitude'] as num).toDouble();
              lon = (bestMatch['longitude'] as num).toDouble();
              final String cName = bestMatch['name'] ?? targetLocation;
              final String country = bestMatch['country'] ?? "";
              resolvedPlaceName = country.isNotEmpty ? "$cName, $country" : cName;
            }
          }
        }

        final weatherUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m',
          'daily': 'temperature_2m_max,temperature_2m_min',
          'timezone': 'auto',
        });
        final wResp = await http.get(weatherUri).timeout(const Duration(seconds: 4));
        if (wResp.statusCode == 200) {
          final wData = jsonDecode(wResp.body);
          final cur = wData['current'];
          final daily = wData['daily'];
          if (cur != null) {
            final temp = cur['temperature_2m'];
            final feels = cur['apparent_temperature'];
            final hum = cur['relative_humidity_2m'];
            final wind = cur['wind_speed_10m'];
            final maxT = (daily?['temperature_2m_max'] as List?)?.first ?? temp;
            final minT = (daily?['temperature_2m_min'] as List?)?.first ?? temp;

            final String cleanWeatherSummaryEn =
                "🌤️ Live Weather in $resolvedPlaceName:\n"
                "• Current Temperature: ${temp}°C (Feels like ${feels}°C)\n"
                "• Today's High / Low: ${maxT}°C / ${minT}°C\n"
                "• Humidity: $hum% | Wind Speed: $wind km/h";

            return {
              'type': 'weather',
              'context': cleanWeatherSummaryEn,
            };
          }
        }
      } catch (_) {}
    }

    // GENERAL GOOGLE / DUCKDUCKGO / WIKI WEB SEARCH (Capped to top 3 concise results so AI never overflows!)
    final List<String> conciseSnippets = [];

    // 1. DuckDuckGo Web Search HTML Scraper (Top 2 results)
    try {
      final ddgHtmlUri = Uri.https('html.duckduckgo.com', '/html/', {'q': rawQuery});
      final resp = await http.get(ddgHtmlUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept-Language': '$detectedLang,en-US;q=0.9,en;q=0.8',
      }).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final htmlBody = utf8.decode(resp.bodyBytes);
        final RegExp snippetRegex = RegExp(r'<a class="result__snippet"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false);
        final matches = snippetRegex.allMatches(htmlBody);
        for (final m in matches) {
          if (conciseSnippets.length >= 2) break;
          final String cleanSnippet = _decodeHtmlEntities(m.group(1) ?? "");
          if (cleanSnippet.length > 25) {
            conciseSnippets.add("• $cleanSnippet");
          }
        }
      }
    } catch (_) {}

    // 2. Google News / Web Index RSS (Top 2 results)
    if (conciseSnippets.length < 3) {
      try {
        final String hl = (detectedLang.length == 2) ? detectedLang : 'en';
        final Uri googleRssUri = Uri.https('news.google.com', '/rss/search', {'q': rawQuery, 'hl': hl});
        final resp = await http.get(googleRssUri, headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
        }).timeout(const Duration(seconds: 3));

        if (resp.statusCode == 200) {
          final xmlBody = utf8.decode(resp.bodyBytes);
          final RegExp itemTitleRegex = RegExp(r'<item>[\s\S]*?<title>([\s\S]*?)<\/title>', caseSensitive: false);
          for (final m in itemTitleRegex.allMatches(xmlBody)) {
            if (conciseSnippets.length >= 3) break;
            final String cleanTitle = _decodeHtmlEntities(m.group(1) ?? "");
            if (cleanTitle.isNotEmpty) conciseSnippets.add("• $cleanTitle");
          }
        }
      } catch (_) {}
    }

    // 3. Wikipedia fallback if still under 3 snippets
    if (conciseSnippets.length < 2) {
      final String wikiLang = (detectedLang.length == 2) ? detectedLang : 'en';
      try {
        final uri = Uri.https('$wikiLang.wikipedia.org', '/w/api.php', {
          'action': 'query',
          'list': 'search',
          'srsearch': rawQuery,
          'utf8': '1',
          'format': 'json',
        });
        final resp = await http.get(uri).timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          final List searchResults = data['query']?['search'] ?? [];
          for (int i = 0; i < searchResults.length && conciseSnippets.length < 3; i++) {
            final title = searchResults[i]['title'];
            final snippet = _decodeHtmlEntities(searchResults[i]['snippet'].toString());
            conciseSnippets.add("• $title: $snippet");
          }
        }
      } catch (_) {}
    }

    String joined = conciseSnippets.join('\n');
    if (joined.length > 650) {
      joined = joined.substring(0, 650);
    }

    return {
      'type': 'web',
      'context': joined,
    };
  }

  Future<String> _generateIntelligentAiResponse({
    required String userPrompt,
    required String englishTranslation,
    required String detectedLang,
    required String contextType,
    required String webOrWeatherContext,
    required String visionInfo,
    required String ragTranscript,
  }) async {
    final String modelPersona = _activeAiModelTitle.toLowerCase().contains("deepseek") ? "DeepSeek-R1" : "Qwen-2.5";

    // FAST PATH FOR WEATHER: If the user asked for weather and we have the exact live weather card, translate it cleanly into their exact language right away!
    if (contextType == 'weather' && webOrWeatherContext.isNotEmpty) {
      if (detectedLang != 'en' && detectedLang != 'same') {
        final List<String> lines = webOrWeatherContext.split('\n');
        final List<String> translatedLines = await _translateBatchLines(lines, detectedLang);
        return translatedLines.join('\n');
      }
      return webOrWeatherContext;
    }

    final List<Map<String, String>> chatHistory = [];
    final String systemInstruction =
        "You are $modelPersona running on $_hardwareTierBadge. "
        "Reply in the EXACT SAME LANGUAGE as the user's message. "
        "Answer directly, naturally, and concisely without raw markdown asterisks (**)."
        "${visionInfo.isNotEmpty ? '\n$visionInfo' : ''}"
        "${ragTranscript.isNotEmpty ? '\n$ragTranscript' : ''}"
        "${webOrWeatherContext.isNotEmpty ? '\nReference facts:\n$webOrWeatherContext' : ''}";

    chatHistory.add({'role': 'system', 'content': systemInstruction});
    chatHistory.add({'role': 'user', 'content': userPrompt});

    final List<String> modelPriority = _webSearchEnabled
        ? ['openai', 'searchgpt', 'mistral']
        : ['openai', 'mistral'];

    for (final modelName in modelPriority) {
      try {
        final uri = Uri.parse('https://text.pollinations.ai/openai');
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': modelName,
                'messages': chatHistory,
                'temperature': 0.7,
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          final String? content = decoded['choices']?[0]?['message']?['content'];
          if (content != null && content.trim().isNotEmpty) {
            return _cleanMarkdownFormatting(content);
          }
        }
      } catch (_) {}
    }

    // Fallback 2: Short GET request (kept under 400 chars so URL never fails!)
    try {
      final String shortContext = webOrWeatherContext.length > 220
          ? webOrWeatherContext.substring(0, 220)
          : webOrWeatherContext;
      final String combinedPrompt =
          "Reply in the user's language ($detectedLang). ${shortContext.isNotEmpty ? 'Context: $shortContext. ' : ''}Question: $userPrompt";
      final uri = Uri.parse(
        'https://text.pollinations.ai/${Uri.encodeComponent(combinedPrompt)}?model=openai',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
        return _cleanMarkdownFormatting(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    // Clean Fallback if offline or server busy
    if (webOrWeatherContext.isNotEmpty) {
      return _cleanMarkdownFormatting(webOrWeatherContext);
    }

    String baseAnswerEn =
        "You are currently in Offline Mode. Connect to Wi-Fi or mobile data to search the web, or ask me about your video transcripts and coding!";
    if (detectedLang != 'en' && detectedLang != 'same') {
      return await _translateSingleLineWithRetry(baseAnswerEn, detectedLang);
    }
    return baseAnswerEn;
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty && _attachedVisionFile == null) return;
    if (_isAiGenerating) return;

    final File? currentAttachment = _attachedVisionFile;
    setState(() {
      _messages.add(ChatMessage(
        sender: "user",
        text: text.isEmpty ? "[Attached Media: ${currentAttachment!.path.split('/').last}]" : text,
        attachmentPath: currentAttachment?.path,
      ));
      _chatController.clear();
      _attachedVisionFile = null;
      _isAiGenerating = true;
    });
    _scrollToBottom();

    final langInfo = await _detectLanguageAndTranslateToEnglish(text);
    final String englishQuery = langInfo['enText'] ?? text;
    final String detectedLang = langInfo['lang'] ?? 'en';

    String contextType = "none";
    String webOrWeatherContext = "";
    if (_webSearchEnabled && text.isNotEmpty) {
      final resMap = await _fetchSmartWebOrWeatherContext(text, englishQuery, detectedLang);
      contextType = resMap['type'] ?? "none";
      webOrWeatherContext = resMap['context'] ?? "";
    }

    String visionAnalysis = "";
    if (currentAttachment != null) {
      final infoSess = await FFprobeKit.getMediaInformation(currentAttachment.path);
      final info = infoSess.getMediaInformation();
      final duration = info?.getDuration() ?? "Static Photo / Image";
      final sizeBytes = await currentAttachment.length();
      final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
      visionAnalysis =
          "[Attached Media File: ${currentAttachment.path.split('/').last} ($sizeMB MB, Duration: $duration)]";
    }

    String ragTranscriptContext = "";
    if (_lastGeneratedTranscript.isNotEmpty) {
      final preview = _lastGeneratedTranscript.length > 500
          ? "${_lastGeneratedTranscript.substring(0, 500)}..."
          : _lastGeneratedTranscript;
      ragTranscriptContext = "[Current Video Subtitle Transcript: $preview]";
    }

    final String aiReply = await _generateIntelligentAiResponse(
      userPrompt: text.isEmpty ? "Analyze this attached media file." : text,
      englishTranslation: englishQuery,
      detectedLang: detectedLang,
      contextType: contextType,
      webOrWeatherContext: webOrWeatherContext,
      visionInfo: visionAnalysis,
      ragTranscript: ragTranscriptContext,
    );

    setState(() {
      _messages.add(ChatMessage(sender: "ai", text: aiReply));
      _isAiGenerating = false;
    });
    _scrollToBottom();
  }

  Widget _buildMediaPickerHeader(String fileName) {
    return Column(
      children: [
        GestureDetector(
          onTap: _isProcessing ? null : _pickFile,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _inputFile != null ? Colors.tealAccent : Colors.white24,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.upload_file_outlined, color: Colors.tealAccent, size: 28),
                const SizedBox(height: 4),
                Text(
                  _inputFile != null ? "Selected File:" : "No File Selected",
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
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
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                if (_lastOutputPath != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    _lastOutputPath!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _inputFile?.path.split('/').last ?? "Tap to Pick Media File";

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF181818),
          elevation: 0,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pro Media Studio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.tealAccent, width: 0.8),
                  ),
                  child: Text(
                    _hardwareTierBadge,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: "Resolution & Quality"),
              Tab(text: "Viral & Creator"),
              Tab(text: "Subtitles & Dubbing"),
              Tab(text: "Speed, FPS & GIF"),
              Tab(text: "Audio & Formats"),
              Tab(text: "🤖 Local AI Chat"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tabs 1-5: Media Tool Tabs
            ..._categories.values.map((presets) {
              return Column(
                children: [
                  _buildMediaPickerHeader(fileName),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                    ),
                  ),
                ],
              );
            }),

            // Tab 6: FULL-SCREEN Multilingual AI Chat
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.psychology_outlined, color: Colors.tealAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _activeAiModelTitle,
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _showAiModelRecommendationDialog,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune, color: Colors.tealAccent, size: 14),
                                  SizedBox(width: 5),
                                  Text(
                                    "Switch AI Brain",
                                    style: TextStyle(
                                      color: Colors.tealAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              "Recommended: $_recommendedModel",
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.travel_explore, color: Colors.tealAccent, size: 15),
                              const SizedBox(width: 4),
                              const Text("Google & Web", style: TextStyle(color: Colors.white70, fontSize: 11)),
                              const SizedBox(width: 4),
                              SizedBox(
                                height: 26,
                                child: Switch(
                                  value: _webSearchEnabled,
                                  activeColor: Colors.tealAccent,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (val) => setState(() => _webSearchEnabled = val),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg.sender == "user";
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(13),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.82,
                          ),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.teal.shade800 : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isUser ? Colors.tealAccent : Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.attachmentPath != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.perm_media, color: Colors.tealAccent, size: 15),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          msg.attachmentPath!.split('/').last,
                                          style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              SelectableText(
                                msg.text,
                                style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.38),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_attachedVisionFile != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    color: Colors.teal.withOpacity(0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.image, color: Colors.tealAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Attached for Vision AI: ${_attachedVisionFile!.path.split('/').last}",
                            style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                          onPressed: () => setState(() => _attachedVisionFile = null),
                        ),
                      ],
                    ),
                  ),
                if (_isAiGenerating)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _webSearchEnabled
                              ? "Searching Google & Web + Thinking..."
                              : "AI is thinking locally...",
                          style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  color: const Color(0xFF181818),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: "Attach Photo or Video for Vision Analysis",
                        icon: const Icon(Icons.add_a_photo_outlined, color: Colors.tealAccent),
                        onPressed: _pickVisionAttachment,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: _webSearchEnabled
                                ? "Ask or search Google/Web in any language..."
                                : "Ask Offline AI in any language...",
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFF121212),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onSubmitted: (_) => _sendChatMessage(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.tealAccent),
                        onPressed: _sendChatMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
