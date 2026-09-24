import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import '../services/database_service.dart'; // optional (not used)

class InvoiceHistoryScreen extends StatefulWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  List<Map<String, dynamic>> invoices = [];
  List<Map<String, dynamic>> filteredInvoices = [];

  final _searchCtrl = TextEditingController();
  String _filterPayment = 'All';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  // -------- helpers --------
  String normalizeShopKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  DateTime _parseDate(dynamic v) {
    final s = v?.toString() ?? '';
    final d = DateTime.tryParse(s);
    return d ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  String _safePayType(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return 'Unknown';
    return s;
  }

  /// ✅ MIGRATE:
  /// - add shopKey if missing
  /// - normalize paymentType trim
  /// - add credit if missing (Credit => total, else 0)
  /// - clamp credit to >= 0
  Future<bool> _migrateInvoicesIfNeeded(
    SharedPreferences prefs,
    List<dynamic> allInvoicesRaw,
  ) async {
    bool changed = false;

    for (final invAny in allInvoicesRaw) {
      if (invAny is! Map) continue;

      final inv = invAny.cast<String, dynamic>();

      // normalize paymentType
      if (inv.containsKey('paymentType')) {
        final p = _safePayType(inv['paymentType']);
        if (inv['paymentType'] != p) {
          inv['paymentType'] = p;
          changed = true;
        }
      } else {
        inv['paymentType'] = 'Unknown';
        changed = true;
      }

      final payType = _safePayType(inv['paymentType']);

      // shopKey
      final existingKey = (inv['shopKey'] ?? '').toString().trim();
      if (existingKey.isEmpty) {
        final name = (inv['shopName'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          inv['shopKey'] = normalizeShopKey(name);
          changed = true;
        }
      }

      // credit (only if missing)
      if (!inv.containsKey('credit') || inv['credit'] == null) {
        inv['credit'] = payType == 'Credit'
            ? _round2(_toDouble(inv['total']))
            : 0.0;
        changed = true;
      }

      // clamp credit
      final c = _toDouble(inv['credit']);
      if (c < 0) {
        inv['credit'] = 0.0;
        changed = true;
      }
    }

    if (changed) {
      await prefs.setString('invoice_history', jsonEncode(allInvoicesRaw));
    }
    return changed;
  }

  Future<void> _loadInvoices() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('invoice_history');

      final List<dynamic> raw = data != null ? jsonDecode(data) : [];

      if (raw.isNotEmpty) {
        await _migrateInvoicesIfNeeded(prefs, raw);
      }

      final List<Map<String, dynamic>> local = raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      // latest first
      local.sort(
        (a, b) => _parseDate(b['date']).compareTo(_parseDate(a['date'])),
      );

      if (!mounted) return;
      setState(() {
        invoices = local;
        filteredInvoices = List.from(local);
      });

      _applyFilters();
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error loading invoices: $e');
      if (!mounted) return;
      setState(() {
        invoices = [];
        filteredInvoices = [];
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final search = _searchCtrl.text.toLowerCase().trim();

    if (!mounted) return;
    setState(() {
      filteredInvoices = invoices.where((inv) {
        final shop = (inv['shopName'] ?? '').toString().toLowerCase();
        final matchesShop = shop.contains(search);

        final payType = _safePayType(inv['paymentType']);
        final matchesPayment = _filterPayment == 'All'
            ? true
            : payType == _filterPayment;

        return matchesShop && matchesPayment;
      }).toList();
    });
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('invoice_history');

    if (!mounted) return;
    setState(() {
      invoices.clear();
      filteredInvoices.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🧹 All local history cleared')),
    );
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    final s = dateValue.toString();
    if (s.isEmpty) return '';
    try {
      final parsed = DateTime.tryParse(s);
      return parsed != null
          ? DateFormat('MMM dd, yyyy – hh:mm a').format(parsed)
          : s;
    } catch (_) {
      return s;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            tooltip: 'Reload invoices',
            onPressed: _loadInvoices,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            tooltip: 'Clear local history',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Confirm Delete'),
                  content: const Text('Clear all saved invoices locally?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Yes, Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true) _clearHistory();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // Search + Filter
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search by shop name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _applyFilters(),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _filterPayment,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                    DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                  ],
                  onChanged: (val) {
                    setState(() => _filterPayment = val ?? 'All');
                    _applyFilters();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredInvoices.isEmpty
                  ? const Center(
                      child: Text(
                        'No invoices found',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredInvoices.length,
                      itemBuilder: (ctx, i) {
                        final inv = filteredInvoices[i];

                        final payType = _safePayType(inv['paymentType']);
                        final isCredit = payType == 'Credit';

                        final total = _toDouble(inv['total']);
                        final remainingCreditRaw = isCredit
                            ? _toDouble(inv['credit'])
                            : 0.0;

                        // ✅ never show negative
                        final safeRemaining = remainingCreditRaw < 0
                            ? 0.0
                            : remainingCreditRaw;

                        final cleared = isCredit && safeRemaining <= 0;

                        final List itemsRaw = (inv['items'] is List)
                            ? (inv['items'] as List)
                            : const [];

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 2,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    (inv['shopName'] ?? 'Unknown').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  'LKR ${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDate(inv['date'])),
                                    Text(
                                      payType,
                                      style: TextStyle(
                                        color: isCredit
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isCredit)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      cleared
                                          ? '✅ Credit Cleared'
                                          : 'Remaining Credit: LKR ${safeRemaining.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: cleared
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            children: [
                              ...itemsRaw.map((itemAny) {
                                final item = (itemAny is Map)
                                    ? itemAny.cast<String, dynamic>()
                                    : <String, dynamic>{};

                                final name = (item['name'] ?? '').toString();
                                final qty = _toInt(item['qty']);
                                final price = _toDouble(item['price']);
                                final lineTotal = qty * price;

                                return ListTile(
                                  dense: true,
                                  title: Text(name),
                                  subtitle: Text(
                                    'Qty: $qty × LKR ${price.toStringAsFixed(2)}',
                                  ),
                                  trailing: Text(
                                    'LKR ${lineTotal.toStringAsFixed(2)}',
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
