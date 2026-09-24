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

  // ✅ Includes ShopDetailScreen "collection_history" totals
  double totalCreditCollection = 0.0;

  double todayCashSale = 0.0;
  double totalCashValue = 0.0;

  // Optional breakdown
  double _creditCollectionFromInvoices = 0.0;
  double _creditCollectionFromShopCollections = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDailySummary();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// ✅ Sum collections recorded via ShopDetailScreen (collection_history) for selected date
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
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString('invoice_history');
    final List invoices = data != null ? jsonDecode(data) : [];

    final Map<String, Map<String, dynamic>> itemMap = {};
    double soldTotal = 0.0;

    double previousCreditCollection = 0.0;
    double dailyCashCollection = 0.0;

    final collectionsFromHistory = await _getCollectionsTotalForSelectedDate();

    final todayKey = DateFormat('yyyy-MM-dd').format(selectedDate);

    for (var inv in invoices) {
      final dateStr = inv['date'] ?? '';
      if (!dateStr.toString().contains(todayKey)) continue;

      final items = inv['items'] as List?;
      if (items == null) continue;

      final paymentType = inv['paymentType'] ?? '';

      final todayPart =
          double.tryParse(inv['collection_today']?.toString() ?? '0') ?? 0.0;
      final prevPart =
          double.tryParse(inv['collection_previous']?.toString() ?? '0') ?? 0.0;
      final collection =
          double.tryParse(inv['collection']?.toString() ?? '0') ?? 0.0;

      // ✅ Daily cash bill
      if (todayPart > 0) {
        dailyCashCollection += todayPart;
      } else if (paymentType == 'Cash' && collection > 0) {
        dailyCashCollection += collection;
      }

      // ✅ Old credit recovered from invoice fields (legacy)
      if (prevPart > 0) {
        previousCreditCollection += prevPart;
      }

      // 🧾 Items
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

    // saved inv qty per day
    final todayKeyStorage = DateFormat('yyyy-MM-dd').format(selectedDate);
    final savedInvQtyJson = prefs.getString('inv_qty_$todayKeyStorage');
    Map<String, dynamic> savedInvQty = {};
    if (savedInvQtyJson != null) {
      savedInvQty = jsonDecode(savedInvQtyJson);
    }

    // live stock (optional)
    final productsStr = prefs.getString('products');
    Map<String, dynamic> liveStock = {};
    if (productsStr != null) {
      final List products = jsonDecode(productsStr);
      for (var p in products) {
        liveStock[p['name']] = p['stock'];
      }
    }

    final finalCreditCollection =
        previousCreditCollection + collectionsFromHistory;

    setState(() {
      summaryData = itemMap.values.toList();
      for (var item in summaryData) {
        final name = item['name'];
        final invQty = savedInvQty[name] ?? 0;
        item['invQty'] = invQty;

        // ✅ balanceQty
        item['balanceQty'] = liveStock[name] ?? (invQty - item['soldQty']);
      }

      totalSoldValue = soldTotal;

      _creditCollectionFromInvoices = previousCreditCollection;
      _creditCollectionFromShopCollections = collectionsFromHistory;

      totalCreditCollection = finalCreditCollection;

      todayCashSale = dailyCashCollection;
      totalCashValue = todayCashSale + totalCreditCollection;

      _loading = false;
    });

    // controllers
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

  // -------------------- 80mm Print helpers --------------------
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

  /// 🖨 Print summary (80mm) ✅ includes Bal Qty
  Future<void> _printSummary() async {
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

      // 80mm layout
      const itemW = 16; // item name width
      const invW = 4;
      const soldW = 4;
      const balW = 4;
      const totalW = 10; // money width

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
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Printer error: $e')));
    }
  }

  Color _balanceColor(int balance) {
    if (balance < 0) return Colors.redAccent;
    if (balance > 0) return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM dd, yyyy').format(selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          ),
          IconButton(icon: const Icon(Icons.print), onPressed: _printSummary),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date: $dateLabel',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Header Row
                  Container(
                    color: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 2, child: Text('Item')),
                        Expanded(child: Text('Inv Qty')),
                        Expanded(child: Text('Sold Qty')),
                        Expanded(child: Text('Bal Qty')),
                        Expanded(child: Text('Sold Price')),
                      ],
                    ),
                  ),
                  const Divider(),

                  // Item Rows
                  Expanded(
                    child: ListView.builder(
                      itemCount: summaryData.length,
                      itemBuilder: (ctx, i) {
                        final item = summaryData[i];
                        final controller = invQtyControllers[item['name']]!;
                        final bal = item['balanceQty'] ?? 0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(item['name'])),
                              Expanded(
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
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.all(6),
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        item['invQty'] = int.tryParse(val) ?? 0;
                                        item['balanceQty'] =
                                            item['invQty'] - item['soldQty'];
                                      });
                                      _saveInvQtyData();
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item['soldQty'].toString(),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  bal.toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _balanceColor(bal),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  (item['soldValue'] as double).toStringAsFixed(
                                    2,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(thickness: 1.2),
                  const SizedBox(height: 8),

                  Text(
                    'Total Sold Value: LKR ${totalSoldValue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Credit Bill Collection: LKR ${totalCreditCollection.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Daily Cash Bill: LKR ${todayCashSale.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '💰 Total Cash Value: LKR ${totalCashValue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Print Daily Summary'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(45),
                      backgroundColor: Colors.blueAccent,
                    ),
                    onPressed: _printSummary,
                  ),
                ],
              ),
            ),
    );
  }
}
