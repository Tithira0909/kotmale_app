import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/product.dart';
import '../services/bluetooth_service.dart';

import 'printer_settings_screen.dart';
import 'invoice_history_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour palette (matches reference screenshot)
// ─────────────────────────────────────────────────────────────────────────────
const Color _kBg       = Color(0xFFF0EDF6); // lavender / off-white page bg
const Color _kWhite    = Colors.white;
const Color _kPurple   = Color(0xFF6750A4); // primary accent
const Color _kLavender = Color(0xFFEBE4F7); // button fill / nav fill
const Color _kInk      = Color(0xFF1D1B20); // dark charcoal text
const Color _kGrey     = Color(0xFF79747E); // outline / hint
const Color _kGreen    = Color(0xFF2E7D32); // balance positive
const Color _kBorder   = Color(0xFFBDB6C8); // field border colour

// ─────────────────────────────────────────────────────────────────────────────
// InvoiceScreen
// ─────────────────────────────────────────────────────────────────────────────
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  // ── Controllers & focus ───────────────────────────────────────────────────
  final TextEditingController _shopCtrl  = TextEditingController();
  final TextEditingController _qtyCtrl   = TextEditingController();
  final FocusNode _shopFocus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────────
  Product? selectedProduct;
  List<Product> allProducts   = [];
  List<Product> invoiceItems  = [];
  List<String>  allShops      = [];
  double        _previousCredit = 0.0;
  bool          includeBalanceBF = true;

  // ── Formatter ─────────────────────────────────────────────────────────────
  final NumberFormat _fmt = NumberFormat('#,##0.00', 'en_US');

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _normKey(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  double _toDouble(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
  double _round2(double v)   => double.parse(v.toStringAsFixed(2));

  String _fmtLkr(double amount) => 'LKR ${_fmt.format(amount)}';

  // ── Life-cycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadShopsAndCredits();
  }

  @override
  void dispose() {
    _shopCtrl.dispose();
    _qtyCtrl.dispose();
    _shopFocus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Business logic (UNCHANGED from original)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('products');
    if (saved != null && saved.isNotEmpty) {
      try {
        final List decoded = jsonDecode(saved);
        if (!mounted) return;
        setState(() {
          allProducts = decoded.map((p) => Product.fromJson(p)).toList();
        });
      } catch (_) {}
    }
  }

  Future<double> _computeShopCreditBalance(String shopName) async {
    final prefs   = await SharedPreferences.getInstance();
    final shopKey = _normKey(shopName);

    double opening = 0.0;
    final openStr = prefs.getString('shop_opening_balances');
    if (openStr != null && openStr.isNotEmpty) {
      final Map<String, dynamic> openMap = jsonDecode(openStr);
      opening = _toDouble(openMap[shopKey]);
      if (opening < 0) opening = 0.0;
    }

    double creditInvoiceTotal = 0.0;
    final invStr = prefs.getString('invoice_history');
    if (invStr != null && invStr.isNotEmpty) {
      final List all = jsonDecode(invStr);
      for (final invAny in all) {
        if (invAny is! Map) continue;
        final inv     = invAny.cast<String, dynamic>();
        final invShop = _normKey(inv['shopName']?.toString() ?? '');
        if (invShop != shopKey) continue;
        final payType = (inv['paymentType']?.toString().trim() ?? '');
        if (['Credit', 'Cheque'].contains(payType)) {
          final t = _toDouble(inv['total']);
          if (t > 0) creditInvoiceTotal += t;
        }
      }
    }

    double creditPaid = 0.0;
    final colStr = prefs.getString('collection_history');
    if (colStr != null && colStr.isNotEmpty) {
      final List cols = jsonDecode(colStr);
      for (final cAny in cols) {
        if (cAny is! Map) continue;
        final c     = cAny.cast<String, dynamic>();
        final cShop = _normKey(c['shopName']?.toString() ?? '');
        if (cShop != shopKey) continue;
        final applied = c.containsKey('creditApplied')
            ? _toDouble(c['creditApplied'])
            : _toDouble(c['amount']);
        if (applied > 0) creditPaid += applied;
      }
    }

    final issued = _round2(opening + creditInvoiceTotal);
    final paid   = _round2(creditPaid);
    final bal    = _round2((issued - paid) < 0 ? 0.0 : (issued - paid));
    return bal;
  }

  Future<void> _loadShopsAndCredits() async {
    final prefs = await SharedPreferences.getInstance();
    final Set<String> names = {};

    final shopsStr = prefs.getString('shops');
    if (shopsStr != null) {
      try {
        final List decoded = jsonDecode(shopsStr);
        for (var s in decoded) {
          if (s != null && s.toString().trim().isNotEmpty) {
            names.add(s.toString().trim());
          }
        }
      } catch (_) {}
    }

    final creditsStr = prefs.getString('shop_credits');
    if (creditsStr != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(creditsStr);
        decoded.forEach((k, v) => names.add(k.trim()));
      } catch (_) {}
    }

    final hist = prefs.getString('invoice_history');
    if (hist != null) {
      try {
        final List list = jsonDecode(hist);
        for (var inv in list) {
          final n = (inv['shopName'] ?? '').toString().trim();
          if (n.isNotEmpty) names.add(n);
        }
      } catch (_) {}
    }

    final shopList = names.toList()..sort();
    if (!mounted) return;
    setState(() => allShops = shopList);
  }

  Future<void> _onShopSelected(String shop) async {
    final credit = await _computeShopCreditBalance(shop);
    if (!mounted) return;
    setState(() => _previousCredit = credit);
  }

  void _addToInvoice() {
    if (selectedProduct == null) {
      _snack('Please select a product first');
      return;
    }
    final qtyText = _qtyCtrl.text.trim();
    final qty = qtyText.isEmpty ? 1 : (int.tryParse(qtyText) ?? 0);
    if (qty <= 0) {
      _snack('Enter a valid quantity (> 0)');
      return;
    }
    // Price comes from the selected product (still editable per item in the list)
    final price = selectedProduct!.price;
    if (price < 0) {
      _snack('Enter a valid unit price');
      return;
    }

    final idx = invoiceItems.indexWhere((it) => it.name == selectedProduct!.name);
    if (idx != -1) {
      // Update qty; also update price in case it was overridden
      setState(() {
        invoiceItems[idx].qty   += qty;
        invoiceItems[idx].price  = price;
      });
    } else {
      setState(() {
        invoiceItems.add(
          Product(
            id:    selectedProduct!.id,
            name:  selectedProduct!.name,
            price: price,
            qty:   qty,
          ),
        );
      });
    }
    _qtyCtrl.clear();
  }

  void _updateItemQty(int index, int delta) {
    setState(() {
      final newQty = invoiceItems[index].qty + delta;
      if (newQty > 0) {
        invoiceItems[index].qty = newQty;
      } else {
        invoiceItems.removeAt(index);
      }
    });
  }

  double get subtotal  => invoiceItems.fold(0.0, (s, p) => s + p.price * p.qty);
  double get grandTotal => _round2(subtotal + _previousCredit);

  void _editItem(Product product) {
    final qtyCtrl   = TextEditingController(text: product.qty.toString());
    final priceCtrl = TextEditingController(text: product.price.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: _kPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Edit ${product.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              decoration: InputDecoration(
                labelText: 'Quantity',
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: InputDecoration(
                labelText: 'Unit Price (LKR)',
                prefixIcon: const Icon(Icons.payments_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final newQty   = int.tryParse(qtyCtrl.text.trim())    ?? product.qty;
              final newPrice = double.tryParse(priceCtrl.text.trim()) ?? product.price;
              setState(() {
                product.qty   = newQty;
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
      _snack('Please add at least one item to the invoice');
      return;
    }

    final prefs      = await SharedPreferences.getInstance();
    final printerMac = prefs.getString('printer_mac');
    if (printerMac == null || printerMac.isEmpty) {
      if (!mounted) return;
      _snack('Please connect a printer in Printer Settings');
      return;
    }

    try {
      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        final ok = await BluetoothService.connect(printerMac);
        if (!ok) {
          if (!mounted) return;
          _snack('Failed to connect to Bluetooth printer');
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
      buf.writeln(centerText(' ITEM           U.PRICE    QTY   TOTAL'));
      buf.writeln(line('-'));

      for (var p in invoiceItems) {
        final name     = p.name.length > 12 ? p.name.substring(0, 12) : p.name;
        final nameCol  = name.padRight(12);
        final unitCol  = p.price.toStringAsFixed(2).padLeft(7);
        final qtyCol   = p.qty.toString().padLeft(4);
        final totalCol = (p.price * p.qty).toStringAsFixed(2).padLeft(7);
        buf.writeln(centerText('$nameCol $unitCol $qtyCol $totalCol'));
      }

      buf.writeln(line('-'));
      buf.writeln(centerText('Sub Total:  LKR ${subtotal.toStringAsFixed(2)}'));

      if (includeBalanceBF) {
        buf.writeln(centerText(
            'Credit Balance: LKR ${_previousCredit.toStringAsFixed(2)}'));
      }

      buf.writeln(centerText('New Balance: LKR ${grandTotal.toStringAsFixed(2)}'));
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

      if (!mounted) return;
      await _showPaymentPopup(shopName, date);
    } catch (e) {
      if (!mounted) return;
      _snack('Printer error: $e');
    }
  }

  Future<void> _showPaymentPopup(String shop, String date) async {
    // ── snapshot totals once ───────────────────────────────────────────────
    final double payable = _round2(grandTotal); // subtotal + previous credit

    // ── mutable state ──────────────────────────────────────────────────────
    String paymentType = 'Cash';
    final amountCtrl =
        TextEditingController(text: payable.toStringAsFixed(2));

    // ── helpers ────────────────────────────────────────────────────────────
    /// Numeric value currently in the amount field.
    double paidNow() {
      final v = double.tryParse(amountCtrl.text.trim());
      return _round2(v == null || v < 0 ? 0.0 : v);
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final total  = payable;
          final paid   = paidNow();
          final bal    = _round2(total > paid ? total - paid : 0.0);
          final change = _round2(paid  > total ? paid  - total : 0.0);


          // ── Cash button ─────────────────────────────────────────────────
          Widget cashChip() => Expanded(
                child: GestureDetector(
                  onTap: () => setSt(() {
                    paymentType = 'Cash';
                    amountCtrl.text = payable.toStringAsFixed(2);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 46,
                    decoration: BoxDecoration(
                      color: paymentType == 'Cash'
                          ? _kPurple
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: paymentType == 'Cash'
                            ? _kPurple
                            : const Color(0xFFCAC4D0),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (paymentType == 'Cash') ...[
                          const Icon(Icons.check,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          'Cash',
                          style: TextStyle(
                            color: paymentType == 'Cash'
                                ? Colors.white
                                : _kInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

          // ── Cheque button ───────────────────────────────────────────────
          Widget chequeChip() => Expanded(
                child: GestureDetector(
                  onTap: () => setSt(() {
                    paymentType = 'Cheque';
                    amountCtrl.text = payable.toStringAsFixed(2);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 46,
                    decoration: BoxDecoration(
                      color: paymentType == 'Cheque'
                          ? _kPurple
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: paymentType == 'Cheque'
                            ? _kPurple
                            : const Color(0xFFCAC4D0),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (paymentType == 'Cheque') ...[
                          const Icon(Icons.check,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          'Cheque',
                          style: TextStyle(
                            color: paymentType == 'Cheque'
                                ? Colors.white
                                : _kInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

          // ── Credit button ───────────────────────────────────────────────
          Widget creditChip() => Expanded(
                child: GestureDetector(
                  onTap: () => setSt(() {
                    paymentType = 'Credit';
                    amountCtrl.text = '0.00';
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 46,
                    decoration: BoxDecoration(
                      color: paymentType == 'Credit'
                          ? _kPurple
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: paymentType == 'Credit'
                            ? _kPurple
                            : const Color(0xFFCAC4D0),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (paymentType == 'Credit') ...[
                          const Icon(Icons.check,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          'Credit',
                          style: TextStyle(
                            color: paymentType == 'Credit'
                                ? Colors.white
                                : _kInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
          // ── Summary row ─────────────────────────────────────────────────
          Widget summRow(String label, double value,
              {bool bold = false, Color? vc}) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF49454F)),
                    ),
                  ),
                  Text(
                    'LKR ${_fmt.format(value)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          bold ? FontWeight.bold : FontWeight.bold,
                      color: vc ?? _kInk,
                    ),
                  ),
                ],
              ),
            );
          }

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Title row ──────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
color: _kPurple.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.credit_card_rounded,
                            color: _kPurple, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Payment\nSettlement',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kInk,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── "Select Payment Type" label ────────────────────────
                  const Text(
                    'Select Payment Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF79747E),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Toggle buttons ─────────────────────────────────────
                  Row(
                    children: [
                      cashChip(),
                      const SizedBox(width: 8),
                      chequeChip(),
                      const SizedBox(width: 8),
                      creditChip(),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Amount Paid field ──────────────────────────────────
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _kInk),
                    onTap: () => amountCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: amountCtrl.text.length,
                    ),
                    onChanged: (_) => setSt(() {}),
                    decoration: InputDecoration(
                      labelText: 'Amount Paid (LKR)',
                      labelStyle: const TextStyle(
                          fontSize: 13, color: Color(0xFF79747E)),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFFCAC4D0), width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _kPurple, width: 2),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Summary rows ───────────────────────────────────────
                  summRow('Total Amount', total),
                  summRow('Paid Amount', paid),
                  summRow('Balance', bal,
                      vc: bal > 0 ? Colors.orange.shade800 : _kInk),
                  summRow('Change', change,
                      vc: change > 0 ? const Color(0xFF2E7D32) : _kInk),

                  const SizedBox(height: 20),

                  // ── Cancel text button ─────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: _kPurple,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Save Invoice pill button ────────────────────────────
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: Colors.black26,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Save Invoice'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      final paid        = paidNow();
      final creditLeft  = _round2(payable > paid ? payable - paid : 0.0);
      final effectiveType = creditLeft <= 0
          ? (paymentType == 'Credit' ? 'Credit' : paymentType)
          : (paid <= 0 ? 'Credit' : 'Split');
      await _saveInvoice(shop, date, effectiveType, paid, creditLeft);
    }
  }


  Future<void> _saveInvoice(
      String shop, String date, String paymentType,
      [double? cashPaid, double? creditAmount]) async {
    final prefs   = await SharedPreferences.getInstance();
    final histStr = prefs.getString('invoice_history');
    List invoices = histStr != null ? jsonDecode(histStr) : [];

    final prevBal   = _round2(_previousCredit < 0 ? 0.0 : _previousCredit);
    final invAmount = _round2(subtotal);
    // payable = items + old balance carried forward
    final payable   = _round2(grandTotal);

    // Normalise amounts from the new popup
    final double cashReceived  = _round2(cashPaid    ?? 0.0);
    final double creditOnInv   = _round2(creditAmount ?? 0.0);
    // amountPaid = cash received (for backwards compat with other screens)
    final double amountPaid    = cashReceived;

    // New shop balance after this invoice:
    //   prevBal + invoiceItems - cash that can clear old balance - cashPaid towards items
    //   Simplified: creditOnInv is the portion that stays outstanding
    final newShopBal = _round2(creditOnInv < 0 ? 0.0 : creditOnInv);

    // How much of the CASH received was applied to the previous credit balance
    final double creditApplied = _round2(() {
      if (creditAmount == null) {
        // Legacy call (only cashPaid supplied)
        final extra = cashReceived - invAmount;
        if (extra <= 0) return 0.0;
        return extra > prevBal ? prevBal : extra;
      }
      // New split-payment call: cash covers [prevBal + invAmount - creditOnInv]
      // so creditApplied = reduction in prevBal
      final paidTowardsAll = cashReceived;
      final paidTowardsInv = invAmount - creditOnInv.clamp(0.0, invAmount);
      final extra = paidTowardsAll - paidTowardsInv;
      if (extra <= 0) return 0.0;
      return extra > prevBal ? prevBal : extra;
    }());

    // Derive the payment-type string for legacy fields
    final String effectiveType = creditOnInv <= 0
        ? 'Cash'
        : (cashReceived <= 0 ? 'Credit' : paymentType);

    final newInv = {
      'id':              DateTime.now().millisecondsSinceEpoch.toString(),
      'shopName':        shop,
      'date':            date,
      'items':           invoiceItems.map((i) => i.toJson()).toList(),
      'subtotal':        subtotal,
      'previousBalance': _previousCredit,
      // 'total' = this invoice only (no B/F) to avoid double-counting in credit sum.
      'total':           ['Credit', 'Cheque'].contains(effectiveType) ? (creditOnInv > 0 ? creditOnInv : invAmount) : (creditOnInv > 0 ? creditOnInv : 0.0),
      'grandTotal':      grandTotal,
      'paymentType':     effectiveType,
      'cashPaid':        cashReceived,
      'creditAmount':    creditOnInv,
      'amountPaid':      amountPaid,
      'creditApplied':   creditApplied,
      'newShopBalance':  newShopBal,
      'balance':         newShopBal,
      'change':          (cashReceived - payable) > 0 ? cashReceived - payable : 0.0,
      'isPaid':          creditOnInv <= 0,
    };

    invoices.add(newInv);
    await prefs.setString('invoice_history', jsonEncode(invoices));

    // Record old-credit settlement as a collection so all screens agree.
    if (creditApplied > 0) {
      final colStr = prefs.getString('collection_history');
      final List cols = colStr != null ? jsonDecode(colStr) : [];
      final bool wasCredit = effectiveType == 'Credit';
      cols.add({
        'shopName':      shop,
        'amount':        creditApplied,
        'creditApplied': creditApplied,
        'date':          date,
        'oldBalance':    _round2(prevBal + (wasCredit ? invAmount : 0.0)),
        'newBalance':    newShopBal,
        'unapplied':     0.0,
        'source':        'invoice',
        'invoiceId':     newInv['id'],
      });
      await prefs.setString('collection_history', jsonEncode(cols));
    }

    // Keep the cached shop credit map in sync.
    final creditsStr = prefs.getString('shop_credits');
    final Map<String, dynamic> credits =
        creditsStr != null ? jsonDecode(creditsStr) : {};
    credits[_normKey(shop)] = newShopBal;
    await prefs.setString('shop_credits', jsonEncode(credits));

    await _loadShopsAndCredits();

    if (!mounted) return;
    setState(() {
      invoiceItems.clear();
      _shopCtrl.clear();
      _previousCredit = 0.0;
      selectedProduct = null;
    });

    _snack('✅ Invoice created & saved successfully!', color: _kPurple);
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Rounded outlined input border
  OutlineInputBorder _fieldBorder([Color c = _kBorder, double w = 1.2]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );

  /// Lavender pill button (Add Item / Print Invoice)
  Widget _pillBtn({
    required IconData    icon,
    required String      label,
    required VoidCallback onPressed,
    double height    = 48,
    double fontSize  = 15,
    double? fullWidth,
  }) {
    final child = SizedBox(
      height: height,
      width:  fullWidth,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon:  Icon(icon, size: fontSize + 5, color: _kPurple),
        label: Text(
          label,
          style: TextStyle(
            fontSize:   fontSize,
            fontWeight: FontWeight.w600,
            color:      _kPurple,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kLavender,
          foregroundColor: _kPurple,
          elevation: 1.5,
          shadowColor: Colors.black26,
          padding: EdgeInsets.symmetric(
            horizontal: fullWidth != null ? 0 : 18,
          ),
          shape: const StadiumBorder(),
        ),
      ),
    );
    return child;
  }

  /// Summary row (right-aligned)
  Widget _summaryRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label  ${_fmtLkr(value)}',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize:   bold ? 17 : 15,
          fontWeight: bold ? FontWeight.bold : FontWeight.w400,
          color:      _kInk,
        ),
      ),
    );
  }

  /// Autocomplete shop / customer field
  Widget _buildShopField() {
    return RawAutocomplete<String>(
      textEditingController: _shopCtrl,
      focusNode: _shopFocus,
      optionsBuilder: (v) {
        if (v.text.isEmpty) return const Iterable<String>.empty();
        return allShops.where(
            (o) => o.toLowerCase().contains(v.text.toLowerCase()));
      },
      onSelected: _onShopSelected,
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        return TextField(
          controller:         controller,
          focusNode:          focusNode,
          onEditingComplete:  onEditingComplete,
          onChanged: (val) {
            if (val.trim().isNotEmpty) _onShopSelected(val.trim());
          },
          style: const TextStyle(fontSize: 16, color: _kInk),
          decoration: InputDecoration(
            hintText:  'Shop / Customer Name',
            hintStyle: const TextStyle(fontSize: 16, color: _kGrey),
            filled:    true,
            fillColor: _kWhite,
            border:         _fieldBorder(),
            enabledBorder:  _fieldBorder(),
            focusedBorder:  _fieldBorder(_kPurple, 2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color:        Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 220,
                maxWidth:  MediaQuery.of(context).size.width - 32,
              ),
              child: ListView.builder(
                padding:     EdgeInsets.zero,
                shrinkWrap:  true,
                itemCount:   options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  return ListTile(
                    title:  Text(o),
                    onTap:  () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Invoice item tile with qty controls
  Widget _buildItemTile(int idx, Product item) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: const Color(0xFFE7E0EC)),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
color:      Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Name + price
          Expanded(
            child: InkWell(
              onTap: () => _editItem(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize:   15,
                      fontWeight: FontWeight.w600,
                      color:      _kInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtLkr(item.price)}  ·  ${_fmtLkr(item.price * item.qty)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _kGrey),
                  ),
                ],
              ),
            ),
          ),

          // – qty + controls
          _circleBtn(Icons.remove, () => _updateItemQty(idx, -1)),
          SizedBox(
            width: 30,
            child: Text(
              '${item.qty}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize:   15,
                fontWeight: FontWeight.bold,
                color:      _kInk,
              ),
            ),
          ),
          _circleBtn(Icons.add, () => _updateItemQty(idx, 1)),

          // Delete
          IconButton(
            tooltip:    'Remove',
            icon:       const Icon(Icons.delete_outline, size: 22),
            color:      Colors.red.shade400,
            onPressed:  () => _updateItemQty(idx, -item.qty),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap:        onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width:  32,
        height: 32,
        decoration: const BoxDecoration(
          color: _kLavender,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: _kPurple),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          // ── Page heading (below AppBar) ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Create Invoice',
                      style: TextStyle(
                        fontSize:   24,
                        fontWeight: FontWeight.w600,
                        color:      _kInk,
                      ),
                    ),
                  ),
                  // Settings icon
                  IconButton(
                    tooltip:   'Printer Settings',
                    icon:      const Icon(Icons.settings, size: 26, color: Color(0xFF2B2B2B)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PrinterSettingsScreen()),
                    ),
                  ),
                  // Archive / Invoice history icon
                  IconButton(
                    tooltip:   'Invoice History',
                    icon:      const Icon(Icons.archive, size: 26, color: Color(0xFF2B2B2B)),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const InvoiceHistoryScreen()),
                      );
                      _loadShopsAndCredits();
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Form section ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Shop / Customer field ─────────────────────────────
                  _buildShopField(),
                  const SizedBox(height: 8),
                  // ── Balance B/F ──────────────────────────────────────
                  Text(
                    'Balance B/F: ${_fmtLkr(_previousCredit)}',
                    style: const TextStyle(
                      fontSize:   16,
                      fontWeight: FontWeight.bold,
                      color:      _kGreen,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Product dropdown ──────────────────────────────────
                  DropdownButtonFormField<Product>(
                    // ignore: deprecated_member_use
                    value:          selectedProduct,
                    isExpanded:     true,
                    icon:           const Icon(Icons.arrow_drop_down, size: 28, color: _kGrey),
                    dropdownColor:  Colors.white,
                    decoration: InputDecoration(
                      filled:         true,
                      fillColor:      _kWhite,
                      border:         _fieldBorder(),
                      enabledBorder:  _fieldBorder(),
                      focusedBorder:  _fieldBorder(_kPurple, 2),
                      contentPadding: const EdgeInsets.fromLTRB(18, 22, 10, 22),
                    ),
                    hint: const Text(
                      'Select Product',
                      style: TextStyle(fontSize: 16, color: _kGrey),
                    ),
                    style: const TextStyle(fontSize: 15, color: _kInk),
                    items: allProducts
                        .map((p) => DropdownMenuItem<Product>(
                              value: p,
                              child: Text(
                                '${p.name} (${_fmtLkr(p.price)})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (p) => setState(() => selectedProduct = p),
                  ),
                  const SizedBox(height: 12),

                  // ── Quantity (underline input) + "+ Add Item" pill ─────
                  LayoutBuilder(builder: (context, c) {
                    final narrow = c.maxWidth < 340;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller:   _qtyCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addToInvoice(),
                            style: const TextStyle(fontSize: 18, color: _kInk),
                            onChanged:    (_) => setState(() {}),
                            onTap: () => _qtyCtrl.selection = TextSelection(
                              baseOffset:   0,
                              extentOffset: _qtyCtrl.text.length,
                            ),
                            decoration: const InputDecoration(
                              isDense:   true,
                              hintText:  'Quantity',
                              hintStyle: TextStyle(fontSize: 18, color: Color(0xFF49454F)),
                              contentPadding: EdgeInsets.only(top: 14, bottom: 16),
                              border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF79747E), width: 1.2)),
                              enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF79747E), width: 1.2)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: _kPurple, width: 2)),
                            ),
                          ),
                        ),
                        SizedBox(width: narrow ? 12 : 16),
                        _pillBtn(
                          icon:      Icons.add,
                          label:     'Add Item',
                          onPressed: _addToInvoice,
                          height:    narrow ? 46 : 52,
                          fontSize:  narrow ? 14.5 : 16,
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 20),

                  // ── Divider below input section ───────────────────────
                  const Divider(color: Color(0xFFCAC4D0), height: 1, thickness: 1),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // ── Invoice items list ────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildItemTile(i, invoiceItems[i]),
                childCount: invoiceItems.length,
              ),
            ),
          ),

          // ── Summary + Print button (anchored towards bottom) ─────────────
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),

                  // Summary block — right-aligned
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _summaryRow('Sub Total: ', subtotal),
                          _summaryRow('Balance B/F:', _previousCredit),
                          const SizedBox(height: 2),
                          _summaryRow('New Balance:', grandTotal, bold: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Print Invoice button — full-width pill
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _printInvoice,
                      icon:  const Icon(Icons.print, size: 22, color: _kPurple),
                      label: const Text(
                        'Print Invoice',
                        style: TextStyle(
                          fontSize:   17,
                          fontWeight: FontWeight.w600,
                          color:      _kPurple,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kLavender,
                        foregroundColor: _kPurple,
                        elevation:   2,
                        shadowColor: Colors.black26,
                        shape:       const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
