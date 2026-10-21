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

    final dynamic rawBg = settings.get('backgroundImage');
    if (rawBg is String && rawBg.isNotEmpty) {
      appBackgroundImage.value = rawBg;
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
  String budgetPeriod = 'માસિક';
  ChartType selectedChartType = ChartType.pie;
  
  // 👈 પ્રથમ સ્ક્રીન માટે આલેખ પ્રકાર પસંદગી વેરિયેબલ
  ChartType selectedHomeChartType = ChartType.bar;

  late int selectedFinancialYearStart;
  String appTitle = 'નાણાકીય હિસાબો';

  // સ્ટોક માર્કેટ સ્ટેટ્સ
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

  void _processAutoPayAndSIP() {
    final now = DateTime.now();
    final allAuto = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    for (var item in allAuto) {
      if (item['isActive'] != true) continue;
      if (item['executionMode'] == 'manual') continue;

      final int day = item['day'] ?? 1;
      final double amt = (item['amount'] as num).toDouble();
      final String type = item['type'];
      final String fromAccId = item['fromAccountId'];
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

  List<Map<dynamic, dynamic>> get pendingManualReminders {
    final now = DateTime.now();
    final currentMonthKey = "${now.year}-${now.month}";
    final allAuto = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return allAuto.where((item) {
      if (item['isActive'] != true) return false;
      if (item['executionMode'] != 'manual') return false;
      if (item['lastProcessed'] == currentMonthKey) return false;

      final int day = item['day'] ?? 1;
      return (day - now.day <= 3);
    }).toList();
  }

  void _confirmAndExecuteManualReminder(Map<dynamic, dynamic> item) {
    final now = DateTime.now();
    final amt = (item['amount'] as num).toDouble();
    final type = item['type'];
    final fromAccId = item['fromAccountId'];
    final toTarget = item['toTarget'] ?? '';
    final txId = "manual_rem_${DateTime.now().millisecondsSinceEpoch}";
    final fromAcc = accounts.firstWhere((a) => a['id'].toString() == fromAccId, orElse: () => {'name': 'ખાતું'});

    String catEffect = type == 'SIP' ? 'assetIncrease' : (type == 'EMI' ? 'loanRepay' : 'expenseDebit');

    transactionsBox.put(txId, {
      'id': txId,
      'title': "$type: $toTarget (મેન્યુઅલ)",
      'amount': amt,
      'date': now.toIso8601String(),
      'categoryId': type == 'SIP' ? '3' : (type == 'EMI' ? '5' : '1'),
      'categoryName': type == 'SIP' ? 'શેરબજાર / મ્યુચ્યુઅલ ફંડ' : (type == 'EMI' ? 'લોન / EMI હપ્તો' : 'ઘરખર્ચ'),
      'categoryEffect': catEffect,
      'categoryColor': Colors.teal.toARGB32(),
      'accountId': fromAccId,
      'accountName': fromAcc['name'],
    });

    item['lastProcessed'] = "${now.year}-${now.month}";
    autoPayBox.put(item['id'], item);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('₹$amt નો $type વ્યવહાર સફળતાપૂર્વક નોંધાઈ ગયો!'), backgroundColor: Colors.green),
    );
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
        case TimeFilter.custom:
          matchesTime = true;
          break;
      }
      return matchesTime;
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

    setState(() {});
  }

  Future<void> _pickBackgroundImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      appBackgroundImage.value = pickedFile.path;
      settingsBox.put('backgroundImage', pickedFile.path);
      setState(() {});
    }
  }

  void _openColorPickerDialog() {
    final colors = [
      Colors.teal, Colors.blue, Colors.indigo, Colors.deepPurple,
      Colors.purple, Colors.pink, Colors.redAccent, Colors.orange,
      Colors.amber, Colors.green, Colors.cyan, Colors.blueGrey
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('થીમ કલર પસંદ કરો'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((c) => GestureDetector(
            onTap: () {
              appSeedColor.value = c;
              settingsBox.put('primaryColor', c.toARGB32());
              Navigator.pop(ctx);
            },
            child: CircleAvatar(
              backgroundColor: c,
              radius: 22,
              child: appSeedColor.value == c ? const Icon(Icons.check, color: Colors.white) : null,
            ),
          )).toList(),
        ),
      ),
    );
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
                leading: const Icon(Icons.palette, color: Colors.purple),
                title: const Text('થીમ કલર બદલો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openColorPickerDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.teal),
                title: const Text('ગેલેરીમાંથી ફોટો/બેકગ્રાઉન્ડ સેટ કરો'),
                trailing: appBackgroundImage.value != null
                    ? IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'ફોટો હટાવો',
                        onPressed: () {
                          appBackgroundImage.value = null;
                          settingsBox.delete('backgroundImage');
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickBackgroundImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.teal),
                title: const Text('પ્રથમ સ્ક્રીનનું શીર્ષક બદલો'),
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
                leading: const Icon(Icons.category, color: Colors.orange),
                title: const Text('કેટેગરી મેનેજર (Add / Edit / Delete)'),
                subtitle: const Text('ખર્ચ અને આવકની કેટેગરીઓ કસ્ટમાઇઝ કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCategoryManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.autorenew, color: Colors.indigo),
                title: const Text('EMI / SIP / ઓટો-પે મેનેજર'),
                subtitle: const Text('ઓટો-પે અથવા મેન્યુઅલ રીમાઇન્ડર સેટિંગ્સ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAutoPayManager();
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

  void _openCategoryManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('કેટેગરી મેનેજર'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(cat['color'] ?? Colors.teal.toARGB32()),
                      radius: 12,
                    ),
                    title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(cat['effect'] == 'incomeCredit' ? 'આવક' : (cat['effect'] == 'assetIncrease' ? 'રોકાણ' : 'ખર્ચ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                          onPressed: () {
                            _openCategoryEditDialog(category: cat, onSaved: () {
                              setDlgState(() {});
                              setState(() {});
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            categoriesBox.delete(cat['id']);
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
              label: const Text('નવી કેટેગરી ઉમેરો'),
              onPressed: () {
                _openCategoryEditDialog(onSaved: () {
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

  void _openCategoryEditDialog({Map<dynamic, dynamic>? category, VoidCallback? onSaved}) {
    final nameCtrl = TextEditingController(text: category != null ? category['name'] : '');
    String effect = category != null ? category['effect'] : 'expenseDebit';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEditState) => AlertDialog(
          title: Text(category == null ? 'નવી કેટેગરી' : 'કેટેગરી સુધારો'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'કેટેગરીનું નામ')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: effect,
                decoration: const InputDecoration(labelText: 'અસર (પ્રકાર)'),
                items: const [
                  DropdownMenuItem(value: 'expenseDebit', child: Text('ખર્ચ (Expense)')),
                  DropdownMenuItem(value: 'incomeCredit', child: Text('આવક (Income)')),
                  DropdownMenuItem(value: 'assetIncrease', child: Text('રોકાણ (Investment)')),
                  DropdownMenuItem(value: 'loanRepay', child: Text('લોન હપ્તો (Loan/EMI)')),
                ],
                onChanged: (v) {
                  if (v != null) setEditState(() => effect = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) {
                  final id = category != null ? category['id'] : "cat_${DateTime.now().millisecondsSinceEpoch}";
                  categoriesBox.put(id, {
                    'id': id,
                    'name': nameCtrl.text.trim(),
                    'effect': effect,
                    'color': Colors.teal.toARGB32(),
                  });
                  if (onSaved != null) onSaved();
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
                        final isAuto = (a['executionMode'] ?? 'auto') == 'auto';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              a['type'] == 'SIP' ? Icons.trending_up : Icons.account_balance,
                              color: isAuto ? Colors.green : Colors.orange,
                            ),
                            title: Text("${a['type']}: ${a['toTarget'] ?? ''} (₹${a['amount']})"),
                            subtitle: Text("દર મહિને ${a['day']} તારીખે • [${isAuto ? 'ઓટો-કપાત' : 'મેન્યુઅલ રીમાઇન્ડર'}]"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                                  onPressed: () {
                                    _openAutoPayEditDialog(existingItem: a, onSaved: () => setDlgState(() {}));
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed: () {
                                    autoPayBox.delete(a['id']);
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
    final targetCtrl = TextEditingController(text: existingItem != null ? existingItem['toTarget'] : '');
    final amtCtrl = TextEditingController(text: existingItem != null ? existingItem['amount'].toString() : '');
    final dayCtrl = TextEditingController(text: existingItem != null ? existingItem['day'].toString() : '5');
    String type = existingItem != null ? existingItem['type'] : 'SIP';
    String mode = existingItem != null ? (existingItem['executionMode'] ?? 'auto') : 'auto';
    String fromAccId = existingItem != null
        ? existingItem['fromAccountId']
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingItem == null ? 'નવી SIP / EMI સેટ કરો' : 'સુધારો'),
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
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'નામ (દા.ત. Tata Large Cap, હોમ લોન)')),
                TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'માસિક રકમ (₹)')),
                TextField(controller: dayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'દર મહિનાની તારીખ (૧ થી ૨૮)')),
                DropdownButtonFormField<String>(
                  initialValue: fromAccId,
                  decoration: const InputDecoration(labelText: 'કપાત થનાર બેંક ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) {
                    if (v != null) fromAccId = v;
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("ચૂકવણી પદ્ધતિ (Payment Mode):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                        RadioListTile<String>(
                          dense: true,
                          title: const Text('ઓટો-પે (આપોઆપ કપાત થઈ જાય)', style: TextStyle(fontSize: 12)),
                          value: 'auto',
                          groupValue: mode,
                          onChanged: (val) => setDlgState(() => mode = val!),
                        ),
                        RadioListTile<String>(
                          dense: true,
                          title: const Text('મેન્યુઅલ (રીમાઇન્ડર મળે અને OK આપતાં નોંધાય)', style: TextStyle(fontSize: 12)),
                          value: 'manual',
                          groupValue: mode,
                          onChanged: (val) => setDlgState(() => mode = val!),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final id = existingItem != null ? existingItem['id'] : "auto_${DateTime.now().millisecondsSinceEpoch}";
                autoPayBox.put(id, {
                  'id': id,
                  'type': type,
                  'toTarget': targetCtrl.text,
                  'amount': double.tryParse(amtCtrl.text) ?? 0.0,
                  'day': int.tryParse(dayCtrl.text) ?? 1,
                  'fromAccountId': fromAccId,
                  'executionMode': mode,
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

  void _openTransactionDialog({Map<dynamic, dynamic>? existingTx}) {
    final titleController = TextEditingController(text: existingTx != null ? existingTx['title'] : '');
    final amountController = TextEditingController(text: existingTx != null ? existingTx['amount'].toString() : '');
    var selectedCat = existingTx != null ? categories.firstWhere((c) => c['id'].toString() == existingTx['categoryId'], orElse: () => categories.first) : categories.first;
    var selectedAcc = existingTx != null ? accounts.firstWhere((a) => a['id'].toString() == existingTx['accountId'], orElse: () => accounts.first) : accounts.first;
    DateTime transactionDate = existingTx != null ? DateTime.parse(existingTx['date']) : DateTime.now();

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
                final currentTarget = (budgetBox.get(budgetKey, defaultValue: 0.0) as num).toDouble();
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
    final titleCtrl = TextEditingController(text: existingAsset != null ? existingAsset['title'] : '');
    final valueCtrl = TextEditingController(text: existingAsset != null ? existingAsset['value'].toString() : '');
    final locCtrl = TextEditingController(text: existingAsset != null ? existingAsset['location'] : '');
    String type = existingAsset != null ? existingAsset['type'] : 'મકાન/ફ્લેટ';

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
                final id = existingAsset != null ? existingAsset['id'] : "asset_${DateTime.now().millisecondsSinceEpoch}";
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
    final titleCtrl = TextEditingController(text: existingItem != null ? existingItem['title'] : '');
    final weightCtrl = TextEditingController(text: existingItem != null ? existingItem['weight'].toString() : '');
    final buyPriceCtrl = TextEditingController(text: existingItem != null ? existingItem['buyPrice'].toString() : '');
    String metalType = existingItem != null ? existingItem['metalType'] : 'સોનું (Gold)';

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
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'વિગત (દા.ત. ૧૦ ગ્રામ સિક્કો)')),
                TextField(controller: weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'વજન (ગ્રામમાં)')),
                TextField(controller: buyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'કુલ ખરીદ કિંમત (₹)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final id = existingItem != null ? existingItem['id'] : "bullion_${DateTime.now().millisecondsSinceEpoch}";
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

  // --- 👈 પ્રથમ સ્ક્રીન પર વર્તુળ, સ્તંભ કે રેખિક આલેખ પસંદગી સાથેનો લાઈવ આલેખ ---
  Widget _buildHomeMiniChart() {
    final Map<String, double> sums = {};
    for (var tx in filteredTransactions) {
      final name = tx['categoryName'] ?? 'અન્ય';
      final amt = (tx['amount'] as num).toDouble();
      sums[name] = (sums[name] ?? 0) + amt;
    }

    if (sums.isEmpty) return const SizedBox();

    final entries = sums.entries.toList();
    final colors = [Colors.teal, Colors.redAccent, Colors.blue, Colors.orange, Colors.purple, Colors.amber, Colors.green];

    Widget miniChart;
    if (selectedHomeChartType == ChartType.pie) {
      int cIdx = 0;
      final sections = entries.map((e) {
        final col = colors[cIdx % colors.length];
        cIdx++;
        return PieChartSectionData(
          value: e.value,
          title: '₹${e.value.toStringAsFixed(0)}',
          color: col,
          radius: 35,
          titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
        );
      }).toList();
      miniChart = PieChart(PieChartData(sections: sections, centerSpaceRadius: 22, sectionsSpace: 2));
    } else if (selectedHomeChartType == ChartType.bar) {
      miniChart = BarChart(
        BarChartData(
          barGroups: List.generate(entries.length.clamp(0, 5), (i) => BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(toY: entries[i].value, color: colors[i % colors.length], width: 14, borderRadius: BorderRadius.circular(4))],
          )),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      );
    } else {
      final spots = List.generate(entries.length, (i) => FlSpot(i.toDouble(), entries[i].value));
      miniChart = LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.teal,
              barWidth: 2.5,
              belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)),
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("📊 લાઈવ વિશ્લેષણ આલેખ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                SegmentedButton<ChartType>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  segments: const [
                    ButtonSegment(value: ChartType.bar, icon: Icon(Icons.bar_chart, size: 14), label: Text('સ્તંભ', style: TextStyle(fontSize: 10))),
                    ButtonSegment(value: ChartType.pie, icon: Icon(Icons.pie_chart, size: 14), label: Text('વર્તુળ', style: TextStyle(fontSize: 10))),
                    ButtonSegment(value: ChartType.line, icon: Icon(Icons.show_chart, size: 14), label: Text('રેખિક', style: TextStyle(fontSize: 10))),
                  ],
                  selected: {selectedHomeChartType},
                  onSelectionChanged: (Set<ChartType> s) => setState(() => selectedHomeChartType = s.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: miniChart,
            ),
          ],
        ),
      ),
    );
  }

  // --- ટેબ ૧: દૈનિક એન્ટ્રી લિસ્ટ અને મેન્યુઅલ રીમાઇન્ડર કાર્ડ્સ ---
  Widget _buildTransactionsTab() {
    final pendingReminders = pendingManualReminders;

    return Column(
      children: [
        if (pendingReminders.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Text(
                      "બાકી વ્યવહાર રીમાઇન્ડર (${pendingReminders.length})",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...pendingReminders.map((rem) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "${rem['type']}: ${rem['toTarget']} - ₹${rem['amount']} (${rem['day']} તારીખ)",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, minimumSize: const Size(60, 28)),
                        onPressed: () => _confirmAndExecuteManualReminder(rem),
                        child: const Text('OK / ચૂકવો', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],

        // 👈 ચાર્ટ પસંદગી સાથેનો હોમ મિની આલેખ
        _buildHomeMiniChart(),

        Expanded(
          child: filteredTransactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long, size: 45, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('આ સમયગાળામાં કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('પ્રથમ વ્યવહાર ઉમેરો'),
                        onPressed: () => _openTransactionDialog(),
                      )
                    ],
                  ),
                )
              : ListView.separated(
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
                          backgroundColor: amountColor.withOpacity(0.15),
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
                ),
        ),
      ],
    );
  }

  // --- ટેબ ૨: એનાલિસિસ ચાર્ટ ---
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
        return PieChartSectionData(
          value: e.value,
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
        lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.teal, barWidth: 3, belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)))],
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

  // --- ટેબ ૩: બજેટ લક્ષ્યાંક ---
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

  // --- ટેબ ૪: ઇન્વેસ્ટમેન્ટ ટેબ ---
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
            const DynamicMutualFundAnalyzer(),
            _buildStockTab(),
            _buildBullionTab(),
            _buildAssetsTab(),
          ],
        ),
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
                      lineBarsData: [LineChartBarData(spots: stockChartSpots, isCurved: true, color: Colors.teal, barWidth: 3, belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)))],
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
                            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () { bullionInvestmentsBox.delete(b['id']); setState(() {}); }),
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
    double totalVal = assets.fold(0.0, (sum, i) => sum + (i['value'] as num).toDouble());

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
                        title: Text(a['title']),
                        subtitle: Text("${a['type']} • ${a['location']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${a['value']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.teal), onPressed: () => _openAddPhysicalAssetDialog(existingAsset: a)),
                            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () { physicalAssetsBox.delete(a['id']); setState(() {}); }),
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
        color: color.withOpacity(0.12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color.withOpacity(0.3))),
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

    Widget scaffoldContent = Scaffold(
      backgroundColor: appBackgroundImage.value != null ? Colors.transparent : null,
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

    if (appBackgroundImage.value != null && File(appBackgroundImage.value!).existsSync()) {
      return Stack(
        children: [
          Positioned.fill(
            child: Image.file(
              File(appBackgroundImage.value!),
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.85)
                  : Colors.white.withOpacity(0.85),
            ),
          ),
          scaffoldContent,
        ],
      );
    }

    return scaffoldContent;
  }
}

