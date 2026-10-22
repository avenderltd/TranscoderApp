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
  final int timestamp;

  ChatMessage({
    required this.sender,
    required this.text,
    this.attachmentPath,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'text': text,
        'attachmentPath': attachmentPath,
        'timestamp': timestamp,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        sender: json['sender'] ?? 'ai',
        text: json['text'] ?? '',
        attachmentPath: json['attachmentPath'],
        timestamp: json['timestamp'],
      );
}

class AiModelOption {
  final String id;
  final String tierCategory; // "Mobile", "Laptop / Gaming PC", "Workstation", "Supercomputer"
  final String friendlyName;
  final String technicalName;
  final String sizeLabel;
  final int minValidBytes;
  final String hardwareRequiredLabel;
  final String whatItDoes;
  final String howItHelpsYou;
  final String downloadUrl;
  final String fileName;
  final int minCoresRecommended;
  final int minRamGBRecommended;

  AiModelOption({
    required this.id,
    required this.tierCategory,
    required this.friendlyName,
    required this.technicalName,
    required this.sizeLabel,
    required this.minValidBytes,
    required this.hardwareRequiredLabel,
    required this.whatItDoes,
    required this.howItHelpsYou,
    required this.downloadUrl,
    required this.fileName,
    required this.minCoresRecommended,
    required this.minRamGBRecommended,
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
  int _estimatedRamGB = 8;
  int _optimalThreads = 4;
  String _optimalPreset = "superfast";
  String _recommendedModel = "Option 2 (1.5B) or Option 3 (3B)";

  // Local AI Chat, Permanent Memory & Voice Call State
  final TextEditingController _chatController = TextEditingController();
  bool _webSearchEnabled = true;
  bool _autoVoiceReplyEnabled = true;
  String _aiVoiceGender = "female";
  bool _isRecordingVoice = false;
  bool _isSpeakingNow = false;
  bool _isAiGenerating = false;

  File? _loadedGgufModel;
  String _activeAiModelTitle = "DeepSeek-R1 Smart Logic & Coding (1.5B)";
  bool _isDownloadingModel = false;
  double _modelDownloadProgress = 0.0;
  String _downloadingModelName = "";
  File? _attachedVisionFile;

  List<String> _permanentMemoryFacts = [];
  List<ChatMessage> _messages = [
    ChatMessage(
      sender: "ai",
      text:
          "Hello! مرحباً! Hallo! 👋\n\nI have Permanent Memory and Live Human Voice Chat (tap the Mic button to talk with your voice, and I will talk back!).\n\nTap 'All 12 AI Brains' above to browse all models—from 0.5B phone models up to 671B Supercomputer models!",
    )
  ];

  final List<AiModelOption> _aiModelCatalog = [
    AiModelOption(
      id: "qwen_05b",
      tierCategory: "📱 Mobile & Everyday",
      friendlyName: "1. Qwen 2.5 Ultra-Fast Everyday (0.5B)",
      technicalName: "Qwen2.5-0.5B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "398 MB",
      minValidBytes: 350 * 1024 * 1024,
      hardwareRequiredLabel: "✅ Runs on ANY Android Phone (2GB+ RAM)",
      whatItDoes: "An ultra-light AI brain that downloads in seconds and replies fast offline.",
      howItHelpsYou: "Best for quick everyday questions, grammar fixes, and short summaries.",
      downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
      fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
      minCoresRecommended: 2,
      minRamGBRecommended: 2,
    ),
    AiModelOption(
      id: "deepseek_15b",
      tierCategory: "📱 Mobile & Everyday",
      friendlyName: "2. DeepSeek-R1 Smart Logic & Coding (1.5B)",
      technicalName: "DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M GGUF)",
      sizeLabel: "1.12 GB",
      minValidBytes: 950 * 1024 * 1024,
      hardwareRequiredLabel: "⭐ Best Match for Modern Phones (6GB+ RAM)",
      whatItDoes: "A reasoning AI that thinks step-by-step. Understands coding, math, and all languages.",
      howItHelpsYou: "Ideal for writing Flutter/Python/FFmpeg code and solving logic problems.",
      downloadUrl: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
      fileName: "DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
      minCoresRecommended: 6,
      minRamGBRecommended: 6,
    ),
    AiModelOption(
      id: "qwen_3b",
      tierCategory: "📱 Flagship Phone & Laptop",
      friendlyName: "3. Qwen 2.5 Creator & Multilingual Pro (3B)",
      technicalName: "Qwen2.5-3B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "1.93 GB",
      minValidBytes: 1700 * 1024 * 1024,
      hardwareRequiredLabel: "⭐ Best for Flagship Phones (8GB+ RAM)",
      whatItDoes: "Enhanced parameters for multilingual translation and scriptwriting.",
      howItHelpsYou: "Great for writing YouTube scripts and analyzing media transcripts.",
      downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf",
      fileName: "qwen2.5-3b-instruct-q4_k_m.gguf",
      minCoresRecommended: 7,
      minRamGBRecommended: 8,
    ),
    AiModelOption(
      id: "llama_32_3b",
      tierCategory: "📱 Flagship Phone & Laptop",
      friendlyName: "4. Meta Llama 3.2 Conversational Pro (3B)",
      technicalName: "Llama-3.2-3B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "2.02 GB",
      minValidBytes: 1800 * 1024 * 1024,
      hardwareRequiredLabel: "⭐ Great for Flagship Phones & Laptops",
      whatItDoes: "Tuned for natural human dialogue and personal assistant tasks.",
      howItHelpsYou: "Feels like talking to a real person during voice chat.",
      downloadUrl: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
      fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
      minCoresRecommended: 7,
      minRamGBRecommended: 8,
    ),
    AiModelOption(
      id: "deepseek_7b",
      tierCategory: "💻 Gaming Laptop & PC",
      friendlyName: "5. DeepSeek-R1 Workstation Reasoning (7B)",
      technicalName: "DeepSeek-R1-Distill-Qwen-7B (Q4_K_M GGUF)",
      sizeLabel: "4.68 GB",
      minValidBytes: 4100 * 1024 * 1024,
      hardwareRequiredLabel: "💻 For Gaming Laptops (ASUS TUF / RTX)",
      whatItDoes: "A full 7B desktop-class reasoning brain.",
      howItHelpsYou: "Gives you software engineering and scientific reasoning.",
      downloadUrl: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
      fileName: "DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
      minCoresRecommended: 8,
      minRamGBRecommended: 12,
    ),
    AiModelOption(
      id: "qwen_coder_14b",
      tierCategory: "💻 Gaming Laptop & PC",
      friendlyName: "6. Qwen 2.5 Coder & Architect Master (14B)",
      technicalName: "Qwen2.5-Coder-14B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "8.99 GB",
      minValidBytes: 8000 * 1024 * 1024,
      hardwareRequiredLabel: "💻 Requires PC with 16GB+ RAM & GPU",
      whatItDoes: "World-class open-weights coding model across 92 languages.",
      howItHelpsYou: "Architects apps and debugs complex stack traces offline.",
      downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct-GGUF/resolve/main/qwen2.5-coder-14b-instruct-q4_k_m.gguf",
      fileName: "qwen2.5-coder-14b-instruct-q4_k_m.gguf",
      minCoresRecommended: 10,
      minRamGBRecommended: 16,
    ),
    AiModelOption(
      id: "mistral_small_24b",
      tierCategory: "🖥️ Pro Workstation",
      friendlyName: "7. Mistral Small 3 European Multilingual (24B)",
      technicalName: "Mistral-Small-24B-Instruct-2501 (Q4_K_M GGUF)",
      sizeLabel: "14.3 GB",
      minValidBytes: 13000 * 1024 * 1024,
      hardwareRequiredLabel: "🖥️ Requires Workstation (24GB+ RAM / RTX 3090)",
      whatItDoes: "European powerhouse with mastery of German, French, and English.",
      howItHelpsYou: "Delivers GPT-4o quality translations and legal/financial analysis.",
      downloadUrl: "https://huggingface.co/bartowski/Mistral-Small-24B-Instruct-2501-GGUF/resolve/main/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf",
      fileName: "Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf",
      minCoresRecommended: 12,
      minRamGBRecommended: 24,
    ),
    AiModelOption(
      id: "deepseek_32b",
      tierCategory: "🖥️ Pro Workstation",
      friendlyName: "8. DeepSeek-R1 Ultra Workstation (32B)",
      technicalName: "DeepSeek-R1-Distill-Qwen-32B (Q4_K_M GGUF)",
      sizeLabel: "19.8 GB",
      minValidBytes: 18000 * 1024 * 1024,
      hardwareRequiredLabel: "🖥️ Requires Workstation PC (32GB+ RAM)",
      whatItDoes: "Outperforms OpenAI o1-mini on math and advanced science.",
      howItHelpsYou: "Built for deep-tech founders and researchers.",
      downloadUrl: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf",
      fileName: "DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf",
      minCoresRecommended: 14,
      minRamGBRecommended: 32,
    ),
    AiModelOption(
      id: "llama_33_70b",
      tierCategory: "🖥️ Heavy Server / Workstation",
      friendlyName: "9. Meta Llama 3.3 Datacenter Flagship (70B)",
      technicalName: "Llama-3.3-70B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "42.5 GB",
      minValidBytes: 40000 * 1024 * 1024,
      hardwareRequiredLabel: "🖥️ Requires Dual-GPU Workstation / 64GB+ RAM",
      whatItDoes: "Datacenter flagship matching 400B+ models in evaluation.",
      howItHelpsYou: "Turns a 64GB+ workstation into a private corporate server.",
      downloadUrl: "https://huggingface.co/bartowski/Llama-3.3-70B-Instruct-GGUF/resolve/main/Llama-3.3-70B-Instruct-Q4_K_M.gguf",
      fileName: "Llama-3.3-70B-Instruct-Q4_K_M.gguf",
      minCoresRecommended: 16,
      minRamGBRecommended: 64,
    ),
    AiModelOption(
      id: "qwen_25_72b",
      tierCategory: "🖥️ Heavy Server / Workstation",
      friendlyName: "10. Qwen 2.5 Supreme Sovereign AI (72B)",
      technicalName: "Qwen2.5-72B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "47.4 GB",
      minValidBytes: 44000 * 1024 * 1024,
      hardwareRequiredLabel: "🖥️ Requires 64GB–128GB RAM Server",
      whatItDoes: "72B parameters of world knowledge with a 128K context window.",
      howItHelpsYou: "Reads entire books or long movie transcripts in a single prompt.",
      downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-72B-Instruct-GGUF/resolve/main/qwen2.5-72b-instruct-q4_k_m-00001-of-00012.gguf",
      fileName: "qwen2.5-72b-instruct-q4_k_m.gguf",
      minCoresRecommended: 16,
      minRamGBRecommended: 64,
    ),
    AiModelOption(
      id: "llama_31_405b",
      tierCategory: "🏢 Supercomputer (\$100k-\$500k)",
      friendlyName: "11. Meta Llama 3.1 Behemoth Supercomputer (405B)",
      technicalName: "Meta-Llama-3.1-405B-Instruct (Q4_K_M GGUF)",
      sizeLabel: "245 GB",
      minValidBytes: 230000 * 1024 * 1024,
      hardwareRequiredLabel: "🏢 Requires Multi-GPU Server (\$100k+ Rig)",
      whatItDoes: "Largest dense open-weights transformer ever trained.",
      howItHelpsYou: "Designed for government labs and research clusters.",
      downloadUrl: "https://huggingface.co/bartowski/Meta-Llama-3.1-405B-Instruct-GGUF",
      fileName: "Meta-Llama-3.1-405B-Instruct-Q4_K_M.gguf",
      minCoresRecommended: 32,
      minRamGBRecommended: 256,
    ),
    AiModelOption(
      id: "deepseek_r1_671b",
      tierCategory: "🏢 Supercomputer (\$500k+ Cluster)",
      friendlyName: "12. DeepSeek-R1 Full Uncensored Frontier MoE (671B)",
      technicalName: "DeepSeek-R1-671B-Full-MoE (Q4_K_M GGUF)",
      sizeLabel: "404 GB",
      minValidBytes: 380000 * 1024 * 1024,
      hardwareRequiredLabel: "🏢 Requires \$500,000+ NVIDIA H100 Cluster",
      whatItDoes: "The full un-distilled 671B DeepSeek-R1 Mixture-of-Experts brain.",
      howItHelpsYou: "Pinnacle of human-level scientific discovery and software engineering.",
      downloadUrl: "https://huggingface.co/unsloth/DeepSeek-R1-GGUF",
      fileName: "DeepSeek-R1-671B-Q4_K_M.gguf",
      minCoresRecommended: 64,
      minRamGBRecommended: 512,
    ),
  ];

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
    _loadPermanentMemoryFromDisk();
    _checkAlreadyDownloadedModels();
    _setupShareIntent();
  }

  Future<File> _getMemoryFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ai_permanent_memory_v1.json');
  }

