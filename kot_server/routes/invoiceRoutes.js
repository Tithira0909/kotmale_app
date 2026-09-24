import express from "express";
import { saveInvoice, getTodayInvoices } from "../controllers/invoiceController.js";

const router = express.Router();

router.post("/", saveInvoice);
router.get("/today", getTodayInvoices);

export default router;
