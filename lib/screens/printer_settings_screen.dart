import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/bluetooth_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<BluetoothInfo> devices = [];
  Map<String, String>? selected;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
    _scanPrinters();
  }

  /// 🧠 Load previously saved printer
  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('printer_mac');
    final savedName = prefs.getString('printer_name');
    if (savedMac != null && savedMac.isNotEmpty) {
      setState(() {
        selected = {'name': savedName ?? 'Unknown', 'mac': savedMac};
      });
    }
  }

  /// 🔍 Scan paired Bluetooth devices
  Future<void> _scanPrinters() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool isEnabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable Bluetooth first')),
      );
      return;
    }

    final found = await BluetoothService.scan();
    setState(() => devices = found);
  }

  /// 🔗 Connect and save selected printer
  Future<void> _connectPrinter(BluetoothInfo d) async {
    setState(() => _loading = true);
    try {
      bool ok = await BluetoothService.connect(d.macAdress);
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('printer_name', d.name ?? 'Unknown');
        await prefs.setString('printer_mac', d.macAdress ?? '');

        setState(() {
          selected = {'name': d.name ?? 'Unknown', 'mac': d.macAdress ?? ''};
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Connected and saved: ${d.name}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to connect: ${d.name}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 🧾 Test print
  Future<void> _testPrint() async {
    if (selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No printer connected')));
      return;
    }

    const testText = '''
*** KOTMALE APP TEST PRINT ***
Printer Connection Successful!
-----------------------------
Thank you for testing!
\n\n\n
''';

    try {
      await BluetoothService.printInvoice(testText);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Test print sent to printer')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Test print failed: $e')));
    }
  }

  /// 🧹 Forget saved printer
  Future<void> _forgetPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('printer_name');
    await prefs.remove('printer_mac');
    setState(() => selected = null);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('🗑 Printer removed')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: _scanPrinters,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 10),
                Text(
                  selected == null
                      ? 'No printer connected'
                      : 'Connected to: ${selected!['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (selected != null)
                  TextButton.icon(
                    onPressed: _forgetPrinter,
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text(
                      'Forget Printer',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (_, i) {
                      final d = devices[i];
                      return ListTile(
                        title: Text(d.name ?? 'Unknown'),
                        subtitle: Text(d.macAdress ?? ''),
                        trailing: ElevatedButton(
                          onPressed: () => _connectPrinter(d),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                (selected != null &&
                                    selected!['mac'] == d.macAdress)
                                ? Colors.green
                                : Colors.blue,
                          ),
                          child: Text(
                            (selected != null &&
                                    selected!['mac'] == d.macAdress)
                                ? 'Connected'
                                : 'Connect',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    onPressed: _testPrint,
                    icon: const Icon(Icons.print),
                    label: const Text('Test Print'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
