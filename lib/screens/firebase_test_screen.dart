import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseTestScreen extends StatefulWidget {
  const FirebaseTestScreen({super.key});

  @override
  State<FirebaseTestScreen> createState() => _FirebaseTestScreenState();
}

class _FirebaseTestScreenState extends State<FirebaseTestScreen> {
  final TextEditingController _msgCtrl = TextEditingController();

  /// Reference to Firestore collection
  final CollectionReference _testCollection = FirebaseFirestore.instance
      .collection('test_messages');

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    await _testCollection.add({
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
      'device':
          'Device_${DateTime.now().millisecondsSinceEpoch}', // identify sender
    });

    _msgCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔥 Firebase Live Test'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          // 🔹 Input + Send button
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Type a message to sync',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),

          // 🔹 Live message list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _testCollection
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Send one!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final msg = data['message'] ?? '';
                    final device = data['device'] ?? '';
                    final time = data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate().toString()
                        : 'pending...';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: ListTile(
                        title: Text(msg),
                        subtitle: Text('From: $device\n$time'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
