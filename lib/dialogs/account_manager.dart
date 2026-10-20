import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AccountManagerDialog {
  static void show(BuildContext context, Box accountsBox, Function(String) getBalance) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final accounts = accountsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
          return AlertDialog(
            title: const Text('ખાતાઓ (Accounts) મેનેજ કરો'),
            content: SizedBox(
              width: double.maxFinite,
              height: 350,
              child: accounts.isEmpty
                  ? const Center(child: Text('કોઈ ખાતું ઉમેરેલ નથી.'))
                  : ListView.builder(
                      itemCount: accounts.length,
                      itemBuilder: (context, i) {
                        final a = accounts[i];
                        final bal = getBalance(a['id'].toString());
                        return Card(
                          child: ListTile(
                            dense: true,
                            title: Text(a['name'] ?? ''),
                            subtitle: Text("${a['type']}\nસિલક: ₹$bal"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                accountsBox.delete(a['id']);
                                setDlgState(() {});
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('નવું ખાતું'),
                onPressed: () => _openAddEditAccount(context, accountsBox, () => setDlgState(() {})),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
            ],
          );
        },
      ),
    );
  }

  static void _openAddEditAccount(BuildContext context, Box accountsBox, VoidCallback onSaved) {
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController(text: '0');
    String type = 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)';
    final types = [
      'સેવિંગ્સ એકાઉન્ટ (Savings A/C)',
      'સેલેરી એકાઉન્ટ (Salary A/C)',
      'કરન્ટ એકાઉન્ટ (Current A/C)',
      'રોકડ (Cash Wallet)',
      'ક્રેડિટ કાર્ડ (Credit Card)',
      'ફિક્સ ડિપોઝીટ (FD / RD)',
      'લોન / દેવું (Loan A/C)',
      'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('નવું ખાતું ઉમેરો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ખાતાનું નામ (SBI, HDFC વગેરે)')),
            DropdownButtonFormField<String>(
              value: type,
              items: types.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) => type = v!,
            ),
            TextField(controller: balCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'પ્રારંભિક સિલક (₹)')),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                final id = 'acc_${DateTime.now().millisecondsSinceEpoch}';
                accountsBox.put(id, {
                  'id': id,
                  'name': nameCtrl.text,
                  'type': type,
                  'openingBalance': double.tryParse(balCtrl.text) ?? 0.0,
                });
                onSaved();
                Navigator.pop(ctx);
              }
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }
}
