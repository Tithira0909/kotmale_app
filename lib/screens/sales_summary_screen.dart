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

  // rows: { shopKey, shopName, cash, creditSales, collection }
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> _filteredRows = [];

  double totalCash = 0.0;
  double totalCreditSales = 0.0;
  double totalCollection = 0.0;

  // UI
  final TextEditingController _searchCtrl = TextEditingController();

  // date filter
  DateTime _selectedDate = DateTime.now();

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

  // ---------- helpers ----------
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

  String _money(double v) => 'LKR ${v.toStringAsFixed(2)}';

  // ✅ Cash/Collection column = cash sales + collections (repayments)
  double _cashCollection(Map<String, dynamic> r) =>
      (r["cash"] as double) + (r["collection"] as double);

  /// ✅ CREDIT COLLECTION only (repayments)
  double _getCreditApplied(Map<String, dynamic> c) {
    if (c.containsKey('creditApplied')) return _toDouble(c['creditApplied']);
    return _toDouble(c['amount']); // legacy fallback
  }

  void _applyFilter() {
    final q = _normKey(_searchCtrl.text);

    final list = rows.where((r) {
      final name = _normKey(r["shopName"]?.toString() ?? '');
      return q.isEmpty ? true : name.contains(q);
    }).toList();

    // sort: biggest total first (cash/collection + credit sales)
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
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final invoiceStr = prefs.getString('invoice_history');
    final collectionStr = prefs.getString('collection_history');

    final List invoices = invoiceStr != null ? jsonDecode(invoiceStr) : [];
    final List collections = collectionStr != null
        ? jsonDecode(collectionStr)
        : [];

    final Map<String, Map<String, dynamic>> map = {};

    // invoices for date
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

      if (paymentType == 'Credit') {
        map[shopKey]!["creditSales"] =
            (map[shopKey]!["creditSales"] as double) + total;
      } else {
        map[shopKey]!["cash"] = (map[shopKey]!["cash"] as double) + total;
      }
    }

    // collections for date (repayments)
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to print')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final printerMac = prefs.getString('printer_mac');
    if (printerMac == null || printerMac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Connect a printer first.')),
      );
      return;
    }

    try {
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        final ok = await BluetoothService.connect(printerMac);
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Printer connection failed')),
          );
          return;
        }
      }

      // 40 chars width (works with most 58mm/80mm libs)
      const int w = 40;

      String line([String ch = '-']) => List.filled(w, ch).join();

      String center(String text) {
        text = text.trimRight();
        if (text.length >= w) return text;
        final left = ((w - text.length) / 2).floor();
        return text.padLeft(left + text.length);
      }

      // columns: 3 + 13 + 12 + 12 = 40
      String row4(String no, String shop, String cashCol, String credit) {
        String fit(String s, int len) {
          s = s.trim();
          if (s.length <= len) return s;
          if (len <= 1) return s.substring(0, len);
          return s.substring(0, len - 1) + '.';
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
      buf.writeln(center('SALES SUMMARY'));
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
        const SnackBar(content: Text('🖨️ Sales Summary printed')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Printer error: $e')));
    }
  }

  // ---------------- UI TABLE (NICELY DESIGNED) ----------------
  Widget _cell(
    String text, {
    bool header = false,
    bool right = false,
    Color? bg,
    bool bold = false,
  }) {
    return Container(
      height: header ? 46 : 54,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      color: bg,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: header || bold ? FontWeight.w800 : FontWeight.w600,
          fontSize: header ? 13.5 : 13,
          color: header ? Colors.black : Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _niceTable() {
    final totalCashCol = totalCash + totalCollection;

    final headerBg = Colors.blueGrey.withOpacity(0.12);
    final zebraA = Colors.white;
    final zebraB = Colors.blueGrey.withOpacity(0.05);
    final totalBg = Colors.blueGrey.withOpacity(0.16);

    final border = TableBorder.all(
      color: Colors.black.withOpacity(0.55),
      width: 1,
    );

    final tableRows = <TableRow>[
      TableRow(
        children: [
          _cell('No', header: true, bg: headerBg),
          _cell('Shop Name', header: true, bg: headerBg),
          _cell('Cash / Collection', header: true, bg: headerBg, right: true),
          _cell('Credit payments', header: true, bg: headerBg, right: true),
        ],
      ),
      ...List.generate(_filteredRows.length, (i) {
        final r = _filteredRows[i];
        final shop = r["shopName"]?.toString() ?? 'Unknown';
        final cashCol = _cashCollection(r);
        final credit = (r["creditSales"] as double);
        final bg = (i % 2 == 0) ? zebraA : zebraB;

        return TableRow(
          children: [
            _cell('${i + 1}', bg: bg),
            _cell(shop, bg: bg),
            _cell(_money(cashCol), bg: bg, right: true),
            _cell(_money(credit), bg: bg, right: true, bold: credit > 0),
          ],
        );
      }),
      TableRow(
        children: [
          _cell('', header: true, bg: totalBg),
          _cell('TOTAL', header: true, bg: totalBg),
          _cell(_money(totalCashCol), header: true, bg: totalBg, right: true),
          _cell(
            _money(totalCreditSales),
            header: true,
            bg: totalBg,
            right: true,
          ),
        ],
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
          color: Colors.white,
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 760),
            child: Table(
              border: border,
              columnWidths: const {
                0: FixedColumnWidth(60), // No
                1: FlexColumnWidth(1.5), // Shop
                2: FlexColumnWidth(1.1), // Cash/Col
                3: FlexColumnWidth(1.1), // Credit
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: tableRows,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM dd, yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.green),
            tooltip: 'Print',
            onPressed: _printSalesSummary,
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _calculateShopSummary(forDate: _selectedDate),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Daily summary',
            onPressed: _openDailySummary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Date: $dateLabel',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          '${_filteredRows.length} shops',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => _applyFilter(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter();
                        },
                      ),
                      labelText: 'Search shop...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: _filteredRows.isEmpty
                        ? Center(
                            child: Text(
                              'No data found for $dateLabel',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _niceTable(),
                  ),

                  const SizedBox(height: 10),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Print Sales Summary'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(45),
                      backgroundColor: Colors.blueAccent,
                    ),
                    onPressed: _printSalesSummary,
                  ),
                ],
              ),
            ),
    );
  }
}
