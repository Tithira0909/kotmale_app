import 'package:flutter/material.dart';
import 'invoice_screen.dart';
import 'home_screen.dart';
import 'shop_list_screen.dart';
import 'sales_summary_screen.dart';
import 'printer_settings_screen.dart';
import 'add_product_screen.dart';
import '../models/product.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // 👇 these are all your tab screens
  final List<Widget> _screens = const [
    InvoiceScreen(),
    HomeScreen(),
    ShopListScreen(),
    SalesSummaryScreen(),
    PrinterSettingsScreen(),
  ];

  final List<String> _titles = const [
    'Invoice',
    'Products',
    'Shops',
    'Sales Summary',
    'Printer Settings',
  ];

  // 🌟 shared prefs cache for passing product updates from FAB
  Future<void> _addProductFromFab(BuildContext context) async {
    final newProduct = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    if (newProduct != null) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('products');
      List<Product> products = [];
      if (saved != null) {
        final List decoded = jsonDecode(saved);
        products = decoded.map((p) => Product.fromJson(p)).toList();
      }
      products.add(newProduct);
      final encoded = jsonEncode(products.map((p) => p.toJson()).toList());
      await prefs.setString('products', encoded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),

      body: _screens[_currentIndex],

      // ✅ Floating Action Button appears only on Products tab
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: () async {
                await _addProductFromFab(context);
                // force rebuild of HomeScreen to show new data
                setState(() {});
              },
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.add),
            )
          : null,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Invoice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Shops'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Sales'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Printer'),
        ],
      ),
    );
  }
}
