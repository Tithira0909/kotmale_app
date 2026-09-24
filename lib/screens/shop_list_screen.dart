import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shop_detail_screen.dart';

class ShopListScreen extends StatefulWidget {
  const ShopListScreen({super.key});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  List<String> allShops = [];
  List<String> filteredShops = [];
  Map<String, double> creditBalances = {}; // computed (>=0)
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadShopCredits();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  String _normKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  // ---------- opening balances ----------
  Future<Map<String, double>> _getOpeningBalances(
    SharedPreferences prefs,
  ) async {
    final s = prefs.getString('shop_opening_balances');
    if (s == null || s.isEmpty) return {};
    final Map<String, dynamic> decoded = jsonDecode(s);
    return decoded.map((k, v) => MapEntry(_normKey(k), _round2(_toDouble(v))));
  }

  Future<void> _setOpeningBalances(
    SharedPreferences prefs,
    Map<String, double> data,
  ) async {
    await prefs.setString('shop_opening_balances', jsonEncode(data));
  }

  /// ✅ MAIN: compute shop credit balance EXACTLY like ShopDetailScreen
  /// balance = (opening + sum(credit invoice totals)) - sum(creditApplied)
  /// NOTE: If old collection record doesn't have creditApplied, fallback to amount
  Future<double> _computeShopCreditBalance(
    SharedPreferences prefs,
    String shopKey,
  ) async {
    final openingMap = await _getOpeningBalances(prefs);
    double opening = _round2(openingMap[shopKey] ?? 0.0);
    if (opening < 0) opening = 0.0;

    // sum credit invoice totals
    double creditInvoiceTotal = 0.0;
    final invStr = prefs.getString('invoice_history');
    if (invStr != null && invStr.isNotEmpty) {
      final List decoded = jsonDecode(invStr);
      for (final invAny in decoded) {
        if (invAny is! Map) continue;
        final inv = invAny.cast<String, dynamic>();

        final k = _normKey(inv['shopName']?.toString() ?? '');
        if (k != shopKey) continue;

        final payType = inv['paymentType']?.toString().trim() ?? '';
        if (payType == 'Credit') {
          final t = _toDouble(inv['total']);
          if (t > 0) creditInvoiceTotal += t;
        }
      }
    }
    creditInvoiceTotal = _round2(creditInvoiceTotal);

    // sum creditApplied only (this reduces credit)
    double creditPaid = 0.0;
    final colStr = prefs.getString('collection_history');
    if (colStr != null && colStr.isNotEmpty) {
      final List decoded = jsonDecode(colStr);
      for (final cAny in decoded) {
        if (cAny is! Map) continue;
        final c = cAny.cast<String, dynamic>();

        final k = _normKey(c['shopName']?.toString() ?? '');
        if (k != shopKey) continue;

        // ✅ New records: creditApplied
        // ✅ Old records: fallback to amount (backward compatibility)
        final applied = c.containsKey('creditApplied')
            ? _toDouble(c['creditApplied'])
            : _toDouble(c['amount']);

        if (applied > 0) creditPaid += applied;
      }
    }
    creditPaid = _round2(creditPaid);

    final issued = _round2(opening + creditInvoiceTotal);
    final bal = _round2(
      (issued - creditPaid) < 0 ? 0.0 : (issued - creditPaid),
    );
    return bal;
  }

  /// ✅ Update shop_credits cache so other screens can use it
  Future<Map<String, double>> _rebuildShopCreditsCache(
    SharedPreferences prefs,
    Set<String> shopKeys,
  ) async {
    final Map<String, double> computed = {};

    for (final k in shopKeys) {
      computed[k] = await _computeShopCreditBalance(prefs, k);
    }

    await prefs.setString('shop_credits', jsonEncode(computed));
    return computed;
  }

  Future<void> _loadShopCredits() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final openingMap = await _getOpeningBalances(prefs);

    final invStr = prefs.getString('invoice_history');
    final colStr = prefs.getString('collection_history');

    final Set<String> shopKeys = {};

    // shops from invoices
    if (invStr != null && invStr.isNotEmpty) {
      final List decoded = jsonDecode(invStr);
      for (final invAny in decoded) {
        if (invAny is! Map) continue;
        final s = _normKey(invAny['shopName']?.toString() ?? '');
        if (s.isNotEmpty) shopKeys.add(s);
      }
    }

    // shops from collections
    if (colStr != null && colStr.isNotEmpty) {
      final List decoded = jsonDecode(colStr);
      for (final cAny in decoded) {
        if (cAny is! Map) continue;
        final s = _normKey(cAny['shopName']?.toString() ?? '');
        if (s.isNotEmpty) shopKeys.add(s);
      }
    }

    // shops from opening map (manual add)
    for (final k in openingMap.keys) {
      final s = _normKey(k);
      if (s.isNotEmpty) shopKeys.add(s);
    }

    // ✅ rebuild & cache correct credit values
    final computedCredits = await _rebuildShopCreditsCache(prefs, shopKeys);

    final sorted = shopKeys.toList()..sort();

