import { InvoiceModel } from "../Models/invoiceModel.js";

export const saveInvoice = (req, res) => {
  const { shopName, date, paymentType, collection, credit, items } = req.body;

  if (!shopName || !date || !items || items.length === 0) {
    return res.status(400).json({ message: "Invalid invoice data" });
  }

  InvoiceModel.saveInvoice(
    { shopName, date, paymentType, collection, credit },
    items,
    (err) => {
      if (err) {
        console.error("DB error:", err);
        return res.status(500).json({ message: "Database error" });
      }
      res.json({ success: true, message: "Invoice saved successfully" });
    }
  );
};

export const getTodayInvoices = (req, res) => {
  InvoiceModel.getTodayInvoices((err, rows) => {
    if (err)
      return res.status(500).json({ message: "Database error", error: err });
    res.json(rows);
  });
};
