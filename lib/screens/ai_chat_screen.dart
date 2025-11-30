import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/ai_chat_service.dart';
import '../services/database_service.dart';
import '../services/huggingface_service.dart';
import '../services/groq_service.dart';
import '../services/gemini_service.dart';
import '../services/sambanova_service.dart';
import '../services/openrouter_service.dart';

/// شاشة الدردشة مع الذكاء الاصطناعي
class AIChatScreen extends StatefulWidget {
  const AIChatScreen({Key? key}) : super(key: key);

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  late AIChatService _chatService;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _addWelcomeMessage();
  }

  Future<void> _initializeService() async {
    print('🚀 AI Chat Screen: تهيئة الخدمة...');
    
    final dbService = DatabaseService();
    await dbService.database; // تهيئة قاعدة البيانات
    
    // قراءة API keys من .env
    final openRouterKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
    final sambaNovaKey = dotenv.env['SAMBANOVA_API_KEY'] ?? '';
    final geminiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final groqKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final huggingFaceKey = dotenv.env['HUGGINGFACE_API_KEY'] ?? '';
    
    print('🔑 API Keys:');
    print('   - OpenRouter: ${openRouterKey.isNotEmpty ? "موجود ✅ (الأولوية الأولى!)" : "غير موجود ❌"}');
    print('   - SambaNova: ${sambaNovaKey.isNotEmpty ? "موجود ✅" : "غير موجود ❌"}');
    print('   - Gemini: ${geminiKey.isNotEmpty ? "موجود ✅" : "غير موجود ❌"}');
    print('   - Groq: ${groqKey.isNotEmpty ? "موجود ✅" : "غير موجود ❌"}');
    print('   - HuggingFace (Qwen): ${huggingFaceKey.isNotEmpty ? "موجود ✅" : "غير موجود ❌"}');
    
    // إنشاء الخدمات (OpenRouter له الأولوية الأولى)
    OpenRouterService? openRouterService;
    SambaNovaService? sambaNovaService;
    GeminiService? geminiService;
    GroqService? groqService;
    HuggingFaceService? huggingFaceService;
    
    if (openRouterKey.isNotEmpty) {
      openRouterService = OpenRouterService(apiKey: openRouterKey);
      print('✅ تم تفعيل OpenRouter (Qwen/Llama) - الأولوية الأولى');
    }
    
    if (sambaNovaKey.isNotEmpty) {
      sambaNovaService = SambaNovaService(apiKey: sambaNovaKey);
      print('✅ تم تفعيل SambaNova (Llama 405B) - الأولوية الثانية');
    }
    
    if (geminiKey.isNotEmpty) {
      geminiService = GeminiService(apiKey: geminiKey);
      print('✅ تم تفعيل Gemini - الأولوية الثالثة');
    }
    
    if (groqKey.isNotEmpty) {
      groqService = GroqService(apiKey: groqKey);
      print('✅ تم تفعيل Groq - الأولوية الرابعة');
    }
    
    if (huggingFaceKey.isNotEmpty) {
      huggingFaceService = HuggingFaceService(apiKey: huggingFaceKey);
      print('✅ تم تفعيل Qwen 2.5 (HuggingFace) - الأولوية الخامسة');
    }
    
    _chatService = AIChatService(
      dbService,
      openRouterService: openRouterService,
      sambaNovaService: sambaNovaService,
      geminiService: geminiService,
      groqService: groqService,
      huggingFaceService: huggingFaceService,
    );
    
    print('✅ AI Chat Service جاهز!');
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(ChatMessage(
        text: "مرحبًا! أنا مساعدك الذكي 🤖\n\n"
              "يمكنني مساعدتك في:\n"
              "• تدقيق جميع الحسابات والأرصدة\n"
              "• فحص صحة الفواتير والمعاملات\n"
              "• التحقق من المخزون والوحدات\n"
              "• كشف الأخطاء المحاسبية\n"
              "• إنشاء التقارير والملخصات\n\n"
              "اختر من الاقتراحات أو اكتب طلبك:",
        isUser: false,
        suggestions: AIChatService.defaultSuggestions,
      ));
    });
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: message, isUser: true));
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      final response = await _chatService.processMessage(
        message,
        conversationHistory: _messages.map((m) => m.text).toList(),
      );

      setState(() {
        _messages.add(ChatMessage(
          text: response.text,
          isUser: false,
          suggestions: response.followups,
          status: response.status,
          data: response.data,
        ));
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: "عذرًا، حدث خطأ: ${e.toString()}",
          isUser: false,
          status: 'error',
        ));
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الدردشة مع الذكاء الاصطناعي'),
          backgroundColor: Colors.blue[700],
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _addWelcomeMessage();
                });
              },
              tooltip: 'بدء محادثة جديدة',
            ),
          ],
        ),
        body: Column(
          children: [
            // قائمة الرسائل
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),

            // مؤشر التحميل
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('جاري التحليل...'),
                  ],
                ),
              ),

            // حقل الإدخال
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك هنا...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _sendMessage(_messageController.text),
                    color: Colors.blue[700],
                    iconSize: 28,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          // فقاعة الرسالة
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isUser
                  ? Colors.blue[100]
                  : _getStatusColor(message.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 15,
                color: message.isUser ? Colors.black87 : Colors.black,
              ),
            ),
          ),

          // الاقتراحات السريعة
          if (message.suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: message.suggestions.map((suggestion) {
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () => _sendMessage(suggestion),
                  backgroundColor: Colors.blue[50],
                  labelStyle: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.green[50]!;
      case 'warning':
        return Colors.orange[50]!;
      case 'error':
        return Colors.red[50]!;
      default:
        return Colors.grey[100]!;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}


