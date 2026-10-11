import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auth_gate.dart';
import 'export_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'નાણાકીય મેનેજર',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const AuthGate(),
    );
  }
}

enum TimeFilter { daily, monthly, quarterly, halfYearly, yearly }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Box categoriesBox;
  late Box transactionsBox;
  TimeFilter selectedFilter = TimeFilter.monthly;

  @override
  void initState() {
    super.initState();
    categoriesBox = Hive.box('categoriesBox');
    transactionsBox = Hive.box('transactionsBox');

    if (categoriesBox.isEmpty) {
      _saveDefaultCategories();
    }
  }

  void _saveDefaultCategories() {
    final defaultCats = [
      {'id': '1', 'name': 'રોકાણ (Investment)', 'effect': 'assetIncrease', 'color': Colors.blue.value},
      {'id': '2', 'name': 'ઘરખર્ચ (Expense)', 'effect': 'expenseDebit', 'color': Colors.redAccent.value},
      {'id': '3', 'name': 'પગાર (Income)', 'effect': 'incomeCredit', 'color': Colors.green.value},
    ];
    for (var cat in defaultCats) {
      categoriesBox.put(cat['id'], cat);
    }
  }

  List<Map<dynamic, dynamic>> get categories {
    return categoriesBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
  }

  List<Map<dynamic, dynamic>> get filteredTransactions {
    final now = DateTime.now();
    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return allTx.where((tx) {
      final date = DateTime.parse(tx['date']);
      final diffDays = now.difference(date).inDays;

      switch (selectedFilter) {
        case TimeFilter.daily:
          return date.year == now.year && date.month == now.month && date.day == now.day;
        case TimeFilter.monthly:
          return date.year == now.year && date.month == now.month;
        case TimeFilter.quarterly:
          return diffDays <= 90 && date.isBefore(now.add(const Duration(days: 1)));
        case TimeFilter.halfYearly:
          return diffDays <= 182 && date.isBefore(now.add(const Duration(days: 1)));
        case TimeFilter.yearly:
          return date.year == now.year;
      }
    }).toList();
  }

  double _calculateTotal(String effect) {
    return filteredTransactions
        .where((t) => t['categoryEffect'] == effect)
        .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
  }

  void _addTransactionDialog() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    if (categories.isEmpty) return;
    var selectedCat = categories.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('નવો હિસાબ ઉમેરો', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'વિગત / શીર્ષક')),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'રકમ (₹)'),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedCat['id'].toString(),
                items: categories.map((cat) {
                  return DropdownMenuItem<String>(
                    value: cat['id'].toString(),
                    child: Text('${cat['name']}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() {
                      selectedCat = categories.firstWhere((c) => c['id'].toString() == val);
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final enteredAmount = double.tryParse(amountController.text) ?? 0.0;
                  if (enteredAmount <= 0 || titleController.text.isEmpty) return;

                  final id = DateTime.now().millisecondsSinceEpoch.toString();
                  transactionsBox.put(id, {
                    'id': id,
                    'title': titleController.text,
                    'amount': enteredAmount,
                    'date': DateTime.now().toIso8601String(),
                    'categoryName': selectedCat['name'],
                    'categoryEffect': selectedCat['effect'],
                    'categoryColor': selectedCat['color'],
                  });

                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('સેવ કરો'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _manageCategoriesDialog() {
    final nameController = TextEditingController();
    String selectedEffect = 'assetIncrease';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('નવી કેટેગરી બનાવો'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'કેટેગરીનું નામ')),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedEffect,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'assetIncrease', child: Text('સંપત્તિમાં વધારો (Investment)')),
                  DropdownMenuItem(value: 'expenseDebit', child: Text('ખાતામાંથી બાદ (Expense)')),
                  DropdownMenuItem(value: 'incomeCredit', child: Text('ખાતામાં જમા (Income)')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedEffect = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  final id = DateTime.now().millisecondsSinceEpoch.toString();
                  final color = Colors.primaries[categories.length % Colors.primaries.length].value;

                  categoriesBox.put(id, {
                    'id': id,
                    'name': nameController.text,
                    'effect': selectedEffect,
                    'color': color,
                  });

                  setState(() {});
                  Navigator.pop(ctx);
                }
              },
              child: const Text('ઉમેરો'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetGain = _calculateTotal('assetIncrease');
    final totalExpense = _calculateTotal('expenseDebit');

    return Scaffold(
      appBar: AppBar(
        title: const Text('નાણાકીય વૉલ્ટ'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download),
            tooltip: 'એક્સપોર્ટ કરો',
            onSelected: (value) async {
              if (filteredTransactions.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('એક્સપોર્ટ માટે કોઈ ડેટા નથી!')),
                );
                return;
              }

              if (value == 'csv') {
                await ExportService.exportToCSV(filteredTransactions);
              } else if (value == 'pdf') {
                await ExportService.exportToPDF(
                  filteredTransactions,
                  assetGain,
                  totalExpense,
                  selectedFilter.name.toUpperCase(),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Excel (CSV) શેર કરો'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.red),
                    SizedBox(width: 8),
                    Text('PDF પ્રિન્ટ / સેવ કરો'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'કેટેગરી મેનેજ કરો',
            onPressed: _manageCategoriesDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: TimeFilter.values.map((filter) {
                    final label = {
                      TimeFilter.daily: 'દિવસ',
                      TimeFilter.monthly: 'મહિનો',
                      TimeFilter.quarterly: 'ત્રિમાસિક',
                      TimeFilter.halfYearly: 'અર્ધ વાર્ષિક',
                      TimeFilter.yearly: 'વાર્ષિક',
                    }[filter]!;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: selectedFilter == filter,
                        onSelected: (_) => setState(() => selectedFilter = filter),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard('સંપત્તિ વધારો', '₹${assetGain.toStringAsFixed(2)}', Colors.blue),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard('કુલ ખર્ચ', '₹${totalExpense.toStringAsFixed(2)}', Colors.redAccent),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('કેટેગરી ચાર્ટ વિશ્લેષણ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: filteredTransactions.isEmpty
                    ? const Center(child: Text('આ સમયગાળામાં કોઈ વ્યવહાર નથી'))
                    : PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: _generateChartSections(),
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredTransactions.length,
                itemBuilder: (ctx, i) {
                  final tx = filteredTransactions[i];
                  final date = DateTime.parse(tx['date']);
                  return Dismissible(
                    key: Key(tx['id'].toString()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      transactionsBox.delete(tx['id']);
                      setState(() {});
                    },
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: Color(tx['categoryColor'])),
                        title: Text(tx['title']),
                        subtitle: Text('${tx['categoryName']} • ${DateFormat('dd MMM yyyy').format(date)}'),
                        trailing: Text(
                          '₹${(tx['amount'] as num).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: tx['categoryEffect'] == 'assetIncrease'
                                ? Colors.blue
                                : (tx['categoryEffect'] == 'expenseDebit' ? Colors.red : Colors.green),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTransactionDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _generateChartSections() {
    Map<String, double> categorySums = {};
    Map<String, int> categoryColors = {};

    for (var tx in filteredTransactions) {
      final name = tx['categoryName'].toString();
      categorySums[name] = (categorySums[name] ?? 0.0) + (tx['amount'] as num).toDouble();
      categoryColors[name] = tx['categoryColor'] as int;
    }

    return categorySums.entries.map((entry) {
      return PieChartSectionData(
        value: entry.value,
        title: '${entry.key}\n₹${entry.value.toInt()}',
        color: Color(categoryColors[entry.key] ?? Colors.grey.value),
        radius: 60,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }
}
