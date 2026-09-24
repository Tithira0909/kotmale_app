const Product = require('../models/productModel');

// Add a new product
exports.addProduct = (req, res) => {
  const { name, price, qty } = req.body;
  
  Product.addProduct(name, price, qty, (err, result) => {
    if (err) {
      return res.status(500).json({ message: 'Error adding product', error: err });
    }
    res.status(201).json({ message: 'Product added successfully', productId: result.insertId });
  });
};

// Get all products
exports.getAllProducts = (req, res) => {
  Product.getAllProducts((err, products) => {
    if (err) {
      return res.status(500).json({ message: 'Error fetching products', error: err });
    }
    res.status(200).json(products);
  });
};
