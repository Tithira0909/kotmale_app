import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shop_detail_screen.dart';

enum ShopFilter { all, hasCredit, settled }

enum ShopSort { creditHighLow, nameAZ, creditLowHigh }

class ShopListScreen extends StatefulWidget {
  const ShopListScreen({super.key});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  List<String> allShops = [];
  List<String> filteredShops = [];
  Map<String, double> creditBalances = {}; // computed balance (>=0)
  Map<String, double> openingBalances = {}; // opening balance map
  bool _loading = true;

  ShopFilter _selectedFilter = ShopFilter.all;
  ShopSort _selectedSort = ShopSort.creditHighLow;
  final TextEditingController _searchCtrl = TextEditingController();

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

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

  // ---------- Helpers ----------
  String _normKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  String _formatLkr(double amount) {
    return 'LKR ${_currencyFormat.format(amount)}';
  }

  // ---------- Opening Balances ----------
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
  Future<double> _computeShopCreditBalance(
    SharedPreferences prefs,
    String shopKey,
  ) async {
    final openingMap = await _getOpeningBalances(prefs);
    double opening = _round2(openingMap[shopKey] ?? 0.0);
    if (opening < 0) opening = 0.0;

    // Sum credit invoice totals
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

    // Sum creditApplied only (this reduces credit balance)
    double creditPaid = 0.0;
    final colStr = prefs.getString('collection_history');
    if (colStr != null && colStr.isNotEmpty) {
      final List decoded = jsonDecode(colStr);
      for (final cAny in decoded) {
        if (cAny is! Map) continue;
        final c = cAny.cast<String, dynamic>();

        final k = _normKey(c['shopName']?.toString() ?? '');
        if (k != shopKey) continue;

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
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final openingMap = await _getOpeningBalances(prefs);

    final invStr = prefs.getString('invoice_history');
    final colStr = prefs.getString('collection_history');

    final Set<String> shopKeys = {};

    // Shops from invoices
    if (invStr != null && invStr.isNotEmpty) {
      final List decoded = jsonDecode(invStr);
      for (final invAny in decoded) {
        if (invAny is! Map) continue;
        final s = _normKey(invAny['shopName']?.toString() ?? '');
        if (s.isNotEmpty) shopKeys.add(s);
      }
    }

    // Shops from collections
    if (colStr != null && colStr.isNotEmpty) {
      final List decoded = jsonDecode(colStr);
      for (final cAny in decoded) {
        if (cAny is! Map) continue;
        final s = _normKey(cAny['shopName']?.toString() ?? '');
        if (s.isNotEmpty) shopKeys.add(s);
      }
    }

    // Shops from opening map
    for (final k in openingMap.keys) {
      final s = _normKey(k);
      if (s.isNotEmpty) shopKeys.add(s);
    }

    final computedCredits = await _rebuildShopCreditsCache(prefs, shopKeys);

    if (!mounted) return;
    setState(() {
      allShops = shopKeys.toList();
      creditBalances = computedCredits;
      openingBalances = openingMap;
      _applyFilterAndSort();
      _loading = false;
    });
  }

  void _applyFilterAndSort() {
    final query = _normKey(_searchCtrl.text);

    List<String> list = allShops.where((s) {
      final matchesQuery = query.isEmpty || _normKey(s).contains(query);
      final bal = creditBalances[_normKey(s)] ?? 0.0;

      if (!matchesQuery) return false;

      switch (_selectedFilter) {
        case ShopFilter.hasCredit:
          return bal > 0;
        case ShopFilter.settled:
          return bal == 0;
        case ShopFilter.all:
        default:
          return true;
      }
    }).toList();

    // Sort list
    list.sort((a, b) {
      final balA = creditBalances[_normKey(a)] ?? 0.0;
      final balB = creditBalances[_normKey(b)] ?? 0.0;

      switch (_selectedSort) {
        case ShopSort.creditHighLow:
          return balB.compareTo(balA);
        case ShopSort.creditLowHigh:
          return balA.compareTo(balB);
        case ShopSort.nameAZ:
          return a.compareTo(b);
      }
    });

    setState(() {
      filteredShops = list;
    });
  }

  Future<void> _clearAllShops() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Clear All Shop Data'),
          ],
        ),
        content: const Text(
          'This will permanently delete all shops, invoices, collections, and credit balances.\n\nAre you sure you want to proceed?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
      openingBalances.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🧹 All shop data has been cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteShop(String shopKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Shop'),
          ],
        ),
        content: Text(
          'Delete shop "${shopKey.toUpperCase()}" and all associated invoices, collections & credit records?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final keyLower = _normKey(shopKey);

    // Invoices
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

    // Collections
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

    // Opening balances
    final opening = await _getOpeningBalances(prefs);
    opening.remove(keyLower);
    await _setOpeningBalances(prefs, opening);

    // Credits cache
    final creditsStr = prefs.getString('shop_credits');
    if (creditsStr != null) {
      final Map<String, dynamic> decoded = jsonDecode(creditsStr);
      decoded.remove(keyLower);
      await prefs.setString('shop_credits', jsonEncode(decoded));
    }

    await _loadShopCredits();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ Shop "${shopKey.toUpperCase()}" deleted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// ✅ Add/Edit shop + opening credit
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

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              existingShopKey == null ? Icons.storefront : Icons.edit_note,
              color: Colors.blueAccent,
            ),
            const SizedBox(width: 8),
            Text(existingShopKey == null ? 'Add New Shop' : 'Edit Shop'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Shop Name',
                prefixIcon: const Icon(Icons.store),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: creditCtrl,
              decoration: InputDecoration(
                labelText: 'Opening / Previous Balance (LKR)',
                hintText: '0.00',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.blue.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Opening balance is added to credit. Collections reduce it automatically.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Save Shop',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final rawName = nameCtrl.text.trim();
    if (rawName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shop name cannot be empty'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final newKey = _normKey(rawName);
    double opening = _toDouble(creditCtrl.text.trim());
    if (opening < 0) opening = 0.0;
    opening = _round2(opening);

    // Rename shopName in invoices/collections when editing
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

    // Save opening balance
    if (opening > 0) {
      openingMap[newKey] = opening;
    } else {
      openingMap.remove(newKey);
    }
    await _setOpeningBalances(prefs, openingMap);

    await _loadShopCredits();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingShopKey == null
              ? '✅ Shop "$rawName" added'
              : '✅ Shop "$rawName" updated',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------- Calculations ----------
  double get _totalOutstandingCredit {
    return creditBalances.values.fold(0.0, (sum, val) => sum + val);
  }

  int get _shopsWithCreditCount {
    return creditBalances.values.where((b) => b > 0).length;
  }

  int get _settledShopsCount {
    return allShops.length - _shopsWithCreditCount;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'Loading Shop Credits...',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadShopCredits,
              child: CustomScrollView(
                slivers: [
                  // --- Summary Header Banner ---
                  SliverToBoxAdapter(child: _buildSummaryBanner(theme)),

                  // --- Search & Filter Section ---
                  SliverToBoxAdapter(child: _buildSearchAndFilterBar()),

                  // --- Shop Cards List ---
                  filteredShops.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) =>
                                  _buildShopCard(filteredShops[i], theme),
                              childCount: filteredShops.length,
                            ),
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditShopDialog(),
        elevation: 4,
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business),
        label: const Text(
          'Add Shop',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ---------- UI Components ----------

  Widget _buildSummaryBanner(ThemeData theme) {
    final total = _totalOutstandingCredit;
    final pendingCount = _shopsWithCreditCount;
    final totalShopsCount = allShops.length;
    final settledCount = _settledShopsCount;

    return Container(
      margin: const EdgeInsets.all(14),
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
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'TOTAL OUTSTANDING CREDIT',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      tooltip: 'Refresh Credits',
                      onPressed: _loadShopCredits,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_sweep_outlined,
                        color: Colors.redAccent,
                        size: 22,
                      ),
                      tooltip: 'Clear All Data',
                      onPressed: _clearAllShops,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _formatLkr(total),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.store,
                    label: 'Total Shops',
                    value: '$totalShopsCount',
                    color: Colors.white,
                  ),
                ),
                Container(height: 30, width: 1, color: Colors.white24),
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.pending_actions,
                    label: 'With Credit',
                    value: '$pendingCount',
                    color: Colors.amberAccent,
                  ),
                ),
                Container(height: 30, width: 1, color: Colors.white24),
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.check_circle_outline,
                    label: 'Settled',
                    value: '$settledCount',
                    color: Colors.lightGreenAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          // Search box + Sort button row
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => _applyFilterAndSort(),
                    decoration: InputDecoration(
                      hintText: 'Search by shop name...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.indigo,
                        size: 22,
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                _applyFilterAndSort();
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
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: PopupMenuButton<ShopSort>(
                  icon: const Icon(
                    Icons.sort_rounded,
                    color: Colors.indigo,
                    size: 22,
                  ),
                  tooltip: 'Sort Shops',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (sort) {
                    setState(() => _selectedSort = sort);
                    _applyFilterAndSort();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: ShopSort.creditHighLow,
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_downward,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Text('Highest Credit First'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ShopSort.creditLowHigh,
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_upward,
                            size: 16,
                            color: Colors.teal,
                          ),
                          SizedBox(width: 8),
                          Text('Lowest Credit First'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ShopSort.nameAZ,
                      child: Row(
                        children: [
                          Icon(
                            Icons.sort_by_alpha,
                            size: 16,
                            color: Colors.indigo,
                          ),
                          SizedBox(width: 8),
                          Text('Name (A - Z)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Segment Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'All (${allShops.length})',
                  filter: ShopFilter.all,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'With Credit ($_shopsWithCreditCount)',
                  filter: ShopFilter.hasCredit,
                  activeColor: Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Settled ($_settledShopsCount)',
                  filter: ShopFilter.settled,
                  activeColor: Colors.teal.shade700,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required ShopFilter filter,
    Color? activeColor,
  }) {
    final isSelected = _selectedFilter == filter;
    final color = activeColor ?? Colors.indigo.shade700;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withOpacity(0.15),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? color : Colors.grey.shade300,
        width: isSelected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = filter);
          _applyFilterAndSort();
        }
      },
    );
  }

  Widget _buildShopCard(String shopKey, ThemeData theme) {
    final norm = _normKey(shopKey);
    final balance = creditBalances[norm] ?? 0.0;
    final hasCredit = balance > 0;
    final opening = openingBalances[norm] ?? 0.0;

    final displayName = shopKey.toUpperCase();
    final firstLetter = displayName.isNotEmpty ? displayName[0] : 'S';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: hasCredit ? Colors.red.shade100 : Colors.teal.shade100,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShopDetailScreen(shopName: shopKey),
              ),
            );
            await _loadShopCredits();
          },
          onLongPress: () {
            _showAddEditShopDialog(existingShopKey: shopKey);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar Initial Circle
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasCredit
                          ? [Colors.red.shade400, Colors.red.shade700]
                          : [Colors.teal.shade400, Colors.teal.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      firstLetter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Shop Info (Name + Opening balance)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (opening > 0) ...[
                            Text(
                              'Opening: LKR ${_currencyFormat.format(opening)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ] else ...[
                            Text(
                              'Tap to view ledger & invoices',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Credit Balance Badge Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: hasCredit
                            ? Colors.red.shade50
                            : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasCredit
                              ? Colors.red.shade200
                              : Colors.teal.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasCredit
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            size: 14,
                            color: hasCredit
                                ? Colors.red.shade700
                                : Colors.teal.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasCredit ? _formatLkr(balance) : 'SETTLED',
                            style: TextStyle(
                              color: hasCredit
                                  ? Colors.red.shade700
                                  : Colors.teal.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Colors.indigo.shade400,
                          ),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          tooltip: 'Edit Shop / Opening Credit',
                          onPressed: () => _showAddEditShopDialog(
                            existingShopKey: shopKey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red.shade300,
                          ),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          tooltip: 'Delete Shop',
                          onPressed: () => _deleteShop(shopKey),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
                Icons.storefront_outlined,
                size: 48,
                color: Colors.indigo.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              allShops.isEmpty ? 'No Shops Registered Yet' : 'No Shops Found',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              allShops.isEmpty
                  ? 'Add your first shop and opening balance using the button below.'
                  : 'No shops match your current search or filter criteria.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            if (allShops.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _selectedFilter = ShopFilter.all);
                  _applyFilterAndSort();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reset Search & Filters'),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _showAddEditShopDialog(),
                icon: const Icon(Icons.add_business),
                label: const Text('Add New Shop'),
              ),
          ],
        ),
      ),
    );
  }
}