    if (!mounted) return;
    setState(() {
      allShops = sorted;
      creditBalances = computedCredits;
      filteredShops = List.from(allShops);
      _loading = false;
    });
  }

  void _filterShops(String query) {
    query = _normKey(query);
    setState(() {
      filteredShops = allShops.where((s) => s.contains(query)).toList();
    });
  }

  Future<void> _clearAllShops() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Shop Data'),
        content: const Text(
          'This will permanently delete all shops, invoices, collections and balances.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('invoice_history');
    await prefs.remove('collection_history');
    await prefs.remove('shop_credits');
    await prefs.remove('shop_opening_balances');

    setState(() {
      allShops.clear();
      filteredShops.clear();
      creditBalances.clear();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('🧹 All shop data cleared')));
  }

  Future<void> _deleteShop(String shopKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Shop'),
        content: Text(
          'Delete shop "${shopKey.toUpperCase()}" and all its invoices, collections & balances?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final keyLower = _normKey(shopKey);

    // invoices
    final invStr = prefs.getString('invoice_history');
    if (invStr != null) {
      final List decoded = jsonDecode(invStr);
      final updated = decoded.where((invAny) {
        if (invAny is! Map) return true;
        final s = _normKey(invAny['shopName']?.toString() ?? '');
        return s != keyLower;
      }).toList();
      await prefs.setString('invoice_history', jsonEncode(updated));
    }

    // collections
    final colStr = prefs.getString('collection_history');
    if (colStr != null) {
      final List decoded = jsonDecode(colStr);
      final updated = decoded.where((cAny) {
        if (cAny is! Map) return true;
        final s = _normKey(cAny['shopName']?.toString() ?? '');
        return s != keyLower;
      }).toList();
      await prefs.setString('collection_history', jsonEncode(updated));
    }

    // opening balances
    final opening = await _getOpeningBalances(prefs);
    opening.remove(keyLower);
    await _setOpeningBalances(prefs, opening);

    // credits cache (will rebuild anyway)
    final creditsStr = prefs.getString('shop_credits');
    if (creditsStr != null) {
      final Map<String, dynamic> decoded = jsonDecode(creditsStr);
      decoded.remove(keyLower);
      await prefs.setString('shop_credits', jsonEncode(decoded));
    }

    await _loadShopCredits();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🗑️ Shop "${shopKey.toUpperCase()}" deleted')),
    );
  }

  Color _balanceColor(double bal) => bal > 0 ? Colors.red : Colors.green;

  String _balanceText(double bal) {
    if (bal > 0) return 'Credit: LKR ${bal.toStringAsFixed(2)}';
    return 'No outstanding balance';
  }

  /// ✅ Add/Edit shop + opening credit (previous balance)
  Future<void> _showAddEditShopDialog({String? existingShopKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final openingMap = await _getOpeningBalances(prefs);

    final nameCtrl = TextEditingController();
    final creditCtrl = TextEditingController(text: '0.00');

    if (existingShopKey != null) {
      final oldKey = _normKey(existingShopKey);
      nameCtrl.text = existingShopKey.toUpperCase();
      creditCtrl.text = (openingMap[oldKey] ?? 0.0).toStringAsFixed(2);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingShopKey == null ? 'Add New Shop' : 'Edit Shop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Shop name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: creditCtrl,
              decoration: const InputDecoration(
                labelText: 'Previous Credit Balance (LKR)',
                hintText: '0.00',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'This is the opening/previous balance.\nCollections will reduce it automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
    );

    if (ok != true) return;

    final rawName = nameCtrl.text.trim();
    if (rawName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop name cannot be empty')),
      );
      return;
    }

    final newKey = _normKey(rawName);
    double opening = _toDouble(creditCtrl.text.trim());
    if (opening < 0) opening = 0.0;
    opening = _round2(opening);

    // rename shopName in invoices/collections when editing
    if (existingShopKey != null) {
      final oldKey = _normKey(existingShopKey);

      final invStr = prefs.getString('invoice_history');
      if (invStr != null) {
        final List decoded = jsonDecode(invStr);
        for (final invAny in decoded) {
          if (invAny is! Map) continue;
          final inv = invAny.cast<String, dynamic>();
          final k = _normKey(inv['shopName']?.toString() ?? '');
          if (k == oldKey) inv['shopName'] = rawName;
        }
        await prefs.setString('invoice_history', jsonEncode(decoded));
      }

      final colStr = prefs.getString('collection_history');
      if (colStr != null) {
        final List decoded = jsonDecode(colStr);
        for (final cAny in decoded) {
          if (cAny is! Map) continue;
          final c = cAny.cast<String, dynamic>();
          final k = _normKey(c['shopName']?.toString() ?? '');
          if (k == oldKey) c['shopName'] = rawName;
        }
        await prefs.setString('collection_history', jsonEncode(decoded));
      }

      if (openingMap.containsKey(oldKey) || newKey != oldKey) {
        openingMap.remove(oldKey);
      }
    }

    // save opening balance
    if (opening > 0) {
      openingMap[newKey] = opening;
    } else {
      openingMap.remove(newKey);
    }
    await _setOpeningBalances(prefs, openingMap);

    await _loadShopCredits();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(existingShopKey == null ? 'Shop added' : 'Shop updated'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Credit List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            tooltip: 'Reload',
            onPressed: _loadShopCredits,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            tooltip: 'Clear All Data',
            onPressed: _clearAllShops,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search by shop name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _filterShops,
                  ),
                ),
                Expanded(
                  child: filteredShops.isEmpty
                      ? const Center(
                          child: Text(
                            'No shops found',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredShops.length,
                          itemBuilder: (ctx, i) {
                            final shopKey = filteredShops[i];
                            final balance =
                                creditBalances[_normKey(shopKey)] ?? 0.0;
                            final color = _balanceColor(balance);

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child: ListTile(
                                title: Text(
                                  shopKey.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(
                                  _balanceText(balance),
                                  style: TextStyle(color: color),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () => _deleteShop(shopKey),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 18,
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ShopDetailScreen(shopName: shopKey),
                                    ),
                                  );
                                  await _loadShopCredits();
                                },
                                onLongPress: () {
                                  _showAddEditShopDialog(
                                    existingShopKey: shopKey,
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditShopDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
