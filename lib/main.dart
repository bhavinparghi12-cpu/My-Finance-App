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
                cardTheme: const CardThemeData(color: Colors.white, elevation: 1),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: primaryColor,
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardTheme: const CardThemeData(color: Color(0xFF1E1E1E), elevation: 1),
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

  // મ્યુચ્યુઅલ ફંડ સ્ટેટ્સ
  final TextEditingController _mfSearchController = TextEditingController(text: "TATA large and mid cap");
  bool _isMfLoading = false;
  String currentMfName = "Tata Large & Mid Cap Fund - Direct Plan - Growth Option";
  double currentMfNav = 536.86;
  double estimatedNavImpact = 1.20;
  String lastMfUpdatedTime = DateFormat('hh:mm a').format(DateTime.now());
  String marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
  Color statusColor = Colors.green;
  List<Map<String, dynamic>> mfHoldings = [];

  // સ્ટોક સ્ટેટ્સ
  final TextEditingController _stockNameCtrl = TextEditingController(text: "RELIANCE");
  final TextEditingController _stockPriceCtrl = TextEditingController(text: "2740.0");
  double currentStockPrice = 2740.0;
  double stockSupport = 2603.0;
  double stockResistance = 2959.2;
  double stockTarget = 3151.0;
  String stockNewsSentiment = "🟢 તેજીમય સમાચાર (મજબૂત રિટેલ & 5G ગ્રોથ)";
  List<FlSpot> stockChartSpots = const [
    FlSpot(0, 2650), FlSpot(1, 2690), FlSpot(2, 2670),
    FlSpot(3, 2720), FlSpot(4, 2710), FlSpot(5, 2740)
  ];

  // કિંમતી ધાતુઓ શહેર રેટ્સ
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

  // લાઈવ મ્યુચ્યુઅલ ફંડ એનાલિસિસ
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
    } else {
      mfHoldings = [
        {"name": "Reliance Industries", "weight": 10.2, "trend": "તેજી", "growth": "+7.5%"},
        {"name": "ICICI Bank Ltd", "weight": 9.1, "trend": "તેજી", "growth": "+10.4%"},
        {"name": "State Bank of India", "weight": 6.5, "trend": "સ્થિર", "growth": "+5.2%"},
      ];
      estimatedNavImpact = 1.45;
    }

    marketStatus = estimatedNavImpact > 1.0 ? "🟢 મજબૂત તેજી (Bullish Alert)" : "⚪ સામાન્ય ગતિ (Range Bound)";
    statusColor = estimatedNavImpact > 1.0 ? Colors.green : Colors.blue;
    lastMfUpdatedTime = DateFormat('hh:mm a').format(DateTime.now());
    setState(() => _isMfLoading = false);
  }

  // સ્ટોક લેવલ્સ
  void _calculateStockLevels(String stockName, double? userPrice) {
    final name = stockName.trim().toUpperCase();
    double price = userPrice ?? 0.0;

    if (price <= 0 || (userPrice == 410.0 && name != "TATA POWER")) {
      if (name.contains("RELIANCE")) {
        price = 2740.0;
        stockNewsSentiment = "🟢 તેજીમય સમાચાર (મજબૂત રિટેલ & 5G ગ્રોથ)";
      } else if (name.contains("TATA POWER")) {
        price = 410.0;
        stockNewsSentiment = "🟢 સોલાર પાર્ક અને EV ચાર્જિંગ સ્ટેશનના ઓર્ડર્સ";
      } else if (name.contains("TCS")) {
        price = 4120.0;
        stockNewsSentiment = "⚪ સ્થિર પરિણામો & \$2.5B નવો AI ઓર્ડર મળ્યો";
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

  // સેટિંગ્સ ડાયલોગ
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
                leading: const Icon(Icons.account_balance, color: Colors.green),
                title: const Text('બેંક અને વૉલેટ ખાતાઓ (Accounts)'),
                subtitle: const Text('ખાતાઓ ઉમેરો, સુધારો અને પ્રકાર બદલો'),
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

  // ખાતાઓ મેનેજ કરવાનો સંપૂર્ણ ડાયલોગ (ઉમેરવા/સુધારવા સાથે)
  void _openAccountManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('ખાતાઓ (Accounts) મેનેજ કરો'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: accounts.isEmpty
                ? const Center(child: Text('કોઈ ખાતું ઉમેરેલ નથી.'))
                : ListView.builder(
                    itemCount: accounts.length,
                    itemBuilder: (context, i) {
                      final a = accounts[i];
                      final currentBal = getAccountCurrentBalance(a['id'].toString());
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          title: Text(a['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${a['type'] ?? 'ખાતું'}\nશરૂઆતની સિલક: ₹${a['openingBalance'] ?? 0} | હાલની સિલક: ₹${currentBal.toStringAsFixed(0)}'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                                onPressed: () {
                                  _openAccountEditDialog(account: a, onSaved: () {
                                    setDlgState(() {});
                                    setState(() {});
                                  });
                                },
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
              onPressed: () {
                _openAccountEditDialog(onSaved: () {
                  setDlgState(() {});
                  setState(() {});
                });
              },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
          ],
        ),
      ),
    );
  }

  void _openAccountEditDialog({Map<dynamic, dynamic>? account, VoidCallback? onSaved}) {
    final nameCtrl = TextEditingController(text: account != null ? account['name'] : '');
    final openingBalCtrl = TextEditingController(text: account != null ? (account['openingBalance']?.toString() ?? '0') : '0');
    String type = account != null ? (account['type'] ?? 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)') : 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)';

    final accountTypes = [
      'સેવિંગ્સ એકાઉન્ટ (Savings A/C)',
      'સેલેરી એકાઉન્ટ (Salary A/C)',
      'કરન્ટ એકાઉન્ટ (Current A/C)',
      'રોકડ (Cash Wallet)',
      'ક્રેડિટ કાર્ડ (Credit Card)',
      'ફિક્સ ડિપોઝીટ (FD / RD)',
      'લોન / દેવું (Loan A/C)',
      'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)',
    ];

    if (!accountTypes.contains(type)) accountTypes.add(type);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEditState) => AlertDialog(
          title: Text(account == null ? 'નવું ખાતું ઉમેરો' : 'ખાતામાં સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ખાતાનું નામ (દા.ત. SBI, HDFC)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ખાતાનો પ્રકાર'),
                  items: accountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) {
                    if (v != null) setEditState(() => type = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: openingBalCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'પ્રારંભિક સિલક (₹)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final id = account != null ? account['id'] : 'acc_${DateTime.now().millisecondsSinceEpoch}';
                  accountsBox.put(id, {
                    'id': id,
                    'name': nameCtrl.text.trim(),
                    'type': type,
                    'openingBalance': double.tryParse(openingBalCtrl.text) ?? 0.0,
                  });
                  if (onSaved != null) onSaved();
                  setState(() {});
                  Navigator.pop(ctx);
                }
              },
              child: const Text('સેવ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  // ૧. દૈનિક એન્ટ્રી લિસ્ટ
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

  // ૨. એનાલિસિસ ચાર્ટ
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
                  const Text('આલેખ વિશ્લેષણ (ખર્ચ & આવક)', style: TextStyle(fontWeight: FontWeight.bold)),
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

  // ૩. બજેટ ટેબ
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

  // ૪. ઇન્વેસ્ટમેન્ટ ટેબ (MF, Stocks, સોનું-ચાંદી, મિલકત)
  Widget _buildInvestmentTab() {
    String invTitle = settingsBox.get('customInvTitle', defaultValue: 'ઇન્વેસ્ટમેન્ટ');

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(invTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            _buildMfTab(),
            _buildStockTab(),
            _buildBullionTab(),
            _buildAssetsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMfTab() {
    return _isMfLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mfSearchController,
                        decoration: const InputDecoration(hintText: "મ્યુચ્યુઅલ ફંડ શોધો...", border: OutlineInputBorder(), isDense: true),
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
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currentMfName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("લાઈવ NAV: ₹${currentMfNav.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text("સમય: $lastMfUpdatedTime", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        const Divider(),
                        Text("સંભવિત અસર: +$estimatedNavImpact% | $marketStatus", style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...mfHoldings.map((h) => Card(
                      child: ListTile(
                        dense: true,
                        title: Text(h['name']),
                        subtitle: Text("વેઇટેજ: ${h['weight']}% | પરફોર્મન્સ: ${h['growth']}"),
                        trailing: Text(h['trend'], style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                    )),
              ],
            ),
          );
  }

  Widget _buildStockTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(controller: _stockNameCtrl, decoration: const InputDecoration(labelText: 'સ્ટોકનું નામ', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: _stockPriceCtrl, decoration: const InputDecoration(labelText: 'હાલનો ભાવ (₹)', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      onPressed: () => _calculateStockLevels(_stockNameCtrl.text, double.tryParse(_stockPriceCtrl.text)),
                      child: const Text('ચાર્ટ અને લેવલ વિશ્લેષણ'),
                    ),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [const Text("સપોર્ટ", style: TextStyle(color: Colors.green)), Text("₹${stockSupport.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
                      Column(children: [const Text("રેઝિસ્ટન્સ", style: TextStyle(color: Colors.red)), Text("₹${stockResistance.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
                      Column(children: [const Text("ટાર્ગેટ", style: TextStyle(color: Colors.blue)), Text("₹${stockTarget.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(stockNewsSentiment, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${_stockNameCtrl.text.toUpperCase()} - ટેકનિકલ ટ્રેન્ડ"),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    child: LineChart(LineChartData(
                      lineBarsData: [LineChartBarData(spots: stockChartSpots, isCurved: true, color: Colors.teal)],
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: true),
                    )),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBullionTab() {
    final rates = bullionCityRates[selectedCity] ?? {"gold24": 74850.0, "gold22": 68620.0, "silver": 88500.0};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: selectedCity,
            decoration: const InputDecoration(labelText: 'શહેર પસંદ કરો', border: OutlineInputBorder()),
            items: bullionCityRates.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => selectedCity = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text("સોનું (24K)", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
                        Text("₹${rates['gold24']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  color: Colors.blueGrey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text("ચાંદી (1 Kg)", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                        Text("₹${rates['silver']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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

  Widget _buildAssetsTab() {
    final assets = physicalAssetsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    return ListView.builder(
      shrinkWrap: true,
      itemCount: assets.length,
      itemBuilder: (ctx, i) {
        final a = assets[i];
        return Card(
          child: ListTile(
            title: Text(a['title']),
            subtitle: Text("${a['type']} • ${a['location']}"),
            trailing: Text("₹${a['value']}", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    //final assetGain = _calculateTotal('assetIncrease');
    //final totalExpense = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    //final totalIncome = _calculateTotal('incomeCredit');

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
          IconButton(icon: const Icon(Icons.settings), tooltip: 'સેટિંગ્સ', onPressed: _openSettingsDialog),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'લોક કરો', onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthGate()))),
        ],
      ),
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
                        DropdownMenuItem(value: TimeFilter.yearly, child: Text('વાર્ષિક')),
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
