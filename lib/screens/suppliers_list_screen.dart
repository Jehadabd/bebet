import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/supplier.dart';
import 'add_supplier_screen.dart';
import 'supplier_details_screen.dart';
import 'ai_import_review_screen.dart';
import '../services/suppliers_service.dart';
import 'package:intl/intl.dart';

class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({Key? key}) : super(key: key);

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  final List<Supplier> _suppliers = [];
  final SuppliersService _suppliersService = SuppliersService();
  
  final TextEditingController _searchController = TextEditingController();
  List<Supplier> _filteredSuppliers = [];
  String _filterType = 'all';
  bool _isLoading = true;
  bool _isFirstLoad = true; // 🚀 لتمييز أول تحميل
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en');

  @override
  void initState() {
    super.initState();
    _loadSuppliers(forceRefresh: true);
    _loadInvoiceCount();
  }

  /// 🚀 تحميل الموردين مع Cache ذكي
  /// forceRefresh = true يعني تجاهل Cache وأعد التحميل من قاعدة البيانات
  Future<void> _loadSuppliers({bool forceRefresh = false}) async {
    // إذا لم يكن هناك طلب للتحديث القسري، نستخدم Cache الموجود في SuppliersService
    if (!forceRefresh && !_isFirstLoad) {
      // Cache موجود بالفعل في SuppliersService.getAllSuppliers()
      // لا حاجة لإظهار loading
    } else {
      setState(() => _isLoading = true);
    }
    
    // 🚀 Cache يتم إدارته تلقائياً في SuppliersService
    final list = await _suppliersService.getAllSuppliers();
    
    if (mounted) {
      setState(() {
        _suppliers.clear();
        _suppliers.addAll(list);
        _applyFilter();
        _isLoading = false;
        _isFirstLoad = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSuppliers = _suppliers.where((s) {
        final matchesQuery = s.companyName.toLowerCase().contains(query) ||
                             (s.phoneNumber != null && s.phoneNumber!.contains(query));
        
        // debt condition
        if (_filterType == 'with_debt') {
          return matchesQuery && s.currentBalance > 0;
        } else if (_filterType == 'no_debt') {
          return matchesQuery && s.currentBalance <= 0;
        }
        return matchesQuery;
      }).toList();
    });
  }

  void _onAddSupplier() {
    Navigator.of(context)
        .push<Supplier>(
      MaterialPageRoute(builder: (_) => const AddSupplierScreen()),
    )
        .then((created) {
      if (created != null) {
        _insertSupplier(created);
      }
    });
  }

  Future<void> _insertSupplier(Supplier s) async {
    final id = await _suppliersService.insertSupplier(s);
    final created = s.copyWith(id: id);
    _loadSuppliers(forceRefresh: true); // 🚀 تحديث قسري بعد الإضافة
  }

  void _openSupplierDetails(Supplier supplier) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierDetailsScreen(supplier: supplier),
      ),
    ).then((_) => _loadSuppliers(forceRefresh: true)); // 🚀 تحديث قسري بعد العودة من التفاصيل
  }

  String? _pendingAIType;

  Future<void> _askTypeThenPick() async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر نوع العملية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('فاتورة شراء'),
              onTap: () => Navigator.of(context).pop('invoice'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.payments),
              title: const Text('سند قبض'),
              onTap: () => Navigator.of(context).pop('receipt'),
            ),
          ],
        ),
      ),
    );
    if (type == null) return;
    _pendingAIType = type;
    await _pickFileAndOpenAI();
    _pendingAIType = null;
  }

  Future<void> _pickFileAndOpenAI() async {
    final selectedType = _pendingAIType ?? 'invoice';
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png'
            ? 'image/png'
            : 'image/jpeg');

    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final geminiApiKey2 = dotenv.env['GEMINI_API_KEY_2'] ?? '';
    final geminiApiKey3 = dotenv.env['GEMINI_API_KEY_3'] ?? '';
    final geminiApiKey4 = dotenv.env['GEMINI_API_KEY_4'] ?? '';
    final groqApiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final cloudflareApiToken = dotenv.env['CLOUDFLARE_API_TOKEN'] ?? '';
    final cloudflareAccountId = dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '';
    final googleVisionApiKey = dotenv.env['GOOGLE_VISION_API_KEY'] ?? '';
    final ocrSpaceApiKey = dotenv.env['OCR_SPACE_API_KEY'] ?? '';
    final glmApiKey = dotenv.env['GLM_API_KEY'] ?? '';
    final mistralApiKey = dotenv.env['MISTRAL_API_KEY'] ?? '';  // ✅ Mistral Pixtral
    
    if (geminiApiKey.isEmpty && groqApiKey.isEmpty && cloudflareApiToken.isEmpty && glmApiKey.isEmpty && mistralApiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على مفتاح API في .env')),
      );
      return;
    }
    
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AiImportReviewScreen(
          fileBytes: bytes,
          mimeType: mime,
          type: selectedType,
          geminiApiKey: geminiApiKey,
          geminiApiKey2: geminiApiKey2.isNotEmpty ? geminiApiKey2 : null,
          geminiApiKey3: geminiApiKey3.isNotEmpty ? geminiApiKey3 : null,
          geminiApiKey4: geminiApiKey4.isNotEmpty ? geminiApiKey4 : null,
          groqApiKey: groqApiKey.isNotEmpty ? groqApiKey : null,
          cloudflareApiToken: cloudflareApiToken.isNotEmpty ? cloudflareApiToken : null,
          cloudflareAccountId: cloudflareAccountId.isNotEmpty ? cloudflareAccountId : null,
          ocrSpaceApiKey: ocrSpaceApiKey.isNotEmpty ? ocrSpaceApiKey : null,
          glmApiKey: glmApiKey.isNotEmpty ? glmApiKey : null,
          mistralApiKey: mistralApiKey.isNotEmpty ? mistralApiKey : null,  // ✅ Mistral Pixtral
        ),
      ),
    );
    if (saved == true && mounted) {
      await _loadSuppliers(forceRefresh: true); // 🚀 تحديث قسري بعد حفظ AI
    }
  }

  int _totalInvoiceCount = 0;

  Future<void> _loadInvoiceCount() async {
    final count = await _suppliersService.getTotalInvoiceCount();
    if (mounted) {
      setState(() {
        _totalInvoiceCount = count;
      });
    }
  }

  Widget _buildStatsHeader() {
    final totalSuppliers = _suppliers.length;
    final totalDebt = _suppliers.fold(0.0, (sum, s) => sum + s.currentBalance);
    final totalPurchases = _suppliers.fold(0.0, (sum, s) => sum + s.totalPurchases);
    final totalPaid = _suppliers.fold(0.0, (sum, s) => sum + (s.totalPurchases - s.currentBalance));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // RTL
      child: Row(
        children: [
          _buildNewStatCard('إجمالي الديون', 'IQD ${_formatCompact(totalDebt)}', Icons.monetization_on_outlined, const Color(0xFFFFEBEE), const Color(0xFFE53935), '+12% هذا الشهر', Colors.red),
          const SizedBox(width: 16),
          _buildNewStatCard('إجمالي التسديد', 'IQD ${_formatCompact(totalPaid)}', Icons.payments_outlined, const Color(0xFFE8F5E9), const Color(0xFF43A047), null, null),
          const SizedBox(width: 16),
          _buildNewStatCard('حجم المشتريات', 'IQD ${_formatCompact(totalPurchases)}', Icons.shopping_bag_outlined, const Color(0xFFE3F2FD), const Color(0xFF1E88E5), '+5% عن العام الماضي', Colors.green),
          const SizedBox(width: 16),
          _buildNewStatCard('إجمالي الفواتير', '$_totalInvoiceCount', Icons.receipt_long_outlined, const Color(0xFFFFF3E0), const Color(0xFFFB8C00), null, null),
          const SizedBox(width: 16),
          _buildNewStatCard('عدد الموردين', '$totalSuppliers', Icons.people_alt_outlined, const Color(0xFFF3E5F5), const Color(0xFF8E24AA), null, null),
        ],
      ),
    );
  }

  Widget _buildNewStatCard(String title, String value, IconData icon, Color bgColor, Color iconColor, String? trendText, Color? trendColor) {
    return Container(
      width: 220,
      height: 100, // Fixed height for consistency
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                if (trendText != null) ...[
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.trending_up, size: 12, color: trendColor),
                        const SizedBox(width: 2),
                        Text(trendText, style: TextStyle(fontSize: 10, color: trendColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
        ],
      ),
    );
  }

  String _formatCompact(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return _nf.format(number);
  }

  Widget _buildSupplierCard(Supplier supplier) {
    final bool hasDebt = supplier.currentBalance > 0;
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => _openSupplierDetails(supplier),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // أيقونة المورد
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  supplier.companyName.isNotEmpty ? supplier.companyName[0] : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              // معلومات المورد
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.companyName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      supplier.phoneNumber ?? supplier.address ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // الرصيد
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_formatCompact(supplier.currentBalance)} د.ع',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasDebt ? 'مدين' : 'تعامل نقدي',
                    style: TextStyle(
                      fontSize: 11,
                      color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('لا توجد نتائج', style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Text('نظام الموردين الذكي', style: TextStyle(color: Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF3B82F6),
                  child: const Text('N', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
             Row(
               mainAxisAlignment: MainAxisAlignment.end,
               children: const [
                 Text('الرئيسية', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 16)),
                 SizedBox(width: 8),
                 Icon(Icons.grid_view, color: Color(0xFF3B82F6), size: 20),
               ],
             ),
             const SizedBox(height: 16),
            _buildStatsHeader(),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'بحث...',
                      suffixIcon: const Icon(Icons.search), // Search icon on the right side of the text like photo
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (_) => _applyFilter(),
                  ),
                ),
                const Text('الموردون المعتمدون', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSuppliers.isEmpty
                      ? Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: _buildEmptyState(),
                        )
                      : ListView.builder(
                          itemCount: _filteredSuppliers.length,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemBuilder: (context, index) {
                            return _buildSupplierCard(_filteredSuppliers[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat, // Bottom left
      floatingActionButton: FloatingActionButton(
        onPressed: () {
           showModalBottomSheet(context: context, builder: (context) {
             return SafeArea(
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   ListTile(
                     leading: const Icon(Icons.person_add),
                     title: const Text('إضافة مورد يدوياً'),
                     onTap: () {
                       Navigator.pop(context);
                       _onAddSupplier();
                     },
                   ),
                   ListTile(
                     leading: const Icon(Icons.auto_awesome),
                     title: const Text('إضافة عبر الذكاء الاصطناعي (AI)'),
                     onTap: () {
                       Navigator.pop(context);
                       _askTypeThenPick();
                     },
                   ),
                 ],
               ),
             );
           });
        },
        backgroundColor: const Color(0xFF3B82F6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}


