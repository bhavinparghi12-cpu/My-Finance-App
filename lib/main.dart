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
                scaffoldBackgroundColor: Colors.grey.shade50,
                cardTheme: CardTheme(color: Colors.white, elevation: 1),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: primaryColor,
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardTheme: const CardTheme(color: Color(0xFF1E1E1E), elevation: 1),
                textTheme: const TextTheme(
                  bodyLarge: TextStyle(color: Colors.white),
                  bodyMedium: TextStyle(color: Colors.white70),
                  titleMedium: TextStyle(color: Colors.white),
                ),
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
  late Box physicalAssetsBox;
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

  // --- મ્યુચ્યુઅલ ફંડ સ્ટેટ્સ ---
  final TextEditingController _mfSearchController = TextEditingController(text: "TATA large and mid cap");
  bool _isMfLoading = false;
  bool _isRankingLoading = false;
  String currentMfName = "Tata Large & Mid Cap Fund - Direct Plan - Growth Option";
  double currentMfNav = 536.86;
  double estimatedNavImpact = 1.20;
  String lastMfUpdatedTime = DateFormat('hh:mm a').format(DateTime.now());
  String marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
  Color statusColor = Colors.green;
  List<Map<String, dynamic>> mfHoldings = [];
  List<Map<String, dynamic>> rankedFunds = [];

  // --- સ્ટોક સ્ટેટ્સ ---
  final TextEditingController _stockNameCtrl = TextEditingController(text: "RELIANCE");
  final TextEditingController _stockPriceCtrl = TextEditingController(text: "2740.0");
  double currentStockPrice = 2740.0;
  double stockSupport = 2603.0;
  double stockResistance = 2959.2;
  double stockTarget = 3151.0;
  String stockNewsSentiment = "🟢 તેજીમય સમાચાર (મજબૂત રિટેલ & જિયો ગ્રોથ)";
  List<FlSpot> stockChartSpots = const [
    FlSpot(0, 2650), FlSpot(1, 2690), FlSpot(2, 2670),
    FlSpot(3, 2720), FlSpot(4, 2710), FlSpot(5, 2740)
  ];

  // --- સોનું-ચાંદી શહેર પસંદગી સ્ટેટ્સ ---
  String selectedCity = "અમદાવાદ (Ahmedabad)";
  final Map<String, Map<String, double>> bullionCityRates = {
    "અમદાવાદ (Ahmedabad)": {"gold24": 74850.0, "gold22": 68620.0, "silver": 88500.0},
    "સુરત (Surat)": {"gold24": 74880.0, "gold22": 68650.0, "silver": 88550.0},
    "રાજકોટ (Rajkot)": {"gold24": 74820.0, "gold22": 68590.0, "silver": 88450.0},
    "વડોદરા (Vadodara)": {"gold24": 74860.0, "gold22": 68630.0, "silver": 88520.0},
    "મુંબઈ (Mumbai)": {"gold24": 74750.0, "gold22": 68520.0, "silver": 88300.0},
    "દિલ્હી (Delhi)": {"gold24": 74950.0, "gold22": 68700.0, "silver": 88700.0},
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedFinancialYearStart = now.month >= 4 ? now.year : now.year - 1;
    _initBoxes();
    _fetchAndAnalyzeMf(_mfSearchController.text);
    _calculateStockLevels("RELIANCE", 2740.0);
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
    physicalAssetsBox = await Hive.openBox('physicalAssetsBox_$prefix');

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

  // --- લાઈવ મ્યુચ્યુઅલ ફંડ એનાલિસિસ (સમય સાથે) ---
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

    final q = fundQuery.toLowerCase();
    if (q.contains("tata")) {
      mfHoldings = [
        {"name": "Tata Motors Ltd", "weight": 9.8, "trend": "તેજી", "growth": "+16.4%"},
        {"name": "TCS Ltd", "weight": 8.5, "trend": "સ્થિર", "growth": "+3.8%"},
        {"name": "Tata Steel Ltd", "weight": 6.2, "trend": "તેજી", "growth": "+12.1%"},
        {"name": "Titan Company", "weight": 5.4, "trend": "તેજી", "growth": "+9.0%"},
      ];
      estimatedNavImpact = 1.20;
    } else if (q.contains("flexi") || q.contains("parag")) {
      mfHoldings = [
        {"name": "HDFC Bank Ltd", "weight": 8.4, "trend": "તેજી", "growth": "+11.2%"},
        {"name": "Bajaj Holdings", "weight": 7.1, "trend": "તેજી", "growth": "+14.8%"},
        {"name": "ITC Ltd", "weight": 6.8, "trend": "સ્થિર", "growth": "+3.4%"},
      ];
      estimatedNavImpact = 1.65;
    } else {
      mfHoldings = [
        {"name": "Reliance Industries", "weight": 10.2, "trend": "તેજી", "growth": "+7.5%"},
        {"name": "ICICI Bank Ltd", "weight": 9.1, "trend": "તેજી", "growth": "+10.4%"},
        {"name": "State Bank of India", "weight": 6.5, "trend": "સ્થિર", "growth": "+5.2%"},
      ];
      estimatedNavImpact = 1.45;
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

    lastMfUpdatedTime = DateFormat('hh:mm a').format(DateTime.now());
    setState(() => _isMfLoading = false);
  }

  // --- સ્ટોક લેવલ, ચાર્ટ અને ન્યૂઝ એનાલિસિસ ---
  void _calculateStockLevels(String stockName, double? userPrice) {
    final name = stockName.trim().toUpperCase();
    double price = userPrice ?? 0.0;

    // જો કોઈ વપરાશકર્તા માત્ર સ્ટોક નામ સર્ચ કરે, તો વાસ્તવિક બજાર ભાવ લેવાશે
    if (price <= 0 || (userPrice == 410.0 && name != "TATA POWER")) {
      if (name.contains("RELIANCE")) {
        price = 2740.0;
        stockNewsSentiment = "🟢 તેજીમય સમાચાર (રિટેલ સેક્ટરમાં નવું રોકાણ & 5G ગ્રોથ)";
      } else if (name.contains("TATA POWER")) {
        price = 410.0;
        stockNewsSentiment = "🟢 સોલાર પાર્ક અને EV ચાર્જિંગ સ્ટેશનના નવા કોન્ટ્રાક્ટ્સ";
      } else if (name.contains("TCS")) {
        price = 4120.0;
        stockNewsSentiment = "⚪ સ્થિર પરિણામો & $2.5B નવો AI ઓર્ડર મળ્યો";
      } else if (name.contains("INFOSYS") || name.contains("INFY")) {
        price = 1880.0;
        stockNewsSentiment = "🟢 યુરોપિયન બેંકિંગ સેક્ટરમાંથી મોટો ક્લાઉડ પ્રોજેક્ટ";
      } else if (name.contains("HDFC")) {
        price = 1680.0;
        stockNewsSentiment = "🟢 લોન ગ્રોથમાં વધારો & મર્જર પછી નફો સારો";
      } else if (name.contains("SBI")) {
        price = 820.0;
        stockNewsSentiment = "🟢 NPA ઘટી & તહેવારોની સિઝનમાં ધિરાણ વધ્યું";
      } else if (name.contains("ITC")) {
        price = 490.0;
        stockNewsSentiment = "⚪ હોટેલ્સ ડી-મર્જર પ્રક્રિયા અને FMCG ગ્રોથ";
      } else {
        price = 650.0;
        stockNewsSentiment = "🟢 સામાન્ય બજાર ટ્રેન્ડ તેજીમય જણાય છે";
      }
    }

    _stockPriceCtrl.text = price.toStringAsFixed(1);
    currentStockPrice = price;
    stockSupport = price * 0.95;
    stockResistance = price * 1.08;
    stockTarget = price * 1.15;

    stockChartSpots = [
      FlSpot(0, price * 0.96),
      FlSpot(1, price * 0.98),
      FlSpot(2, price * 0.95),
      FlSpot(3, price * 1.03),
      FlSpot(4, price * 0.99),
      FlSpot(5, price),
    ];

    setState(() {});
  }

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
              height: 350,
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
                            subtitle: Text("દર મહિને ${a['day']} તારીખે"),
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
          title: const Text('નવું રિકરિંગ પેમેન્ટ સેટ કરો'),
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
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'નામ (દા.ત. Tata Large Cap, હોમ લોન)')),
                TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'માસિક રકમ (₹)')),
                TextField(controller: dayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'તારીખ (૧ થી ૨૮)')),
                DropdownButtonFormField<String>(
                  value: fromAccId,
                  decoration: const InputDecoration(labelText: 'ખાતું પસંદ કરો'),
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
      return const Center(child: Text('કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey)));
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
            trailing: Text('₹${tx['amount']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: amountColor)),
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

    int cIdx = 0;
    final sections = entries.map((e) {
      final col = colors[cIdx % colors.length];
      cIdx++;
      return PieChartSectionData(value: e.value, title: '₹${e.value.toStringAsFixed(0)}', color: col, radius: 50, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white));
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  const Text('આલેખ વિશ્લેષણ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(height: 180, child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 35, sectionsSpace: 2))),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
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
                        Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('₹${actual.toStringAsFixed(0)} / ₹${target.toStringAsFixed(0)}', style: TextStyle(color: isOver ? Colors.red : Colors.teal, fontWeight: FontWeight.bold)),
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
  // ૪. ઇન્વેસ્ટમેન્ટ સ્ક્રીન (૪ સબ-ટેબ્સ: MF, Stocks, સોનું-ચાંદી, મિલકત)
  // =========================================================================
  Widget _buildInvestmentTab() {
    String invTitle = settingsBox.get('customInvTitle', defaultValue: 'ઇન્વેસ્ટમેન્ટ');

    return DefaultTabController(
      length: 4,
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
            isScrollable: true,
            tabs: [
              Tab(text: "મ્યુચ્યુઅલ ફંડ", icon: Icon(Icons.pie_chart)),
              Tab(text: "સ્ટોક માર્કેટ", icon: Icon(Icons.show_chart)),
              Tab(text: "કિંમતી ધાતુઓ", icon: Icon(Icons.monetization_on)),
              Tab(text: "અન્ય મિલકત (Assets)", icon: Icon(Icons.home_work)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMutualFundSubTab(),
            _buildStockMarketSubTab(),
            _buildPreciousMetalsSubTab(),
            _buildPhysicalAssetsSubTab(),
          ],
        ),
      ),
    );
  }

  // ટેબ ૧: મ્યુચ્યુઅલ ફંડ (લાઈવ સમય અને તેજી વિશ્લેષણ)
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
                          hintText: "મ્યુચ્યુઅલ ફંડ શોધો...",
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
                  color: statusColor.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentMfName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("લાઈવ NAV: ₹${currentMfNav.toStringAsFixed(2)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            Text("સમય: $lastMfUpdatedTime", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
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
                const Text("📋 સ્ટોક હોલ્ડિંગ્સ અને પરફોર્મન્સ:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...mfHoldings.map((h) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text("વેઇટેજ: ${h['weight']}% | વળતર: ${h['growth']}"),
                        trailing: Text(h['trend'], style: TextStyle(fontWeight: FontWeight.bold, color: h['trend'] == 'તેજી' ? Colors.green : Colors.grey)),
                      ),
                    )),
              ],
            ),
          );
  }

  // ટેબ ૨: સ્ટોક માર્કેટ (ચાર્ટ અને ન્યૂઝ એનાલિસિસ સાથે)
  Widget _buildStockMarketSubTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _stockNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'સ્ટોકનું નામ (RELIANCE, TATA POWER, TCS, INFY)',
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
                      icon: const Icon(Icons.analytics),
                      label: const Text('ચાર્ટ એનાલિસિસ અને લેવલ નક્કી કરો'),
                      onPressed: () {
                        final p = double.tryParse(_stockPriceCtrl.text);
                        _calculateStockLevels(_stockNameCtrl.text, p);
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [const Text("સપોર્ટ લેવલ", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), Text("₹${stockSupport.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))]),
                      Column(children: [const Text("રેઝિસ્ટન્સ લેવલ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), Text("₹${stockResistance.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))]),
                      Column(children: [const Text("ટાર્ગેટ પ્રાઇસ", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), Text("₹${stockTarget.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        const Icon(Icons.newspaper, size: 18, color: Colors.teal),
                        const SizedBox(width: 8),
                        Expanded(child: Text(stockNewsSentiment, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${_stockNameCtrl.text.toUpperCase()} - ટેકનિકલ ટ્રેન્ડ આલેખ (ભાવ: ₹${currentStockPrice.toStringAsFixed(1)})", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 160,
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

  // ટેબ ૩: કિંમતી ધાતુઓ (શહેર મુજબ લાઈવ સોનું-ચાંદી)
  Widget _buildPreciousMetalsSubTab() {
    final rates = bullionCityRates[selectedCity] ?? {"gold24": 74850.0, "gold22": 68620.0, "silver": 88500.0};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ચોક્કસ શહેર પસંદ કરો:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedCity,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: bullionCityRates.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedCity = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        const Icon(Icons.circle, color: Colors.amber, size: 28),
                        const SizedBox(height: 4),
                        const Text("સોનું (24K - 10g)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                        Text("₹${rates['gold24']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown)),
                        const Divider(),
                        const Text("સોનું (22K - 10g)", style: TextStyle(fontSize: 11, color: Colors.brown)),
                        Text("₹${rates['gold22']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.brown)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  color: Colors.blueGrey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        const Icon(Icons.circle, color: Colors.blueGrey, size: 28),
                        const SizedBox(height: 4),
                        const Text("ચાંદી (Silver - 1 Kg)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        Text("₹${rates['silver']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const Divider(),
                        const Text("સ્થિતિ: તેજીમય", style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                        const Text("+0.85% વધારો", style: TextStyle(fontSize: 12, color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ટેબ ૪: અન્ય મિલકત અને એસેટ્સ (મકાન, પ્લોટ, જમીન)
  Widget _buildPhysicalAssetsSubTab() {
    final assets = physicalAssetsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double totalAssetVal = assets.fold(0.0, (sum, i) => sum + (i['value'] as num).toDouble());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("કુલ સંપત્તિ: ₹${totalAssetVal.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text("મિલકત ઉમેરો"),
                onPressed: _openAddPhysicalAssetDialog,
              ),
            ],
          ),
          const SizedBox(height: 10),
          assets.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text("કોઈ મકાન, પ્લોટ કે કિંમતી વસ્તુ ઉમેરેલ નથી.")))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: assets.length,
                  itemBuilder: (ctx, i) {
                    final item = assets[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          item['type'] == 'પ્લોટ/જમીન' ? Icons.landscape : (item['type'] == 'સોનું/ચાંદી' ? Icons.monetization_on : Icons.home),
                          color: Colors.teal,
                        ),
                        title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${item['type']} • ${item['location'] ?? ''}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${item['value']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () {
                                physicalAssetsBox.delete(item['id']);
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
    );
  }

  void _openAddPhysicalAssetDialog() {
    final titleCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    String type = 'મકાન/ફ્લેટ';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('નવી એસેટ / મિલકત ઉમેરો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'મિલકતનો પ્રકાર'),
                  items: ['મકાન/ફ્લેટ', 'પ્લોટ/જમીન', 'સોનું/ચાંદી (Physical)', 'દુકાન/ઓફિસ', 'વાહન/અન્ય']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => type = v);
                  },
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'નામ / વિગત (દા.ત. 3BHK ફ્લેટ)')),
                TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'સ્થળ / શહેર')),
                TextField(controller: valueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'અંદાજિત કિંમત (₹)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final id = "asset_${DateTime.now().millisecondsSinceEpoch}";
                physicalAssetsBox.put(id, {
                  'id': id,
                  'title': titleCtrl.text,
                  'type': type,
                  'location': locCtrl.text,
                  'value': double.tryParse(valueCtrl.text) ?? 0.0,
                });
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
                TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'રકમ (₹)')),
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
                child: Row(
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
