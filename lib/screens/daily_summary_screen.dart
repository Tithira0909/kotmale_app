import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/bluetooth_service.dart';

class DailySummaryScreen extends StatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  DateTime selectedDate = DateTime.now();
  bool _loading = true;

  List<Map<String, dynamic>> summaryData = [];
  Map<String, TextEditingController> invQtyControllers = {};

  double totalSoldValue = 0.0;
  double totalCreditCollection = 0.0;
  double todayCashSale = 0.0;
  double totalCashValue = 0.0;
  double totalCreditSales = 0.0;
  double totalOutstandingBalance = 0.0;

  double _creditCollectionFromInvoices = 0.0;
  double _creditCollectionFromShopCollections = 0.0;

  List<Map<String, dynamic>> _todayInvoices = [];

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadDailySummary();
  }

  @override
  void dispose() {
    for (var controller in invQtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatLkr(double amount) {
    return 'LKR ${_currencyFormat.format(amount)}';
  }

  Future<double> _getCollectionsTotalForSelectedDate() async {
    final prefs = await SharedPreferences.getInstance();
    final collectionData = prefs.getString('collection_history');
    if (collectionData == null) return 0.0;

    final List decoded = jsonDecode(collectionData);

    double sum = 0.0;
    for (var c in decoded) {
      final dateStr = c['date']?.toString();
      if (dateStr == null || dateStr.isEmpty) continue;

      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;

      if (_isSameDay(dt, selectedDate)) {
        sum += double.tryParse(c['amount']?.toString() ?? '0') ?? 0.0;
      }
    }
    return sum;
  }

  Future<void> _loadDailySummary() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString('invoice_history');
    final List invoices = data != null ? jsonDecode(data) : [];

    final Map<String, Map<String, dynamic>> itemMap = {};
    double soldTotal = 0.0;
    double creditSalesSum = 0.0;

    double previousCreditCollection = 0.0;
    double dailyCashCollection = 0.0;

    final collectionsFromHistory = await _getCollectionsTotalForSelectedDate();
    final todayKey = DateFormat('yyyy-MM-dd').format(selectedDate);
    List<Map<String, dynamic>> todayInvsList = [];

    for (var inv in invoices) {
      if (inv is! Map) continue;
      final invMap = inv.cast<String, dynamic>();

      final dateStr = invMap['date'] ?? '';
      if (!dateStr.toString().contains(todayKey)) continue;

      todayInvsList.add(invMap);

      final paymentType = invMap['paymentType'] ?? '';
      final totalInvVal =
          double.tryParse(invMap['total']?.toString() ?? '0') ?? 0.0;

      if (paymentType == 'Credit') {
        creditSalesSum += totalInvVal;
      }

      final todayPart =
          double.tryParse(invMap['collection_today']?.toString() ?? '0') ?? 0.0;
      final prevPart =
          double.tryParse(invMap['collection_previous']?.toString() ?? '0') ??
              0.0;
      final collection =
          double.tryParse(invMap['collection']?.toString() ?? '0') ?? 0.0;

      if (todayPart > 0) {
        dailyCashCollection += todayPart;
      } else if (paymentType == 'Cash' && collection > 0) {
        dailyCashCollection += collection;
      } else if (paymentType == 'Cash' && collection == 0) {
        dailyCashCollection += totalInvVal;
      }

      if (prevPart > 0) {
        previousCreditCollection += prevPart;
      }

      final items = invMap['items'] as List?;
      if (items != null) {
        for (var item in items) {
          final name = item['name'];
          final qty = int.tryParse(item['qty'].toString()) ?? 0;
          final price = double.tryParse(item['price'].toString()) ?? 0.0;
          final total = qty * price;
          soldTotal += total;

          if (!itemMap.containsKey(name)) {
            itemMap[name] = {
              'name': name,
              'invQty': 0,
              'soldQty': 0,
              'balanceQty': 0,
              'soldValue': 0.0,
            };
          }

          itemMap[name]!['soldQty'] += qty;
          itemMap[name]!['soldValue'] += total;
        }
      }
    }

    final todayKeyStorage = DateFormat('yyyy-MM-dd').format(selectedDate);
    final savedInvQtyJson = prefs.getString('inv_qty_$todayKeyStorage');
    Map<String, dynamic> savedInvQty = {};
    if (savedInvQtyJson != null) {
      savedInvQty = jsonDecode(savedInvQtyJson);
    }

    final productsStr = prefs.getString('products');
    Map<String, dynamic> liveStock = {};
    if (productsStr != null) {
      final List products = jsonDecode(productsStr);
      for (var p in products) {
        liveStock[p['name']] = p['stock'] ?? p['qty'];
      }
    }

    final finalCreditCollection =
        previousCreditCollection + collectionsFromHistory;

    final newList = itemMap.values.toList();
    for (var item in newList) {
      final name = item['name'];
      final invQty = savedInvQty[name] ?? 0;
      item['invQty'] = invQty;
      item['balanceQty'] = liveStock[name] ?? (invQty - item['soldQty']);
    }

    // Sort summary list by sold value descending
    newList.sort((a, b) =>
        (b['soldValue'] as double).compareTo(a['soldValue'] as double));

    // Sort today's invoices descending
    todayInvsList.sort((a, b) {
      final da =
          DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final db =
          DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return db.compareTo(da);
    });

    if (!mounted) return;
    setState(() {
      summaryData = newList;
      totalSoldValue = soldTotal;
      totalCreditSales = creditSalesSum;
      _todayInvoices = todayInvsList;

      _creditCollectionFromInvoices = previousCreditCollection;
      _creditCollectionFromShopCollections = collectionsFromHistory;

      totalCreditCollection = finalCreditCollection;
      todayCashSale = dailyCashCollection;
      totalCashValue = todayCashSale + totalCreditCollection;

      // Outstanding balance for today's sales = Total Sold - Daily Cash Received
      totalOutstandingBalance = (totalSoldValue - todayCashSale) < 0
          ? 0.0
          : (totalSoldValue - todayCashSale);

      _loading = false;
    });

    for (var controller in invQtyControllers.values) {
      controller.dispose();
    }
    invQtyControllers.clear();

    for (var item in summaryData) {
      invQtyControllers[item['name']] = TextEditingController(
        text: item['invQty'].toString(),
      );
    }
  }

  Future<void> _saveInvQtyData() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(selectedDate);

    final Map<String, dynamic> dataToSave = {};
    for (var item in summaryData) {
      dataToSave[item['name']] = item['invQty'];
    }

    await prefs.setString('inv_qty_$todayKey', jsonEncode(dataToSave));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      _loadDailySummary();
    }
  }

  void _changeDateByDays(int days) {
    setState(() {
      selectedDate = selectedDate.add(Duration(days: days));
    });
    _loadDailySummary();
  }

  String _fit(String s, int width) {
    final t = s.trim();
    if (t.length == width) return t;
    if (t.length > width) return t.substring(0, width);
    return t.padRight(width);
  }

  String _num(dynamic v, int width) {
    final s = (v ?? 0).toString();
    if (s.length >= width) return s.substring(0, width);
    return s.padLeft(width);
  }

  String _moneyNum(double v, int width) {
    final s = v.toStringAsFixed(2);
    if (s.length >= width) return s.substring(0, width);
    return s.padLeft(width);
  }

  Future<void> _printSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final printerMac = prefs.getString('printer_mac');
    if (printerMac == null || printerMac.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              '⚠️ Please connect a printer first in Printer Settings'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    try {
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        final ok = await BluetoothService.connect(printerMac);
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ Printer connection failed'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
          return;
        }
      }

      const itemW = 16;
      const invW = 4;
      const soldW = 4;
      const balW = 4;
      const totalW = 10;

      final dateLabel = DateFormat('yyyy-MM-dd').format(selectedDate);

      final buf = StringBuffer();
      buf.writeln('       *** DAILY SUMMARY ***');
      buf.writeln('Date: $dateLabel');
      buf.writeln('----------------------------------------');
      buf.writeln(
        '${_fit("Item", itemW)}'
        '${_fit("Inv", invW)}'
        '${_fit("Sold", soldW)}'
        '${_fit("Bal", balW)}'
        '${_fit("Total", totalW)}',
      );
      buf.writeln('----------------------------------------');

      for (var item in summaryData) {
        final name = _fit(item['name']?.toString() ?? '', itemW);
        final inv = _num(item['invQty'], invW);
        final sold = _num(item['soldQty'], soldW);
        final bal = _num(item['balanceQty'], balW);

        final total = _moneyNum((item['soldValue'] as double?) ?? 0.0, totalW);

        buf.writeln('$name$inv$sold$bal$total');
      }

      buf.writeln('----------------------------------------');
      buf.writeln(
        'Total Sold Value : LKR ${totalSoldValue.toStringAsFixed(2)}',
      );
      buf.writeln(
        'Credit Bill Coll.: LKR ${totalCreditCollection.toStringAsFixed(2)}',
      );
      buf.writeln(
        '  From Invoices   : LKR ${_creditCollectionFromInvoices.toStringAsFixed(2)}',
      );
      buf.writeln(
        '  From Collections: LKR ${_creditCollectionFromShopCollections.toStringAsFixed(2)}',
      );
      buf.writeln(
        'Daily Cash Bill   : LKR ${todayCashSale.toStringAsFixed(2)}',
      );
      buf.writeln(
        'Total Cash Value  : LKR ${totalCashValue.toStringAsFixed(2)}',
      );
      buf.writeln('----------------------------------------');
      buf.writeln('Thank you!\n\n\n');

      await BluetoothService.printInvoice(buf.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🖨️ Daily Summary printed successfully'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: const Color(0xFF1E40AF),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer error: $e'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Color _balanceColor(int balance) {
    if (balance < 0) return Colors.red.shade700;
    if (balance > 0) return const Color(0xFF047857);
    return const Color(0xFF475569);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Daily Summary',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print Report',
            onPressed: _printSummary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: _loadDailySummary,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1E40AF)),
              )
            : RefreshIndicator(
                color: const Color(0xFF1E40AF),
                onRefresh: _loadDailySummary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 1. Date Selector Banner ---
                      _buildDateSelectorBanner(),

                      const SizedBox(height: 14),

                      // --- 2. Summary Metric Cards (2-Column Grid) ---
                      _buildSummaryGridSection(),

                      const SizedBox(height: 18),

                      // --- 3. Payment Summary Card ---
                      _buildPaymentSummaryCard(),

                      const SizedBox(height: 18),

                      // --- 4. Sales Breakdown Table ---
                      _buildSalesBreakdownSection(),

                      const SizedBox(height: 18),

                      // --- 5. Top Selling Products ---
                      _buildTopSellingProductsSection(),

                      const SizedBox(height: 18),

                      // --- 6. Recent Invoices / Transactions ---
                      _buildRecentTransactionsSection(),

                      const SizedBox(height: 20),

                      // --- 7. Print Daily Summary Action Button ---
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E40AF),
                            side: const BorderSide(
                                color: Color(0xFF1E40AF), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _printSummary,
                          icon: const Icon(Icons.print_outlined, size: 20),
                          label: const Text(
                            'Print Daily Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // --- 1. Date Selector Banner ---
  Widget _buildDateSelectorBanner() {
    final dateFormatted = DateFormat('EEEE, MMM dd, yyyy').format(selectedDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF1E40AF), size: 24),
            onPressed: () => _changeDateByDays(-1),
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      color: Color(0xFF1E40AF), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    dateFormatted,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF1E40AF), size: 24),
            onPressed: () => _changeDateByDays(1),
          ),
        ],
      ),
    );
  }

  // --- 2. Summary Cards Grid (2-Column Grid) ---
  Widget _buildSummaryGridSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Daily Metrics Overview',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricGridCard(
                title: 'Total Sales',
                value: _formatLkr(totalSoldValue),
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFF1E40AF),
                bgColor: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricGridCard(
                title: 'Total Invoices',
                value: '${_todayInvoices.length} Invoices',
                icon: Icons.receipt_long_outlined,
                iconColor: const Color(0xFF4338CA),
                bgColor: const Color(0xFFEEF2FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricGridCard(
                title: 'Cash Received',
                value: _formatLkr(todayCashSale),
                icon: Icons.attach_money_rounded,
                iconColor: const Color(0xFF047857),
                bgColor: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricGridCard(
                title: 'Credit Sales',
                value: _formatLkr(totalCreditSales),
                icon: Icons.credit_score_outlined,
                iconColor: Colors.amber.shade900,
                bgColor: Colors.amber.shade50,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricGridCard(
                title: 'Outstanding Bal.',
                value: _formatLkr(totalOutstandingBalance),
                icon: Icons.account_balance_wallet_outlined,
                iconColor: Colors.red.shade700,
                bgColor: Colors.red.shade50,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricGridCard(
                title: 'Collections',
                value: _formatLkr(totalCreditCollection),
                icon: Icons.price_check_rounded,
                iconColor: const Color(0xFF0284C7),
                bgColor: const Color(0xFFE0F2FE),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricGridCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. Payment Summary Card ---
  Widget _buildPaymentSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.account_balance_outlined,
                  size: 18, color: Color(0xFF1E40AF)),
              SizedBox(width: 8),
              Text(
                'Payment Summary',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(
              'Daily Cash Sales', _formatLkr(todayCashSale), false),
          const SizedBox(height: 6),
          _buildSummaryRow('Old Credit Recovered (Invoices)',
              _formatLkr(_creditCollectionFromInvoices), false),
          const SizedBox(height: 6),
          _buildSummaryRow('Shop Collections',
              _formatLkr(_creditCollectionFromShopCollections), false),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 8),
          _buildSummaryRow(
              'Total Net Cash Received', _formatLkr(totalCashValue), true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String amount, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? const Color(0xFF0F172A) : Colors.grey.shade700,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amount,
            style: TextStyle(
              fontSize: isBold ? 14 : 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? const Color(0xFF1E40AF) : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  // --- 4. Sales Breakdown Table Section ---
  Widget _buildSalesBreakdownSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Sales Breakdown',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              '${summaryData.length} items recorded',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        summaryData.isEmpty
            ? _buildEmptyState()
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.015),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 550),
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(1.6),
                          1: FixedColumnWidth(80),
                          2: FixedColumnWidth(70),
                          3: FixedColumnWidth(70),
                          4: FlexColumnWidth(1.2),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          // Header
                          TableRow(
                            decoration:
                                const BoxDecoration(color: Color(0xFF1E40AF)),
                            children: [
                              _tableCell('Item Name',
                                  header: true, color: Colors.white),
                              _tableCell('Inv Qty',
                                  header: true,
                                  color: Colors.white,
                                  center: true),
                              _tableCell('Sold Qty',
                                  header: true,
                                  color: Colors.white,
                                  center: true),
                              _tableCell('Bal Qty',
                                  header: true,
                                  color: Colors.white,
                                  center: true),
                              _tableCell('Sold Total',
                                  header: true,
                                  color: Colors.white,
                                  right: true),
                            ],
                          ),
                          // Rows
                          ...List.generate(summaryData.length, (i) {
                            final item = summaryData[i];
                            final controller = invQtyControllers[item['name']]!;
                            final bal = item['balanceQty'] ?? 0;
                            final bg = (i % 2 == 0)
                                ? Colors.white
                                : const Color(0xFFF8FAFC);

                            return TableRow(
                              decoration: BoxDecoration(color: bg),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  child: Text(
                                    item['name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                // Editable Inv Qty
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  child: Focus(
                                    onFocusChange: (hasFocus) {
                                      if (hasFocus) {
                                        controller.selection = TextSelection(
                                          baseOffset: 0,
                                          extentOffset: controller.text.length,
                                        );
                                      }
                                    },
                                    child: TextField(
                                      controller: controller,
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          item['invQty'] =
                                              int.tryParse(val) ?? 0;
                                          item['balanceQty'] =
                                              item['invQty'] - item['soldQty'];
                                        });
                                        _saveInvQtyData();
                                      },
                                    ),
                                  ),
                                ),
                                // Sold Qty
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '${item['soldQty']}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5),
                                  ),
                                ),
                                // Bal Qty
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          _balanceColor(bal).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$bal',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                        color: _balanceColor(bal),
                                      ),
                                    ),
                                  ),
                                ),
                                // Sold Total
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    _formatLkr(
                                        (item['soldValue'] as double?) ?? 0.0),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFF1E40AF),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _tableCell(
    String text, {
    bool header = false,
    bool center = false,
    bool right = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Align(
        alignment: center
            ? Alignment.center
            : right
                ? Alignment.centerRight
                : Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontWeight: header ? FontWeight.bold : FontWeight.normal,
            fontSize: header ? 12 : 12,
            color: color ?? const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }

  // --- 5. Top Selling Products Section ---
  Widget _buildTopSellingProductsSection() {
    final topItems = summaryData.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Selling Products',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        topItems.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  'No product sales recorded for this date.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              )
            : Column(
                children: topItems.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final item = entry.value;
                  final name = item['name']?.toString() ?? 'Product';
                  final qty = item['soldQty'] ?? 0;
                  final totalVal = (item['soldValue'] as double?) ?? 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.015),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: rank == 1
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '#$rank',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: rank == 1
                                    ? const Color(0xFF1E40AF)
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$qty units sold',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatLkr(totalVal),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  // --- 6. Recent Invoices / Transactions Section ---
  Widget _buildRecentTransactionsSection() {
    final DateFormat timeFormat = DateFormat('hh:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Transactions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              '${_todayInvoices.length} total',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _todayInvoices.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  'No transactions recorded on this date.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              )
            : Column(
                children: _todayInvoices.take(5).map((inv) {
                  final shopName = inv['shopName']?.toString() ?? 'General';
                  final totalVal =
                      double.tryParse(inv['total']?.toString() ?? '0') ?? 0.0;
                  final payType = inv['paymentType']?.toString() ?? 'Cash';
                  final dtStr = inv['date']?.toString() ?? '';
                  final dt = DateTime.tryParse(dtStr);
                  final timeLabel = dt != null ? timeFormat.format(dt) : '';
                  final isCredit = payType == 'Credit';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.015),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isCredit
                                ? Colors.amber.shade50
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.receipt_outlined,
                            size: 16,
                            color: isCredit
                                ? Colors.amber.shade900
                                : const Color(0xFF047857),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shopName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (timeLabel.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  timeLabel,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatLkr(totalVal),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isCredit
                                    ? Colors.amber.shade100
                                    : const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                payType,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isCredit
                                      ? Colors.amber.shade900
                                      : const Color(0xFF065F46),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  // --- Empty State ---
  Widget _buildEmptyState() {
    final dateStr = DateFormat('MMM dd, yyyy').format(selectedDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 36,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 10),
          Text(
            'No Data for $dateStr',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No sales or inventory logs recorded on this date.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
