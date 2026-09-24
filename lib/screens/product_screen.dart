import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import 'add_product_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // 👇 Let MainNavigation call this to open AddProductScreen
  void addProduct(BuildContext context) async {
    final state = context.findAncestorStateOfType<_HomeScreenState>();
    state?._addProduct();
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('products');
    if (saved != null) {
      final List decoded = jsonDecode(saved);
      setState(() {
        _products = decoded.map((p) => Product.fromJson(p)).toList();
      });
    }
  }

  Future<void> _saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_products.map((p) => p.toJson()).toList());
    await prefs.setString('products', encoded);
  }

  Future<void> _addProduct() async {
    final newProduct = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    if (newProduct != null) {
      setState(() {
        _products.add(newProduct);
      });
      await _saveProducts();
    }
  }

  Future<void> _deleteProduct(String id) async {
    setState(() {
      _products.removeWhere((p) => p.id == id);
    });
    await _saveProducts();
  }

  @override
  Widget build(BuildContext context) {
    return _products.isEmpty
        ? const Center(
            child: Text(
              'No products available.\nTap the "+" button to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
        : ListView.builder(
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final p = _products[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(
                    'Qty: ${p.qty} | LKR ${p.price.toStringAsFixed(2)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteProduct(p.id),
                  ),
                ),
              );
            },
          );
  }
}
