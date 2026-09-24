import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kot_app/screens/add_product_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/product.dart';
import '../services/bluetooth_service.dart';
import 'printer_settings_screen.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final TextEditingController _shopCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '');

  Product? selectedProduct;
  List<Product> allProducts = [];
  List<Product> invoiceItems = [];

  List<String> allShops = [];
  Map<String, double> _creditCache = {};
  double _previousCredit = 0.0; // must match ShopDetail currentBalance

  bool includeBalanceBF = true; // checkbox for print only

  // ---------- helpers ----------
  String _normKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  double _toDouble(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadShopsAndCredits();
  }

  Future<void> _loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('products');
    if (saved != null) {
      final List decoded = jsonDecode(saved);
      setState(() {
        allProducts = decoded.map((p) => Product.fromJson(p)).toList();
      });
    }
  }

  /// ✅ Compute CREDIT BALANCE exactly like ShopDetailScreen:
  /// creditIssued = opening + sum(credit invoice totals)
  /// creditPaid   = sum(creditApplied)  (fallback to amount if old records)
  /// balance      = max(0, creditIssued - creditPaid)
  Future<double> _computeShopCreditBalance(String shopName) async {
    final prefs = await SharedPreferences.getInstance();
    final shopKey = _normKey(shopName);

    // 1) opening balance
    double opening = 0.0;
    final openStr = prefs.getString('shop_opening_balances');
    if (openStr != null && openStr.isNotEmpty) {
      final Map<String, dynamic> openMap = jsonDecode(openStr);
      opening = _toDouble(openMap[shopKey]);
      if (opening < 0) opening = 0.0;
    }

    // 2) total credit invoices
    double creditInvoiceTotal = 0.0;
    final invStr = prefs.getString('invoice_history');
    if (invStr != null && invStr.isNotEmpty) {
      final List all = jsonDecode(invStr);
      for (final invAny in all) {
        if (invAny is! Map) continue;
        final inv = invAny.cast<String, dynamic>();
        final invShop = _normKey(inv['shopName']?.toString() ?? '');
        if (invShop != shopKey) continue;

        final payType = (inv['paymentType']?.toString().trim() ?? '');
        if (payType == 'Credit') {
          final t = _toDouble(inv['total']);
          if (t > 0) creditInvoiceTotal += t;
        }
      }
    }

    // 3) total credit applied (ONLY this reduces credit balance)
    double creditPaid = 0.0;
    final colStr = prefs.getString('collection_history');
    if (colStr != null && colStr.isNotEmpty) {
      final List cols = jsonDecode(colStr);
      for (final cAny in cols) {
        if (cAny is! Map) continue;
        final c = cAny.cast<String, dynamic>();
        final cShop = _normKey(c['shopName']?.toString() ?? '');
        if (cShop != shopKey) continue;

        // ✅ use creditApplied if exists, else fallback to amount (old data)
        final applied = c.containsKey('creditApplied')
            ? _toDouble(c['creditApplied'])
            : _toDouble(c['amount']);

        if (applied > 0) creditPaid += applied;
      }
    }

    final issued = _round2(opening + creditInvoiceTotal);
    final paid = _round2(creditPaid);
    final bal = _round2((issued - paid) < 0 ? 0.0 : (issued - paid));
    return bal;
  }

  Future<void> _loadShopsAndCredits() async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, double> creditMap = {};
    final Set<String> names = {};

    // shops from cache + history
    final creditsStr = prefs.getString('shop_credits');
    if (creditsStr != null) {
      final Map<String, dynamic> decoded = jsonDecode(creditsStr);
      decoded.forEach((k, v) {
        names.add(k.trim());
      });
    }

    final hist = prefs.getString('invoice_history');
    if (hist != null) {
      final List list = jsonDecode(hist);
      for (var inv in list) {
        final n = (inv['shopName'] ?? '').toString().trim();
        if (n.isNotEmpty) names.add(n);
      }
    }

    // ✅ compute balances for each shop so InvoiceScreen matches ShopDetail always
    final shopList = names.toList()..sort();
    for (final s in shopList) {
      creditMap[_normKey(s)] = await _computeShopCreditBalance(s);
    }

    if (!mounted) return;
    setState(() {
      _creditCache = creditMap;
      allShops = shopList;
    });
  }

  Future<void> _onShopSelected(String shop) async {
    final credit = await _computeShopCreditBalance(
      shop,
    ); // ✅ matches ShopDetail
    if (!mounted) return;
    setState(() => _previousCredit = credit);
  }

  void _addToInvoice() {
    if (selectedProduct == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a product')));
      return;
    }

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter valid quantity')));
      return;
    }

    final idx = invoiceItems.indexWhere(
      (it) => it.name == selectedProduct!.name,
    );
    if (idx != -1) {
      setState(() => invoiceItems[idx].qty += qty);
    } else {
      setState(() {
        invoiceItems.add(
          Product(
            id: selectedProduct!.id,
            name: selectedProduct!.name,
            price: selectedProduct!.price,
            qty: qty,
          ),
        );
      });
    }

    _qtyCtrl.clear();
  }

  double get subtotal => invoiceItems.fold(0.0, (s, p) => s + p.price * p.qty);

  // display/print only
  double get grandTotal => _round2(subtotal + _previousCredit);

  void _editItem(Product product) {
    final qtyCtrl = TextEditingController(text: product.qty.toString());
    final priceCtrl = TextEditingController(text: product.price.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Unit Price (LKR)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = int.tryParse(qtyCtrl.text.trim()) ?? product.qty;
              final newPrice =
                  double.tryParse(priceCtrl.text.trim()) ?? product.price;
              setState(() {
                product.qty = newQty;
                product.price = newPrice;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _printInvoice() async {
    if (invoiceItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one item')));
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
            const SnackBar(content: Text('Failed to connect to printer')),
          );
          return;
        }
      }

      const int lineWidth = 40;

      String centerText(String text) {
        text = text.trimRight();
        if (text.length >= lineWidth) return text;
        final left = ((lineWidth - text.length) / 2).floor();
        return text.padLeft(left + text.length);
      }

      String line(String ch) => List.filled(lineWidth, ch).join();

      final shopName = _shopCtrl.text.trim().isEmpty
          ? 'Unknown Shop'
          : _shopCtrl.text.trim();
      final date = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      final buf = StringBuffer();

      buf.writeln(centerText('           CHINTHAKA DISTRIBUTORS'));
      buf.writeln(centerText('       380/3 Pahala Imbulgoda, Imbulgoda'));
      buf.writeln(centerText('            0779531855 / 0759284569'));
      buf.writeln(line('-'));

      buf.writeln(centerText(' SHOP:  ${shopName.toUpperCase()}'));
      buf.writeln(centerText(' DATE: $date'));
      buf.writeln(line('-'));

      final header = ' ITEM           U.PRICE    QTY   TOTAL';
      buf.writeln(centerText(header));
      buf.writeln(line('-'));

      for (var p in invoiceItems) {
        final name = p.name.length > 12 ? p.name.substring(0, 12) : p.name;

        final nameCol = name.padRight(12);
        final unitCol = p.price.toStringAsFixed(2).padLeft(7);
        final qtyCol = p.qty.toString().padLeft(4);
        final totalCol = (p.price * p.qty).toStringAsFixed(2).padLeft(7);

        final row = '$nameCol $unitCol $qtyCol $totalCol';
        buf.writeln(centerText(row));
      }

      buf.writeln(line('-'));
      buf.writeln(centerText('Sub Total:  LKR ${subtotal.toStringAsFixed(2)}'));

      if (includeBalanceBF) {
        buf.writeln(
          centerText(
            'Credit Balance: LKR ${_previousCredit.toStringAsFixed(2)}',
          ),
        );
      }

      buf.writeln(
        centerText('New Balance: LKR ${grandTotal.toStringAsFixed(2)}'),
      );
      buf.writeln(line('-'));
      buf.writeln(centerText('Thank you!'));
      buf.writeln('\n');

      final List<int> bytes = [];
      bytes.addAll([27, 64]);
      bytes.addAll([29, 33, 0]);
      bytes.addAll(utf8.encode(buf.toString()));
      bytes.addAll([29, 33, 0]);
      bytes.addAll(utf8.encode('\n\n\n'));

      await PrintBluetoothThermal.writeBytes(bytes);

      await _showPaymentPopup(shopName, date);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Printer error: $e')));
    }
  }

  Future<void> _showPaymentPopup(String shop, String date) async {
    String paymentType = 'Cash';
    final amountCtrl = TextEditingController(
      text: grandTotal.toStringAsFixed(2),
    );
    bool payToday = true;
    bool payPrevious = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('💰 Select Payment Method'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChoiceChip(
                    label: const Text('Cash'),
                    selected: paymentType == 'Cash',
                    onSelected: (_) {
                      setSt(() {
                        paymentType = 'Cash';
                        amountCtrl.text = _calcSelectedTotal(
                          payToday,
                          payPrevious,
                        ).toStringAsFixed(2);
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Cheque'),
                    selected: paymentType == 'Cheque',
                    onSelected: (_) {
                      setSt(() {
                        paymentType = 'Cheque';
                        amountCtrl.text = _calcSelectedTotal(
                          payToday,
                          payPrevious,
                        ).toStringAsFixed(2);
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Credit'),
                    selected: paymentType == 'Credit',
                    onSelected: (_) {
                      setSt(() {
                        paymentType = 'Credit';
                        payToday = false;
                        payPrevious = false;
                        amountCtrl.text = '0.00';
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              CheckboxListTile(
                title: Text(
                  'Today\'s Total (LKR ${subtotal.toStringAsFixed(2)})',
                ),
                value: payToday,
                onChanged: paymentType == 'Credit'
                    ? null
                    : (v) {
                        setSt(() => payToday = v!);
                        amountCtrl.text = _calcSelectedTotal(
                          payToday,
                          payPrevious,
                        ).toStringAsFixed(2);
                      },
              ),

              CheckboxListTile(
                title: Text(
                  'Credit Balance (LKR ${_previousCredit.toStringAsFixed(2)})',
                ),
                value: payPrevious,
                onChanged: paymentType == 'Credit'
                    ? null
                    : (v) {
                        setSt(() => payPrevious = v!);
                        amountCtrl.text = _calcSelectedTotal(
                          payToday,
                          payPrevious,
                        ).toStringAsFixed(2);
                      },
              ),

              const SizedBox(height: 10),

              CheckboxListTile(
                title: const Text('Include Credit Balance in Invoice'),
                value: includeBalanceBF,
                onChanged: (value) {
                  setState(() => includeBalanceBF = value ?? true);
                },
              ),

              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                enabled: paymentType != 'Credit',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Collection Amount (LKR)',
                  helperText: paymentType == 'Credit'
                      ? 'No collection for Credit.'
                      : 'Auto-calculated, editable if needed.',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    double collection = _toDouble(amountCtrl.text.trim());
    if (paymentType == 'Credit') collection = 0.0;
    if (collection < 0) collection = 0.0;
    if (collection > grandTotal) collection = grandTotal;

    await _saveInvoice(
      shop: shop,
      date: date,
      paymentType: paymentType,
      collection: _round2(collection),
      payToday: payToday,
      payPrevious: payPrevious,
    );
  }

  double _calcSelectedTotal(bool payToday, bool payPrevious) {
    double total = 0.0;
    if (payToday) total += subtotal;
    if (payPrevious) total += _previousCredit;
    return _round2(total);
  }

  /// ✅ Uses SHOP DETAIL credit balance (computed), not cache.
  /// ✅ Credit reduces only if payPrevious ticked (paidPrev stored in creditApplied)
  Future<void> _saveInvoice({
    required String shop,
    required String date,
    required String paymentType,
    required double collection,
    required bool payToday,
    required bool payPrevious,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _normKey(shop);

    // ✅ EXACT credit balance like ShopDetail
    final oldCredit = await _computeShopCreditBalance(shop);

    double remainingCash = collection;

    // only this part reduces credit balance
    double paidPrev = 0.0;
    if (payPrevious) {
      paidPrev = remainingCash > oldCredit ? oldCredit : remainingCash;
      remainingCash = _round2(remainingCash - paidPrev);
    }

    double paidToday = 0.0;
    if (payToday) {
      paidToday = remainingCash > subtotal ? subtotal : remainingCash;
      remainingCash = _round2(remainingCash - paidToday);
    }

    final unpaidToday = _round2(
      (subtotal - paidToday) < 0 ? 0.0 : (subtotal - paidToday),
    );

    // ✅ new credit = old credit - paidPrev + unpaidToday
    final newCredit = _round2(
      ((oldCredit - paidPrev) < 0 ? 0.0 : (oldCredit - paidPrev)) + unpaidToday,
    );

    final selectedTotal = _round2(
      (payToday ? subtotal : 0.0) + (payPrevious ? oldCredit : 0.0),
    );
    final advance = _round2(
      collection > selectedTotal ? (collection - selectedTotal) : 0.0,
    );

    // invoice_history
    final hist = prefs.getString('invoice_history');
    List<dynamic> invoices = hist != null ? jsonDecode(hist) : [];

    final bool isCreditInvoice = unpaidToday > 0 || paymentType == 'Credit';

    invoices.add({
      'shopName': shop,
      'date': date,
      'subtotal': subtotal.toStringAsFixed(2),
      'previousCredit': oldCredit.toStringAsFixed(2),
      'total': subtotal.toStringAsFixed(2),
      'paymentType': isCreditInvoice ? 'Credit' : paymentType,
      'paidMethod': paymentType,
      'paidToday': paidToday.toStringAsFixed(2),
      'paidPrevious': paidPrev.toStringAsFixed(2),
      'collection': collection.toStringAsFixed(2),
      'credit': unpaidToday.toStringAsFixed(2),
      'items': invoiceItems.map((p) => p.toJson()).toList(),
    });

    await prefs.setString('invoice_history', jsonEncode(invoices));

    // collection_history (only if cash/cheque)
    if (paymentType != 'Credit' && collection > 0) {
      final colStr = prefs.getString('collection_history');
      final List<dynamic> cols = colStr != null ? jsonDecode(colStr) : [];

      cols.add({
        "shopName": shop,
        "amount": collection,
        "creditApplied": _round2(
          paidPrev,
        ), // ✅ only this reduces credit balance
        "date": DateTime.now().toIso8601String(),
        "oldBalance": oldCredit,
        "newBalance": newCredit,
        "unapplied": advance,
      });

      await prefs.setString('collection_history', jsonEncode(cols));
    }

    // shop_credits cache update (so invoice screen + shop list will match)
    final creditsStr = prefs.getString('shop_credits');
    Map<String, dynamic> credits = creditsStr != null
        ? jsonDecode(creditsStr)
        : {};
    credits[key] = newCredit;
    await prefs.setString('shop_credits', jsonEncode(credits));

    _creditCache[key] = newCredit;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Saved ($paymentType). Credit Balance: LKR ${newCredit.toStringAsFixed(2)}',
        ),
      ),
    );

    setState(() {
      _shopCtrl.clear();
      invoiceItems.clear();
      _previousCredit = 0.0;
    });

    await _loadShopsAndCredits();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Invoice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.inventory),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddProductScreen()),
            ).then((_) => _loadProducts()),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Autocomplete<String>(
              optionsBuilder: (v) {
                if (v.text.isEmpty) return const Iterable<String>.empty();
                final q = v.text.toLowerCase();
                return allShops.where((s) => s.toLowerCase().contains(q));
              },
              onSelected: (shop) async {
                final upper = shop.toUpperCase();
                _shopCtrl.text = upper;
                await _onShopSelected(shop); // ✅ computed balance
              },
              fieldViewBuilder:
                  (ctx, controller, focusNode, onEditingComplete) {
                    controller.text = _shopCtrl.text;
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (t) async {
                        final upper = t.toUpperCase();
                        controller.value = controller.value.copyWith(
                          text: upper,
                          selection: TextSelection.collapsed(
                            offset: upper.length,
                          ),
                        );
                        _shopCtrl.text = upper;

                        if (upper.isNotEmpty) {
                          await _onShopSelected(upper); // ✅ computed balance
                        } else {
                          if (!mounted) return;
                          setState(() => _previousCredit = 0.0);
                        }
                      },
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'SHOP / CUSTOMER NAME',
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
            ),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Credit Balance: LKR ${_previousCredit.toStringAsFixed(2)}',
                style: TextStyle(
                  color: _previousCredit > 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<Product>(
              value: selectedProduct,
              items: allProducts
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        '${p.name} - LKR ${p.price.toStringAsFixed(2)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (p) => setState(() => selectedProduct = p),
              decoration: const InputDecoration(
                labelText: 'Select Product',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _addToInvoice,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ],
            ),

            const Divider(height: 30),
            Expanded(
              child: ListView.builder(
                itemCount: invoiceItems.length,
                itemBuilder: (_, i) {
                  final p = invoiceItems[i];
                  return Card(
                    child: ListTile(
                      title: Text('${p.name} × ${p.qty}'),
                      subtitle: Text('Unit: LKR ${p.price.toStringAsFixed(2)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editItem(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                setState(() => invoiceItems.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sub Total:  LKR ${subtotal.toStringAsFixed(2)}',
                  textAlign: TextAlign.end,
                ),
                Text(
                  'Credit Balance: LKR ${_previousCredit.toStringAsFixed(2)}',
                  textAlign: TextAlign.end,
                ),
                Text(
                  'New Balance: LKR ${grandTotal.toStringAsFixed(2)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _printInvoice,
              icon: const Icon(Icons.print),
              label: const Text('Print Invoice'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
