import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MonthlySummaryScreen extends StatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  State<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends State<MonthlySummaryScreen> {
  List<Map<String, dynamic>> productSummary = [];
  double totalSoldValue = 0.0;
  double totalCreditCollected = 0.0;
  bool _loading = true;
  DateTime selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadMonthlyData();
  }

  Future<void> _loadMonthlyData() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final invoiceData = prefs.getString('invoice_history');
    if (invoiceData == null) {
      setState(() => _loading = false);
      return;
    }

    final List invoices = jsonDecode(invoiceData);
    final monthKey = DateFormat('yyyy-MM').format(selectedMonth);

    final Map<String, Map<String, dynamic>> itemSummary = {};

    double soldValue = 0.0;
    double creditTotal = 0.0;

    for (var inv in invoices) {
      final dateStr = inv['date'] ?? '';
      if (!dateStr.toString().contains(monthKey)) continue;

      final items = inv['items'] as List?;
      if (items == null) continue;

      final paymentType = inv['paymentType'] ?? '';
      final collection =
          double.tryParse(inv['collection']?.toString() ?? '0') ?? 0.0;

      if (paymentType == 'Credit') {
        creditTotal += collection;
      }

      for (var item in items) {
        final name = item['name'];
        final qty = int.tryParse(item['qty'].toString()) ?? 0;
        final price = double.tryParse(item['price'].toString()) ?? 0.0;
        final total = qty * price;
        soldValue += total;

        if (!itemSummary.containsKey(name)) {
          itemSummary[name] = {
            'name': name,
            'received': 0,
            'sold': 0,
            'balance': 0,
            'totalPrice': 0.0,
          };
        }

        itemSummary[name]!['sold'] += qty;
        itemSummary[name]!['totalPrice'] += total;
      }
    }

    setState(() {
      productSummary = itemSummary.values.toList();
      totalSoldValue = soldValue;
      totalCreditCollected = creditTotal;
      _loading = false;
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2023, 1),
      lastDate: DateTime.now(),
      helpText: 'Select Month',
    );
    if (picked != null) {
      setState(() => selectedMonth = DateTime(picked.year, picked.month));
      _loadMonthlyData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
            tooltip: 'Select Month',
          ),
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
                    'Date: $monthLabel',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 🧾 Table Header
                  Container(
                    color: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: const Row(
                      children: [
                        Expanded(flex: 2, child: Text('Item')),
                        Expanded(child: Text('Recv Qty')),
                        Expanded(child: Text('Sold Qty')),
                        Expanded(child: Text('B/L Qty')),
                        Expanded(child: Text('Sold Price')),
                      ],
                    ),
                  ),
                  const Divider(),

                  // 🧩 Product rows
                  Expanded(
                    child: ListView.builder(
                      itemCount: productSummary.length,
                      itemBuilder: (ctx, i) {
                        final item = productSummary[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(item['name'])),
                              const Expanded(child: Text('-')), // recv qty
                              Expanded(
                                child: Text(
                                  item['sold'].toString(),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const Expanded(
                                child: Text('-', textAlign: TextAlign.center),
                              ),
                              Expanded(
                                child: Text(
                                  item['totalPrice'].toStringAsFixed(2),
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
                  const SizedBox(height: 10),

                  // Totals
                  Text(
                    'Total Sold Qty Price: LKR ${totalSoldValue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Credit Bill Collections: LKR ${totalCreditCollected.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