  Future<void> _loadPermanentMemoryFromDisk() async {
    try {
      final file = await _getMemoryFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        final List? savedMsgs = data['messages'];
        final List? savedFacts = data['facts'];
        setState(() {
          if (savedMsgs != null && savedMsgs.isNotEmpty) {
            _messages = savedMsgs.map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))).toList();
          }
          if (savedFacts != null) {
            _permanentMemoryFacts = savedFacts.map((f) => f.toString()).toList();
          }
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _savePermanentMemoryToDisk() async {
    try {
      final file = await _getMemoryFile();
      final msgsToSave = _messages.length > 500 ? _messages.sublist(_messages.length - 500) : _messages;
      final payload = jsonEncode({
        'facts': _permanentMemoryFacts,
        'messages': msgsToSave.map((m) => m.toJson()).toList(),
      });
      await file.writeAsString(payload);
    } catch (_) {}
  }

  void _extractAndStorePermanentFact(String userText) {
    final String clean = userText.trim();
    if (clean.length < 4) return;
    final String lower = clean.toLowerCase();

    final bool isImportantFact = lower.contains("my name") ||
        lower.contains("i am ") ||
        lower.contains("i'm ") ||
        lower.contains("remember") ||
        lower.contains("don't forget") ||
        lower.contains("always ") ||
        lower.contains("never ") ||
        lower.contains("i live") ||
        lower.contains("my company") ||
        lower.contains("i like") ||
        lower.contains("اسمي") ||
        lower.contains("أنا ") ||
        lower.contains("انا ") ||
        lower.contains("تذكر") ||
        lower.contains("لا تنسى") ||
        lower.contains("دائما") ||
        lower.contains("أحب") ||
        lower.contains("شركتي") ||
        lower.contains("ich bin") ||
        lower.contains("ich heiße") ||
        lower.contains("merke dir");

    if (isImportantFact || clean.length > 25) {
      if (!_permanentMemoryFacts.contains(clean)) {
        _permanentMemoryFacts.add(clean);
        if (_permanentMemoryFacts.length > 80) {
          _permanentMemoryFacts.removeAt(0);
        }
      }
    }
  }

  Future<void> _speakAiResponseAloud(String text, String langCode) async {
    final String cleanSpeech = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), 'Code block generated.')
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .replaceAll(RegExp(r'[#*`_~>•]'), '')
        .trim();
    if (cleanSpeech.isEmpty) return;

