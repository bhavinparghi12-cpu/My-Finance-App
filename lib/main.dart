import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_gate.dart';
import 'export_service.dart';

final ValueNotifier<Color> appSeedColor = ValueNotifier<Color>(Colors.teal);
final ValueNotifier<String?> appBackgroundImage = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ૧. Firebase સુરક્ષિત રીતે શરૂ કરો
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  // ૨. Hive સુરક્ષિત રીતે શરૂ કરો
  try {
    await Hive.initFlutter();
    final settings = await Hive.openBox('settingsBox');

    final dynamic rawColor = settings.get('primaryColor');
    if (rawColor != null && rawColor is int) {
      appSeedColor.value = Color(rawColor);
    } else {
      appSeedColor.value = Colors.teal;
    }

    final dynamic rawImage = settings.get('backgroundImage');
    if (rawImage != null && rawImage is String) {
      appBackgroundImage.value = rawImage;
    }
  } catch (e) {
    debugPrint("Hive Init Error: $e");
  }

  // ૩. કોઈપણ સંજોગોમાં runApp રન થવું જ જોઈએ
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
          home: const AuthGate(),
        );
      },
    );
  }
}

enum TimeFilter { daily, monthly, quarterly, halfYearly, yearly, allHistory, custom }
enum AnalysisView { all, expenseOnly, incomeOnly, investmentOnly }
enum ChartType { pie, bar, line }

class DashboardScreen extends StatefulWidget {
  final String userEmail;
  final String catBoxName;
  final String accBoxName;
  final String txBoxName;

