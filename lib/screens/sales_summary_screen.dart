import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../services/bluetooth_service.dart';
import 'daily_summary_screen.dart';

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  bool _loading = true;

  // Rows: { shopKey, shopName, cash, creditSales, collection }
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> _filteredRows = [];

  double totalCash = 0.0;
  double totalCreditSales = 0.0;
  double totalCollection = 0.0;

  bool _isTableView = true;

  final TextEditingController _searchCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _calculateShopSummary(forDate: _selectedDate);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  String _normKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  String _normShop(dynamic s) => _normKey((s?.toString() ?? ''));

  String _prettyShop(dynamic s) {
    final raw = (s?.toString() ?? '').trim();
    if (raw.isEmpty) return 'Unknown';
    return raw
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  double _toDouble(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  DateTime _parseDate(dynamic v) {
    final s = v?.toString() ?? '';
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatLkr(double amount) {
    return 'LKR ${_currencyFormat.format(amount)}';
  }

  /// ✅ Cash/Collection column = cash sales + collections (repayments)
  double _cashCollection(Map<String, dynamic> r) =>
      (r["cash"] as double) + (r["collection"] as double);

  /// ✅ CREDIT COLLECTION only (repayments)
  double _getCreditApplied(Map<String, dynamic> c) {
    if (c.containsKey('creditApplied')) return _toDouble(c['creditApplied']);
    return _toDouble(c['amount']);
  }

  void _applyFilter() {
    final q = _normKey(_searchCtrl.text);

    final list = rows.where((r) {
      final name = _normKey(r["shopName"]?.toString() ?? '');
      return q.isEmpty ? true : name.contains(q);
    }).toList();

    // Sort: biggest total first (cash/collection + credit sales)
    list.sort(
      (a, b) => (_cashCollection(b) + (b["creditSales"] as double)).compareTo(
        _cashCollection(a) + (a["creditSales"] as double),
      ),
    );

    setState(() => _filteredRows = list);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() => _selectedDate = picked);
    await _calculateShopSummary(forDate: _selectedDate);
  }

  void _changeDateByDays(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _calculateShopSummary(forDate: _selectedDate);
  }

  void _openDailySummary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DailySummaryScreen()),
    );
  }

  /// ✅ FOR SELECTED DATE:
  /// - Cash = invoice total where paymentType != Credit
  /// - Credit = invoice total where paymentType == Credit
  /// - Collection = collections (creditApplied/amount)
  Future<void> _calculateShopSummary({required DateTime forDate}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final invoiceStr = prefs.getString('invoice_history');
    final collectionStr = prefs.getString('collection_history');

    final List invoices = invoiceStr != null ? jsonDecode(invoiceStr) : [];
    final List collections = collectionStr != null
        ? jsonDecode(collectionStr)
        : [];

    final Map<String, Map<String, dynamic>> map = {};

    // Invoices for date
    for (final invAny in invoices) {
      if (invAny is! Map) continue;
      final inv = invAny.cast<String, dynamic>();

      final invDate = _parseDate(inv['date']);
      if (!_isSameDay(invDate, forDate)) continue;

      final shopKey = _normShop(inv['shopName']);
      if (shopKey.isEmpty) continue;

      map.putIfAbsent(shopKey, () {
        return {
          "shopKey": shopKey,
          "shopName": _prettyShop(inv['shopName']),
          "cash": 0.0,
          "creditSales": 0.0,
          "collection": 0.0,
        };
      });

      final paymentType = (inv['paymentType']?.toString().trim() ?? '');
      final total = _toDouble(inv['total']);

      if (paymentType == 'Credit' || paymentType == 'Cheque') {
        map[shopKey]!["creditSales"] =
            (map[shopKey]!["creditSales"] as double) + total;
      } else {
        map[shopKey]!["cash"] = (map[shopKey]!["cash"] as double) + total;
      }
    }

    // Collections for date (repayments)
    for (final cAny in collections) {
      if (cAny is! Map) continue;
      final c = cAny.cast<String, dynamic>();

      final colDate = _parseDate(c['date']);
      if (!_isSameDay(colDate, forDate)) continue;

      final shopKey = _normShop(c['shopName']);
      if (shopKey.isEmpty) continue;

      map.putIfAbsent(shopKey, () {
        return {
          "shopKey": shopKey,
          "shopName": _prettyShop(c['shopName']),
          "cash": 0.0,
          "creditSales": 0.0,
          "collection": 0.0,
        };
      });

      final applied = _getCreditApplied(c);
      map[shopKey]!["collection"] =
          (map[shopKey]!["collection"] as double) + applied;
    }

    final list = map.values.toList();

    double tCash = 0.0, tCredit = 0.0, tCol = 0.0;

    for (final r in list) {
      tCash += (r["cash"] as double);
      tCredit += (r["creditSales"] as double);
      tCol += (r["collection"] as double);
    }

    if (!mounted) return;
    setState(() {
      rows = list;
      totalCash = tCash;
      totalCreditSales = tCredit;
      totalCollection = tCol;
      _loading = false;
    });

    _applyFilter();
  }

  // ---------------- PRINT MODE ----------------
  Future<void> _printSalesSummary() async {
    if (_filteredRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No sales data available to print for this date'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final printerMac = prefs.getString('printer_mac');
    if (printerMac == null || printerMac.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please connect a printer first in Printer Settings'),
          behavior: SnackBarBehavior.floating,
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
            const SnackBar(
              content: Text('❌ Printer connection failed'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      const int w = 40;

      String line([String ch = '-']) => List.filled(w, ch).join();

      String center(String text) {
        text = text.trimRight();
        if (text.length >= w) return text;
        final left = ((w - text.length) / 2).floor();
        return text.padLeft(left + text.length);
      }

      String row4(String no, String shop, String cashCol, String credit) {
        String fit(String s, int len) {
          s = s.trim();
          if (s.length <= len) return s;
          if (len <= 1) return s.substring(0, len);
          return '${s.substring(0, len - 1)}.';
        }

        final cNo = fit(no, 3).padRight(3);
        final cShop = fit(shop, 13).padRight(13);
        final c2 = fit(cashCol, 12).padLeft(12);
        final c3 = fit(credit, 12).padLeft(12);
        return cNo + cShop + c2 + c3;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final timeStr = DateFormat('HH:mm').format(DateTime.now());

      final totalCashCol = totalCash + totalCollection;

      final buf = StringBuffer();
      buf.writeln(center('CHINTHAKA DISTRIBUTORS'));
      buf.writeln(center('SALES SUMMARY REPORT'));
      buf.writeln(center('Date: $dateStr   Time: $timeStr'));
      buf.writeln(line());
      buf.writeln(row4('No', 'Shop', 'Cash/Col', 'Credit'));
      buf.writeln(line());

      for (int i = 0; i < _filteredRows.length; i++) {
        final r = _filteredRows[i];
        final shop = r["shopName"]?.toString() ?? 'Unknown';
        final cashCol = _cashCollection(r);
        final credit = (r["creditSales"] as double);

        buf.writeln(
          row4(
            '${i + 1}.',
            shop,
            cashCol.toStringAsFixed(2),
            credit.toStringAsFixed(2),
          ),
        );
      }

      buf.writeln(line());
      buf.writeln(
        row4(
          '',
          'TOTAL',
          totalCashCol.toStringAsFixed(2),
          totalCreditSales.toStringAsFixed(2),
        ),
      );
      buf.writeln(line());
      buf.writeln(center('Thank you!'));
      buf.writeln('\n\n\n');

      await BluetoothService.printInvoice(buf.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🖨️ Sales Summary report printed successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get grandTotalRevenue => totalCash + totalCollection + totalCreditSales;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Sales Summary'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print Report',
            onPressed: _printSalesSummary,
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Daily History',
            onPressed: _openDailySummary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _calculateShopSummary(forDate: _selectedDate),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _calculateShopSummary(forDate: _selectedDate),
              child: CustomScrollView(
                slivers: [
                  // --- Date Navigation & Executive Dashboard ---
                  SliverToBoxAdapter(child: _buildHeaderDashboard()),

                  // --- Search & View Switcher ---
                  SliverToBoxAdapter(child: _buildControlsBar()),

                  // --- Data Content ---
                  _filteredRows.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          sliver: _isTableView
                              ? SliverToBoxAdapter(child: _buildTableView())
                              : SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (ctx, i) =>
                                        _buildShopSalesCard(_filteredRows[i], i),
                                    childCount: _filteredRows.length,
                                  ),
                                ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _printSalesSummary,
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.print),
        label: const Text(
          'Print Report',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ---------- UI Widgets ----------

  Widget _buildHeaderDashboard() {
    final isNarrow = MediaQuery.of(context).size.width < 380;
    final dateFormatted = DateFormat(
      isNarrow ? 'EEE, MMM dd, yyyy' : 'EEEE, MMM dd, yyyy',
    ).format(_selectedDate);
    final totalCashCol = totalCash + totalCollection;

    return Container(
      margin: EdgeInsets.all(isNarrow ? 10 : 14),
      padding: EdgeInsets.all(isNarrow ? 12 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.indigo.shade900,
            Colors.indigo.shade700,
            Colors.blue.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Date selector row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white70,
                  size: 18,
                ),
                onPressed: () => _changeDateByDays(-1),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          dateFormatted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isNarrow ? 13 : 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 18,
                ),
                onPressed: () => _changeDateByDays(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),

          // Total Daily Sales
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'TOTAL DAILY REVENUE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatLkr(grandTotalRevenue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Cash vs Credit breakdown cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            color: Colors.lightGreenAccent,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Cash & Collection',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatLkr(totalCashCol),
                          style: const TextStyle(
                            color: Colors.lightGreenAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.credit_score,
                            color: Colors.amberAccent,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Credit Issued',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatLkr(totalCreditSales),
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlsBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _applyFilter(),
                decoration: InputDecoration(
                  hintText: 'Search shop in summary...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _applyFilter();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _isTableView ? Icons.grid_view_rounded : Icons.table_chart_rounded,
                color: Colors.indigo,
              ),
              tooltip: _isTableView ? 'Switch to Cards' : 'Switch to Table',
              onPressed: () => setState(() => _isTableView = !_isTableView),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableView() {
    final totalCashCol = totalCash + totalCollection;

    final headerBg = Colors.indigo.shade800;
    final zebraA = Colors.white;
    final zebraB = Colors.indigo.shade50.withValues(alpha: 0.3);
    final totalBg = Colors.indigo.shade100;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          _narrowTable = narrow;
          // Fit the screen; only scroll horizontally on very small widths.
          final tableWidth =
              constraints.maxWidth < 340 ? 340.0 : constraints.maxWidth;
          return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Table(
              columnWidths: {
                0: FixedColumnWidth(narrow ? 30 : 50),
                1: const FlexColumnWidth(1.4),
                2: const FlexColumnWidth(1.3),
                3: const FlexColumnWidth(1.3),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // Header Row
                TableRow(
                  decoration: BoxDecoration(color: headerBg),
                  children: [
                    _cell('#', header: true, color: Colors.white),
                    _cell('Shop Name', header: true, color: Colors.white),
                    _cell(
                      narrow ? 'Cash/Col' : 'Cash & Collection',
                      header: true,
                      right: true,
                      color: Colors.white,
                    ),
                    _cell(
                      narrow ? 'Credit' : 'Credit Issued',
                      header: true,
                      right: true,
                      color: Colors.white,
                    ),
                  ],
                ),
                // Rows
                ...List.generate(_filteredRows.length, (i) {
                  final r = _filteredRows[i];
                  final shop = r["shopName"]?.toString() ?? 'Unknown';
                  final cashCol = _cashCollection(r);
                  final credit = (r["creditSales"] as double);
                  final bg = (i % 2 == 0) ? zebraA : zebraB;

                  return TableRow(
                    decoration: BoxDecoration(color: bg),
                    children: [
                      _cell('${i + 1}'),
                      _cell(shop, bold: true),
                      _cell(
                        _formatAmt(cashCol),
                        right: true,
                        color: Colors.teal.shade800,
                      ),
                      _cell(
                        _formatAmt(credit),
                        right: true,
                        bold: credit > 0,
                        color: credit > 0
                            ? Colors.red.shade700
                            : Colors.grey.shade600,
                      ),
                    ],
                  );
                }),
                // Total Summary Row
                TableRow(
                  decoration: BoxDecoration(color: totalBg),
                  children: [
                    _cell('', header: true),
                    _cell('TOTAL', header: true, bold: true),
                    _cell(
                      _formatAmt(totalCashCol),
                      header: true,
                      right: true,
                      color: Colors.teal.shade900,
                    ),
                    _cell(
                      _formatAmt(totalCreditSales),
                      header: true,
                      right: true,
                      color: Colors.red.shade900,
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
    );
  }

  bool _narrowTable = false;

  /// Drops the "LKR" prefix in narrow tables to save space.
  String _formatAmt(double v) =>
      _narrowTable ? _currencyFormat.format(v) : _formatLkr(v);

  Widget _cell(
    String text, {
    bool header = false,
    bool right = false,
    bool bold = false,
    Color? color,
  }) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontWeight: header || bold ? FontWeight.bold : FontWeight.normal,
        fontSize: _narrowTable ? 12 : 13,
        color: color ?? Colors.black87,
      ),
      maxLines: 1,
      overflow: right ? TextOverflow.visible : TextOverflow.ellipsis,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _narrowTable ? 6 : 10,
        vertical: 12,
      ),
      child: Align(
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        // Amounts scale down instead of being cut off.
        child: right
            ? FittedBox(fit: BoxFit.scaleDown, child: textWidget)
            : textWidget,
      ),
    );
  }

  Widget _buildShopSalesCard(Map<String, dynamic> r, int index) {
    final shop = r["shopName"]?.toString() ?? 'Unknown';
    final cashCol = _cashCollection(r);
    final credit = (r["creditSales"] as double);
    final totalShopRevenue = cashCol + credit;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.indigo.shade100,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shop,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatLkr(totalShopRevenue),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 14,
                    color: Colors.teal,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Cash & Col: ${_formatLkr(cashCol)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.credit_score,
                    size: 14,
                    color: credit > 0 ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Credit: ${_formatLkr(credit)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: credit > 0 ? Colors.red.shade700 : Colors.grey,
                      fontWeight: credit > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final dateStr = DateFormat('MMM dd, yyyy').format(_selectedDate);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: Colors.indigo.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Sales Data for $dateStr',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No invoices or collection records were logged on this date.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _selectedDate = DateTime.now());
                _calculateShopSummary(forDate: _selectedDate);
              },
              icon: const Icon(Icons.today),
              label: const Text('Go to Today'),
            ),
          ],
        ),
      ),
    );
  }
}