    setState(() => _isSpeakingNow = true);
    try {
      final String ttsLang = (langCode == 'same' || langCode.isEmpty) ? 'en' : langCode;
      await _flutterTts.stop();
      await _flutterTts.setLanguage(ttsLang);
      await _flutterTts.setPitch(_aiVoiceGender == "male" ? 0.85 : 1.03);
      await _flutterTts.setSpeechRate(0.51);

      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeakingNow = false);
      });
      _flutterTts.setErrorHandler((_) {
        if (mounted) setState(() => _isSpeakingNow = false);
      });

      await _flutterTts.speak(cleanSpeech);
    } catch (_) {
      if (mounted) setState(() => _isSpeakingNow = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    if (mounted) setState(() => _isSpeakingNow = false);
  }

  Future<void> _toggleLiveVoiceRecording() async {
    if (_isSpeakingNow) {
      await _stopSpeaking();
    }

    if (_isRecordingVoice) {
      try {
        final String? recordedPath = await _voiceRecorder.stop();
        setState(() {
          _isRecordingVoice = false;
          _isAiGenerating = true;
        });

        if (recordedPath == null || !await File(recordedPath).exists()) {
          setState(() => _isAiGenerating = false);
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final wav16kPath = '${tempDir.path}/voice_chat_16k.wav';
        await FFmpegKit.execute('-y -i "$recordedPath" -ar 16000 -ac 1 -c:a pcm_s16le "$wav16kPath"');

        final whisper = Whisper(
          model: WhisperModel.base,
          downloadHost: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
        );

        final res = await whisper.transcribe(
          transcribeRequest: TranscribeRequest(
            audio: wav16kPath,
            language: "auto",
            isTranslate: false,
            isNoTimestamps: true,
            splitOnWord: false,
          ),
        );

        final String spokenText = res.text.trim();
        if (spokenText.isNotEmpty) {
          _chatController.text = spokenText;
          setState(() => _isAiGenerating = false);
          await _sendChatMessage(forceVoiceReply: true);
        } else {
          setState(() {
            _isAiGenerating = false;
            _messages.add(ChatMessage(
              sender: "ai",
              text: "🎙️ I didn't catch any speech in that recording. Tap the mic and speak clearly!",
            ));
          });
        }
      } catch (e) {
        setState(() {
          _isRecordingVoice = false;
          _isAiGenerating = false;
        });
      }
    } else {
      try {
        if (await _voiceRecorder.hasPermission()) {
          final tempDir = await getTemporaryDirectory();
          final recPath = '${tempDir.path}/live_voice_input.m4a';
          await _voiceRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
            path: recPath,
          );
          setState(() => _isRecordingVoice = true);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please grant Microphone permission to use Live Voice Chat!")),
            );
          }
        }
      } catch (e) {
        setState(() => _isRecordingVoice = false);
      }
    }
  }

  Future<void> _analyzeDeviceHardware() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final int cores = Platform.numberOfProcessors;
      _deviceCores = cores;

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        final bool isHighEnd = cores >= 7 && androidInfo.version.sdkInt >= 33;
        _estimatedRamGB = isHighEnd ? 12 : 6;
        setState(() {
          _optimalThreads = isHighEnd ? 6 : 4;
          _optimalPreset = "superfast";
          _hardwareTierBadge = isHighEnd
              ? "Pro Mobile (${androidInfo.model} • $cores Cores)"
              : "Balanced Mobile (${androidInfo.model} • $cores Cores)";
          _recommendedModel = isHighEnd ? "Models #1–#5 (Up to 7B)" : "Models #1–#3 (Up to 3B)";
          _statusMessage = "Ready • Hardware Profile Active";
        });
      } else {
        _estimatedRamGB = (cores >= 16) ? 64 : ((cores >= 8) ? 16 : 8);
        setState(() {
          _optimalThreads = (cores > 4) ? cores - 2 : 4;
          _optimalPreset = "fast";
          _hardwareTierBadge = "Laptop / PC Studio ($cores Cores)";
          _recommendedModel = "Models #1–#8 (Up to 32B+)";
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
        await _savePermanentMemoryToDisk();
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
                "⏸️ Download paused at ${(finalBytes / (1024 * 1024)).toStringAsFixed(0)} MB. Tap 'Download Offline' again to resume right where it left off!",
          ));
        });
      }
      await _savePermanentMemoryToDisk();
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
    String modelSearchQuery = "";
    bool showAllIncludingSupercomputer = true;
    List<Map<String, String>> liveHfResults = [];
    bool isSearchingHf = false;

    Future<void> searchHuggingFaceLive(String query, StateSetter setModalState) async {
      if (query.trim().isEmpty) return;
      setModalState(() => isSearchingHf = true);
      try {
        final uri = Uri.https('huggingface.co', '/api/models', {
          'search': '${query.trim()} gguf',
          'limit': '8',
          'sort': 'downloads',
          'direction': '-1',
        });
        final resp = await http.get(uri).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final List data = jsonDecode(utf8.decode(resp.bodyBytes));
          final List<Map<String, String>> parsed = [];
          for (final item in data) {
            final String modelId = (item['id'] ?? '').toString();
            final String downloads = (item['downloads'] ?? 0).toString();
            if (modelId.isNotEmpty) {
              parsed.add({
                'id': modelId,
                'downloads': downloads,
              });
            }
          }
          setModalState(() {
            liveHfResults = parsed;
            isSearchingHf = false;
          });
          return;
        }
      } catch (_) {}
      setModalState(() => isSearchingHf = false);
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredCatalog = _aiModelCatalog.where((opt) {
              final bool matchesSearch = modelSearchQuery.isEmpty ||
                  opt.friendlyName.toLowerCase().contains(modelSearchQuery.toLowerCase()) ||
                  opt.technicalName.toLowerCase().contains(modelSearchQuery.toLowerCase()) ||
                  opt.tierCategory.toLowerCase().contains(modelSearchQuery.toLowerCase()) ||
                  opt.whatItDoes.toLowerCase().contains(modelSearchQuery.toLowerCase());
              if (!matchesSearch) return false;
              if (!showAllIncludingSupercomputer) {
                return opt.minRamGBRecommended <= (_estimatedRamGB + 4);
              }
              return true;
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF161616),
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Global AI Brain Store (0.5B to 671B)",
                    style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Detected: $_hardwareTierBadge • $_recommendedModel",
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Search models (e.g. 70B, DeepSeek, Qwen, Llama)...",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Colors.tealAccent, size: 18),
                        suffixIcon: IconButton(
                          tooltip: "Search HuggingFace Hub",
                          icon: const Icon(Icons.cloud_queue, color: Colors.tealAccent, size: 18),
                          onPressed: () => searchHuggingFaceLive(modelSearchQuery, setModalState),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF121212),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (val) {
                        setModalState(() => modelSearchQuery = val);
                      },
                      onSubmitted: (val) => searchHuggingFaceLive(val, setModalState),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("🌍 All 12 Tiers (Up to 671B)"),
                            selected: showAllIncludingSupercomputer,
                            selectedColor: Colors.tealAccent.withOpacity(0.22),
                            labelStyle: TextStyle(
                              color: showAllIncludingSupercomputer ? Colors.tealAccent : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) => setModalState(() => showAllIncludingSupercomputer = true),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("⭐ Best for My Device"),
                            selected: !showAllIncludingSupercomputer,
                            selectedColor: Colors.tealAccent.withOpacity(0.22),
                            labelStyle: TextStyle(
                              color: !showAllIncludingSupercomputer ? Colors.tealAccent : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) => setModalState(() => showAllIncludingSupercomputer = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isDownloadingModel) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 10),
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
                            LinearProgressIndicator(
                              value: _modelDownloadProgress,
                              color: Colors.tealAccent,
                              backgroundColor: Colors.white12,
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isSearchingHf)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(color: Colors.tealAccent),
                      ),
                    if (liveHfResults.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "🌐 Live HuggingFace Hub GGUF Matches:",
                                  style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                InkWell(
                                  onTap: () => setModalState(() => liveHfResults = []),
                                  child: const Icon(Icons.close, size: 15, color: Colors.white70),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...liveHfResults.take(4).map((hf) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "• ${hf['id']} (${hf['downloads']} DLs)",
                                          style: const TextStyle(color: Colors.white, fontSize: 11),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          setState(() => _activeAiModelTitle = hf['id']!);
                                          Navigator.pop(context);
                                        },
                                        child: const Text("Activate", style: TextStyle(color: Colors.tealAccent, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ],
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredCatalog.length,
                        itemBuilder: (context, index) {
                          final opt = filteredCatalog[index];
                          final bool fitsThisDeviceEasily = opt.minRamGBRecommended <= (_estimatedRamGB + 4);
                          final bool isSupercomputerModel = opt.minRamGBRecommended >= 64;
                          final bool isCurrentlyActive = _activeAiModelTitle == opt.friendlyName;

                          return Card(
                            color: const Color(0xFF222222),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isCurrentlyActive
                                    ? Colors.tealAccent
                                    : (fitsThisDeviceEasily ? Colors.teal.withOpacity(0.5) : Colors.amber.withOpacity(0.4)),
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
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: fitsThisDeviceEasily
                                              ? Colors.tealAccent.withOpacity(0.15)
                                              : Colors.amber.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          opt.tierCategory,
                                          style: TextStyle(
                                            color: fitsThisDeviceEasily ? Colors.tealAccent : Colors.amberAccent,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        opt.sizeLabel,
                                        style: const TextStyle(
                                          color: Colors.tealAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    opt.friendlyName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    opt.hardwareRequiredLabel,
                                    style: TextStyle(
                                      color: fitsThisDeviceEasily ? Colors.tealAccent : Colors.amberAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                                          "Use Profile",
                                          style: TextStyle(color: Colors.tealAccent, fontSize: 11.5),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isSupercomputerModel && Platform.isAndroid)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            "🔒 Needs ${opt.minRamGBRecommended}GB+ Rig",
                                            style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                                          ),
                                        )
                                      else
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal.shade700,
                                            foregroundColor: Colors.white,
                                          ),
                                          icon: const Icon(Icons.download_rounded, size: 15),
                                          label: Text(
                                            isCurrentlyActive && _loadedGgufModel != null
                                                ? "Downloaded ✓"
                                                : "Download (${opt.sizeLabel})",
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
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
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18),
                  label: const Text("Clear Memory", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  onPressed: () async {
                    setState(() {
                      _permanentMemoryFacts.clear();
                      _messages = [
                        ChatMessage(sender: "ai", text: "Memory cleared! Ready for a fresh start.")
                      ];
                    });
                    await _savePermanentMemoryToDisk();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open, color: Colors.tealAccent, size: 18),
                  label: const Text("Load .GGUF", style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
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
    _voiceRecorder.dispose();
    _flutterTts.stop();
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
      await _savePermanentMemoryToDisk();
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
      'لبنان': {'name': 'لبنان (بيروت)', 'lat': 33.89, 'lon': 35.50},
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

  bool _isConversationalFollowUp(String text) {
    final String clean = text.trim().toLowerCase();
    if (clean.length <= 8) return true;
    final List<String> followUpStarters = [
      'نعم',
      'اه',
      'أيوة',
      'لا',
      'اقصد',
      'أقصد',
      'يعني',
      'yes',
      'yeah',
      'yep',
      'no',
      'i mean',
      'what about',
      'ja',
      'nein',
      'oui',
      'non',
    ];
    for (final w in followUpStarters) {
      if (clean == w || clean.startsWith('$w ')) return true;
    }
    return false;
  }

  String _extractCoreTopicForSearch(String query) {
    return query
        .replaceAll(
          RegExp(
            r'^(ما معنى|ما هو معنى|ما هو تعريف|ما هي|شو يعني|ايش يعني|أقصد|اقصد|تعريف كلمات|تعريف كلمة|معنى كلمة|معنى|what is the meaning of|what is a|what is|define|meaning of)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll('سترت', 'سترة')
        .replaceAll('البقلنسوة', 'بقلنسوة')
        .replaceAll('البقلنسوه', 'بقلنسوة')
        .replaceAll('بقلنسوه', 'بقلنسوة')
        .replaceAll('؟', '')
        .replaceAll('?', '')
        .trim();
  }

  Future<Map<String, String>> _fetchSmartBackgroundKnowledge(
    String rawQuery,
    String englishQuery,
    String detectedLang,
  ) async {
    if (_isConversationalFollowUp(rawQuery)) {
      return {'type': 'chat_only', 'context': ''};
    }

    final String lowerEn = englishQuery.toLowerCase();
    final String lowerRaw = rawQuery.toLowerCase();

    final bool isWeatherQuery = lowerEn.contains("weather") ||
        lowerEn.contains("temperature") ||
        lowerEn.contains("forecast") ||
        lowerRaw.contains("طقس") ||
        lowerRaw.contains("الطقس") ||
        lowerRaw.contains("درجة الحرارة") ||
        lowerRaw.contains("wetter") ||
        lowerRaw.contains("météo");

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

        final knownCountry = _resolveKnownCountryOrRegion(targetLocation.isNotEmpty ? targetLocation : rawQuery);
        if (knownCountry != null) {
          lat = knownCountry['lat'];
          lon = knownCountry['lon'];
          resolvedPlaceName = knownCountry['name'];
        } else if (targetLocation.isNotEmpty) {
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

            return {
              'type': 'weather',
              'context':
                  "Live Weather in $resolvedPlaceName: Current Temperature ${temp}°C (Feels like ${feels}°C), High ${maxT}°C / Low ${minT}°C, Humidity $hum%, Wind $wind km/h.",
            };
          }
        }
      } catch (_) {}
    }

    final String coreNativeTopic = _extractCoreTopicForSearch(rawQuery);
    final langTopicInfo = await _detectLanguageAndTranslateToEnglish(coreNativeTopic);
    final String coreEnglishTopic = _extractCoreTopicForSearch(langTopicInfo['enText'] ?? englishQuery);

    final List<String> knowledgeFacts = [];
    final String wikiLang = (detectedLang.length == 2) ? detectedLang : 'en';

    for (final entry in [
      {'host': wikiLang, 'q': coreNativeTopic},
      {'host': 'en', 'q': coreEnglishTopic},
    ]) {
      final String host = entry['host']!;
      final String q = entry['q']!;
      if (q.isEmpty) continue;
      try {
        final searchUri = Uri.https('$host.wikipedia.org', '/w/api.php', {
          'action': 'query',
          'list': 'search',
          'srsearch': q,
          'srlimit': '2',
          'utf8': '1',
          'format': 'json',
        });
        final resp = await http.get(searchUri).timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          final List searchResults = data['query']?['search'] ?? [];
          if (searchResults.isNotEmpty) {
            final String topTitle = searchResults[0]['title'].toString();
            final summaryUri = Uri.https(
              '$host.wikipedia.org',
              '/api/rest_v1/page/summary/${Uri.encodeComponent(topTitle.replaceAll(' ', '_'))}',
            );
            final sumResp = await http.get(summaryUri).timeout(const Duration(seconds: 3));
            if (sumResp.statusCode == 200) {
              final sumData = jsonDecode(utf8.decode(sumResp.bodyBytes));
              final String extract = (sumData['extract'] ?? '').toString().trim();
              if (extract.isNotEmpty) {
                knowledgeFacts.add("$topTitle: $extract");
              }
            } else {
              final snippet = _decodeHtmlEntities(searchResults[0]['snippet'].toString());
              knowledgeFacts.add("$topTitle: $snippet");
            }
          }
        }
      } catch (_) {}
    }

    try {
      final ddgHtmlUri = Uri.https('html.duckduckgo.com', '/html/', {'q': rawQuery});
      final resp = await http.get(ddgHtmlUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept-Language': '$detectedLang,en-US;q=0.9,en;q=0.8',
      }).timeout(const Duration(seconds: 3));

      if (resp.statusCode == 200) {
        final htmlBody = utf8.decode(resp.bodyBytes);
        final RegExp snippetRegex = RegExp(r'<a class="result__snippet"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false);
        int count = 0;
        for (final m in snippetRegex.allMatches(htmlBody)) {
          if (count >= 2) break;
          final String cleanSnippet = _decodeHtmlEntities(m.group(1) ?? "");
          if (cleanSnippet.length > 30) {
            knowledgeFacts.add(cleanSnippet);
            count++;
          }
        }
      }
    } catch (_) {}

    String combined = knowledgeFacts.join('\n');
    if (combined.length > 900) {
      combined = combined.substring(0, 900);
    }

    return {
      'type': 'knowledge',
      'context': combined,
    };
  }

  Future<String> _generateIntelligentAiResponse({
    required String userPrompt,
    required String englishTranslation,
    required String detectedLang,
    required String contextType,
    required String backgroundKnowledge,
    required String visionInfo,
    required String ragTranscript,
  }) async {
    final String modelPersona = _activeAiModelTitle;

    final StringBuffer memoryVaultBuffer = StringBuffer();
    if (_permanentMemoryFacts.isNotEmpty) {
      memoryVaultBuffer.writeln("PERMANENT MEMORY VAULT (Everything the user has ever told you across all sessions):");
      final recentFacts = _permanentMemoryFacts.length > 30
          ? _permanentMemoryFacts.sublist(_permanentMemoryFacts.length - 30)
          : _permanentMemoryFacts;
      for (final f in recentFacts) {
        memoryVaultBuffer.writeln("- $f");
      }
    }

    final List<Map<String, String>> chatHistory = [];
    final String systemInstruction =
        "You are $modelPersona, a world-class, warm, human-like AI assistant inside Pro Media Studio on $_hardwareTierBadge. "
        "CRITICAL RULES:\n"
        "1. Always reply in the EXACT SAME LANGUAGE as the user's message (if Arabic, reply in fluent, natural Arabic; if German, reply in German; if English, reply in English).\n"
        "2. You have 100% PERMANENT INFINITE MEMORY. Never say you forget conversations—use the PERMANENT MEMORY VAULT and chat history below to remember the user's name, projects, preferences, and everything they ever told you!\n"
        "3. Talk like a real, intelligent human speaking face-to-face. Never dump raw search links or newspaper headlines.\n"
        "4. Understand typos effortlessly (e.g., 'سترت البقلنسوه' = 'سترة بقلنسوة' / Hoodie / هودي) and explain clearly right away.\n"
        "5. Do not use raw markdown double-asterisks (**).\n"
        "${memoryVaultBuffer.toString()}"
        "${visionInfo.isNotEmpty ? '\n$visionInfo' : ''}"
        "${ragTranscript.isNotEmpty ? '\n$ragTranscript' : ''}"
        "${backgroundKnowledge.isNotEmpty ? '\nVerified Reference Knowledge:\n$backgroundKnowledge' : ''}";

    chatHistory.add({'role': 'system', 'content': systemInstruction});

    final int historyCount = _messages.length;
    final int startIdx = (historyCount > 15) ? historyCount - 15 : 1;
    for (int i = startIdx; i < historyCount - 1; i++) {
      final m = _messages[i];
      chatHistory.add({
        'role': m.sender == 'user' ? 'user' : 'assistant',
        'content': m.text,
      });
    }

    chatHistory.add({
      'role': 'user',
      'content': backgroundKnowledge.isNotEmpty
          ? "$userPrompt\n\n(Reference facts to answer naturally: $backgroundKnowledge)"
          : userPrompt,
    });

    final List<String> modelsToTry = ['openai', 'deepseek', 'mistral', 'searchgpt'];

    for (final modelName in modelsToTry) {
      try {
        final uri = Uri.parse('https://text.pollinations.ai/openai');
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': modelName,
                'messages': chatHistory,
                'temperature': 0.5,
              }),
            )
            .timeout(const Duration(seconds: 14));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          final String? content = decoded['choices']?[0]?['message']?['content'];
          if (content != null && content.trim().isNotEmpty) {
            return _cleanMarkdownFormatting(content);
          }
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    try {
      final uri = Uri.parse('https://text.pollinations.ai/');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': chatHistory,
              'model': 'openai',
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
        return _cleanMarkdownFormatting(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}

    if (backgroundKnowledge.isNotEmpty) {
      if (detectedLang != 'en' && detectedLang != 'same') {
        final translated = await _translateSingleLineWithRetry(backgroundKnowledge, detectedLang);
        return _cleanMarkdownFormatting(translated);
      }
      return _cleanMarkdownFormatting(backgroundKnowledge);
    }

    String fallbackMsg = "I'm here and listening! Could you tell me a bit more?";
    if (detectedLang != 'en' && detectedLang != 'same') {
      return await _translateSingleLineWithRetry(fallbackMsg, detectedLang);
    }
    return fallbackMsg;
  }

  Future<void> _sendChatMessage({bool forceVoiceReply = false}) async {
    final text = _chatController.text.trim();
    if (text.isEmpty && _attachedVisionFile == null) return;
    if (_isAiGenerating) return;

    if (text.isNotEmpty) {
      _extractAndStorePermanentFact(text);
    }

    String contextualQuery = text;
    if (_isConversationalFollowUp(text) && _messages.length >= 2) {
      for (int i = _messages.length - 1; i >= 1; i--) {
        if (_messages[i].sender == 'user' && !_isConversationalFollowUp(_messages[i].text)) {
          contextualQuery = "${_messages[i].text} ($text)";
          break;
        }
      }
    }

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
    await _savePermanentMemoryToDisk();
    _scrollToBottom();

    final langInfo = await _detectLanguageAndTranslateToEnglish(contextualQuery);
    final String englishQuery = langInfo['enText'] ?? contextualQuery;
    final String detectedLang = langInfo['lang'] ?? 'en';

    String contextType = "none";
    String backgroundKnowledge = "";
    if (_webSearchEnabled && text.isNotEmpty) {
      final resMap = await _fetchSmartBackgroundKnowledge(contextualQuery, englishQuery, detectedLang);
      contextType = resMap['type'] ?? "none";
      backgroundKnowledge = resMap['context'] ?? "";
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
      backgroundKnowledge: backgroundKnowledge,
      visionInfo: visionAnalysis,
      ragTranscript: ragTranscriptContext,
    );

    setState(() {
      _messages.add(ChatMessage(sender: "ai", text: aiReply));
      _isAiGenerating = false;
    });
    await _savePermanentMemoryToDisk();
    _scrollToBottom();

    if (_autoVoiceReplyEnabled || forceVoiceReply) {
      await _speakAiResponseAloud(aiReply, detectedLang);
    }
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
              Tab(text: "🤖 Local AI & Voice"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
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
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _activeAiModelTitle,
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 12,
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.apps, color: Colors.tealAccent, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    "All 12 AI Brains",
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
                      const Divider(color: Colors.white12, height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _aiVoiceGender = _aiVoiceGender == "female" ? "male" : "female";
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _aiVoiceGender == "female" ? "👩 Female Voice" : "👨 Male Voice",
                                    style: const TextStyle(color: Colors.tealAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text("Voice Reply", style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                              SizedBox(
                                height: 24,
                                child: Switch(
                                  value: _autoVoiceReplyEnabled,
                                  activeColor: Colors.tealAccent,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (val) {
                                    setState(() => _autoVoiceReplyEnabled = val);
                                    if (!val) _stopSpeaking();
                                  },
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.travel_explore, color: Colors.tealAccent, size: 14),
                              const SizedBox(width: 3),
                              const Text("Web", style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                              SizedBox(
                                height: 24,
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
                            maxWidth: MediaQuery.of(context).size.width * 0.84,
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
                              if (!isUser)
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: InkWell(
                                    onTap: () => _speakAiResponseAloud(msg.text, "auto"),
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Icon(Icons.volume_up_rounded, size: 16, color: Colors.white54),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isSpeakingNow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    color: Colors.teal.withOpacity(0.2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.spatial_audio_off, color: Colors.tealAccent, size: 16),
                            SizedBox(width: 8),
                            Text(
                              "AI is speaking aloud...",
                              style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 16),
                          label: const Text("Stop Voice", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                          onPressed: _stopSpeaking,
                        ),
                      ],
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
                if (_isRecordingVoice)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: Colors.redAccent.withOpacity(0.2),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic, color: Colors.redAccent, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Listening to your voice... Tap Mic again to send!",
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                if (_isAiGenerating)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                        ),
                        SizedBox(width: 8),
                        Text(
                          "AI is thinking with Permanent Memory...",
                          style: TextStyle(color: Colors.tealAccent, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
                  color: const Color(0xFF181818),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: "Attach Photo or Video for Vision Analysis",
                        icon: const Icon(Icons.add_a_photo_outlined, color: Colors.tealAccent),
                        onPressed: _pickVisionAttachment,
                      ),
                      GestureDetector(
                        onTap: _toggleLiveVoiceRecording,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isRecordingVoice ? Colors.redAccent : Colors.tealAccent.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isRecordingVoice ? Colors.white : Colors.tealAccent,
                              width: 1.4,
                            ),
                          ),
                          child: Icon(
                            _isRecordingVoice ? Icons.stop_rounded : Icons.mic_none_rounded,
                            color: _isRecordingVoice ? Colors.white : Colors.tealAccent,
                            size: 20,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: _isRecordingVoice
                                ? "Speaking... Tap red stop button when done"
                                : "Type or tap 🎙️ to talk in any language...",
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                            filled: true,
                            fillColor: const Color(0xFF121212),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _sendChatMessage(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.tealAccent),
                        onPressed: () => _sendChatMessage(),
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
