import 'package:flutter/material.dart';
import 'invoice_screen.dart';
import 'product_screen.dart';
import 'shop_list_screen.dart';
import 'sales_summary_screen.dart';
import 'printer_settings_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // Screens matching the 5 tabs in the screenshot:
  // Invoice | Products | Shops | Sales | Printer
  late final List<Widget> _screens = const [
    InvoiceScreen(),
    ProductScreen(),
    ShopListScreen(),
    SalesSummaryScreen(),
    PrinterSettingsScreen(),
  ];

  final List<String> _titles = const [
    'Invoice',
    'Products',
    'Shops',
    'Sales',
    'Printer',
  ];

  // ── Colours matching the screenshot ──────────────────────────────────────
  static const Color _appBarBlue = Color(0xFF4285F4);
  static const Color _navBarBg = Color(0xFFF3EDF7); // lavender
  static const Color _selectedFg = Color(0xFF4285F4); // blue
  static const Color _unselectedFg = Color(0xFF9E9E9E); // grey

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── Blue Application Bar ──────────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          color: _appBarBlue,
          child: AppBar(
            title: Text(
              _titles[_currentIndex],
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 20,
                letterSpacing: 0.3,
              ),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
          ),
        ),
      ),

      // ── Body ──────────────────────────────────────────────────────────────
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      // ── Bottom Navigation Bar ────────────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _navBarBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.receipt_long_outlined, Icons.receipt_long,
                  'Invoice'),
              _navItem(
                  1, Icons.inventory_2_outlined, Icons.inventory_2, 'Products'),
              _navItem(2, Icons.store_mall_directory_outlined,
                  Icons.store_mall_directory, 'Shops'),
              _navItem(3, Icons.bar_chart_outlined, Icons.bar_chart, 'Sales'),
              _navItem(4, Icons.print_outlined, Icons.print, 'Printer'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      int index, IconData icon, IconData selectedIcon, String label) {
    final bool selected = _currentIndex == index;
    final Color color = selected ? _selectedFg : _unselectedFg;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        customBorder: const RoundedRectangleBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
