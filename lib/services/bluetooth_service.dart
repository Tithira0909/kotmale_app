import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class BluetoothService {
  /// 🔍 Scan for paired Bluetooth devices
  static Future<List<BluetoothInfo>> scan() async {
    try {
      final List<BluetoothInfo> paired =
          await PrintBluetoothThermal.pairedBluetooths;
      return paired;
    } catch (e) {
      print('Error scanning Bluetooth devices: $e');
      return [];
    }
  }

  /// 🔗 Connect to a selected Bluetooth printer
  static Future<bool> connect(String macAdress) async {
    try {
      bool isConnected = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAdress,
      );
      return isConnected;
    } catch (e) {
      print('Error connecting to printer: $e');
      return false;
    }
  }

  /// 🖨️ Print invoice text to the connected printer
  static Future<void> printInvoice(String text) async {
    try {
      // The printer expects bytes, so we encode the text
      await PrintBluetoothThermal.writeBytes(text.codeUnits);
    } catch (e) {
      print('Error printing invoice: $e');
    }
  }

  /// 🔌 Disconnect printer (optional, good for cleanup)
  static Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (e) {
      print('Error disconnecting printer: $e');
    }
  }
}