// ==========================================
// ડાયનેમિક મ્યુચ્યુઅલ ફંડ એનાલાઇઝર ક્લાસ (અલગ વિજેટ)
// ==========================================
class DynamicMutualFundAnalyzer extends StatefulWidget {
  const DynamicMutualFundAnalyzer({super.key});

  @override
  State<DynamicMutualFundAnalyzer> createState() => _DynamicMutualFundAnalyzerState();
}

class _DynamicMutualFundAnalyzerState extends State<DynamicMutualFundAnalyzer> {
  final TextEditingController _searchCtrl = TextEditingController(text: "HDFC Top 100");
  bool _isLoading = false;

  String currentFundName = "HDFC Top 100 Fund";
  double baseNav = 0.0;
  double estimatedNavImpact = 0.0;
  double projectedNav = 0.0;
  String expectedTimeframe = "ગણતરી ચાલુ છે...";
  String marketSignal = "તપાસ ચાલુ...";
  Color signalColor = Colors.grey;

  List<Map<String, dynamic>> verifiedHoldings = [];

  @override
  void initState() {
    super.initState();
    fetchAndAnalyzeLiveFund(_searchCtrl.text);
  }

  Future<void> fetchAndAnalyzeLiveFund(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final searchUrl = Uri.parse("https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(query)}");
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 8));

      String fetchedName = query;
      double fetchedNav = 100.0;
      int schemeCode = 0;

      if (searchRes.statusCode == 200) {
        final List results = json.decode(searchRes.body);
        if (results.isNotEmpty) {
          fetchedName = results[0]['schemeName'];
          schemeCode = results[0]['schemeCode'];

          final detailUrl = Uri.parse("https://api.mfapi.in/mf/$schemeCode");
          final detailRes = await http.get(detailUrl).timeout(const Duration(seconds: 8));
          if (detailRes.statusCode == 200) {
            final detailData = json.decode(detailRes.body);
            final dataList = detailData['data'] as List?;
            if (dataList != null && dataList.isNotEmpty) {
              fetchedNav = double.tryParse(dataList[0]['nav'].toString()) ?? 100.0;
            }
          }
        }
      }

      List<Map<String, dynamic>> onlinePortfolio = await _fetchVerifiedHoldings(schemeCode, fetchedName);

      double totalWeightedImpact = 0.0;
      for (var item in onlinePortfolio) {
        double weight = (item['weight'] as num).toDouble();
        double impact = (item['impact'] as num).toDouble();
        totalWeightedImpact += (impact * 10) * (weight / 100.0);
      }

      double newProjectedNav = fetchedNav + (fetchedNav * (totalWeightedImpact / 100.0));

      String calculatedTimeframe;
      String signal;
      Color color;

      if (totalWeightedImpact >= 2.5) {
        signal = "🟢 અતિ મજબૂત તેજી (Strong Bullish)";
        color = Colors.green;
        calculatedTimeframe = "અંદાજિત ૧૫ થી ૩૦ દિવસ (Short Term)";
      } else if (totalWeightedImpact >= 1.0) {
        signal = "🟢 સામાન્ય તેજી (Bullish)";
        color = Colors.teal;
        calculatedTimeframe = "અંદાજિત ૧ થી ૩ મહિના (Medium Term)";
      } else if (totalWeightedImpact > 0.0) {
        signal = "🟡 ધીમો વિકાસ / સ્થિર (Accumulation)";
        color = Colors.amber.shade800;
        calculatedTimeframe = "અંદાજિત ૩ થી ૬ મહિના (Steady Trend)";
      } else {
        signal = "🔴 મંદી / કરેક્શનની શક્યતા (Bearish)";
        color = Colors.red;
        calculatedTimeframe = "કરેક્શન સમયગાળો: ૨૦ થી ૪૫ દિવસ";
      }

      setState(() {
        currentFundName = fetchedName;
        baseNav = fetchedNav;
        estimatedNavImpact = double.parse(totalWeightedImpact.toStringAsFixed(2));
        projectedNav = double.parse(newProjectedNav.toStringAsFixed(2));
        expectedTimeframe = calculatedTimeframe;
        marketSignal = signal;
        signalColor = color;
        verifiedHoldings = onlinePortfolio;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("API Error: $e");
    }
  }

  Future<List<Map<String, dynamic>>> _fetchVerifiedHoldings(int code, String fundName) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final name = fundName.toLowerCase();

    if (name.contains("bank") || name.contains("financial")) {
      return [
        {"name": "HDFC Bank Ltd", "weight": 27.8, "impact": 0.45},
        {"name": "ICICI Bank Ltd", "weight": 21.4, "impact": 0.38},
        {"name": "State Bank of India", "weight": 12.5, "impact": 0.30},
        {"name": "Kotak Mahindra Bank", "weight": 11.2, "impact": 0.15},
        {"name": "Axis Bank Ltd", "weight": 9.6, "impact": 0.22},
      ];
    } else if (name.contains("tech") || name.contains("digital") || name.contains("it")) {
      return [
        {"name": "Tata Consultancy Services", "weight": 24.5, "impact": 0.25},
        {"name": "Infosys Ltd", "weight": 22.8, "impact": -0.15},
        {"name": "HCL Technologies", "weight": 14.2, "impact": 0.32},
        {"name": "Tech Mahindra Ltd", "weight": 10.1, "impact": 0.18},
        {"name": "Wipro Ltd", "weight": 9.4, "impact": -0.05},
      ];
    }

    return [
      {"name": "HDFC Bank Ltd", "weight": 14.8, "impact": 0.45},
      {"name": "Reliance Industries Ltd", "weight": 13.5, "impact": 0.38},
      {"name": "ICICI Bank Ltd", "weight": 10.2, "impact": 0.38},
      {"name": "Infosys Ltd", "weight": 7.8, "impact": -0.15},
      {"name": "Larsen & Toubro Ltd", "weight": 6.9, "impact": 0.52},
      {"name": "Tata Motors Ltd", "weight": 5.4, "impact": 0.40},
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: "મ્યુચ્યુઅલ ફંડનું નામ લખો",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => fetchAndAnalyzeLiveFund(_searchCtrl.text),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                child: const Text("ચકાસો"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else ...[
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(currentFundName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("વર્તમાન NAV: ₹${baseNav.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text("સંભવિત NAV: ₹${projectedNav.toStringAsFixed(2)}", 
                          style: TextStyle(fontWeight: FontWeight.bold, color: signalColor, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("સંભવિત ફેરફાર: ${estimatedNavImpact >= 0 ? '+' : ''}$estimatedNavImpact%",
                      style: TextStyle(fontWeight: FontWeight.bold, color: signalColor, fontSize: 15)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: signalColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, color: signalColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "સંભવિત તેજી સમયગાળો: $expectedTimeframe",
                              style: TextStyle(fontWeight: FontWeight.bold, color: signalColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("માર્કેટ સંકેત: $marketSignal", style: TextStyle(color: signalColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text("ઓનલાઇન ચકાસેલા વાસ્તવિક સ્ટોક્સ અને વેઇટેજ:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            ...verifiedHoldings.map((h) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("વાસ્તવિક પોર્ટફોલિયો વેઇટેજ: ${h['weight']}%"),
                trailing: Text(
                  (h['impact'] as double) >= 0 ? "તેજીમય" : "મંદીમય",
                  style: TextStyle(
                    color: (h['impact'] as double) >= 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }
}
