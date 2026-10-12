import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_gate.dart';
import 'export_service.dart';

final ValueNotifier<Color> appSeedColor = ValueNotifier<Color>(Colors.teal);
final ValueNotifier<String?> appBackgroundImage = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Hive.openBox('settingsBox');
  await Hive.openBox('categoriesBox');
  await Hive.openBox('accountsBox'); // ખાતાઓ માટે નવું બોક્સ
  await Hive.openBox('transactionsBox');

  final settings = Hive.box('settingsBox');
  final savedColor = settings.get('primaryColor', defaultValue: Colors.teal.value);
  final savedImage = settings.get('backgroundImage', defaultValue: null);

  appSeedColor.value = Color(savedColor);
  appBackgroundImage.value = savedImage;

  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: appSeedColor,
      builder: (context, primaryColor, _) {
        return MaterialApp(
          title: 'નાણાકીય મેનેજર',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: primaryColor,
          ),
          home: const DashboardScreen(),
        );
      },
    );
  }
}

enum TimeFilter { daily, monthly, quarterly, halfYearly, yearly, custom }
enum AnalysisView { all, expenseOnly, incomeOnly, investmentOnly }
enum ChartGrouping { byCategory, byType }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Box categoriesBox;
  late Box accountsBox;
  late Box transactionsBox;
  late Box settingsBox;

  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTimeRange? customDateRange;
  String? selectedAccountId; // ફિલ્ટર માટે ચોક્કસ એકાઉન્ટ

  AnalysisView selectedAnalysisView = AnalysisView.all;
  ChartGrouping selectedGrouping = ChartGrouping.byCategory;

  @override
  void initState() {
    super.initState();
    categoriesBox = Hive.box('categoriesBox');
    accountsBox = Hive.box('accountsBox');
    transactionsBox = Hive.box('transactionsBox');
    settingsBox = Hive.box('settingsBox');

    if (categoriesBox.isEmpty) _saveDefaultCategories();
    if (accountsBox.isEmpty) _saveDefaultAccounts();
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

  void _saveDefaultAccounts() {
    final defaultAccs = [
      {'id': 'acc_1', 'name': 'રોકડ (Cash)', 'type': 'Cash'},
      {'id': 'acc_2', 'name': 'SBI બેંક એકાઉન્ટ', 'type': 'Bank'},
      {'id': 'acc_3', 'name': 'ક્રેડિટ કાર્ડ (Credit Card)', 'type': 'Credit'},
      {'id': 'acc_4', 'name': 'હોમ/પર્સનલ લોન (Loan)', 'type': 'Loan'},
    ];
    for (var acc in defaultAccs) {
      accountsBox.put(acc['id'], acc);
    }
  }

  List<Map<dynamic, dynamic>> get categories =>
      categoriesBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  List<Map<dynamic, dynamic>> get accounts =>
      accountsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  List<Map<dynamic, dynamic>> get filteredTransactions {
    final now = DateTime.now();
    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return allTx.where((tx) {
      final date = DateTime.parse(tx['date']);
      final diffDays = now.difference(date).inDays;

      // એકાઉન્ટ ફિલ્ટર
      if (selectedAccountId != null && tx['accountId'] != selectedAccountId) {
        return false;
      }

      // સમયગાળાનું ફિલ્ટર
      bool matchesTime = false;
      switch (selectedFilter) {
        case TimeFilter.daily:
          matchesTime = date.year == now.year && date.month == now.month && date.day == now.day;
          break;
        case TimeFilter.monthly:
          matchesTime = date.year == now.year && date.month == now.month;
          break;
        case TimeFilter.quarterly:
          matchesTime = diffDays <= 90 && diffDays >= 0;
          break;
        case TimeFilter.halfYearly:
          matchesTime = diffDays <= 182 && diffDays >= 0;
          break;
        case TimeFilter.yearly:
          matchesTime = date.year == now.year;
          break;
        case TimeFilter.custom:
          if (customDateRange != null) {
            final start = DateTime(customDateRange!.start.year, customDateRange!.start.month, customDateRange!.start.day);
            final end = DateTime(customDateRange!.end.year, customDateRange!.end.month, customDateRange!.end.day, 23, 59, 59);
            matchesTime = date.isAfter(start.subtract(const Duration(seconds: 1))) && date.isBefore(end);
          } else {
            matchesTime = true;
          }
          break;
      }
      if (!matchesTime) return false;

      // પ્રકાર ફિલ્ટર
      switch (selectedAnalysisView) {
        case AnalysisView.expenseOnly:
          return tx['categoryEffect'] == 'expenseDebit';
        case AnalysisView.incomeOnly:
          return tx['categoryEffect'] == 'incomeCredit';
        case AnalysisView.investmentOnly:
          return tx['categoryEffect'] == 'assetIncrease';
        case AnalysisView.all:
          return true;
      }
    }).toList();
  }

  double _calculateTotal(String effect) {
    return filteredTransactions
        .where((t) => t['categoryEffect'] == effect)
        .fold(0.0, (sum, item) {
          final amt = item['amount'];
          if (amt is num) return sum + amt.toDouble();
          return sum + (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
        });
  }

  // ટ્રાન્ઝેક્શન ઉમેરવા અથવા સુધારવા (Edit/Add) માટે એક જ ડાયલોગ
  void _openTransactionDialog({Map<dynamic, dynamic>? existingTx}) {
    final titleController = TextEditingController(text: existingTx != null ? existingTx['title'] : '');
    final amountController = TextEditingController(text: existingTx != null ? existingTx['amount'].toString() : '');
    
    if (categories.isEmpty || accounts.isEmpty) return;

    var selectedCat = existingTx != null
        ? categories.firstWhere((c) => c['id'].toString() == existingTx['categoryId'], orElse: () => categories.first)
        : categories.first;

    var selectedAcc = existingTx != null
        ? accounts.firstWhere((a) => a['id'].toString() == existingTx['accountId'], orElse: () => accounts.first)
        : accounts.first;

    DateTime transactionDate = existingTx != null ? DateTime.parse(existingTx['date']) : DateTime.now();

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existingTx == null ? 'નવો હિસાબ ઉમેરો' : 'હિસાબમાં સુધારો કરો (Edit)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'વિગત / શીર્ષક')),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'રકમ (₹)'),
                ),
                const SizedBox(height: 12),
                const Text('ખાતું પસંદ કરો:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedAcc['id'].toString(),
                  items: accounts.map((acc) {
                    return DropdownMenuItem<String>(
                      value: acc['id'].toString(),
                      child: Text('${acc['name']} (${acc['type']})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedAcc = accounts.firstWhere((a) => a['id'].toString() == val);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text('કેટેગરી પસંદ કરો:', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('તારીખ: ${DateFormat('dd/MM/yyyy').format(transactionDate)}'),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('તારીખ બદલો'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: transactionDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setModalState(() => transactionDate = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final enteredAmount = double.tryParse(amountController.text) ?? 0.0;
                      if (enteredAmount <= 0 || titleController.text.isEmpty) return;

                      final id = existingTx != null ? existingTx['id'] : DateTime.now().millisecondsSinceEpoch.toString();

                      transactionsBox.put(id, {
                        'id': id,
                        'title': titleController.text,
                        'amount': enteredAmount,
                        'date': transactionDate.toIso8601String(),
                        'categoryId': selectedCat['id'],
                        'categoryName': selectedCat['name'],
                        'categoryEffect': selectedCat['effect'],
                        'categoryColor': selectedCat['color'],
                        'accountId': selectedAcc['id'],
                        'accountName': selectedAcc['name'],
                      });

                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    child: Text(existingTx == null ? 'સેવ કરો' : 'અપડેટ કરો'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // બેંક / લોન / ક્રેડિટ ખાતાઓ મેનેજ કરવા માટે ડાયલોગ
  void _manageAccountsDialog() {
    final nameController = TextEditingController();
    String selectedType = 'Bank';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('નવું ખાતું ઉમેરો'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'ખાતાનું નામ (દા.ત. HDFC / પર્સનલ લોન)'),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Bank', child: Text('બેંક એકાઉન્ટ (Savings/Current)')),
                  DropdownMenuItem(value: 'Cash', child: Text('રોકડ (Cash)')),
                  DropdownMenuItem(value: 'Credit', child: Text('ક્રેડિટ કાર્ડ (Credit Card)')),
                  DropdownMenuItem(value: 'Loan', child: Text('લોન એકાઉન્ટ (Loan A/c)')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  final id = 'acc_${DateTime.now().millisecondsSinceEpoch}';
                  accountsBox.put(id, {
                    'id': id,
                    'name': nameController.text,
                    'type': selectedType,
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
    final totalIncome = _calculateTotal('incomeCredit');
    final netSavings = totalIncome - (totalExpense + assetGain);

    // ટકાવારીની ગણતરી
    final expensePercent = totalIncome > 0 ? (totalExpense / totalIncome) * 100 : 0.0;
    final investmentPercent = totalIncome > 0 ? (assetGain / totalIncome) * 100 : 0.0;
    final savingsPercent = totalIncome > 0 ? (netSavings / totalIncome) * 100 : 0.0;

    return ValueListenableBuilder<String?>(
      valueListenable: appBackgroundImage,
      builder: (context, bgPath, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('નાણાકીય વૉલ્ટ'),
            actions: [
              IconButton(
                icon: const Icon(Icons.account_balance),
                tooltip: 'ખાતા મેનેજ કરો',
                onPressed: _manageAccountsDialog,
              ),
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
                  const PopupMenuItem(value: 'csv', child: Text('Excel (CSV) શેર કરો')),
                  const PopupMenuItem(value: 'pdf', child: Text('PDF પ્રિન્ટ / સેવ કરો')),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              children: [
                // સમયગાળો અને એકાઉન્ટ ફિલ્ટર
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18),
                            const SizedBox(width: 8),
                            const Text('સમયગાળો:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<TimeFilter>(
                                isExpanded: true,
                                underline: const SizedBox(),
                                value: selectedFilter,
                                items: const [
                                  DropdownMenuItem(value: TimeFilter.daily, child: Text('આજનો દિવસ (Daily)')),
                                  DropdownMenuItem(value: TimeFilter.monthly, child: Text('ચાલુ મહિનો (Monthly)')),
                                  DropdownMenuItem(value: TimeFilter.quarterly, child: Text('ત્રિમાસિક (Quarterly)')),
                                  DropdownMenuItem(value: TimeFilter.halfYearly, child: Text('અર્ધ વાર્ષિક (Half Yearly)')),
