import { db } from "../config/db.js";

export const InvoiceModel = {
  // Save invoice and items
  saveInvoice: (invoiceData, items, callback) => {
    const { shopName, date, paymentType, collection, credit } = invoiceData;

    db.query(
      `INSERT INTO invoices (shop_name, date, payment_type, collection, credit)
       VALUES (?, ?, ?, ?, ?)`,
      [shopName, date, paymentType, collection, credit],
      (err, result) => {
        if (err) return callback(err);

        const invoiceId = result.insertId;
        if (!items || items.length === 0) return callback(null, result);

        const values = items.map((it) => [
          invoiceId,
          it.product.name,
          it.qty,
          it.unitPrice,
          it.qty * it.unitPrice,
        ]);

        db.query(
          `INSERT INTO invoice_items (invoice_id, product_name, qty, unit_price, total) VALUES ?`,
          [values],
          (err2) => (err2 ? callback(err2) : callback(null, result))
        );
      }
    );
  },

  getTodayInvoices: (callback) => {
    db.query(
      `SELECT * FROM invoices WHERE DATE(date) = CURDATE() ORDER BY id DESC`,
      callback
    );
  },
};
