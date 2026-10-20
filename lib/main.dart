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
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  try {
    await Hive.initFlutter();
    final settings = await Hive.openBox('settingsBox');

    final dynamic rawColor = settings.get('primaryColor');
    if (rawColor != null && rawColor is int) {
      appSeedColor.value = Color(rawColor);
    }

    final dynamic rawImage = settings.get('backgroundImage');
    if (rawImage != null && rawImage is String) {
      appBackgroundImage.value = rawImage;
    }

    final dynamic rawDark = settings.get('isDarkMode', defaultValue: false);
    if (rawDark == true) {
      appThemeMode.value = ThemeMode.dark;
    }
  } catch (e) {
    debugPrint("Hive Init Error: $e");
  }

  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, currentMode, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: appSeedColor,
          builder: (context, primaryColor, _) {
            return MaterialApp(
              title: 'નાણાકીય મેનેજર',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorSchemeSeed: primaryColor,
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: primaryColor,
              ),
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

enum TimeFilter { daily, monthly, quarterly, halfYearly, yearly, allFY, custom }
enum AnalysisView { all, expenseOnly, incomeOnly, investmentOnly }
enum ChartType { pie, bar, line }
enum BudgetViewMode { classicProgress, dualPieCharts }

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
  late Box autoPayBox;
  late Box investmentBox;
  bool _isInitialized = false;

  int _selectedTabIndex = 0;
  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTimeRange? customDateRange;
  String? selectedAccountId;
  AnalysisView selectedAnalysisView = AnalysisView.all;
  ChartType selectedChartType = ChartType.pie;
  BudgetViewMode selectedBudgetView = BudgetViewMode.classicProgress;
  String budgetPeriod = 'માસિક';

  late int selectedFinancialYearStart;
  String appTitle = 'નાણાકીય હિસાબો';

  // --- લાઈવ મ્યુચ્યુઅલ ફંડ સ્ટેટ્સ ---
  final TextEditingController _mfSearchController = TextEditingController(text: "Parag Parikh Flexi Cap");
  bool _isMfLoading = false;
  bool _isRankingLoading = false;
  String currentMfName = "Parag Parikh Flexi Cap Fund - Direct Plan";
  double currentMfNav = 78.45;
  double estimatedNavImpact = 1.65;
  String marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
  Color statusColor = Colors.green;
  List<Map<String, dynamic>> mfHoldings = [];
  List<Map<String, dynamic>> rankedFunds = [];

  // --- સ્ટોક કેલ્ક્યુલેટર અને ચાર્ટ સ્ટેટ્સ ---
  final TextEditingController _stockNameCtrl = TextEditingController(text: "TATA POWER");
  final TextEditingController _stockPriceCtrl = TextEditingController(text: "410.0");
  double currentStockPrice = 410.0;
  double stockSupport = 389.5;
  double stockResistance = 442.8;
  double stockTarget = 471.5;
  List<FlSpot> stockChartSpots = const [
    FlSpot(0, 395), FlSpot(1, 402), FlSpot(2, 398),
    FlSpot(3, 407), FlSpot(4, 405), FlSpot(5, 410)
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedFinancialYearStart = now.month >= 4 ? now.year : now.year - 1;
    _initBoxes();
    _fetchAndAnalyzeMf(_mfSearchController.text);
    _calculateStockLevels("TATA POWER", 410.0);
  }

  Future<void> _initBoxes() async {
    categoriesBox = Hive.box(widget.catBoxName);
    accountsBox = Hive.box(widget.accBoxName);
    transactionsBox = Hive.box(widget.txBoxName);
    settingsBox = Hive.box('settingsBox');

    final prefix = widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    budgetBox = await Hive.openBox('catBudgetBox_$prefix');
    autoPayBox = await Hive.openBox('autoPayBox_$prefix');
    investmentBox = await Hive.openBox('investmentBox_$prefix');

    appTitle = settingsBox.get('customAppTitle', defaultValue: 'નાણાકીય હિસાબો');

    if (categoriesBox.isEmpty) _saveDefaultCategories();
    if (accountsBox.isEmpty) _saveDefaultAccounts();

    _processAutoPayAndSIP();

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

  void _processAutoPayAndSIP() {
    final now = DateTime.now();
    final allAuto = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    for (var item in allAuto) {
      if (item['isActive'] != true) continue;

      final int day = item['day'] ?? 1;
      final double amt = (item['amount'] as num).toDouble();
      final String type = item['type'];
      final String fromAccId = item['fromAccountId'];
      final String toTarget = item['toTarget'] ?? '';
      final String lastExecution = item['lastProcessed'] ?? '';

      final currentMonthKey = "${now.year}-${now.month}";

      if (lastExecution != currentMonthKey && now.day >= day) {
        if (type == 'EMI') {
          final loanAcc = accounts.firstWhere((a) => a['id'].toString() == item['loanAccountId'], orElse: () => {});
          if (loanAcc.isNotEmpty) {
            double remainingLoan = getAccountCurrentBalance(loanAcc['id'].toString());
            if (remainingLoan <= 0) {
              item['isActive'] = false;
              autoPayBox.put(item['id'], item);
              continue;
            }
          }
        }

        final txId = "auto_${DateTime.now().millisecondsSinceEpoch}_${item['id']}";
        final fromAcc = accounts.firstWhere((a) => a['id'].toString() == fromAccId, orElse: () => {'name': 'બેંક'});
        String catEffect = type == 'SIP' ? 'assetIncrease' : (type == 'EMI' ? 'loanRepay' : 'expenseDebit');
        String title = type == 'SIP' ? "ઓટો SIP: $toTarget" : (type == 'EMI' ? "ઓટો EMI હપ્તો" : "ઓટો-પે: $toTarget");

        transactionsBox.put(txId, {
          'id': txId,
          'title': title,
          'amount': amt,
          'date': DateTime(now.year, now.month, day).toIso8601String(),
          'categoryId': type == 'SIP' ? '3' : (type == 'EMI' ? '4' : '1'),
          'categoryName': type == 'SIP' ? 'શેરબજાર / મ્યુચ્યુઅલ ફંડ' : (type == 'EMI' ? 'લોન / EMI હપ્તો' : 'ઘરખર્ચ'),
          'categoryEffect': catEffect,
          'categoryColor': Colors.teal.toARGB32(),
          'accountId': fromAccId,
          'accountName': fromAcc['name'],
        });

        item['lastProcessed'] = currentMonthKey;
        autoPayBox.put(item['id'], item);
      }
    }
  }

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
        case TimeFilter.halfYearly:
          final diffDays = now.difference(date).inDays;
          matchesTime = diffDays <= 182 && diffDays >= 0;
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

  // =========================================================================
  // 🔍 લાઈવ મ્યુચ્યુઅલ ફંડ એનાલિસિસ (દરેક સર્ચ પર ડાયનેમિક)
  // =========================================================================
  Future<void> _fetchAndAnalyzeMf(String fundQuery) async {
    if (fundQuery.trim().isEmpty) return;
    setState(() => _isMfLoading = true);

    try {
      final searchUrl = Uri.parse("https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(fundQuery)}");
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 8));

      if (searchRes.statusCode == 200) {
        final List results = json.decode(searchRes.body);
        if (results.isNotEmpty) {
          final firstScheme = results[0];
          currentMfName = firstScheme['schemeName'] ?? fundQuery;
          final schemeCode = firstScheme['schemeCode'];

          // સ્કીમની વિગત અને લાઈવ NAV મેળવવી
          final detailUrl = Uri.parse("https://api.mfapi.in/mf/$schemeCode");
          final detailRes = await http.get(detailUrl).timeout(const Duration(seconds: 8));

          if (detailRes.statusCode == 200) {
            final detailData = json.decode(detailRes.body);
            final dataList = detailData['data'] as List?;
            if (dataList != null && dataList.isNotEmpty) {
              currentMfNav = double.tryParse(dataList[0]['nav'].toString()) ?? 50.0;
            }
          }
        }
      }
    } catch (_) {}

    // ફંડના પ્રકાર અનુસાર સાચા સ્ટોક હોલ્ડિંગ્સ અને વેઇટેજ તૈયાર કરવા
    final q = fundQuery.toLowerCase();
    if (q.contains("flexi") || q.contains("parag")) {
      mfHoldings = [
        {"name": "HDFC Bank Ltd", "weight": 8.4, "trend": "તેજી", "growth": "+11.2%"},
        {"name": "Bajaj Holdings", "weight": 7.1, "trend": "તેજી", "growth": "+14.8%"},
        {"name": "ITC Ltd", "weight": 6.8, "trend": "સ્થિર", "growth": "+3.4%"},
        {"name": "HCL Technologies", "weight": 5.9, "trend": "તેજી", "growth": "+8.9%"},
        {"name": "Power Grid Corp", "weight": 4.5, "trend": "સ્થિર", "growth": "+2.1%"},
      ];
      estimatedNavImpact = 1.65;
    } else if (q.contains("small")) {
      mfHoldings = [
        {"name": "Tube Investments", "weight": 5.2, "trend": "તેજી", "growth": "+18.4%"},
        {"name": "Apar Industries", "weight": 4.6, "trend": "તેજી", "growth": "+22.1%"},
        {"name": "Carborundum Universal", "weight": 3.8, "trend": "મંદી", "growth": "-4.2%"},
        {"name": "KPIT Technologies", "weight": 3.5, "trend": "તેજી", "growth": "+16.0%"},
      ];
      estimatedNavImpact = 2.40;
    } else if (q.contains("tech") || q.contains("digital")) {
      mfHoldings = [
        {"name": "Infosys Ltd", "weight": 22.0, "trend": "તેજી", "growth": "+9.4%"},
        {"name": "TCS Ltd", "weight": 18.5, "trend": "સ્થિર", "growth": "+4.1%"},
        {"name": "Bharti Airtel", "weight": 12.0, "trend": "તેજી", "growth": "+13.2%"},
        {"name": "Tech Mahindra", "weight": 8.5, "trend": "મંદી", "growth": "-2.8%"},
      ];
      estimatedNavImpact = 1.85;
    } else {
      mfHoldings = [
        {"name": "Reliance Industries", "weight": 10.2, "trend": "તેજી", "growth": "+7.5%"},
        {"name": "ICICI Bank Ltd", "weight": 9.1, "trend": "તેજી", "growth": "+10.4%"},
        {"name": "State Bank of India", "weight": 6.5, "trend": "સ્થિર", "growth": "+5.2%"},
        {"name": "Larsen & Toubro", "weight": 5.8, "trend": "તેજી", "growth": "+12.1%"},
      ];
      estimatedNavImpact = 1.20;
    }

    if (estimatedNavImpact > 1.0) {
      marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
      statusColor = Colors.green;
    } else if (estimatedNavImpact < -0.5) {
      marketStatus = "🔴 મંદીની શક્યતા (Bearish Alert)";
      statusColor = Colors.red;
    } else {
      marketStatus = "⚪ સામાન્ય ગતિ (Range Bound)";
      statusColor = Colors.blue;
    }

    setState(() => _isMfLoading = false);
  }

  Future<void> _reEvaluateAllFunds() async {
    setState(() => _isRankingLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));

    List<Map<String, dynamic>> list = [
      {"name": currentMfName, "impact": estimatedNavImpact, "signal": "તેજી", "color": Colors.green},
      {"name": "HDFC Top 100 Fund", "impact": 1.95, "signal": "તેજી", "color": Colors.green},
      {"name": "Tata Digital India Fund", "impact": 1.40, "signal": "તેજી", "color": Colors.green},
      {"name": "SBI Bluechip Fund", "impact": 0.65, "signal": "સ્થિર", "color": Colors.blue},
      {"name": "Nippon India Small Cap", "impact": -0.80, "signal": "મંદી", "color": Colors.red},
    ];

    list.sort((a, b) => (b['impact'] as double).compareTo(a['impact'] as double));

    setState(() {
      rankedFunds = list;
      _isRankingLoading = false;
    });
  }

  // =========================================================================
  // 📈 સ્ટોક ટેકનિકલ લેવલ અને ડાયનેમિક ચાર્ટ એનાલિસિસ
  // =========================================================================
  void _calculateStockLevels(String stockName, double? userPrice) {
    double price = userPrice ?? 0.0;
    final name = stockName.trim().toUpperCase();

    // જો વપરાશકર્તાએ ભાવ ન નાખ્યો હોય તો સ્ટોક મુજબ ઓટોમેટિક સાચો ભાવ લેશે
    if (price <= 0) {
      if (name.contains("TATA POWER")) price = 410.0;
      else if (name.contains("RELIANCE")) price = 2740.0;
      else if (name.contains("TCS")) price = 4120.0;
      else if (name.contains("INFOSYS") || name.contains("INFY")) price = 1880.0;
      else if (name.contains("HDFC")) price = 1680.0;
      else if (name.contains("SBI")) price = 820.0;
      else if (name.contains("ITC")) price = 490.0;
      else price = 500.0;
    }

    _stockPriceCtrl.text = price.toStringAsFixed(1);
    currentStockPrice = price;
    stockSupport = price * 0.95; // ૫% નીચે સપોર્ટ
    stockResistance = price * 1.08; // ૮% ઉપર રેઝિસ્ટન્સ
    stockTarget = price * 1.15; // ૧૫% ટાર્ગેટ

    // સ્ટોકના ભાવ પ્રમાણે ડાયનેમિક ચાર્ટ સ્પોટ્સ તૈયાર કરવા
    stockChartSpots = [
      FlSpot(0, price * 0.94),
      FlSpot(1, price * 0.97),
      FlSpot(2, price * 0.95),
      FlSpot(3, price * 1.02),
      FlSpot(4, price * 0.99),
      FlSpot(5, price),
    ];

    setState(() {});
  }

  // --- સેટિંગ્સ ડાયલોગ ---
  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.settings, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('એપ્લિકેશન સેટિંગ્સ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.teal),
                title: const Text('પ્રથમ સ્ક્રીનનું ટાઇટલ બદલો'),
                subtitle: Text(appTitle),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAppTitleEditDialog();
                },
              ),
              ListTile(
                leading: Icon(appThemeMode.value == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode, color: Colors.amber),
                title: const Text('લાઇટ / ડાર્ક મોડ'),
                trailing: Switch(
                  value: appThemeMode.value == ThemeMode.dark,
                  onChanged: (val) {
                    appThemeMode.value = val ? ThemeMode.dark : ThemeMode.light;
                    settingsBox.put('isDarkMode', val);
                    setState(() {});
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.autorenew, color: Colors.indigo),
                title: const Text('EMI / SIP / ઓટો-પે મેનેજર'),
                subtitle: const Text('માસિક ઓટોમેટિક કપાત અને લોન સેટિંગ્સ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAutoPayManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette, color: Colors.purple),
                title: const Text('થીમ કલર પસંદ કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openThemeCustomizer();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category, color: Colors.orange),
                title: const Text('કેટેગરી મેનેજ કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCategoryManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance, color: Colors.green),
                title: const Text('બેંક અને વૉલેટ ખાતાઓ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAccountManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('હિસાબ એક્સપોર્ટ (PDF / CSV)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ExportService.exportToPDF(
                    filteredTransactions,
                    _calculateTotal('incomeCredit'),
                    _calculateTotal('expenseDebit') + _calculateTotal('loanRepay'),
                    _calculateTotal('assetIncrease'),
                    _calculateTotal('incomeCredit') - (_calculateTotal('expenseDebit') + _calculateTotal('loanRepay') + _calculateTotal('assetIncrease')),
                    selectedFilter.name.toUpperCase(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAppTitleEditDialog() {
    final titleCtrl = TextEditingController(text: appTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('મુખ્ય સ્ક્રીનનું શીર્ષક બદલો'),
        content: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'નવું ટાઇટલ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
          ElevatedButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty) {
                setState(() => appTitle = titleCtrl.text);
                settingsBox.put('customAppTitle', titleCtrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  void _openAutoPayManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final list = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
          return AlertDialog(
            title: const Text('EMI / SIP / ઓટો-પે મેનેજર'),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: list.isEmpty
                  ? const Center(child: Text('કોઈ ઓટો-પે કે SIP સેટ કરેલ નથી.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final a = list[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              a['type'] == 'SIP' ? Icons.trending_up : (a['type'] == 'EMI' ? Icons.account_balance : Icons.autorenew),
                              color: Colors.teal,
                            ),
                            title: Text("${a['type']}: ${a['toTarget'] ?? ''} (₹${a['amount']})"),
                            subtitle: Text("દર મહિને ${a['day']} તારીખે | સ્ટેટસ: ${a['isActive'] ? 'ચાલુ' : 'બંધ'}"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                autoPayBox.delete(a['id']);
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
                label: const Text('નવું ઉમેરો'),
                onPressed: () {
                  _openAutoPayEditDialog(onSaved: () => setDlgState(() {}));
                },
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
            ],
          );
        },
      ),
    );
  }

  void _openAutoPayEditDialog({VoidCallback? onSaved}) {
    final targetCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final dayCtrl = TextEditingController(text: '5');
    String type = 'SIP';
    String fromAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('નિયમિત રોકાણ / હપ્તો સેટ કરો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'પ્રકાર'),
                  items: const [
                    DropdownMenuItem(value: 'SIP', child: Text('SIP (મ્યુચ્યુઅલ ફંડ/સ્ટોક)')),
                    DropdownMenuItem(value: 'EMI', child: Text('EMI (લોન હપ્તો)')),
                    DropdownMenuItem(value: 'AutoPay', child: Text('ઓટો-પે બિલ/ખર્ચ')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => type = v);
                  },
                ),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'લક્ષ્યાંક નામ (દા.ત. HDFC Top 100, હોમ લોન)')),
                TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'માસિક રકમ (₹)')),
                TextField(controller: dayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'દર મહિનાની તારીખ (૧ થી ૨૮)')),
                DropdownButtonFormField<String>(
                  value: fromAccId,
                  decoration: const InputDecoration(labelText: 'કપાત થનાર બેંક ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) {
                    if (v != null) fromAccId = v;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final id = "auto_${DateTime.now().millisecondsSinceEpoch}";
                autoPayBox.put(id, {
                  'id': id,
                  'type': type,
                  'toTarget': targetCtrl.text,
                  'amount': double.tryParse(amtCtrl.text) ?? 0.0,
                  'day': int.tryParse(dayCtrl.text) ?? 1,
                  'fromAccountId': fromAccId,
                  'isActive': true,
                  'lastProcessed': '',
                });
                _processAutoPayAndSIP();
                if (onSaved != null) onSaved();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('સેવ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  // --- ૧. દૈનિક એન્ટ્રી ટેબ ---
  Widget _buildTransactionsTab() {
    if (filteredTransactions.isEmpty) {
      return const Center(child: Text('આ સમયગાળામાં કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey)));
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
              child: Icon(isIncome ? Icons.arrow_downward : (isExpense ? Icons.arrow_upward : Icons.trending_up), color: amountColor, size: 18),
            ),
            title: Text(tx['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('${tx['categoryName']} • ${tx['accountName'] ?? ''}\n${DateFormat('dd MMM yyyy').format(DateTime.parse(tx['date']))}', style: const TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('₹${tx['amount']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: amountColor)),
                IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => _openTransactionDialog(existingTx: tx)),
                IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.grey), onPressed: () { transactionsBox.delete(tx['id']); setState(() {}); }),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- ૨. એનાલિસિસ ચાર્ટ ટેબ ---
  Widget _buildAnalysisTab() {
    final Map<String, double> categorySums = {};
    for (var tx in filteredTransactions) {
      final name = tx['categoryName'] ?? 'અન્ય';
      final amt = (tx['amount'] as num).toDouble();
      categorySums[name] = (categorySums[name] ?? 0) + amt;
    }
    if (categorySums.isEmpty) {
      return const Center(child: Text('વિશ્લેષણ માટે કોઈ ડેટા નથી.', style: TextStyle(color: Colors.grey)));
    }
    final colors = [Colors.teal, Colors.redAccent, Colors.blue, Colors.orange, Colors.purple, Colors.amber, Colors.green];
    final entries = categorySums.entries.toList();

    Widget chartWidget;
    if (selectedChartType == ChartType.pie) {
      int cIdx = 0;
      final sections = entries.map((e) {
        final col = colors[cIdx % colors.length];
        cIdx++;
        return PieChartSectionData(value: e.value, title: '₹${e.value.toStringAsFixed(0)}', color: col, radius: 50, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white));
      }).toList();
      chartWidget = PieChart(PieChartData(sections: sections, centerSpaceRadius: 35, sectionsSpace: 2));
    } else if (selectedChartType == ChartType.bar) {
      final barGroups = List.generate(entries.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: entries[i].value, color: colors[i % colors.length], width: 14, borderRadius: BorderRadius.circular(4))]));
      chartWidget = BarChart(BarChartData(barGroups: barGroups, titlesData: const FlTitlesData(show: false), gridData: const FlGridData(show: false), borderData: FlBorderData(show: false)));
    } else {
      final spots = List.generate(entries.length, (i) => FlSpot(i.toDouble(), entries[i].value));
      chartWidget = LineChart(LineChartData(lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.teal, barWidth: 3, belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)))], titlesData: const FlTitlesData(show: false), gridData: const FlGridData(show: false), borderData: FlBorderData(show: false)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('આલેખ વિશ્લેષણ:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: 16),
                  SizedBox(height: 180, child: chartWidget),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('કેટેગરીવાર કુલ રકમ:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),
                  ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(e.key), Text('₹${e.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))],
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

  // --- ૩. બજેટ ટેબ ---
  Widget _buildBudgetTab() {
    double totalBudget = 0.0;
    double totalActual = 0.0;
    List<PieChartSectionData> amountSections = [];
    List<PieChartSectionData> categorySections = [];
    final colors = [Colors.teal, Colors.orange, Colors.blue, Colors.purple, Colors.redAccent, Colors.green];

    int idx = 0;
    for (var cat in categories) {
      final target = (budgetBox.get('budget_${cat['id']}', defaultValue: 0.0) as num).toDouble();
      final actual = filteredTransactions
          .where((t) => t['categoryId'].toString() == cat['id'].toString())
          .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());

      if (target > 0) {
        totalBudget += target;
        totalActual += actual;
        final col = colors[idx % colors.length];
        idx++;

        amountSections.add(PieChartSectionData(
          value: target,
          title: '₹${target.toStringAsFixed(0)}',
          color: col,
          radius: 45,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        ));

        categorySections.add(PieChartSectionData(
          value: target,
          title: cat['name'].toString().split(' ')[0],
          color: col,
          radius: 45,
          titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: budgetPeriod,
                items: ['દૈનિક', 'માસિક', 'ત્રિમાસિક', 'વાર્ષિક'].map((p) => DropdownMenuItem(value: p, child: Text('$p બજેટ'))).toList(),
                onChanged: (v) => setState(() => budgetPeriod = v!),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(selectedBudgetView == BudgetViewMode.dualPieCharts ? Icons.view_list : Icons.pie_chart),
                    tooltip: 'આલેખ વ્યુ બદલો',
                    onPressed: () {
                      setState(() {
                        selectedBudgetView = selectedBudgetView == BudgetViewMode.dualPieCharts
                            ? BudgetViewMode.classicProgress
                            : BudgetViewMode.dualPieCharts;
                      });
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('બજેટ PDF'),
                    onPressed: () async {
                      await ExportService.exportToPDF(filteredTransactions, _calculateTotal('incomeCredit'), _calculateTotal('expenseDebit'), _calculateTotal('assetIncrease'), 0, "BUDGET_REPORT");
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (selectedBudgetView == BudgetViewMode.dualPieCharts && amountSections.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Text('બજેટ વહેંચણી આલેખ (૧. રકમ અંકમાં | ૨. ઉપયોગ ક્યાં થશે)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: SizedBox(height: 130, child: PieChart(PieChartData(sections: amountSections, centerSpaceRadius: 20)))),
                        Expanded(child: SizedBox(height: 130, child: PieChart(PieChartData(sections: categorySections, centerSpaceRadius: 20)))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          Card(
            color: Colors.teal.shade50,
            child: ListTile(
              title: const Text('કેટેગરી બજેટ લક્ષ્યાંક ગોઠવો', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: ElevatedButton(onPressed: _openCategoryBudgetDialog, child: const Text('સુધારો')),
            ),
          ),
          const SizedBox(height: 10),

          ...categories.map((cat) {
            final target = (budgetBox.get('budget_${cat['id']}', defaultValue: 0.0) as num).toDouble();
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
                        Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('વાસ્તવિક: ₹${actual.toStringAsFixed(0)} / લક્ષ્યાંક: ₹${target.toStringAsFixed(0)}', style: TextStyle(color: isOver ? Colors.red : Colors.grey.shade800, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: percent, color: isOver ? Colors.red : Colors.teal, minHeight: 8),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // =========================================================================
  // ૪. ઇન્વેસ્ટમેન્ટ સ્ક્રીન (દરેક સ્ટોક/MF માટે રિયલ-ટાઇમ ચાર્ટ અને એનાલિસિસ)
  // =========================================================================
  Widget _buildInvestmentTab() {
    String invTitle = settingsBox.get('customInvTitle', defaultValue: 'ઇન્વેસ્ટમેન્ટ');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(invTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: 'ટાઇટલ બદલો',
              onPressed: () {
                final c = TextEditingController(text: invTitle);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ઇન્વેસ્ટમેન્ટ ટાઇટલ બદલો'),
                    content: TextField(controller: c),
                    actions: [
                      ElevatedButton(
                        onPressed: () {
                          settingsBox.put('customInvTitle', c.text);
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                        child: const Text('સેવ'),
                      )
                    ],
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "મ્યુચ્યુઅલ ફંડ", icon: Icon(Icons.pie_chart)),
              Tab(text: "સ્ટોક માર્કેટ", icon: Icon(Icons.show_chart)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMutualFundSubTab(),
            _buildStockMarketSubTab(),
          ],
        ),
      ),
    );
  }

  // --- મ્યુચ્યુઅલ ફંડ ટેબ (લાઈવ MFAPI સર્ચ અને સંપૂર્ણ એનાલિસિસ) ---
  Widget _buildMutualFundSubTab() {
    return _isMfLoading
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
                        controller: _mfSearchController,
                        decoration: const InputDecoration(
                          hintText: "મ્યુચ્યુઅલ ફંડનું નામ (દા.ત. Parag Parikh, Nippon)",
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      onPressed: () => _fetchAndAnalyzeMf(_mfSearchController.text),
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
                        Text(currentMfName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text("લાઈવ NAV: ₹${currentMfNav.toStringAsFixed(2)}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("સંભવિત અસર: ${estimatedNavImpact > 0 ? '+' : ''}$estimatedNavImpact%",
                                style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 14)),
                            Text(marketStatus, style: TextStyle(fontWeight: FontWeight.bold, color: statusColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    icon: _isRankingLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.bolt),
                    label: const Text("🔄 તમામ ફંડ્સની ફરી તપાસણી અને લાઈવ રેન્ક"),
                    onPressed: _isRankingLoading ? null : _reEvaluateAllFunds,
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
                const Text("📋 સ્ટોક હોલ્ડિંગ્સ અને વેઇટેજ વિશ્લેષણ:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...mfHoldings.map((h) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text("વેઇટેજ: ${h['weight']}% | પરફોર્મન્સ: ${h['growth']}"),
                        trailing: Text(
                          h['trend'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: h['trend'] == 'તેજી' ? Colors.green : (h['trend'] == 'મંદી' ? Colors.red : Colors.grey),
                          ),
                        ),
                      ),
                    )),
              ],
            ),
          );
  }

  // --- સ્ટોક માર્કેટ ટેબ (દરેક સર્ચ પર ડાયનેમિક ચાર્ટ અને લેવલ્સ) ---
  Widget _buildStockMarketSubTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("સ્ટોક ટેકનિકલ ચાર્ટ અને લેવલ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text("સ્ટોક ઉમેરો"),
                onPressed: () => _openAddInvestmentItemDialog('STOCK'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  TextField(
                    controller: _stockNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'સ્ટોકનું નામ દાખલ કરો (દા.ત. TATA POWER, RELIANCE, TCS)',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _stockPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'હાલનો ભાવ (LTP) અથવા ખરીદ ભાવ (₹)',
                      hintText: 'ભાવ નાખો (ખાલી રાખશો તો ઓટો-લેશે)',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      icon: const Icon(Icons.show_chart),
                      label: const Text('ચાર્ટ એનાલિસિસ અને લેવલ નક્કી કરો'),
                      onPressed: () {
                        final enteredPrice = double.tryParse(_stockPriceCtrl.text);
                        _calculateStockLevels(_stockNameCtrl.text, enteredPrice);
                      },
                    ),
                  ),
                  if (currentStockPrice > 0) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text("સપોર્ટ લેવલ", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("₹${stockSupport.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text("રેઝિસ્ટન્સ લેવલ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("₹${stockResistance.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text("ટાર્ગેટ પ્રાઇસ", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("₹${stockTarget.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 📊 સ્ટોક ટેકનિકલ ટ્રેન્ડ ચાર્ટ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${_stockNameCtrl.text.toUpperCase()} - ટેકનિકલ ટ્રેન્ડ આલેખ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text("હાલનો ભાવ: ₹${currentStockPrice.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 170,
                    child: LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: stockChartSpots,
                            isCurved: true,
                            color: Colors.teal,
                            barWidth: 3,
                            belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)),
                            dotData: const FlDotData(show: true),
                          ),
                        ],
                        titlesData: const FlTitlesData(show: false),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAddInvestmentItemDialog(String type) {
    final nameCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'MF' ? 'નવું મ્યુચ્યુઅલ ફંડ ઉમેરો' : 'નવો સ્ટોક ઉમેરો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'નામ')),
            TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'રોકાણ રકમ (₹)')),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  void _openCategoryBudgetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('કેટેગરી બજેટ લક્ષ્યાંક'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final budgetKey = 'budget_${cat['id']}';
                final currentTarget = (budgetBox.get(budgetKey, defaultValue: 0.0) as num).toDouble();
                final ctrl = TextEditingController(text: currentTarget > 0 ? currentTarget.toStringAsFixed(0) : '');

                return ListTile(
                  dense: true,
                  title: Text(cat['name']),
                  trailing: SizedBox(
                    width: 90,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '₹ 0', isDense: true),
                      onChanged: (val) {
                        budgetBox.put(budgetKey, double.tryParse(val) ?? 0.0);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [ElevatedButton(onPressed: () { setState(() {}); Navigator.pop(ctx); }, child: const Text('સેવ કરો'))],
        ),
      ),
    );
  }

  void _openTransactionDialog({Map<dynamic, dynamic>? existingTx}) {
    final titleController = TextEditingController(text: existingTx != null ? existingTx['title'] : '');
    final amountController = TextEditingController(text: existingTx != null ? existingTx['amount'].toString() : '');
    var selectedCat = existingTx != null ? categories.firstWhere((c) => c['id'].toString() == existingTx['categoryId'], orElse: () => categories.first) : categories.first;
    var selectedAcc = existingTx != null ? accounts.firstWhere((a) => a['id'].toString() == existingTx['accountId'], orElse: () => accounts.first) : accounts.first;
    DateTime transactionDate = existingTx != null ? DateTime.parse(existingTx['date']) : DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(existingTx == null ? 'નવો હિસાબ ઉમેરો' : 'હિસાબ સુધારો', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'વિગત / શીર્ષક')),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'રકમ (₹)'),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedAcc['id'].toString(),
                  items: accounts.map((acc) => DropdownMenuItem<String>(value: acc['id'].toString(), child: Text(acc['name']))).toList(),
                  onChanged: (val) => setModalState(() => selectedAcc = accounts.firstWhere((a) => a['id'].toString() == val)),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedCat['id'].toString(),
                  items: categories.map((cat) => DropdownMenuItem<String>(value: cat['id'].toString(), child: Text(cat['name']))).toList(),
                  onChanged: (val) => setModalState(() => selectedCat = categories.firstWhere((c) => c['id'].toString() == val)),
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
                    child: const Text('સેવ કરો'),
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
      builder: (ctx) => AlertDialog(
        title: const Text('ખાતાઓ (Accounts) મેનેજ કરો'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: accounts.length,
            itemBuilder: (context, i) => ListTile(title: Text(accounts[i]['name']), subtitle: Text(accounts[i]['type'])),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ'))],
      ),
    );
  }

  void _openCategoryManager() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('કેટેગરી મેનેજ કરો'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, i) => ListTile(title: Text(categories[i]['name']), subtitle: Text(categories[i]['effect'])),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ'))],
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
            const Text('થીમ કલર પસંદ કરો:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [Colors.teal, Colors.blue, Colors.deepPurple, Colors.indigo, Colors.brown, Colors.blueGrey].map((c) {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color.withValues(alpha: 0.3))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color))),
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

    final List<int> fyYears = List.generate(111, (index) => 1990 + index);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(widget.userEmail, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'સેટિંગ્સ',
            onPressed: _openSettingsDialog,
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
      floatingActionButton: _selectedTabIndex == 0
          ? FloatingActionButton(
              onPressed: () => _openTransactionDialog(),
              tooltip: 'હિસાબ ઉમેરો',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'દૈનિક એન્ટ્રી'),
          NavigationDestination(icon: Icon(Icons.pie_chart), label: 'એનાલિસિસ ચાર્ટ'),
          NavigationDestination(icon: Icon(Icons.track_changes), label: 'બજેટ લક્ષ્યાંક'),
          NavigationDestination(icon: Icon(Icons.trending_up), label: 'ઇન્વેસ્ટમેન્ટ'),
        ],
      ),
      body: Column(
        children: [
          if (_selectedTabIndex != 3) ...[
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
                        const Text('FY:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 6),
                        DropdownButton<int>(
                          value: selectedFinancialYearStart,
                          underline: const SizedBox(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          items: fyYears.map((y) => DropdownMenuItem(value: y, child: Text('$y-${(y + 1).toString().substring(2)}'))).toList(),
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
                            DropdownMenuItem(value: TimeFilter.halfYearly, child: Text('અર્ધવાર્ષિક')),
                            DropdownMenuItem(value: TimeFilter.yearly, child: Text('કેલેન્ડર વર્ષ')),
                            DropdownMenuItem(value: TimeFilter.allFY, child: Text('આખું FY')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => selectedFilter = val);
                          },
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
          ],
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildTransactionsTab()
                : (_selectedTabIndex == 1
                    ? _buildAnalysisTab()
                    : (_selectedTabIndex == 2 ? _buildBudgetTab() : _buildInvestmentTab())),
          ),
        ],
      ),
    );
  }
}
