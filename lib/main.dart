import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_gate.dart';
import 'export_service.dart';

// વૈશ્વિક થીમ નોટિફાયર
final ValueNotifier<Color> appSeedColor = ValueNotifier<Color>(Colors.teal);
final ValueNotifier<String?> appBackgroundImage = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('settingsBox');

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
          home: const AuthGate(),
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
  late Box transactionsBox;
  late Box settingsBox;

  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTimeRange? customDateRange;

  AnalysisView selectedAnalysisView = AnalysisView.all;
  ChartGrouping selectedGrouping = ChartGrouping.byCategory;

  @override
  void initState() {
    super.initState();
    categoriesBox = Hive.box('categoriesBox');
    transactionsBox = Hive.box('transactionsBox');
    settingsBox = Hive.box('settingsBox');

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

      // Analysis Type Filtering
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
        .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
  }

  // તારીખ પસંદગી સાથે નવો હિસાબ ઉમેરો
  void _addTransactionDialog() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    if (categories.isEmpty) return;
    var selectedCat = categories.first;
    DateTime transactionDate = DateTime.now();

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
                }).toList>,
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
              ElevatedButton(
                onPressed: () {
                  final enteredAmount = double.tryParse(amountController.text) ?? 0.0;
                  if (enteredAmount <= 0 || titleController.text.isEmpty) return;

                  final id = DateTime.now().millisecondsSinceEpoch.toString();
                  transactionsBox.put(id, {
                    'id': id,
                    'title': titleController.text,
                    'amount': enteredAmount,
                    'date': transactionDate.toIso8601String(),
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

  // થીમ બદલવા માટેનું ડાયલોગ (કલર્સ અને ફોટો સિલેક્શન)
  void _openThemeDialog() {
    final colors = [
      Colors.teal,
      Colors.indigo,
      Colors.deepPurple,
      Colors.blue,
      Colors.deepOrange,
      Colors.brown,
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('થીમ સેટિંગ્સ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('કલર થીમ પસંદ કરો:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: colors.map((c) {
                return GestureDetector(
                  onTap: () {
                    appSeedColor.value = c;
                    settingsBox.put('primaryColor', c.value);
                  },
                  child: CircleAvatar(backgroundColor: c, radius: 18),
                );
              }).toList(),
            ),
            const Divider(height: 30),
            const Text('બેકગ્રાઉન્ડ ફોટો થીમ:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      appBackgroundImage.value = image.path;
                      settingsBox.put('backgroundImage', image.path);
                    }
                  },
                  icon: const Icon(Icons.photo),
                  label: const Text('ફોટો પસંદ કરો'),
                ),
                const SizedBox(width: 8),
                if (appBackgroundImage.value != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'ફોટો હટાવો',
                    onPressed: () {
                      appBackgroundImage.value = null;
                      settingsBox.delete('backgroundImage');
                    },
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('બંધ કરો')),
        ],
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
    final totalIncome = _calculateTotal('incomeCredit');

    return ValueListenableBuilder<String?>(
      valueListenable: appBackgroundImage,
      builder: (context, bgPath, _) {
        return Container(
          decoration: BoxDecoration(
            image: bgPath != null
                ? DecorationImage(
                    image: FileImage(File(bgPath)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.15),
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
          child: Scaffold(
            backgroundColor: bgPath != null ? Colors.transparent : null,
            appBar: AppBar(
              backgroundColor: bgPath != null ? Colors.white.withOpacity(0.85) : null,
              title: const Text('નાણાકીય વૉલ્ટ'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.palette),
                  tooltip: 'થીમ સેટિંગ્સ',
                  onPressed: _openThemeDialog,
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
                    // સમયગાળો ડ્રોપડાઉન
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 10),
                            const Text('સમયગાળો:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
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
                                  DropdownMenuItem(value: TimeFilter.yearly, child: Text('વાર્ષિક (Yearly)')),
                                  DropdownMenuItem(value: TimeFilter.custom, child: Text('કસ્ટમ કેલેન્ડર (Custom Range)')),
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
                                        selectedFilter = TimeFilter.custom;
                                      });
                                    }
                                  } else {
                                    setState(() => selectedFilter = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selectedFilter == TimeFilter.custom && customDateRange != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          'સમય: ${DateFormat('dd/MM/yy').format(customDateRange!.start)} થી ${DateFormat('dd/MM/yy').format(customDateRange!.end)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // સમરી કાર્ડ્સ
                    Row(
                      children: [
                        Expanded(child: _buildMetricCard('આવક', '₹${totalIncome.toStringAsFixed(0)}', Colors.green)),
                        const SizedBox(width: 6),
                        Expanded(child: _buildMetricCard('ખર્ચ', '₹${totalExpense.toStringAsFixed(0)}', Colors.redAccent)),
                        const SizedBox(width: 6),
                        Expanded(child: _buildMetricCard('રોકાણ', '₹${assetGain.toStringAsFixed(0)}', Colors.blue)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // એનાલિસિસ ફિલ્ટર્સ
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('પ્રકાર:', style: TextStyle(fontWeight: FontWeight.bold)),
                                DropdownButton<AnalysisView>(
                                  value: selectedAnalysisView,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: AnalysisView.all, child: Text('સંયુક્ત (બધા)')),
                                    DropdownMenuItem(value: AnalysisView.expenseOnly, child: Text('માત્ર ખર્ચ')),
                                    DropdownMenuItem(value: AnalysisView.incomeOnly, child: Text('માત્ર આવક')),
                                    DropdownMenuItem(value: AnalysisView.investmentOnly, child: Text('માત્ર રોકાણ')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => selectedAnalysisView = val);
                                  },
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('ચાર્ટ ગ્રૂપિંગ:', style: TextStyle(fontWeight: FontWeight.bold)),
                                DropdownButton<ChartGrouping>(
                                  value: selectedGrouping,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: ChartGrouping.byCategory, child: Text('કેટેગરી પ્રમાણે')),
                                    DropdownMenuItem(value: ChartGrouping.byType, child: Text('પ્રકાર પ્રમાણે (Income/Expense/Invest)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => selectedGrouping = val);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ચાર્ટ સેક્શન
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text('ચાર્ટ વિશ્લેષણ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 220,
                              child: filteredTransactions.isEmpty
                                  ? const Center(child: Text('આ ફિલ્ટરમાં કોઈ વ્યવહાર નથી'))
                                  : PieChart(
                                      PieChartData(
                                        sectionsSpace: 2,
                                        centerSpaceRadius: 40,
                                        sections: _generateChartSections(),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ટ્રાન્ઝેક્શન લિસ્ટ
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
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Card(
      color: color.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _generateChartSections() {
    Map<String, double> sums = {};
    Map<String, Color> colors = {};

    if (selectedGrouping == ChartGrouping.byCategory) {
      for (var tx in filteredTransactions) {
        final name = tx['categoryName'].toString();
        sums[name] = (sums[name] ?? 0.0) + (tx['amount'] as num).toDouble();
        colors[name] = Color(tx['categoryColor'] as int);
      }
    } else {
      // પ્રકાર અનુસાર ગ્રૂપિંગ
      for (var tx in filteredTransactions) {
        final effect = tx['categoryEffect'].toString();
        String label = 'ખર્ચ';
        Color c = Colors.redAccent;
        if (effect == 'incomeCredit') {
          label = 'આવક';
          c = Colors.green;
        } else if (effect == 'assetIncrease') {
          label = 'રોકાણ';
          c = Colors.blue;
        }
        sums[label] = (sums[label] ?? 0.0) + (tx['amount'] as num).toDouble();
        colors[label] = c;
      }
    }

    return sums.entries.map((entry) {
      return PieChartSectionData(
        value: entry.value,
        title: '${entry.key}\n₹${entry.value.toInt()}',
        color: colors[entry.key] ?? Colors.grey,
        radius: 65,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }
}
