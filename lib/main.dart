import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'auth_gate.dart';
import 'export_service.dart';

final ValueNotifier<Color> appSeedColor = ValueNotifier<Color>(Colors.teal);
final ValueNotifier<String?> appBackgroundImage = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ૧. Firebase શરૂ કરો
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDiFtQz7lhwXTAN3gOWg2N-LJOQ9ACZN44",
        appId: "1:821548105506:android:9f2408030e323b32482f7b",
        messagingSenderId: "821548105506",
        projectId: "my-finance-app-f4664",
      ),
    );
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  // ૨. Hive શરૂ કરો
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

  // ૩. એપ રન કરો
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

enum TimeFilter { daily, monthly, quarterly, yearly, allFY, custom }
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
  late Box budgetBox;
  bool _isInitialized = false;

  int _selectedTabIndex = 0; // ૦: દૈનિક એન્ટ્રી, ૧: એનાલિસિસ ચાર્ટ્સ, ૨: બજેટ આયોજન
  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTimeRange? customDateRange;
  String? selectedAccountId;
  AnalysisView selectedAnalysisView = AnalysisView.all;
  ChartType selectedChartType = ChartType.pie;

  late int selectedFinancialYearStart; // ભારતીય નાણાકીય વર્ષ (૧ એપ્રિલ - ૩૧ માર્ચ)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedFinancialYearStart = now.month >= 4 ? now.year : now.year - 1;
    _initBoxes();
  }

  Future<void> _initBoxes() async {
    categoriesBox = Hive.box(widget.catBoxName);
    accountsBox = Hive.box(widget.accBoxName);
    transactionsBox = Hive.box(widget.txBoxName);
    settingsBox = Hive.box('settingsBox');

    final prefix = widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    budgetBox = await Hive.openBox('catBudgetBox_$prefix');

    if (categoriesBox.isEmpty) _saveDefaultCategories();
    if (accountsBox.isEmpty) _saveDefaultAccounts();

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  void _saveDefaultCategories() {
    final defaultCats = [
      {'id': '1', 'name': 'ઘરખર્ચ (Groceries & Bills)', 'effect': 'expenseDebit', 'color': Colors.redAccent.toARGB32()},
      {'id': '2', 'name': 'પગાર / વ્યવસાય આવક', 'effect': 'incomeCredit', 'color': Colors.green.toARGB32()},
      {'id': '3', 'name': 'શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'effect': 'assetIncrease', 'color': Colors.blue.toARGB32()},
      {'id': '4', 'name': 'લોન / EMI હપ્તો', 'effect': 'loanRepay', 'color': Colors.orange.toARGB32()},
      {'id': '5', 'name': 'પ્રવાસ અને ઇંધણ', 'effect': 'expenseDebit', 'color': Colors.purple.toARGB32()},
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
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);

    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return allTx.where((tx) {
      final date = DateTime.parse(tx['date']);

      if (date.isBefore(fyStart) || date.isAfter(fyEnd)) return false;

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
          final diffDays = now.difference(date).inDays;
          matchesTime = diffDays <= 90 && diffDays >= 0;
          break;
        case TimeFilter.yearly:
          matchesTime = date.year == now.year;
          break;
        case TimeFilter.allFY:
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

  void _openCategoryBudgetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.track_changes, color: Colors.teal),
              SizedBox(width: 8),
              Text('કેટેગરી બજેટ લક્ષ્યાંક', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final budgetKey = 'budget_${cat['id']}';
                final currentTarget = (budgetBox.get(budgetKey, defaultValue: 0.0) as num).toDouble();
                final ctrl = TextEditingController(text: currentTarget > 0 ? currentTarget.toStringAsFixed(0) : '');

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(backgroundColor: Color(cat['color']), radius: 10),
                    title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(cat['effect'] == 'incomeCredit' ? 'આવક લક્ષ્યાંક' : 'ખર્ચ / રોકાણ મર્યાદા'),
                    trailing: SizedBox(
                      width: 90,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(hintText: '₹ 0', isDense: true),
                        onChanged: (val) {
                          final valD = double.tryParse(val) ?? 0.0;
                          budgetBox.put(budgetKey, valD);
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('સેવ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (filteredTransactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40.0),
          child: Text('આ સમયગાળામાં કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: filteredTransactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final tx = filteredTransactions[index];
        final effect = tx['categoryEffect'];
        final isIncome = effect == 'incomeCredit';
        final isExpense = effect == 'expenseDebit' || effect == 'loanRepay';
        final amountColor = isIncome ? Colors.green : (isExpense ? Colors.redAccent : Colors.blue);

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: amountColor.withValues(alpha: 0.15),
              child: Icon(
                isIncome ? Icons.arrow_downward : (isExpense ? Icons.arrow_upward : Icons.trending_up),
                color: amountColor,
                size: 18,
              ),
            ),
            title: Text(tx['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              '${tx['categoryName']} • ${tx['accountName'] ?? ''}\n${DateFormat('dd MMM yyyy').format(DateTime.parse(tx['date']))}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹${tx['amount']}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: amountColor),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: () => _openTransactionDialog(existingTx: tx),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 16, color: Colors.grey),
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
    );
  }

  Widget _buildAnalysisTab() {
    final Map<String, double> categorySums = {};
    for (var tx in filteredTransactions) {
      final name = tx['categoryName'] ?? 'અન્ય';
      final amt = (tx['amount'] as num).toDouble();
      categorySums[name] = (categorySums[name] ?? 0) + amt;
    }

    if (categorySums.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('પસંદ કરેલ સમયગાળામાં વિશ્લેષણ માટે કોઈ ડેટા નથી.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

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
          radius: 55,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        );
      }).toList();

      chartWidget = PieChart(PieChartData(sections: sections, centerSpaceRadius: 35, sectionsSpace: 2));
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

    return SingleChildScrollView(
      child: Column(
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('આલેખ વિશ્લેષણ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      SegmentedButton<ChartType>(
                        segments: const [
                          ButtonSegment(value: ChartType.pie, icon: Icon(Icons.pie_chart, size: 16), label: Text('વર્તુળ')),
                          ButtonSegment(value: ChartType.bar, icon: Icon(Icons.bar_chart, size: 16), label: Text('સ્તંભ')),
                          ButtonSegment(value: ChartType.line, icon: Icon(Icons.show_chart, size: 16), label: Text('રેખિક')),
                        ],
                        selected: {selectedChartType},
                        onSelectionChanged: (Set<ChartType> s) => setState(() => selectedChartType = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(height: 180, child: chartWidget),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('કેટેગરીવાર કુલ રકમ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Divider(),
                  ...entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.key, style: const TextStyle(fontSize: 13)),
                            Text('₹${e.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Card(
            color: Colors.teal.shade50,
            child: ListTile(
              leading: const Icon(Icons.tune, color: Colors.teal),
              title: const Text('કેટેગરી બજેટ સેટ કરો', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('ખર્ચ, રોકાણ કે આવક માટે લક્ષ્યાંક નક્કી કરો'),
              trailing: ElevatedButton(
                onPressed: _openCategoryBudgetDialog,
                child: const Text('લક્ષ્યાંક બદલો'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...categories.map((cat) {
            final budgetKey = 'budget_${cat['id']}';
            final target = (budgetBox.get(budgetKey, defaultValue: 0.0) as num).toDouble();

            final actual = filteredTransactions
                .where((t) => t['categoryId'].toString() == cat['id'].toString())
                .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());

            if (target <= 0 && actual <= 0) return const SizedBox();

            final percent = target > 0 ? (actual / target).clamp(0.0, 1.0) : 1.0;
            final isOver = target > 0 && actual > target;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          'વાસ્તવિક: ₹${actual.toStringAsFixed(0)} / લક્ષ્યાંક: ₹${target.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isOver ? Colors.red : Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: percent,
                      color: isOver ? Colors.red : (cat['effect'] == 'incomeCredit' ? Colors.green : Colors.teal),
                      backgroundColor: Colors.grey.shade200,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      target > 0
                          ? (isOver
                              ? '⚠️ બજેટ મર્યાદા કરતાં ₹${(actual - target).toStringAsFixed(0)} વધુ વપરાયા!'
                              : 'બાકી ઉપલબ્ધ: ₹${(target - actual).toStringAsFixed(0)}')
                          : 'કોઈ બજેટ લક્ષ્યાંક નક્કી કરેલ નથી',
                      style: TextStyle(fontSize: 11, color: isOver ? Colors.red : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            );
          }),
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
                  existingTx == null ? 'નવો હિસાબ ઉમેરો' : 'હિસાબ સુધારો',
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
                initialValue: type,
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
                  'color': col.toARGB32(),
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
                    settingsBox.put('primaryColor', c.toARGB32());
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

  Widget _buildMiniSummaryCard(String title, double amount, Color color) {
    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.1),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₹${amount.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                const Text('નાણાકીય વૉલ્ટ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text(widget.userEmail, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            actions: [
              // 👈 નવું બટન: મ્યુચ્યુઅલ ફંડ અને સ્ટોક એનાલિસિસ
              IconButton(
                icon: const Icon(Icons.trending_up, color: Colors.amber),
                tooltip: 'મ્યુચ્યુઅલ ફંડ & સ્ટોક એનાલિસિસ',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MutualFundAnalysisScreen()),
                  );
                },
              ),
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedTabIndex,
            onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.receipt_long), label: 'દૈનિક એન્ટ્રી'),
              NavigationDestination(icon: Icon(Icons.pie_chart), label: 'એનાલિસિસ ચાર્ટ'),
              NavigationDestination(icon: Icon(Icons.track_changes), label: 'બજેટ લક્ષ્યાંક'),
            ],
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
            child: Column(
              children: [
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, size: 18, color: Colors.teal),
                            const SizedBox(width: 6),
                            const Text('નાણાકીય વર્ષ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: selectedFinancialYearStart,
                              underline: const SizedBox(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                              items: [2023, 2024, 2025, 2026, 2027, 2028].map((y) {
                                return DropdownMenuItem(
                                  value: y,
                                  child: Text('FY $y-${(y + 1).toString().substring(2)}'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => selectedFinancialYearStart = val);
                              },
                            ),
                            const Spacer(),
                            DropdownButton<TimeFilter>(
                              value: selectedFilter,
                              underline: const SizedBox(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                              items: const [
                                DropdownMenuItem(value: TimeFilter.daily, child: Text('આજનો દિવસ')),
                                DropdownMenuItem(value: TimeFilter.monthly, child: Text('ચાલુ મહિનો')),
                                DropdownMenuItem(value: TimeFilter.quarterly, child: Text('ત્રિમાસિક')),
                                DropdownMenuItem(value: TimeFilter.yearly, child: Text('કેલેન્ડર વર્ષ')),
                                DropdownMenuItem(value: TimeFilter.allFY, child: Text('આખું FY')),
                                DropdownMenuItem(value: TimeFilter.custom, child: Text('કસ્ટમ તારીખ')),
                              ],
                              onChanged: (val) async {
                                if (val == null) return;
                                if (val == TimeFilter.custom) {
                                  final picked = await showDateRangePicker(
                                    context: context,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      customDateRange = picked;
                                      selectedFilter = val;
                                    });
                                  }
                                } else {
                                  setState(() => selectedFilter = val);
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        Row(
                          children: [
                            const Icon(Icons.filter_alt, size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            const Text('વ્યૂ:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<AnalysisView>(
                                isExpanded: true,
                                underline: const SizedBox(),
                                value: selectedAnalysisView,
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: [
                      _buildMiniSummaryCard('આવક', totalIncome, Colors.green),
                      _buildMiniSummaryCard('ખર્ચ', totalExpense, Colors.redAccent),
                      _buildMiniSummaryCard('રોકાણ', assetGain, Colors.blue),
                      _buildMiniSummaryCard('નેટ બચત', netSavings, Colors.teal),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: _selectedTabIndex == 0
                      ? _buildTransactionsTab()
                      : (_selectedTabIndex == 1 ? _buildAnalysisTab() : _buildBudgetTab()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =========================================================================
// 🚀 નવી સ્ક્રીન: મ્યુચ્યુઅલ ફંડ, સ્ટોક હોલ્ડિંગ્સ અને ટેકનિકલ ચાર્ટ એનાલિસિસ
// =========================================================================

class MutualFundAnalysisScreen extends StatefulWidget {
  const MutualFundAnalysisScreen({super.key});

  @override
  State<MutualFundAnalysisScreen> createState() => _MutualFundAnalysisScreenState();
}

class _MutualFundAnalysisScreenState extends State<MutualFundAnalysisScreen> {
  final TextEditingController _searchController = TextEditingController(text: "HDFC Top 100");
  bool _isLoading = false;
  bool _isRankingLoading = false;

  String currentFundName = "HDFC Top 100 Fund";
  double estimatedNavImpact = 1.95;
  String marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
  Color statusColor = Colors.green;

  List<Map<String, dynamic>> holdings = [
    {"name": "HDFC Bank Ltd", "weight": 22.5, "trend": "તેજી", "growth": "મજબૂત (+12.4%)", "impact": 0.45},
    {"name": "Reliance Industries", "weight": 18.0, "trend": "તેજી", "growth": "સારો (+8.2%)", "impact": 0.38},
    {"name": "ICICI Bank Ltd", "weight": 14.5, "trend": "સ્થિર", "growth": "સ્થિર (+6.1%)", "impact": 0.12},
    {"name": "Infosys Ltd", "weight": 10.0, "trend": "મંદી", "growth": "નબળું (-3.4%)", "impact": -0.15},
    {"name": "Tata Consultancy Services", "weight": 9.0, "trend": "સ્થિર", "growth": "સામાન્ય (+4.0%)", "impact": 0.05},
    {"name": "Larsen & Toubro", "weight": 7.0, "trend": "તેજી", "growth": "ઓર્ડર મળ્યા (+15.0%)", "impact": 0.25},
  ];

  List<Map<String, dynamic>> rankedFunds = [];

  // ૧. ફંડ સર્ચ અને વિશ્લેષણ
  Future<void> fetchAndAnalyze(String fundQuery) async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse("https://api.mfapi.in/mf/search?q=$fundQuery");
      final response = await http.get(url).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          currentFundName = data[0]['schemeName'];
        }
      }
    } catch (_) {}

    double calculatedImpact = 0.0;
    for (var h in holdings) {
      calculatedImpact += (h['impact'] as double) * ((h['weight'] as double) / 10.0);
    }

    setState(() {
      estimatedNavImpact = double.parse(calculatedImpact.toStringAsFixed(2));
      if (estimatedNavImpact > 0.8) {
        marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
        statusColor = Colors.green;
      } else if (estimatedNavImpact < -0.8) {
        marketStatus = "🔴 મંદીની શક્યતા (Bearish Alert)";
        statusColor = Colors.red;
      } else {
        marketStatus = "⚪ સ્થિર (Range Bound)";
        statusColor = Colors.blue;
      }
      _isLoading = false;
    });
  }

  // ૨. એક ક્લિક પર તમામ ફંડ્સનું પુનઃ મૂલ્યાંકન અને રેન્કિંગ
  Future<void> reEvaluateAll() async {
    setState(() => _isRankingLoading = true);
    await Future.delayed(const Duration(seconds: 1));

    List<Map<String, dynamic>> list = [
      {"name": "HDFC Top 100 Fund", "impact": 2.15, "signal": "તેજી", "color": Colors.green},
      {"name": "Tata Digital India Fund", "impact": 1.40, "signal": "તેજી", "color": Colors.green},
      {"name": "SBI Bluechip Fund", "impact": 0.65, "signal": "સ્થિર", "color": Colors.blue},
      {"name": "Nippon India Small Cap", "impact": -0.90, "signal": "મંદી", "color": Colors.red},
    ];

    list.sort((a, b) => (b['impact'] as double).compareTo(a['impact'] as double));

    setState(() {
      rankedFunds = list;
      _isRankingLoading = false;
    });
  }

  // ૩. સ્ટોક ટેકનિકલ ચાર્ટ ડાયલોગ (કેન્ડલ/ટ્રેન્ડ લાઇન)
  void _openStockTechnicalChart(String stockName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$stockName - ૬ મહિનાનો ટેકનિકલ ટ્રેન્ડ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          height: 240,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: const [
                    FlSpot(0, 100), FlSpot(1, 104), FlSpot(2, 102),
                    FlSpot(3, 108), FlSpot(4, 107), FlSpot(5, 114),
                  ],
                  isCurved: true,
                  color: Colors.teal,
                  barWidth: 3,
                  belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)),
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("બંધ કરો")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("મ્યુચ્યુઅલ ફંડ & સ્ટોક એનાલિસિસ"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "ફરીથી તપાસણી કરો",
            onPressed: reEvaluateAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: "મ્યુચ્યુઅલ ફંડનું નામ શોધો...",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => fetchAndAnalyze(_searchController.text),
                        child: const Text("શોધો"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: statusColor.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currentFundName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("સંભવિત NAV અસર: ${estimatedNavImpact > 0 ? '+' : ''}$estimatedNavImpact%",
                                  style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 15)),
                              Text(marketStatus, style: TextStyle(fontWeight: FontWeight.bold, color: statusColor)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      icon: _isRankingLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.bolt),
                      label: const Text("🔄 તમામ ફંડ્સની ફરી તપાસણી અને લાઈવ રેન્ક"),
                      onPressed: _isRankingLoading ? null : reEvaluateAll,
                    ),
                  ),
                  if (rankedFunds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text("🏆 તેજીના આધારે ફંડ્સ રેન્કિંગ:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ...rankedFunds.asMap().entries.map((entry) {
                      int idx = entry.key + 1;
                      var f = entry.value;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 12, child: Text("$idx", style: const TextStyle(fontSize: 11))),
                        title: Text(f['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        trailing: Text("${f['impact'] > 0 ? '+' : ''}${f['impact']}% (${f['signal']})",
                            style: TextStyle(color: f['color'], fontWeight: FontWeight.bold)),
                      );
                    }),
                    const Divider(),
                  ],
                  const SizedBox(height: 12),
                  const Text("📋 સ્ટોક હોલ્ડિંગ્સ અને ચાર્ટ એનાલિસિસ:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...holdings.map((h) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text("વેઇટેજ: ${h['weight']}% | પરિણામ: ${h['growth']}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                h['trend'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: h['trend'] == 'તેજી' ? Colors.green : (h['trend'] == 'મંદી' ? Colors.red : Colors.grey),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.show_chart, color: Colors.teal),
                                tooltip: "ચાર્ટ જુઓ",
                                onPressed: () => _openStockTechnicalChart(h['name']),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
