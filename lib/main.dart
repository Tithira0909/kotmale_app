import 'package:flutter/material.dart';
import 'screens/main_navigation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      const SizedBox.shrink();

  runApp(const KotmaleApp());
}

class KotmaleApp extends StatelessWidget {
  const KotmaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kotmale Stock Manager',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainNavigation(),
    );
  }
}
