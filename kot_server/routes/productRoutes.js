const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');

router.post('/add', productController.addProduct); // API endpoint for adding product

module.exports = router;
