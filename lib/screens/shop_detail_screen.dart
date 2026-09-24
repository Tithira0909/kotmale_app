import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/bluetooth_service.dart';

class ShopDetailScreen extends StatefulWidget {
  final String shopName;
  const ShopDetailScreen({super.key, required this.shopName});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  List<dynamic> shopInvoices = [];
  List<dynamic> collectionHistory = [];

  /// ✅ Credit Balance = (opening + credit invoices total) - (creditApplied total)
  double currentBalance = 0.0;

  bool _loading = true;

  int totalInvoices = 0;
  int paidInvoices = 0;
  int unpaidInvoices = 0;
  double totalOutstanding = 0.0;

  int totalCollections = 0;

  /// ✅ total cash received (report) = sum(amount)
  double totalCollected = 0.0;

  /// ✅ total applied to credit = sum(creditApplied)
  double totalCreditApplied = 0.0;

  /// ✅ cash advance (cash received but NOT applied to credit)
  double totalAdvance = 0.0;

  double openingRemaining = 0.0;

  @override
  void initState() {
    super.initState();
    _loadShopDetails();
  }

  // ---------- helpers ----------
  String _normKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  String get _shopKey => _normKey(widget.shopName);

  DateTime _parseDate(dynamic v) {
    final s = v?.toString() ?? '';
    final d = DateTime.tryParse(s);
    return d ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  bool _isCredit(dynamic invAny) {
    if (invAny is! Map) return false;
    return (invAny['paymentType']?.toString().trim() ?? '') == 'Credit';
  }

  bool _isThisShop(dynamic invAny) {
    if (invAny is! Map) return false;
    final invShop = _normKey(invAny['shopName']?.toString() ?? '');
    return invShop == _shopKey;
  }

  /// Read opening credit from ShopListScreen
  Future<double> _getOpeningBalance(SharedPreferences prefs) async {
    final openStr = prefs.getString('shop_opening_balances');
    if (openStr == null || openStr.isEmpty) return 0.0;

    final Map<String, dynamic> openMap = jsonDecode(openStr);
    final v = _toDouble(openMap[_shopKey]);
    return _round2(v < 0 ? 0.0 : v);
  }

  /// ✅ Applied-to-credit amount from a collection row (backward compatible)
  /// - new data: creditApplied
  /// - old data: fallback to amount
  double _getCreditApplied(Map<String, dynamic> c) {
    if (c.containsKey('creditApplied')) {
      return _round2(_toDouble(c['creditApplied']));
    }
    return _round2(_toDouble(c['amount']));
  }

  /// ✅ Cash advance = cash received - applied to credit
  double _cashAdvance(Map<String, dynamic> c) {
    final received = _toDouble(c['amount']);
    final applied = _getCreditApplied(c);
    final adv = received - applied;
    return _round2(adv > 0 ? adv : 0.0);
  }

  /// ✅ Rebuild invoice remaining credits using FIFO on CREDIT-APPLIED only
  Future<void> _rebuildCreditsFromHistory(SharedPreferences prefs) async {
    final invoiceStr = prefs.getString('invoice_history');
    if (invoiceStr == null) return;

    final collectionStr = prefs.getString('collection_history');

    final List<dynamic> allInvoices = jsonDecode(invoiceStr);
    final List<dynamic> allCollections = collectionStr != null
        ? jsonDecode(collectionStr)
        : [];

    final opening = await _getOpeningBalance(prefs);

    // 1) ledger (opening + credit invoices)
    final List<Map<String, dynamic>> creditLedger = [];

    if (opening > 0) {
      creditLedger.add({
        "_isOpening": true,
        "date": DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        "total": opening,
        "credit": opening,
        "creditPaid": 0.0,
      });
    }

    // reset invoice credits to full and add to ledger
    for (final invAny in allInvoices) {
      if (!_isThisShop(invAny)) continue;
      if (!_isCredit(invAny)) continue;

      final inv = (invAny as Map).cast<String, dynamic>();
      final total = _toDouble(inv['total']);
      inv['credit'] = _round2(total < 0 ? 0.0 : total);
      inv['creditPaid'] = 0.0;
      inv.remove('creditClearedAt');

      creditLedger.add(inv);
    }

    creditLedger.sort(
      (a, b) => _parseDate(a['date']).compareTo(_parseDate(b['date'])),
    );

    // 2) this shop collections FIFO (credit-applied only)
    final List<Map<String, dynamic>> shopCollections = [];
    for (final cAny in allCollections) {
      if (cAny is! Map) continue;
      final c = cAny.cast<String, dynamic>();
      final cShop = _normKey(c['shopName']?.toString() ?? '');
      if (cShop != _shopKey) continue;

      c['amount'] = _round2(_toDouble(c['amount']));
      if (c.containsKey('creditApplied')) {
        c['creditApplied'] = _round2(_toDouble(c['creditApplied']));
      }

      shopCollections.add(c);
    }

    shopCollections.sort(
      (a, b) => _parseDate(a['date']).compareTo(_parseDate(b['date'])),
    );

    // 3) apply FIFO using ONLY creditApplied
    double outstanding = 0.0;
    for (final row in creditLedger) {
      outstanding += _toDouble(row['credit']);
    }
    outstanding = _round2(outstanding < 0 ? 0.0 : outstanding);

    for (final col in shopCollections) {
      double remaining = _getCreditApplied(col);
      if (remaining < 0) remaining = 0.0;

      final oldBal = outstanding;

      for (final row in creditLedger) {
        if (remaining <= 0) break;

        double credit = _toDouble(row['credit']);
        if (credit <= 0) continue;

        final pay = remaining >= credit ? credit : remaining;

        credit -= pay;
        remaining -= pay;

        row['credit'] = _round2(credit < 0 ? 0.0 : credit);

        final alreadyPaid = _toDouble(row['creditPaid']);
        row['creditPaid'] = _round2(alreadyPaid + pay);

        if (_toDouble(row['credit']) == 0) {
          row['creditClearedAt'] =
              col['date'] ?? DateTime.now().toIso8601String();
        }
      }

      // recompute outstanding
      double newBal = 0.0;
      for (final row in creditLedger) {
        newBal += _toDouble(row['credit']);
      }
      newBal = _round2(newBal < 0 ? 0.0 : newBal);

      col['oldBalance'] = _round2(oldBal);
      col['newBalance'] = _round2(newBal);

      outstanding = newBal;
    }

    await prefs.setString('invoice_history', jsonEncode(allInvoices));
    await prefs.setString('collection_history', jsonEncode(allCollections));

    // cache shop_credits as outstanding
    final creditData = prefs.getString('shop_credits');
    final Map<String, dynamic> credits = creditData != null
        ? jsonDecode(creditData)
        : {};
    credits[_shopKey] = outstanding;
    await prefs.setString('shop_credits', jsonEncode(credits));
  }

  /// ✅ load + compute UI lists + stats
  /// Credit Balance = (opening + sum(credit invoice totals)) - sum(creditApplied)
  Future<void> _loadShopDetails({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();

    await _rebuildCreditsFromHistory(prefs);

    final invoiceData = prefs.getString('invoice_history');
    final collectionData = prefs.getString('collection_history');
    final opening = await _getOpeningBalance(prefs);

    List invoices = [];
    List collections = [];

    // invoices (this shop)
    if (invoiceData != null) {
      final List decoded = jsonDecode(invoiceData);
      invoices = decoded.where((inv) => _isThisShop(inv)).toList();

      invoices.sort(
        (a, b) => _parseDate(a['date']).compareTo(_parseDate(b['date'])),
      );
    }

    // collections (this shop)
    if (collectionData != null) {
      final List decodedCollections = jsonDecode(collectionData);
      collections = decodedCollections.where((c) {
        if (c is! Map) return false;
        final cShop = _normKey(c['shopName']?.toString() ?? '');
        return cShop == _shopKey;
      }).toList();

      collections.sort(
        (a, b) => _parseDate(b['date']).compareTo(_parseDate(a['date'])),
      );
    }

    // ---------- FORMULA BALANCE ----------
    double creditInvoiceTotal = 0.0;
    for (final invAny in invoices) {
      final inv = (invAny as Map).cast<String, dynamic>();
      final payType = (inv['paymentType']?.toString().trim() ?? '');
      if (payType == 'Credit') {
        final t = _toDouble(inv['total']);
        creditInvoiceTotal += (t < 0 ? 0.0 : t);
      }
    }
    creditInvoiceTotal = _round2(creditInvoiceTotal);

    double receivedTotal = 0.0;
    double creditAppliedTotal = 0.0;
    double cashAdvanceTotal = 0.0;

    for (final cAny in collections) {
      final c = (cAny as Map).cast<String, dynamic>();
      final amt = _toDouble(c['amount']);
      receivedTotal += (amt < 0 ? 0.0 : amt);

      final applied = _getCreditApplied(c);
      creditAppliedTotal += (applied < 0 ? 0.0 : applied);

      cashAdvanceTotal += _cashAdvance(c);
    }

    receivedTotal = _round2(receivedTotal);
    creditAppliedTotal = _round2(creditAppliedTotal);
    cashAdvanceTotal = _round2(cashAdvanceTotal);

    final totalCreditIssued = _round2(opening + creditInvoiceTotal);

    final computedBalance = _round2(
      (totalCreditIssued - creditAppliedTotal) < 0
          ? 0.0
          : (totalCreditIssued - creditAppliedTotal),
    );

    // opening remaining (paid first by creditApplied)
    final openRem = _round2(
      (opening - creditAppliedTotal) < 0 ? 0.0 : (opening - creditAppliedTotal),
    );

    // update cache so ShopListScreen matches
    final creditData = prefs.getString('shop_credits');
    final Map<String, dynamic> credits = creditData != null
        ? jsonDecode(creditData)
        : {};
    credits[_shopKey] = computedBalance;
    await prefs.setString('shop_credits', jsonEncode(credits));

    // ---------- invoice running balances for display ----------
    double runningOutstanding = openRem;
    for (final invAny in invoices) {
      final inv = (invAny as Map).cast<String, dynamic>();
      final isCredit =
          (inv['paymentType']?.toString().trim() ?? '') == 'Credit';
      final creditRemain = isCredit ? _toDouble(inv['credit']) : 0.0;
      runningOutstanding += (creditRemain < 0 ? 0.0 : creditRemain);
      inv['_balanceAfter'] = _round2(runningOutstanding);
    }

    invoices = invoices.reversed.toList();

    // stats
    int total = invoices.length;
    int paid = 0;
    int unpaid = 0;

    for (final invAny in invoices) {
      final inv = (invAny as Map).cast<String, dynamic>();
      final payType = (inv['paymentType']?.toString().trim() ?? '');
      if (payType == 'Credit') {
        final safe = _toDouble(inv['credit']);
        if (safe > 0) {
          unpaid++;
        } else {
          paid++;
        }
      } else {
        paid++;
      }
    }

    if (!mounted) return;
    setState(() {
      shopInvoices = invoices;
      collectionHistory = collections;

      currentBalance = computedBalance;
      totalOutstanding = computedBalance;

      openingRemaining = openRem;

      totalInvoices = total;
      paidInvoices = paid;
      unpaidInvoices = unpaid;

      totalCollections = collections.length;

      totalCollected = receivedTotal;
      totalCreditApplied = creditAppliedTotal;
      totalAdvance = cashAdvanceTotal;

      _loading = false;
    });
  }

  /// ✅ Collect payment directly against CREDIT BALANCE
  /// Here: creditApplied == applied (capped), amount == cash received
  Future<void> _collectPayment() async {
    final controller = TextEditingController(
      text: currentBalance.toStringAsFixed(2),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Collection (Pay Credit Balance)'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Enter amount received (LKR)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim()) ?? 0.0;
              Navigator.pop(ctx, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final paidAmount = _round2(result);
    if (paidAmount <= 0) return;

    final prefs = await SharedPreferences.getInstance();

    final oldBal = _round2(currentBalance < 0 ? 0.0 : currentBalance);

    final applied = _round2(paidAmount > oldBal ? oldBal : paidAmount);
    final newBal = _round2((oldBal - applied) < 0 ? 0.0 : (oldBal - applied));
    final cashAdv = _round2(
      paidAmount - applied > 0 ? paidAmount - applied : 0,
    );

    final collectionData = prefs.getString('collection_history');
    final List<dynamic> allCollections = collectionData != null
        ? jsonDecode(collectionData)
        : [];

    allCollections.add({
      "shopName": widget.shopName,
      "amount": paidAmount, // cash received
      "creditApplied": applied, // applied to credit
      "date": DateTime.now().toIso8601String(),
      "oldBalance": oldBal,
      "newBalance": newBal,
      "unapplied":
          cashAdv, // keep for backward display, but now equals cash advance
    });

    await prefs.setString('collection_history', jsonEncode(allCollections));

    final creditData = prefs.getString('shop_credits');
    final Map<String, dynamic> credits = creditData != null
        ? jsonDecode(creditData)
        : {};
    credits[_shopKey] = newBal;
    await prefs.setString('shop_credits', jsonEncode(credits));

    if (!mounted) return;
    setState(() {
      currentBalance = newBal;
    });

    await _loadShopDetails(showLoader: false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newBal == 0
              ? '✅ Collection saved! Credit balance cleared.'
              : '💵 Collection saved. New credit balance: LKR ${newBal.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  Future<void> _clearShopHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Shop History'),
        content: const Text(
          'This will remove all invoices, collections and balances for this shop.\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();

    final invoiceData = prefs.getString('invoice_history');
    if (invoiceData != null) {
      final List decoded = jsonDecode(invoiceData);
      final updated = decoded.where((inv) => !_isThisShop(inv)).toList();
      await prefs.setString('invoice_history', jsonEncode(updated));
    }

    final creditData = prefs.getString('shop_credits');
    if (creditData != null) {
      final Map<String, dynamic> decoded = jsonDecode(creditData);
      decoded.remove(_shopKey);
      await prefs.setString('shop_credits', jsonEncode(decoded));
    }

    final collectionData = prefs.getString('collection_history');
    if (collectionData != null) {
      final List decoded = jsonDecode(collectionData);
      final updated = decoded.where((c) {
        if (c is! Map) return true;
        final cShop = _normKey(c['shopName']?.toString() ?? '');
        return cShop != _shopKey;
      }).toList();
      await prefs.setString('collection_history', jsonEncode(updated));
    }

    if (!mounted) return;
    setState(() {
      shopInvoices.clear();
      collectionHistory.clear();
      currentBalance = 0.0;
      totalInvoices = 0;
      paidInvoices = 0;
      unpaidInvoices = 0;
      totalOutstanding = 0.0;
      totalCollections = 0;
      totalCollected = 0.0;
      totalCreditApplied = 0.0;
      totalAdvance = 0.0;
      openingRemaining = 0.0;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('🧹 Shop history cleared')));
  }

  Future<void> _printShopSummary() async {
    if (shopInvoices.isEmpty && collectionHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to print')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final printerMac = prefs.getString('printer_mac');
    if (printerMac == null || printerMac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect a printer first')),
      );
      return;
    }

    try {
      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        final ok = await BluetoothService.connect(printerMac);
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to Bluetooth printer'),
            ),
          );
          return;
        }
      }

      final buf = StringBuffer();
      buf.writeln('       Chinthaka Distributors');
      buf.writeln('   Shop Account Summary Report');
      buf.writeln('------------------------------------');
      buf.writeln('Shop: ${widget.shopName}');
      buf.writeln(
        'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
      );
      buf.writeln('------------------------------------');

      buf.writeln('Total Invoices: $totalInvoices');
      buf.writeln('Credit Balance: LKR ${currentBalance.toStringAsFixed(2)}');
      if (openingRemaining > 0) {
        buf.writeln(
          'Opening Remaining: LKR ${openingRemaining.toStringAsFixed(2)}',
        );
      }
      buf.writeln('Collections: $totalCollections');
      buf.writeln('Cash Received: LKR ${totalCollected.toStringAsFixed(2)}');
      buf.writeln(
        'Applied to Credit: LKR ${totalCreditApplied.toStringAsFixed(2)}',
      );
      if (totalAdvance > 0) {
        buf.writeln('Cash Advance: LKR ${totalAdvance.toStringAsFixed(2)}');
      }
      buf.writeln('------------------------------------');
      buf.writeln('Thank you!\n\n\n');

      await BluetoothService.printInvoice(buf.toString());

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('🖨️ Shop summary printed')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Printer error: $e')));
    }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    final dateStr = dateValue.toString();
    if (dateStr.isEmpty) return '';
    try {
      final parsed = DateTime.tryParse(dateStr);
      return parsed != null
          ? DateFormat('MMM dd, yyyy – hh:mm a').format(parsed)
          : dateStr;
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildInvoiceCard(dynamic invAny) {
    final inv = (invAny as Map).cast<String, dynamic>();

    final paymentType = inv['paymentType']?.toString().trim() ?? 'Unknown';
    final isCreditInv = paymentType == 'Credit';

    final remainingCreditRaw = isCreditInv ? _toDouble(inv['credit']) : 0.0;
    final remainingCredit = remainingCreditRaw < 0 ? 0.0 : remainingCreditRaw;

    final outstanding = isCreditInv && remainingCredit > 0;
    final dayBal = _toDouble(inv['_balanceAfter']);

    final List itemsRaw = (inv['items'] is List)
        ? (inv['items'] as List)
        : const [];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDate(inv['date']),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'LKR ${_toDouble(inv['total']).toStringAsFixed(2)}',
              style: TextStyle(
                color: outstanding ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Payment: $paymentType',
          style: TextStyle(color: outstanding ? Colors.red : Colors.green),
        ),
        children: [
          ...itemsRaw.map((itemAny) {
            final item = (itemAny is Map)
                ? itemAny.cast<String, dynamic>()
                : <String, dynamic>{};

            final name = item['name']?.toString() ?? '';
            final qty = _toDouble(item['qty']);
            final price = _toDouble(item['price']);
            final lineTotal = qty * price;

            return ListTile(
              dense: true,
              title: Text(name),
              subtitle: Text(
                'Qty: ${qty.toStringAsFixed(0)} × LKR ${price.toStringAsFixed(2)}',
              ),
              trailing: Text('LKR ${lineTotal.toStringAsFixed(2)}'),
            );
          }).toList(),
          Padding(
            padding: const EdgeInsets.only(
              bottom: 10,
              right: 16,
              left: 16,
              top: 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Day Balance: LKR ${dayBal.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
                if (isCreditInv)
                  Text(
                    remainingCredit > 0
                        ? 'Remaining Credit: LKR ${remainingCredit.toStringAsFixed(2)}'
                        : '✅ Cleared',
                    style: TextStyle(
                      color: remainingCredit > 0 ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shopTitle = widget.shopName.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(shopTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.green),
            onPressed: _printShopSummary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: _loadShopDetails,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            onPressed: _clearShopHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadShopDetails,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  const SizedBox(height: 10),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    elevation: 3,
                    color: Colors.blueGrey.shade50,
                    child: ListTile(
                      title: const Text(
                        'Current Credit Balance',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'LKR ${currentBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: currentBalance > 0
                              ? Colors.red
                              : Colors.green[800],
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: ElevatedButton.icon(
                        onPressed: _collectPayment,
                        icon: const Icon(Icons.payments),
                        label: const Text('Pay Credit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (openingRemaining > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Text(
                        'Opening Remaining: LKR ${openingRemaining.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (totalAdvance > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      'Collection History',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (collectionHistory.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          'No collections found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...collectionHistory.map((cAny) {
                      final c = (cAny as Map).cast<String, dynamic>();
                      final received = _toDouble(c['amount']);
                      final applied = _getCreditApplied(c);
                      final newBal = _toDouble(c['newBalance']);
                      final adv = _cashAdvance(c);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        elevation: 2,
                        child: ListTile(
                          leading: const Icon(
                            Icons.payments,
                            color: Colors.teal,
                          ),
                          title: Text(
                            'Received: LKR ${received.toStringAsFixed(2)}',
                          ),
                          subtitle: Text(
                            '${_formatDate(c['date'])}\nApplied to Credit: LKR ${applied.toStringAsFixed(2)}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Bal: ${newBal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (adv > 0)
                                Text(
                                  'Adv: ${adv.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      'Invoice History',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (shopInvoices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          'No invoices found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...shopInvoices.map(_buildInvoiceCard).toList(),
                ],
              ),
            ),
    );
  }
}
