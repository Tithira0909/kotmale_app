import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CreditSummaryScreen extends StatefulWidget {
  const CreditSummaryScreen({super.key});

  @override
  State<CreditSummaryScreen> createState() => _CreditSummaryScreenState();
}

class _CreditSummaryScreenState extends State<CreditSummaryScreen> {
  List<Map<String, dynamic>> _creditSummary = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchCreditSummary();
  }

  Future<void> _fetchCreditSummary() async {
    setState(() => _loading = true);

    const apiUrl =
        "http://YOUR_LOCAL_IP/kotmale_api/get_credit_summary.php"; // Update this!

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        setState(() {
          _creditSummary = List<Map<String, dynamic>>.from(
            jsonDecode(response.body),
          );
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Server error: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Connection failed: $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credit Summary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _creditSummary.isEmpty
          ? const Center(
              child: Text(
                'No credit transactions found.\nPlease create and save invoices with credit.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _creditSummary.length,
              itemBuilder: (ctx, i) {
                final credit = _creditSummary[i];
                return Card(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    title: Text(credit['shopName']),
                    subtitle: Text(
                      'Total Credit: LKR ${credit['credit'].toStringAsFixed(2)}\nCollection: LKR ${credit['collection'].toStringAsFixed(2)}\nRemaining: LKR ${(credit['credit'] - credit['collection']).toStringAsFixed(2)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () {
                        // You can show more details if needed
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
