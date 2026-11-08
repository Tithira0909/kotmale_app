import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import 'add_product_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateTab;

  const HomeScreen({super.key, this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;

  double _todaysSales = 0.0;
  int _invoicesCount = 0;
  int _productsCount = 0;
  int _shopsCount = 0;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadSummaryData();
  }

  String _formatLkr(double amount) {
    return 'LKR ${_currencyFormat.format(amount)}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _loadSummaryData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();

    // 1. Invoices & Today Sales
    final invoiceStr = prefs.getString('invoice_history');
    double todaySalesSum = 0.0;
    int invCount = 0;

    if (invoiceStr != null && invoiceStr.isNotEmpty) {
      try {
        final List decoded = jsonDecode(invoiceStr);
        invCount = decoded.length;
        final now = DateTime.now();

        for (final item in decoded) {
          if (item is! Map) continue;
          final dt = DateTime.tryParse(item['date']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final totalVal =
              double.tryParse(item['total']?.toString() ?? '0') ?? 0.0;

          if (_isSameDay(dt, now)) {
            todaySalesSum += totalVal;
          }
        }
      } catch (_) {}
    }

    // 2. Products Count
    final productStr = prefs.getString('products');
    int prodCount = 0;
    if (productStr != null && productStr.isNotEmpty) {
      try {
        final List decoded = jsonDecode(productStr);
        prodCount = decoded.length;
      } catch (_) {}
    }

    // 3. Shops Count
    final shopsStr = prefs.getString('shops');
    final opStr = prefs.getString('shop_opening_balances');
    Set<String> uniqueShops = {};

    if (shopsStr != null && shopsStr.isNotEmpty) {
      try {
        final List decoded = jsonDecode(shopsStr);
        for (final s in decoded) {
          if (s != null && s.toString().trim().isNotEmpty) {
            uniqueShops.add(s.toString().trim().toLowerCase());
          }
        }
      } catch (_) {}
    }

    if (opStr != null && opStr.isNotEmpty) {
      try {
        final Map decoded = jsonDecode(opStr);
        for (final k in decoded.keys) {
          if (k != null && k.toString().trim().isNotEmpty) {
            uniqueShops.add(k.toString().trim().toLowerCase());
          }
        }
      } catch (_) {}
    }

    if (uniqueShops.isEmpty && invoiceStr != null) {
      try {
        final List decoded = jsonDecode(invoiceStr);
        for (final item in decoded) {
          if (item is Map && item['shopName'] != null) {
            final name = item['shopName'].toString().trim();
            if (name.isNotEmpty) uniqueShops.add(name.toLowerCase());
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _todaysSales = todaySalesSum;
      _invoicesCount = invCount;
      _productsCount = prodCount;
      _shopsCount = uniqueShops.length;
      _loading = false;
    });
  }

  Future<void> _addProduct() async {
    final newProduct = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    if (newProduct != null) {
      await _loadSummaryData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Product "${newProduct.name}" added'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E40AF),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E40AF)),
            )
          : RefreshIndicator(
              color: const Color(0xFF1E40AF),
              onRefresh: _loadSummaryData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Welcome Banner ---
                    _buildWelcomeBanner(),

                    const SizedBox(height: 20),

                    // --- 4 Small Summary Cards ---
                    _buildSummaryCards(),

                    const SizedBox(height: 24),

                    // --- 2 Main Action Buttons ---
                    _buildMainActionButtons(),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  // Welcome Text Banner
  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: Color(0xFF1E40AF),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kotmale Distribution Dashboard',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4 Small Summary Cards Grid
  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSmallSummaryCard(
                title: 'Today Sales',
                value: _formatLkr(_todaysSales),
                icon: Icons.payments_rounded,
                iconColor: const Color(0xFF1E40AF),
                bgColor: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSmallSummaryCard(
                title: 'Invoices',
                value: '$_invoicesCount',
                icon: Icons.receipt_long_rounded,
                iconColor: const Color(0xFF4338CA),
                bgColor: const Color(0xFFEEF2FF),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12, height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSmallSummaryCard(
                title: 'Products',
                value: '$_productsCount',
                icon: Icons.inventory_2_rounded,
                iconColor: const Color(0xFF0284C7),
                bgColor: const Color(0xFFE0F2FE),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSmallSummaryCard(
                title: 'Shops',
                value: '$_shopsCount',
                icon: Icons.storefront_rounded,
                iconColor: const Color(0xFF059669),
                bgColor: const Color(0xFFECFDF5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // 2 Main Action Buttons
  Widget _buildMainActionButtons() {
    return Column(
      children: [
        // Create Invoice Button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E40AF),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              if (widget.onNavigateTab != null) {
                widget.onNavigateTab!(1); // Index 1 = Invoice
              }
            },
            icon: const Icon(Icons.receipt_long_rounded, size: 22),
            label: const Text(
              'Create Invoice',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Add Product Button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E40AF),
              side: const BorderSide(color: Color(0xFF1E40AF), width: 1.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _addProduct,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 22),
            label: const Text(
              'Add Product',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
