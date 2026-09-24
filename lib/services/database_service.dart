import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Save a new invoice
  Future<void> saveInvoice(Map<String, dynamic> invoice) async {
    await _db.collection('invoices').add(invoice);
  }

  /// Get all invoices for a shop
  Stream<List<Map<String, dynamic>>> getShopInvoices(String shopName) {
    return _db
        .collection('invoices')
        .where('shopName', isEqualTo: shopName)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Get all invoices for a selected date
  Stream<List<Map<String, dynamic>>> getInvoicesByDate(String dateKey) {
    return _db
        .collection('invoices')
        .where('dateKey', isEqualTo: dateKey)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
