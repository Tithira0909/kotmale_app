import 'package:flutter/material.dart';
import '../models/product.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
  final priceCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Product')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Product Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Enter product name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) {
                    return 'Enter quantity';
                  }
                  if (int.tryParse(v) == null || int.parse(v) <= 0) {
                    return 'Enter a valid quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Price (LKR)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) {
                    return 'Enter price';
                  }
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'Enter a valid price';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final product = Product(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text.trim(),
                      qty: int.tryParse(qtyCtrl.text.trim()) ?? 0,
                      price: double.tryParse(priceCtrl.text.trim()) ?? 0.0,
                    );
                    Navigator.pop(context, product);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Product'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
