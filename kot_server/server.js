const express = require('express');
const pool = require('./config/db'); // Assuming you have a db.js file for MySQL connection
const app = express();
const PORT = 5000;

// Middleware to parse JSON requests
app.use(express.json());

// Test the database connection
app.get('/test-db', (req, res) => {
  pool.query('SELECT 1 + 1 AS solution', (err, results) => {
    if (err) {
      return res.status(500).json({ message: 'Database connection failed', error: err });
    }
    res.json({ message: 'Database connected successfully!', solution: results[0].solution });
  });
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
