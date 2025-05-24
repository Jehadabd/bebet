import 'package:flutter/material.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر ديوني - الشاشة الرئيسية'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Debt Register Screen
                  // Navigator.pushNamed(context, '/debt_register'); // Placeholder
                },
                child: const Text('سجل الديون'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Product Entry Screen
                  // Navigator.pushNamed(context, '/product_entry'); // Placeholder
                },
                child: const Text('إدخال البضاعة'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Create Invoice Screen
                  // Navigator.pushNamed(context, '/create_invoice'); // Placeholder
                },
                child: const Text('إنشاء قائمة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 