  const DashboardScreen({
    super.key,
    required this.userEmail,
    required this.catBoxName,
    required this.accBoxName,
    required this.txBoxName,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Box categoriesBox;
  late Box accountsBox;
  late Box transactionsBox;
  late Box settingsBox;
  Box? budgetBox;
  bool _isBudgetReady = false;

  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTimeRange? customDateRange;
  String? selectedAccountId;
  AnalysisView selectedAnalysisView = AnalysisView.all;
  ChartType selectedChartType = ChartType.pie;

  @override
  void initState() {
    super.initState();
    categoriesBox = Hive.box(widget.catBoxName);
    accountsBox = Hive.box(widget.accBoxName);
    transactionsBox = Hive.box(widget.txBoxName);
    settingsBox = Hive.box('settingsBox');

    _initBudgetBox();

    if (categoriesBox.isEmpty) _saveDefaultCategories();
    if (accountsBox.isEmpty) _saveDefaultAccounts();
  }

  Future<void> _initBudgetBox() async {
    final prefix = widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final bName = 'budgetBox_$prefix';
    if (!Hive.isBoxOpen(bName)) {
      budgetBox = await Hive.openBox(bName);
    } else {
      budgetBox = Hive.box(bName);
    }
    if (mounted) {
      setState(() {
        _isBudgetReady = true;
      });
    }
  }

  void _saveDefaultCategories() {
    final defaultCats = [
      {'id': '1', 'name': 'ઘરખર્ચ (Expense)', 'effect': 'expenseDebit', 'color': Colors.redAccent.toARGB32()},
      {'id': '2', 'name': 'પગાર / વ્યવસાય આવક', 'effect': 'incomeCredit', 'color': Colors.green.toARGB32()},
      {'id': '3', 'name': 'શેરબજાર / મ્યુચ્યુઅલ ફંડ રોકાણ', 'effect': 'assetIncrease', 'color': Colors.blue.toARGB32()},
      {'id': '4', 'name': 'લોન હપ્તો (EMI Payment)', 'effect': 'loanRepay', 'color': Colors.orange.toARGB32()},
    ];
    for (var cat in defaultCats) {
      categoriesBox.put(cat['id'], cat);
    }
  }

  void _saveDefaultAccounts() {
    final defaultAccs = [
      {'id': 'acc_1', 'name': 'રોકડ સિલક (Cash)', 'type': 'રોકડ (Cash Wallet)', 'openingBalance': 0.0},
      {'id': 'acc_2', 'name': 'સેવિંગ્સ બેંક એકાઉન્ટ', 'type': 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)', 'openingBalance': 0.0},
      {'id': 'acc_3', 'name': 'સેલેરી એકાઉન્ટ', 'type': 'સેલેરી એકાઉન્ટ (Salary A/C)', 'openingBalance': 0.0},
      {'id': 'acc_4', 'name': 'ક્રેડિટ કાર્ડ', 'type': 'ક્રેડિટ કાર્ડ (Credit Card)', 'openingBalance': 0.0},
    ];
    for (var acc in defaultAccs) {
      accountsBox.put(acc['id'], acc);
    }
  }

  List<Map<dynamic, dynamic>> get categories =>
      categoriesBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  List<Map<dynamic, dynamic>> get accounts =>
      accountsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  double getAccountCurrentBalance(String accountId) {
    final acc = accounts.firstWhere((a) => a['id'].toString() == accountId, orElse: () => {});
    double balance = (acc['openingBalance'] as num?)?.toDouble() ?? 0.0;

    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    for (var tx in allTx) {
      if (tx['accountId'] == accountId) {
        final amt = (tx['amount'] as num).toDouble();
        final effect = tx['categoryEffect'];
        if (effect == 'incomeCredit') {
          balance += amt;
        } else {
          balance -= amt;
        }
      }
    }
    return balance;
  }

  List<Map<dynamic, dynamic>> get filteredTransactions {
    final now = DateTime.now();
    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return allTx.where((tx) {
      final date = DateTime.parse(tx['date']);
      final diffDays = now.difference(date).inDays;

      if (selectedAccountId != null && tx['accountId'] != selectedAccountId) {
        return false;
      }

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
        case TimeFilter.allHistory:
          matchesTime = true;
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

      switch (selectedAnalysisView) {
        case AnalysisView.expenseOnly:
          return tx['categoryEffect'] == 'expenseDebit' || tx['categoryEffect'] == 'loanRepay';
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

  void _openAccountManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('ખાતાઓ (Accounts) મેનેજ કરો'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final a = accounts[i];
                final currentBal = getAccountCurrentBalance(a['id'].toString());
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    dense: true,
                    title: Text(a['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${a['type']}\nપ્રારંભિક: ₹${a['openingBalance'] ?? 0} | હાલની સિલક: ₹${currentBal.toStringAsFixed(0)}'),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _openAccountEditDialog(account: a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            accountsBox.delete(a['id']);
                            setDlgState(() {});
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('નવું ખાતું ઉમેરો'),
              onPressed: () => _openAccountEditDialog(),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
          ],
        ),
      ),
    );
  }

  void _openAccountEditDialog({Map<dynamic, dynamic>? account}) {
    final nameCtrl = TextEditingController(text: account != null ? account['name'] : '');
    final openingBalCtrl = TextEditingController(
      text: account != null ? (account['openingBalance']?.toString() ?? '0') : '0',
    );
    String type = account != null ? account['type'] : 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)';

    final accountTypes = [
      'સેવિંગ્સ એકાઉન્ટ (Savings A/C)',
      'સેલેરી એકાઉન્ટ (Salary A/C)',
      'કરન્ટ એકાઉન્ટ (Current A/C)',
      'રોકડ (Cash Wallet)',
      'ક્રેડિટ કાર્ડ (Credit Card)',
      'ફિક્સ ડિપોઝીટ (FD / RD)',
      'લોન / દેવું (Loan A/C)',
    ];

    if (!accountTypes.contains(type)) {
      accountTypes.add(type);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(account == null ? 'નવું ખાતું ઉમેરો' : 'ખાતામાં સુધારો'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'ખાતાનું નામ (દા.ત. SBI, HDFC)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type, // 👈 'value' ની જગ્યાએ 'initialValue' સુધાર્યું
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'ખાતાનો પ્રકાર'),
                items: accountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) {
                  if (v != null) type = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: openingBalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'પ્રારંભિક સિલક / મૂડી (₹)',
                  hintText: 'શરૂઆતમાં રહેલી રકમ',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                final id = account != null ? account['id'] : 'acc_${DateTime.now().millisecondsSinceEpoch}';
                final openBal = double.tryParse(openingBalCtrl.text) ?? 0.0;
                accountsBox.put(id, {
                  'id': id,
                  'name': nameCtrl.text,
                  'type': type,
                  'openingBalance': openBal,
                });
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  void _openBudgetPlannerDialog() {
    if (budgetBox == null) return;

    String period = 'માસિક બજેટ (Monthly)';
    final expenseBudgetCtrl = TextEditingController(text: budgetBox!.get('budgetExpense', defaultValue: 0.0).toString());
    final investmentBudgetCtrl = TextEditingController(text: budgetBox!.get('budgetInvestment', defaultValue: 0.0).toString());
    final savingsBudgetCtrl = TextEditingController(text: budgetBox!.get('budgetSavings', defaultValue: 0.0).toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pie_chart_outline, color: Colors.teal),
            SizedBox(width: 8),
            Text('બજેટ લક્ષ્યાંક આયોજન', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: period,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'માસિક બજેટ (Monthly)', child: Text('માસિક બજેટ')),
                  DropdownMenuItem(value: 'ત્રિમાસિક બજેટ (Quarterly)', child: Text('ત્રિમાસિક બજેટ')),
                  DropdownMenuItem(value: 'વાર્ષિક બજેટ (Yearly)', child: Text('વાર્ષિક બજેટ')),
                ],
                onChanged: (v) {},
              ),
              const SizedBox(height: 10),
              TextField(
                controller: expenseBudgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ખર્ચ મર્યાદા લક્ષ્યાંક (₹)'),
              ),
              TextField(
                controller: investmentBudgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'રોકાણ લક્ષ્યાંક (₹)'),
              ),
              TextField(
                controller: savingsBudgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'બચત લક્ષ્યાંક (₹)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          ElevatedButton(
            onPressed: () {
              budgetBox!.put('budgetExpense', double.tryParse(expenseBudgetCtrl.text) ?? 0.0);
              budgetBox!.put('budgetInvestment', double.tryParse(investmentBudgetCtrl.text) ?? 0.0);
              budgetBox!.put('budgetSavings', double.tryParse(savingsBudgetCtrl.text) ?? 0.0);
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('બજેટ સેવ કરો'),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicChart() {
    final Map<String, double> categorySums = {};
    for (var tx in filteredTransactions) {
      final name = tx['categoryName'] ?? 'અન્ય';
      final amt = (tx['amount'] as num).toDouble();
      categorySums[name] = (categorySums[name] ?? 0) + amt;
    }

    if (categorySums.isEmpty) return const SizedBox();

    final colors = [Colors.teal, Colors.redAccent, Colors.blue, Colors.orange, Colors.purple, Colors.amber, Colors.green];
    final entries = categorySums.entries.toList();

    Widget chartWidget;

    if (selectedChartType == ChartType.pie) {
      int cIdx = 0;
      final sections = entries.map((e) {
        final col = colors[cIdx % colors.length];
        cIdx++;
        return PieChartSectionData(
          value: e.value,
          title: '₹${e.value.toStringAsFixed(0)}',
          color: col,
          radius: 50,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        );
      }).toList();

      chartWidget = PieChart(
        PieChartData(sections: sections, centerSpaceRadius: 35, sectionsSpace: 2),
      );
    } else if (selectedChartType == ChartType.bar) {
      final barGroups = List.generate(entries.length, (i) {
        return BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entries[i].value,
              color: colors[i % colors.length],
              width: 14,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        );
      });

      chartWidget = BarChart(
        BarChartData(
          barGroups: barGroups,
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < entries.length) {
                    final label = entries[idx].key;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(label.length > 5 ? '${label.substring(0, 5)}..' : label, style: const TextStyle(fontSize: 9)),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      );
    } else {
      final spots = List.generate(entries.length, (i) => FlSpot(i.toDouble(), entries[i].value));
      chartWidget = LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.teal,
              barWidth: 3,
              belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)),
              dotData: const FlDotData(show: true),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('વિશ્લેષણ આલેખ (Analysis Chart)', style: TextStyle(fontWeight: FontWeight.bold)),
                SegmentedButton<ChartType>(
                  segments: const [
                    ButtonSegment(value: ChartType.pie, icon: Icon(Icons.pie_chart, size: 16)),
                    ButtonSegment(value: ChartType.bar, icon: Icon(Icons.bar_chart, size: 16)),
                    ButtonSegment(value: ChartType.line, icon: Icon(Icons.show_chart, size: 16)),
                  ],
                  selected: {selectedChartType},
                  onSelectionChanged: (Set<ChartType> newSelection) {
                    setState(() => selectedChartType = newSelection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 170, child: chartWidget),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetSummaryCard(double currentExpense, double currentInvestment, double currentSavings) {
    if (!_isBudgetReady || budgetBox == null) return const SizedBox();
    final budgetExpense = (budgetBox!.get('budgetExpense', defaultValue: 0.0) as num).toDouble();

    if (budgetExpense <= 0) return const SizedBox();

    final percent = (currentExpense / budgetExpense).clamp(0.0, 1.0);

    return Card(
      color: Colors.amber.shade50,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('બજેટ મર્યાદા (Expense vs Target)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('₹${currentExpense.toStringAsFixed(0)} / ₹${budgetExpense.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: percent,
              color: percent > 0.85 ? Colors.red : Colors.teal,
              backgroundColor: Colors.grey.shade300,
              minHeight: 7,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color) {
    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.12), // 👈 withValues(alpha:) સુધાર્યું
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 6.0),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '₹${amount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategoryManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('કેટેગરી મેનેજ કરો'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final c = categories[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: Color(c['color']), radius: 12),
                  title: Text(c['name']),
                  subtitle: Text(c['effect']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _openCategoryEditDialog(category: c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                        onPressed: () {
                          categoriesBox.delete(c['id']);
                          setDlgState(() {});
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('નવી કેટેગરી ઉમેરો'),
              onPressed: () => _openCategoryEditDialog(),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
          ],
        ),
      ),
    );
  }

  void _openCategoryEditDialog({Map<dynamic, dynamic>? category}) {
    final nameCtrl = TextEditingController(text: category != null ? category['name'] : '');
    String effect = category != null ? category['effect'] : 'expenseDebit';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == null ? 'નવી કેટેગરી ઉમેરો' : 'કેટેગરીમાં સુધારો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'કેટેગરી નામ')),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: effect,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'expenseDebit', child: Text('ખર્ચ (Expense)')),
                DropdownMenuItem(value: 'incomeCredit', child: Text('આવક (Income)')),
                DropdownMenuItem(value: 'assetIncrease', child: Text('રોકાણ (Investment)')),
                DropdownMenuItem(value: 'loanRepay', child: Text('લોન / દેવું (Loan/Debt)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => effect = v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                final id = category != null ? category['id'] : DateTime.now().millisecondsSinceEpoch.toString();
                Color col = effect == 'incomeCredit'
                    ? Colors.green
                    : (effect == 'assetIncrease' ? Colors.blue : (effect == 'loanRepay' ? Colors.orange : Colors.redAccent));

                categoriesBox.put(id, {
                  'id': id,
                  'name': nameCtrl.text,
                  'effect': effect,
                  'color': col.toARGB32(), // 👈 .toARGB32() સુધાર્યું
                });
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

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
                  existingTx == null ? 'નવો હિસાબ ઉમેરો' : 'હિસાબ સુધારો (Edit Entry)',
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
                    final bal = getAccountCurrentBalance(acc['id'].toString());
                    return DropdownMenuItem<String>(
                      value: acc['id'].toString(),
                      child: Text('${acc['name']} (સિલક: ₹${bal.toStringAsFixed(0)})'),
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
                    child: Text(existingTx == null ? 'સેવ કરો' : 'સુધારો અપડેટ કરો'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openThemeCustomizer() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('થીમ અને બેકગ્રાઉન્ડ બદલો', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text('મનપસંદ થીમ કલર પસંદ કરો:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                Colors.teal,
                Colors.blue,
                Colors.deepPurple,
                Colors.indigo,
                Colors.brown,
                Colors.blueGrey,
              ].map((c) {
                return GestureDetector(
                  onTap: () {
                    appSeedColor.value = c;
                    settingsBox.put('primaryColor', c.toARGB32()); // 👈 .toARGB32() સુધાર્યું
                    Navigator.pop(ctx);
                  },
                  child: CircleAvatar(backgroundColor: c, radius: 18),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            const Text('ફોનની ગેલેરીમાંથી બેકગ્રાઉન્ડ ફોટો:'),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('ગેલેરીમાંથી ફોટો લાવો'),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      appBackgroundImage.value = image.path;
                      await settingsBox.put('backgroundImage', image.path);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                const SizedBox(width: 8),
                if (appBackgroundImage.value != null)
                  TextButton.icon(
                    icon: const Icon(Icons.clear, color: Colors.red),
                    label: const Text('ફોટો હટાવો'),
                    onPressed: () async {
                      appBackgroundImage.value = null;
                      await settingsBox.delete('backgroundImage');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetGain = _calculateTotal('assetIncrease');
    final totalExpense = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    final totalIncome = _calculateTotal('incomeCredit');
    final netSavings = totalIncome - (totalExpense + assetGain);

    return ValueListenableBuilder<String?>(
      valueListenable: appBackgroundImage,
      builder: (context, bgPath, _) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('નાણાકીય વૉલ્ટ', style: TextStyle(fontSize: 18)),
                Text(widget.userEmail, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            actions: [
              IconButton(icon: const Icon(Icons.savings_outlined), tooltip: 'બજેટ આયોજન', onPressed: _openBudgetPlannerDialog),
              IconButton(icon: const Icon(Icons.palette), tooltip: 'થીમ / બેકગ્રાઉન્ડ', onPressed: _openThemeCustomizer),
              IconButton(icon: const Icon(Icons.category), tooltip: 'કેટેગરી મેનેજર', onPressed: _openCategoryManager),
              IconButton(icon: const Icon(Icons.account_balance), tooltip: 'ખાતાઓ', onPressed: _openAccountManager),
              PopupMenuButton<String>(
                icon: const Icon(Icons.file_download),
                tooltip: 'એક્સપોર્ટ રિપોર્ટ',
                onSelected: (value) async {
                  if (filteredTransactions.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('રિપોર્ટ માટે કોઈ ડેટા નથી!')),
                    );
                    return;
                  }
                  if (value == 'csv') {
                    await ExportService.exportToCSV(filteredTransactions);
                  } else if (value == 'pdf') {
                    await ExportService.exportToPDF(
                      filteredTransactions,
                      totalIncome,
                      totalExpense,
                      assetGain,
                      netSavings,
                      selectedFilter.name.toUpperCase(),
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'csv', child: Text('Excel (CSV) શેર કરો')),
                  const PopupMenuItem(value: 'pdf', child: Text('PDF પ્રિન્ટ / સેવ કરો')),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'લોક કરો',
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthGate()));
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openTransactionDialog(),
            tooltip: 'હિસાબ ઉમેરો',
            child: const Icon(Icons.add),
          ),
          body: Container(
            decoration: bgPath != null
                ? BoxDecoration(
                    image: DecorationImage(
                      image: FileImage(File(bgPath)),
                      fit: BoxFit.cover,
                    ),
                  )
                : null,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              const Text('સમયગાળો:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<TimeFilter>(
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  value: selectedFilter,
                                  items: const [
                                    DropdownMenuItem(value: TimeFilter.daily, child: Text('આજનો દિવસ')),
                                    DropdownMenuItem(value: TimeFilter.monthly, child: Text('ચાલુ મહિનો')),
                                    DropdownMenuItem(value: TimeFilter.quarterly, child: Text('ત્રિમાસિક (Quarterly)')),
                                    DropdownMenuItem(value: TimeFilter.halfYearly, child: Text('છ માસિક (Half Yearly)')),
                                    DropdownMenuItem(value: TimeFilter.yearly, child: Text('વાર્ષિક (Yearly)')),
                                    DropdownMenuItem(value: TimeFilter.allHistory, child: Text('તમામ હિસ્ટ્રી (All History)')),
                                    DropdownMenuItem(value: TimeFilter.custom, child: Text('કસ્ટમ તારીખ (Custom Range)')),
                                  ],
                                  onChanged: (TimeFilter? newValue) async {
                                    if (newValue == null) return;
                                    if (newValue == TimeFilter.custom) {
                                      final picked = await showDateRangePicker(
                                        context: context,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          customDateRange = picked;
                                          selectedFilter = newValue;
                                        });
                                      }
                                    } else {
                                      setState(() => selectedFilter = newValue);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          Row(
                            children: [
                              const Icon(Icons.filter_alt, size: 16),
                              const SizedBox(width: 8),
                              const Text('વ્યૂ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<AnalysisView>(
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  value: selectedAnalysisView,
                                  items: const [
                                    DropdownMenuItem(value: AnalysisView.all, child: Text('તમામ વ્યવહારો')),
                                    DropdownMenuItem(value: AnalysisView.expenseOnly, child: Text('માત્ર ખર્ચ / લોન')),
                                    DropdownMenuItem(value: AnalysisView.incomeOnly, child: Text('માત્ર આવક')),
                                    DropdownMenuItem(value: AnalysisView.investmentOnly, child: Text('માત્ર રોકાણ')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => selectedAnalysisView = val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildSummaryCard('આવક', totalIncome, Colors.green),
                      _buildSummaryCard('ખર્ચ/દેવું', totalExpense, Colors.redAccent),
                      _buildSummaryCard('રોકાણ', assetGain, Colors.blue),
                      _buildSummaryCard('બચત', netSavings, Colors.teal),
                    ],
                  ),
                  _buildBudgetSummaryCard(totalExpense, assetGain, netSavings),
                  const SizedBox(height: 10),
                  _buildDynamicChart(),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'વ્યવહારોની હિસ્ટ્રી (${filteredTransactions.length})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (filteredTransactions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30.0),
                      child: Center(child: Text('કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTransactions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tx = filteredTransactions[index];
                        final effect = tx['categoryEffect'];
                        final isIncome = effect == 'incomeCredit';
                        final isExpense = effect == 'expenseDebit' || effect == 'loanRepay';
                        final amountColor = isIncome ? Colors.green : (isExpense ? Colors.redAccent : Colors.blue);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: amountColor.withValues(alpha: 0.15), // 👈 withValues(alpha:) સુધાર્યું
                              child: Icon(
                                isIncome ? Icons.arrow_downward : (isExpense ? Icons.arrow_upward : Icons.trending_up),
                                color: amountColor,
                              ),
                            ),
                            title: Text(tx['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${tx['categoryName']} • ${tx['accountName'] ?? ''}\n${DateFormat('dd MMM yyyy').format(DateTime.parse(tx['date']))}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₹${tx['amount']}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: amountColor),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _openTransactionDialog(existingTx: tx),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.grey),
                                  onPressed: () {
                                    transactionsBox.delete(tx['id']);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
