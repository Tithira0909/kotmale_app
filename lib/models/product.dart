class Product {
  final String id;
  final String name;
  double price;
  int qty;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.qty,
  });

  // Convert Product object to JSON (for saving in SharedPreferences)
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'price': price, 'qty': qty};
  }

  // Convert JSON to Product object
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      price: json['price'],
      qty: json['qty'],
    );
  }
}
