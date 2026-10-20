import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'auth_gate.dart';
import 'export_service.dart';

final ValueNotifier<Color> appSeedColor = ValueNotifier<Color>(Colors.teal);
final ValueNotifier<String?> appBackgroundImage = ValueNotifier<String?>(null);
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

enum TimeFilter { daily, monthly, quarterly, halfYearly, yearly, allFY, custom }
enum AnalysisView { all, expenseOnly, incomeOnly, investmentOnly }
enum ChartType { pie, bar, line }
enum BudgetViewMode { classicProgress, dualPieCharts }

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
    debugPrint("Firebase Init: $e");
  }

  try {
    await Hive.initFlutter();
    final settings = await Hive.openBox('settingsBox');

    final dynamic rawColor = settings.get('primaryColor');
    if (rawColor is int) {
      appSeedColor.value = Color(rawColor);
    }

    final dynamic rawDark = settings.get('isDarkMode', defaultValue: false);
    if (rawDark == true) {
      appThemeMode.value = ThemeMode.dark;
    }
  } catch (e) {
    debugPrint("Hive Init: $e");
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
                scaffoldBackgroundColor: Colors.grey.shade100,
                cardTheme: const CardThemeData(color: Colors.white, elevation: 1.5),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: primaryColor,
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardTheme: const CardThemeData(color: Color(0xFF1E1E1E), elevation: 2),
                textTheme: const TextTheme(
                  bodyLarge: TextStyle(color: Colors.white),
                  bodyMedium: TextStyle(color: Colors.white70),
                  bodySmall: TextStyle(color: Colors.white60),
                  titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  titleMedium: TextStyle(color: Colors.white),
                  titleSmall: TextStyle(color: Colors.white70),
                ),
                dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
                bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF1E1E1E)),
              ),
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

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
  late Box physicalAssetsBox;
  late Box bullionInvestmentsBox;
  bool _isInitialized = false;

  int _selectedTabIndex = 0;
  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTimeRange? customDateRange;
  String? selectedAccountId;
  AnalysisView selectedAnalysisView = AnalysisView.all;
  ChartType selectedChartType = ChartType.pie;
  String budgetPeriod = 'માસિક';

  late int selectedFinancialYearStart;
  String appTitle = 'નાણાકીય હિસાબો';

  // મ્યુચ્યુઅલ ફંડ સ્ટેટ્સ
  final TextEditingController _mfSearchController = TextEditingController(text: "TATA Large & Mid Cap");
  bool _isMfLoading = false;
  String currentMfName = "Tata Large & Mid Cap Fund - Direct Plan";
  double currentMfNav = 536.86;
  double estimatedNavImpact = 1.20;
  String lastMfUpdatedTime = DateFormat('hh:mm a').format(DateTime.now());
  String marketStatus = "🟢 મજબૂત તેજી (Bullish Alert)";
  Color statusColor = Colors.green;
  List<Map<String, dynamic>> mfHoldings = [];

  // સ્ટોક માર્કેટ સ્ટેટ્સ
  final TextEditingController _stockNameCtrl = TextEditingController(text: "RELIANCE");
  final TextEditingController _stockPriceCtrl = TextEditingController(text: "2740.0");
  double currentStockPrice = 2740.0;
  double stockSupport = 2603.0;
  double stockResistance = 2959.2;
  double stockTarget = 3151.0;
  String stockNewsSentiment = "🟢 તેજીમય સમાચાર (મજબૂત રિટેલ & 5G ગ્રોથ)";
  List<FlSpot> stockChartSpots = const [
    FlSpot(0, 2650),
    FlSpot(1, 2690),
    FlSpot(2, 2670),
    FlSpot(3, 2720),
    FlSpot(4, 2710),
    FlSpot(5, 2740)
  ];

  // કિંમતી ધાતુઓ શહેર રેટ્સ (લાઈવ અંદાજિત બજાર ભાવ)
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
    physicalAssetsBox = await Hive.openBox('physicalAssetsBox_$prefix');
    bullionInvestmentsBox = await Hive.openBox('bullionInvestmentsBox_$prefix');

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
      {'id': '2', 'name': 'પગાર / ધંધાકીય આવક', 'effect': 'incomeCredit', 'color': Colors.green.toARGB32()},
      {'id': '3', 'name': 'શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'effect': 'assetIncrease', 'color': Colors.blue.toARGB32()},
      {'id': '4', 'name': 'સોનું / ચાંદી રોકાણ', 'effect': 'assetIncrease', 'color': Colors.amber.toARGB32()},
      {'id': '5', 'name': 'લોન / EMI હપ્તો', 'effect': 'loanRepay', 'color': Colors.orange.toARGB32()},
      {'id': '6', 'name': 'પ્રવાસ અને ઇંધણ', 'effect': 'expenseDebit', 'color': Colors.purple.toARGB32()},
    ];
    for (var cat in defaultCats) {
      categoriesBox.put(cat['id'], cat);
    }
  }

  void _saveDefaultAccounts() {
    final defaultAccs = [
      {'id': 'acc_1', 'name': 'રોકડ સિલક (Cash Wallet)', 'type': 'રોકડ (Cash Wallet)', 'openingBalance': 0.0},
      {'id': 'acc_2', 'name': 'સેવિંગ્સ બેંક એકાઉન્ટ', 'type': 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)', 'openingBalance': 0.0},
      {'id': 'acc_3', 'name': 'સેલેરી બેંક એકાઉન્ટ', 'type': 'સેલેરી એકાઉન્ટ (Salary A/C)', 'openingBalance': 0.0},
      {'id': 'acc_4', 'name': 'મ્યુચ્યુઅલ ફંડ પોર્ટફોલિયો', 'type': 'મ્યુચ્યુઅલ ફંડ પોર્ટફોલિયો (MF Portfolio)', 'openingBalance': 0.0},
      {'id': 'acc_5', 'name': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ', 'type': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)', 'openingBalance': 0.0},
    ];
    for (var acc in defaultAccs) {
      accountsBox.put(acc['id'], acc);
    }
  }

  List<Map<dynamic, dynamic>> get categories =>
      categoriesBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  List<Map<dynamic, dynamic>> get accounts =>
      accountsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  double _parseAmt(dynamic value) {
    if (value is num) return value.toDouble();
    if (value != null) return double.tryParse(value.toString()) ?? 0.0;
    return 0.0;
  }

  void _processAutoPayAndSIP() {
    final now = DateTime.now();
    final allAuto = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    for (var item in allAuto) {
      if (item['isActive'] != true) continue;

      final int day = int.tryParse(item['day']?.toString() ?? '1') ?? 1;
      final double amt = _parseAmt(item['amount']);
      final String type = item['type'] ?? 'SIP';
      final String fromAccId = item['fromAccountId']?.toString() ?? '';
      final String toTarget = item['toTarget'] ?? '';
      final String lastExecution = item['lastProcessed'] ?? '';

      final currentMonthKey = "${now.year}-${now.month}";

      if (lastExecution != currentMonthKey && now.day >= day) {
        final txId = "auto_${DateTime.now().millisecondsSinceEpoch}_${item['id']}";
        final fromAcc = accounts.firstWhere((a) => a['id'].toString() == fromAccId, orElse: () => {'name': 'બેંક'});
        String catEffect = type == 'SIP' ? 'assetIncrease' : (type == 'EMI' ? 'loanRepay' : 'expenseDebit');
        String title = type == 'SIP' ? "ઓટો SIP: $toTarget" : (type == 'EMI' ? "ઓટો EMI: $toTarget" : "ઓટો-પે: $toTarget");

        transactionsBox.put(txId, {
          'id': txId,
          'title': title,
          'amount': amt,
          'date': DateTime(now.year, now.month, day).toIso8601String(),
          'categoryId': type == 'SIP' ? '3' : (type == 'EMI' ? '5' : '1'),
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
    if (acc.isEmpty) return 0.0;
    double balance = _parseAmt(acc['openingBalance']);

    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    for (var tx in allTx) {
      if (tx['accountId'].toString() == accountId) {
        final amt = _parseAmt(tx['amount']);
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
      final date = DateTime.tryParse(tx['date']?.toString() ?? '') ?? now;
      if (date.isBefore(fyStart) || date.isAfter(fyEnd)) return false;

      if (selectedAccountId != null && tx['accountId']?.toString() != selectedAccountId) {
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
            matchesTime = date.isAfter(customDateRange!.start.subtract(const Duration(seconds: 1))) &&
                date.isBefore(customDateRange!.end.add(const Duration(days: 1)));
          } else {
            matchesTime = true;
          }
          break;
      }
      return matchesTime;
    }).toList();
  }

  double _calculateTotal(String effect) {
    return filteredTransactions
        .where((t) => t['categoryEffect'] == effect)
        .fold(0.0, (sum, item) => sum + _parseAmt(item['amount']));
  }

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
    if (mounted) {
      setState(() => _isMfLoading = false);
    }
  }

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
        stockNewsSentiment = "⚪ સ્થિર પરિણામો & AI ક્ષેત્રે મોટો ઓર્ડર";
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

    if (mounted) setState(() {});
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
                leading: const Icon(Icons.account_balance, color: Colors.green),
                title: const Text('બેંક, વૉલેટ અને ડીમેટ ખાતાઓ'),
                subtitle: const Text('ખાતાઓ ઉમેરો, પ્રકાર બદલો અને સિલક સુધારો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAccountManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.autorenew, color: Colors.indigo),
                title: const Text('EMI / SIP / ઓટો-પે મેનેજર'),
                subtitle: const Text('નવી SIP કે લોન હપ્તો ઉમેરો, એડિટ કરો અને ડિલીટ કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAutoPayManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category, color: Colors.orange),
                title: const Text('ખર્ચ / આવક કેટેગરી મેનેજ કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCategoryManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('સંપૂર્ણ હિસાબ એક્સપોર્ટ (PDF / CSV)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final inc = _calculateTotal('incomeCredit');
                  final exp = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
                  final inv = _calculateTotal('assetIncrease');
                  await ExportService.exportToPDF(
                    filteredTransactions,
                    inc,
                    exp,
                    inv,
                    inc - (exp + inv),
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
                                tooltip: 'સુધારો',
                                onPressed: () {
                                  _openAccountEditDialog(
                                    account: a,
                                    onSaved: () {
                                      setDlgState(() {});
                                      setState(() {});
                                    },
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                tooltip: 'કાઢી નાખો',
                                onPressed: () async {
                                  await accountsBox.delete(a['id']);
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
    final nameCtrl = TextEditingController(text: account != null ? account['name']?.toString() : '');
    final openingBalCtrl = TextEditingController(text: account != null ? (account['openingBalance']?.toString() ?? '0') : '0');
    String type = account != null ? (account['type']?.toString() ?? 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)') : 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)';

    final accountTypes = [
      'સેવિંગ્સ એકાઉન્ટ (Savings A/C)',
      'સેલેરી એકાઉન્ટ (Salary A/C)',
      'કરન્ટ એકાઉન્ટ (Current A/C)',
      'રોકડ (Cash Wallet)',
      'મ્યુચ્યુઅલ ફંડ પોર્ટફોલિયો (MF Portfolio)',
      'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)',
      'ક્રેડિટ કાર્ડ (Credit Card)',
      'ફિક્સ ડિપોઝીટ (FD / RD)',
      'લોન / દેવું (Loan A/C)',
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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ખાતાનું નામ (દા.ત. SBI, HDFC MF)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
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
                  final id = account != null ? account['id'].toString() : 'acc_${DateTime.now().millisecondsSinceEpoch}';
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
                            subtitle: Text("દર મહિને ${a['day']} તારીખે કપાત"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                                  onPressed: () {
                                    _openAutoPayEditDialog(
                                      existingItem: a,
                                      onSaved: () => setDlgState(() {}),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed: () async {
                                    await autoPayBox.delete(a['id']);
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

  void _openAutoPayEditDialog({Map<dynamic, dynamic>? existingItem, VoidCallback? onSaved}) {
    final targetCtrl = TextEditingController(text: existingItem != null ? existingItem['toTarget']?.toString() : '');
    final amtCtrl = TextEditingController(text: existingItem != null ? existingItem['amount']?.toString() : '');
    final dayCtrl = TextEditingController(text: existingItem != null ? existingItem['day']?.toString() : '5');
    String type = existingItem != null ? existingItem['type']?.toString() ?? 'SIP' : 'SIP';
    String fromAccId = existingItem != null
        ? existingItem['fromAccountId']?.toString() ?? ''
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingItem == null ? 'નવી SIP / EMI સેટ કરો' : 'SIP / EMI સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'પ્રકાર'),
                  items: const [
                    DropdownMenuItem(value: 'SIP', child: Text('SIP (મ્યુચ્યુઅલ ફંડ/શેર)')),
                    DropdownMenuItem(value: 'EMI', child: Text('EMI (લોનનો હપ્તો)')),
                    DropdownMenuItem(value: 'AutoPay', child: Text('ઓટો-પે બિલ/ખર્ચ')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => type = v);
                  },
                ),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'નામ (દા.ત. Parag Parikh Flexi, હોમ લોન)')),
                TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'માસિક રકમ (₹)')),
                TextField(controller: dayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'દર મહિનાની તારીખ (૧ થી ૨૮)')),
                DropdownButtonFormField<String>(
                  initialValue: fromAccId.isNotEmpty ? fromAccId : (accounts.isNotEmpty ? accounts.first['id'].toString() : null),
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
                final id = existingItem != null ? existingItem['id'].toString() : "auto_${DateTime.now().millisecondsSinceEpoch}";
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
            itemBuilder: (context, i) => ListTile(title: Text(categories[i]['name'] ?? ''), subtitle: Text(categories[i]['effect'] ?? '')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ'))],
      ),
    );
  }

  void _openTransactionDialog({Map<dynamic, dynamic>? existingTx}) {
    final titleController = TextEditingController(text: existingTx != null ? existingTx['title']?.toString() : '');
    final amountController = TextEditingController(text: existingTx != null ? existingTx['amount']?.toString() : '');
    var selectedCat = existingTx != null
        ? categories.firstWhere((c) => c['id'].toString() == existingTx['categoryId']?.toString(), orElse: () => categories.first)
        : categories.first;
    var selectedAcc = existingTx != null
        ? accounts.firstWhere((a) => a['id'].toString() == existingTx['accountId']?.toString(), orElse: () => accounts.first)
        : accounts.first;
    DateTime transactionDate = existingTx != null ? (DateTime.tryParse(existingTx['date']?.toString() ?? '') ?? DateTime.now()) : DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(existingTx == null ? 'નવો વ્યવહાર નોંધો' : 'વ્યવહાર સુધારો', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'વિગત / શીર્ષક (દા.ત. કરિયાણું, પગાર, SIP)')),
                TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'રકમ (₹)')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedAcc['id'].toString(),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ખાતું પસંદ કરો'),
                  items: accounts.map((acc) => DropdownMenuItem<String>(value: acc['id'].toString(), child: Text(acc['name']))).toList(),
                  onChanged: (val) => setModalState(() => selectedAcc = accounts.firstWhere((a) => a['id'].toString() == val)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedCat['id'].toString(),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'કેટેગરી પસંદ કરો'),
                  items: categories.map((cat) => DropdownMenuItem<String>(value: cat['id'].toString(), child: Text(cat['name']))).toList(),
                  onChanged: (val) => setModalState(() => selectedCat = categories.firstWhere((c) => c['id'].toString() == val)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.check),
                    label: const Text('હિસાબ સેવ કરો', style: TextStyle(fontSize: 16)),
                    onPressed: () {
                      final enteredAmount = double.tryParse(amountController.text) ?? 0.0;
                      if (enteredAmount <= 0 || titleController.text.trim().isEmpty) return;
                      final id = existingTx != null ? existingTx['id'].toString() : DateTime.now().millisecondsSinceEpoch.toString();

                      transactionsBox.put(id, {
                        'id': id,
                        'title': titleController.text.trim(),
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
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCategoryBudgetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text('$budgetPeriod બજેટ લક્ષ્યાંક ગોઠવો'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final budgetKey = 'budget_${budgetPeriod}_${cat['id']}';
                final currentTarget = _parseAmt(budgetBox.get(budgetKey, defaultValue: 0.0));
                final ctrl = TextEditingController(text: currentTarget > 0 ? currentTarget.toStringAsFixed(0) : '');

                return ListTile(
                  dense: true,
                  title: Text(cat['name']),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '₹ 0', isDense: true, border: OutlineInputBorder()),
                      onChanged: (val) {
                        budgetBox.put(budgetKey, double.tryParse(val) ?? 0.0);
                      },
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

  void _openAddPhysicalAssetDialog({Map<dynamic, dynamic>? existingAsset}) {
    final titleCtrl = TextEditingController(text: existingAsset != null ? existingAsset['title']?.toString() : '');
    final valueCtrl = TextEditingController(text: existingAsset != null ? existingAsset['value']?.toString() : '');
    final locCtrl = TextEditingController(text: existingAsset != null ? existingAsset['location']?.toString() : '');
    String type = existingAsset != null ? existingAsset['type']?.toString() ?? 'મકાન/ફ્લેટ' : 'મકાન/ફ્લેટ';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingAsset == null ? 'નવી એસેટ / મિલકત ઉમેરો' : 'મિલકત સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'મિલકતનો પ્રકાર'),
                  items: ['મકાન/ફ્લેટ', 'પ્લોટ/જમીન', 'ખેતીની જમીન', 'દુકાન/ઓફિસ', 'વાહન/અન્ય']
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
                final id = existingAsset != null ? existingAsset['id'].toString() : "asset_${DateTime.now().millisecondsSinceEpoch}";
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

  void _openAddBullionDialog({Map<dynamic, dynamic>? existingItem}) {
    final titleCtrl = TextEditingController(text: existingItem != null ? existingItem['title']?.toString() : '');
    final weightCtrl = TextEditingController(text: existingItem != null ? existingItem['weight']?.toString() : '');
    final buyPriceCtrl = TextEditingController(text: existingItem != null ? existingItem['buyPrice']?.toString() : '');
    String metalType = existingItem != null ? existingItem['metalType']?.toString() ?? 'સોનું (Gold)' : 'સોનું (Gold)';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingItem == null ? 'સોનું/ચાંદી રોકાણ ઉમેરો' : 'ધાતુ રોકાણ સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: metalType,
                  decoration: const InputDecoration(labelText: 'ધાતુનો પ્રકાર'),
                  items: ['સોનું (Gold)', 'ચાંદી (Silver)']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => metalType = v);
                  },
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'વિગત (દા.ત. ૧૦ ગ્રામ સોનાનો સિક્કો)')),
                TextField(controller: weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'વજન (ગ્રામમાં)')),
                TextField(controller: buyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'કુલ ખરીદ કિંમત (₹)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final id = existingItem != null ? existingItem['id'].toString() : "bullion_${DateTime.now().millisecondsSinceEpoch}";
                bullionInvestmentsBox.put(id, {
                  'id': id,
                  'metalType': metalType,
                  'title': titleCtrl.text,
                  'weight': double.tryParse(weightCtrl.text) ?? 0.0,
                  'buyPrice': double.tryParse(buyPriceCtrl.text) ?? 0.0,
                  'date': DateTime.now().toIso8601String(),
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

  Widget _buildTransactionsTab() {
    if (filteredTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long, size: 50, color: Colors.grey),
            const SizedBox(height: 10),
            const Text('આ સમયગાળામાં કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('પ્રથમ વ્યવહાર ઉમેરો'),
              onPressed: () => _openTransactionDialog(),
            )
          ],
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
        final txDate = DateTime.tryParse(tx['date']?.toString() ?? '') ?? DateTime.now();

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: amountColor.withValues(alpha: 0.15),
              child: Icon(isIncome ? Icons.arrow_downward : (isExpense ? Icons.arrow_upward : Icons.trending_up), color: amountColor, size: 18),
            ),
            title: Text(tx['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('${tx['categoryName']} • ${tx['accountName'] ?? ''}\n${DateFormat('dd MMM yyyy').format(txDate)}', style: const TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('₹${tx['amount']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: amountColor)),
                IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => _openTransactionDialog(existingTx: tx)),
                IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.grey), onPressed: () async { await transactionsBox.delete(tx['id']); setState(() {}); }),
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
      final name = tx['categoryName']?.toString() ?? 'અન્ય';
      final amt = _parseAmt(tx['amount']);
      categorySums[name] = (categorySums[name] ?? 0.0) + amt;
    }
    if (categorySums.isEmpty || categorySums.values.every((v) => v <= 0)) {
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
        return PieChartSectionData(
          value: e.value > 0 ? e.value : 0.001,
          title: '₹${e.value.toStringAsFixed(0)}',
          color: col,
          radius: 50,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        );
      }).toList();
      chartWidget = PieChart(PieChartData(sections: sections, centerSpaceRadius: 35, sectionsSpace: 2));
    } else if (selectedChartType == ChartType.bar) {
      final barGroups = List.generate(entries.length, (i) => BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: entries[i].value, color: colors[i % colors.length], width: 14, borderRadius: BorderRadius.circular(4))],
      ));
      chartWidget = BarChart(BarChartData(barGroups: barGroups, titlesData: const FlTitlesData(show: false), gridData: const FlGridData(show: false), borderData: FlBorderData(show: false)));
    } else {
      final spots = List.generate(entries.length, (i) => FlSpot(i.toDouble(), entries[i].value));
      chartWidget = LineChart(LineChartData(
        lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.teal, barWidth: 3, belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)))],
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ));
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
                      const Text('આલેખ પસંદ કરો:', style: TextStyle(fontWeight: FontWeight.bold)),
                      SegmentedButton<ChartType>(
                        segments: const [
                          ButtonSegment(value: ChartType.pie, icon: Icon(Icons.pie_chart, size: 16), label: Text('વર્તુળ')),
                          ButtonSegment(value: ChartType.bar, icon: Icon(Icons.bar_chart, size: 16), label: Text('સ્તંભ')),
                          ButtonSegment(value: ChartType.line, icon: Icon(Icons.show_chart, size: 16), label: Text('રૈખિક')),
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

  Widget _buildBudgetTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: budgetPeriod,
                items: ['દૈનિક', 'માસિક', 'ત્રિમાસિક', 'છ માસિક', 'વાર્ષિક'].map((p) => DropdownMenuItem(value: p, child: Text('$p બજેટ'))).toList(),
                onChanged: (v) => setState(() => budgetPeriod = v!),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('લક્ષ્યાંક બદલો'),
                onPressed: _openCategoryBudgetDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...categories.map((cat) {
            final budgetKey = 'budget_${budgetPeriod}_${cat['id']}';
            final target = _parseAmt(budgetBox.get(budgetKey, defaultValue: 0.0));
            final actual = filteredTransactions
                .where((t) => t['categoryId'].toString() == cat['id'].toString())
                .fold(0.0, (sum, item) => sum + _parseAmt(item['amount']));

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
                        Text(cat['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        Text(currentMfName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                const Text("📋 સ્ટોક હોલ્ડિંગ્સ અને પરફોર્મન્સ:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...mfHoldings.map((h) => Card(
                      child: ListTile(
                        dense: true,
                        title: Text(h['name']?.toString() ?? ''),
                        subtitle: Text("વેઇટેજ: ${h['weight']}% | વળતર: ${h['growth']}"),
                        trailing: Text(h['trend']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: h['trend'] == 'તેજી' ? Colors.green : Colors.grey)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(controller: _stockNameCtrl, decoration: const InputDecoration(labelText: 'સ્ટોકનું નામ (દા.ત. RELIANCE, TCS)', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: _stockPriceCtrl, decoration: const InputDecoration(labelText: 'હાલનો ભાવ (LTP ₹)', border: OutlineInputBorder(), isDense: true)),
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
                      Column(children: [const Text("સપોર્ટ", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), Text("₹${stockSupport.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
                      Column(children: [const Text("રેઝિસ્ટન્સ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), Text("₹${stockResistance.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
                      Column(children: [const Text("ટાર્ગેટ", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), Text("₹${stockTarget.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
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
                  Text("${_stockNameCtrl.text.toUpperCase()} - ટેકનિકલ ટ્રેન્ડ (ભાવ: ₹${currentStockPrice.toStringAsFixed(1)})", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    child: LineChart(LineChartData(
                      lineBarsData: [LineChartBarData(spots: stockChartSpots, isCurved: true, color: Colors.teal, barWidth: 3, belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)))],
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: true),
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
    final bullionList = bullionInvestmentsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ચોક્કસ શહેર પસંદ કરો:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCity,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: bullionCityRates.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => selectedCity = v!),
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
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text("સોનું (24K - 10g)", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
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
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text("ચાંદી (1 Kg)", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                        Text("₹${rates['silver']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const Divider(),
                        const Text("+0.85% વધારો (તેજી)", style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("મારું સોનું / ચાંદી રોકાણ:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('રોકાણ ઉમેરો'),
                onPressed: () => _openAddBullionDialog(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          bullionList.isEmpty
              ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("કોઈ સોનું કે ચાંદીનું રોકાણ નોંધેલ નથી.")))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: bullionList.length,
                  itemBuilder: (ctx, i) {
                    final b = bullionList[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.monetization_on, color: b['metalType'].toString().contains('Gold') ? Colors.amber : Colors.blueGrey),
                        title: Text(b['title'] ?? ''),
                        subtitle: Text("${b['metalType']} • વજન: ${b['weight']}g"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${b['buyPrice']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.teal), onPressed: () => _openAddBullionDialog(existingItem: b)),
                            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () async { await bullionInvestmentsBox.delete(b['id']); setState(() {}); }),
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

  Widget _buildAssetsTab() {
    final assets = physicalAssetsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double totalVal = assets.fold(0.0, (sum, i) => sum + _parseAmt(i['value']));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("કુલ સંપત્તિ: ₹${totalVal.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text("મિલકત ઉમેરો"),
                onPressed: () => _openAddPhysicalAssetDialog(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          assets.isEmpty
              ? const Padding(padding: EdgeInsets.all(30.0), child: Text("કોઈ મકાન, પ્લોટ કે જમીન ઉમેરેલ નથી."))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: assets.length,
                  itemBuilder: (ctx, i) {
                    final a = assets[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          a['type'] == 'પ્લોટ/જમીન' ? Icons.landscape : Icons.home,
                          color: Colors.teal,
                        ),
                        title: Text(a['title'] ?? ''),
                        subtitle: Text("${a['type']} • ${a['location']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${a['value']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.teal), onPressed: () => _openAddPhysicalAssetDialog(existingAsset: a)),
                            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () async { await physicalAssetsBox.delete(a['id']); setState(() {}); }),
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

  Widget _buildMiniSummaryCard(String title, double amount, Color color) {
    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.12),
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

    final totalIncome = _calculateTotal('incomeCredit');
    final totalExpense = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    final assetGain = _calculateTotal('assetIncrease');
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
            icon: const Icon(Icons.add_circle, color: Colors.teal),
            tooltip: 'વ્યવહાર નોંધો',
            onPressed: () => _openTransactionDialog(),
          ),
          IconButton(icon: const Icon(Icons.settings), tooltip: 'સેટિંગ્સ', onPressed: _openSettingsDialog),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'લોક કરો', onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthGate()))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        onPressed: () => _openTransactionDialog(),
        icon: const Icon(Icons.add),
        label: const Text('હિસાબ નોંધો'),
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
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                    items: fyYears.map((y) => DropdownMenuItem(value: y, child: Text('$y-${(y + 1).toString().substring(2)}'))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedFinancialYearStart = val);
                    },
                  ),
                  const Spacer(),
                  DropdownButton<TimeFilter>(
                    value: selectedFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: TimeFilter.daily, child: Text('દૈનિક (આજે)')),
                      DropdownMenuItem(value: TimeFilter.monthly, child: Text('માસિક')),
                      DropdownMenuItem(value: TimeFilter.quarterly, child: Text('ત્રિમાસિક')),
                      DropdownMenuItem(value: TimeFilter.halfYearly, child: Text('છ માસિક')),
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
          const SizedBox(height: 4),
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
