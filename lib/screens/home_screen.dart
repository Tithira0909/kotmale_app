import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import 'add_product_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts(); // Load products when the screen is initialized
  }

  // Load the products from SharedPreferences
  Future<void> _loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('products');

    if (saved != null) {
      final List decoded = jsonDecode(saved);
      setState(() {
        products = decoded.map((p) => Product.fromJson(p)).toList();
      });
    } else {
      setState(() => products = []);
    }
  }

  // Save the products back to SharedPreferences after adding or deleting a product
  Future<void> _saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(products.map((p) => p.toJson()).toList());
    await prefs.setString(
      'products',
      encoded,
    ); // Save the products list to SharedPreferences
  }

  // Add a new product from the AddProductScreen
  Future<void> _addProduct() async {
    final newProduct = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );

    if (newProduct != null) {
      setState(() {
        products.add(newProduct);
      });
      await _saveProducts(); // Save updated product list to SharedPreferences
    }
  }

  // Delete a product from the list
  Future<void> _deleteProduct(Product p) async {
    setState(() {
      products.remove(p); // Remove product from list
    });
    await _saveProducts(); // Save updated product list to SharedPreferences
  }

  // Calculate the total stock value (Price * Quantity for all products)
  double get totalValue =>
      products.fold(0.0, (sum, p) => sum + (p.price * p.qty));

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.shopping_cart, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text(
              'No products available.\nTap the + button to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (ctx, i) {
              final p = products[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(
                    'Qty: ${p.qty} × LKR ${p.price.toStringAsFixed(2)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'LKR ${(p.qty * p.price).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteProduct(p),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Total Stock Value: LKR ${totalValue.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _addProduct,
          icon: const Icon(Icons.add),
          label: const Text('Add Product'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }
}
