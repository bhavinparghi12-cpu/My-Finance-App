import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'auth_gate.dart';
import 'export_service.dart';
import 'security_service.dart'; // બાયોમેટ્રિક સુરક્ષા માટે

typedef DataMap = Map<dynamic, dynamic>;

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
                scaffoldBackgroundColor: const Color(0xFFF4F7F6),
                cardTheme: CardThemeData(
                  color: Colors.white,
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorSchemeSeed: primaryColor,
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardTheme: CardThemeData(
                  color: const Color(0xFF1E1E1E),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
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

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  late Box categoriesBox;
  late Box accountsBox;
  late Box transactionsBox;
  late Box settingsBox;
  late Box budgetBox;
  late Box autoPayBox;
  late Box physicalAssetsBox;
  late Box bullionInvestmentsBox;
  bool _isInitialized = false;

  // બાયોમેટ્રિક લોક સ્ટેટ
  bool _isAppLocked = false;
  DateTime? _pausedTime;

  // નેવિગેશન અને ફિલ્ટર સ્ટેટ્સ (ફોટા મુજબ)
  int _selectedTabIndex = 0; // 0: દૈનિક એન્ટ્રી, 1: એનાલિસિસ ચાર્ટ, 2: બજેટ લક્ષ્યાંક, 3: ઇન્વેસ્ટમેન્ટ
  int _investmentSubTabIndex = 0; // 0: મ્યુચ્યુઅલ ફંડ, 1: સ્ટોક માર્કેટ, 2: કિંમતી ધાતુઓ, 3: અન્ય મિલકત
  TimeFilter selectedFilter = TimeFilter.monthly;
  String budgetPeriod = 'માસિક બજેટ';
  ChartType selectedChartType = ChartType.pie;
  ChartType selectedHomeChartType = ChartType.bar;

  late int selectedFinancialYearStart;
  String appTitle = 'નાણાકીય હિસાબો';

  // મ્યુચ્યુઅલ ફંડ સ્ટેટ્સ (ફોટા ૫ મુજબ)
  final TextEditingController _mfNameCtrl = TextEditingController(text: "HDFC Top 100");
  double currentMfNav = 100.00;
  double expectedMfNav = 102.02;
  double expectedMfChange = 2.02;
  String mfDuration = "અંદાજિત ૧ થી ૩ મહિના (Medium Term)";
  String mfSignal = "સામાન્ય તેજી (Bullish)";

  // સ્ટોક માર્કેટ સ્ટેટ્સ (ફોટા ૬ મુજબ)
  final TextEditingController _stockNameCtrl = TextEditingController(text: "RELIANCE");
  final TextEditingController _stockPriceCtrl = TextEditingController(text: "2740.0");
  double currentStockPrice = 2740.0;
  double stockSupport = 2603.0;
  double stockResistance = 2959.2;
  double stockTarget = 3151.0;
  String stockNewsSentiment = "તેજીમય સમાચાર (મજબૂત રિટેલ & 5G ગ્રોથ)";
  List<FlSpot> stockChartSpots = const [
    FlSpot(0, 2650),
    FlSpot(1, 2690),
    FlSpot(2, 2670),
    FlSpot(3, 2720),
    FlSpot(4, 2710),
    FlSpot(5, 2740)
  ];

  // કિંમતી ધાતુઓ રીયલ-ટાઈમ API સ્ટેટ્સ (કોઈ ફિક્સ ભાવ નહીં, 100% API આધારિત)
  String selectedCity = "અમદાવાદ (Ahmedabad)";
  bool isBullionLoading = false;
  String lastBullionUpdateTime = "લોડ થઈ રહ્યું છે...";
  double silverChangePercent = 0.85;

  // શહેર મુજબનો સ્થાનિક તફાવત (Multiplier)
  final Map<String, double> cityMultiplier = {
    "અમદાવાદ (Ahmedabad)": 1.0000,
    "સુરત (Surat)": 1.0006,
    "રાજકોટ (Rajkot)": 0.9997,
    "વડોદરા (Vadodara)": 1.0003,
    "મુંબઈ (Mumbai)": 0.9988,
    "દિલ્હી (Delhi)": 1.0018,
  };

  double _baseGold24Per10g = 0.0;
  double _baseSilverPer1Kg = 0.0;
  double _basePlatinumPer10g = 0.0;

  Map<String, double> get currentCityRates {
    double mult = cityMultiplier[selectedCity] ?? 1.0;
    double g24 = _baseGold24Per10g * mult;
    return {
      "gold24": g24,
      "gold22": g24 * 0.916,
      "gold18": g24 * 0.750,
      "silver": _baseSilverPer1Kg * mult,
      "platinum": _basePlatinumPer10g * mult,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    selectedFinancialYearStart = now.month >= 4 ? now.year : now.year - 1;
    _initBoxes();
    _calculateStockLevels("RELIANCE", 2740.0);
    _fetchLiveBullionRates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mfNameCtrl.dispose();
    _stockNameCtrl.dispose();
    _stockPriceCtrl.dispose();
    super.dispose();
  }

  // એપ બેકગ્રાઉન્ડમાં જાય અને પાછી આવે ત્યારે ફિંગરપ્રિન્ટ ઓટો-લોક ચેક કરવા માટે
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (!SecurityService.isBiometricEnabledInSettings()) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pausedTime ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final timeout = SecurityService.getAutoLockTimeoutSeconds();
        if (timeout >= 0) {
          final elapsed = DateTime.now().difference(_pausedTime!).inSeconds;
          if (elapsed >= timeout && !_isAppLocked) {
            setState(() => _isAppLocked = true);
            await _triggerBiometricUnlock();
          }
        }
        _pausedTime = null;
      }
    }
  }

  Future<void> _triggerBiometricUnlock() async {
    final success = await SecurityService.authenticateWithBiometrics(forceCheck: true);
    if (success && mounted) {
      setState(() => _isAppLocked = false);
    }
  }

  // =========================================================
  // 1. રીયલ-ટાઈમ API વડે સોનું (XAU), ચાંદી (XAG), પ્લેટિનમ (XPT) ના ભાવ
  // =========================================================
  Future<void> _fetchLiveBullionRates({bool showFeedback = false}) async {
    if (mounted) setState(() => isBullionLoading = true);

    try {
      final results = await Future.wait([
        http.get(Uri.parse("https://open.er-api.com/v6/latest/USD")).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse("https://api.gold-api.com/price/XAU")).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse("https://api.gold-api.com/price/XAG")).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse("https://api.gold-api.com/price/XPT")).timeout(const Duration(seconds: 6)),
      ]);

      double usdToInr = 84.50;
      if (results[0].statusCode == 200) {
        final fxData = json.decode(results[0].body);
        usdToInr = (fxData['rates']?['INR'] as num?)?.toDouble() ?? 84.50;
      }

      const double troyOunceInGrams = 31.1034768;
      const double indianTaxAndDutyFactor = 1.095;

      if (results[1].statusCode == 200) {
        final goldData = json.decode(results[1].body);
        double xauUsd = (goldData['price'] as num?)?.toDouble() ?? 0.0;
        if (xauUsd > 0) {
          _baseGold24Per10g = ((xauUsd * usdToInr) / troyOunceInGrams) * 10 * indianTaxAndDutyFactor;
        }
      }

      if (results[2].statusCode == 200) {
        final silverData = json.decode(results[2].body);
        double xagUsd = (silverData['price'] as num?)?.toDouble() ?? 0.0;
        if (xagUsd > 0) {
          double newSilver = ((xagUsd * usdToInr) / troyOunceInGrams) * 1000 * indianTaxAndDutyFactor;
          if (_baseSilverPer1Kg > 0) {
            silverChangePercent = ((newSilver - _baseSilverPer1Kg) / _baseSilverPer1Kg) * 100;
          } else {
            silverChangePercent = (silverData['chp'] as num?)?.toDouble() ?? 0.85;
          }
          _baseSilverPer1Kg = newSilver;
        }
      }

      if (results[3].statusCode == 200) {
        final platData = json.decode(results[3].body);
        double xptUsd = (platData['price'] as num?)?.toDouble() ?? 0.0;
        if (xptUsd > 0) {
          _basePlatinumPer10g = ((xptUsd * usdToInr) / troyOunceInGrams) * 10 * indianTaxAndDutyFactor;
        }
      }

      if (Hive.isBoxOpen('settingsBox')) {
        settingsBox.put('cachedGold24', _baseGold24Per10g);
        settingsBox.put('cachedSilver1Kg', _baseSilverPer1Kg);
        settingsBox.put('cachedPlatinum10g', _basePlatinumPer10g);
      }

      final nowStr = DateFormat('hh:mm a').format(DateTime.now());
      if (mounted) {
        setState(() {
          lastBullionUpdateTime = "લાઈવ અપડેટ: $nowStr";
        });
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ સોનું, ચાંદી અને પ્લેટિનમના રીયલ-ટાઈમ API ભાવ અપડેટ થઈ ગયા!'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
    } catch (_) {
      if (Hive.isBoxOpen('settingsBox')) {
        _baseGold24Per10g = (settingsBox.get('cachedGold24', defaultValue: 0.0) as num).toDouble();
        _baseSilverPer1Kg = (settingsBox.get('cachedSilver1Kg', defaultValue: 0.0) as num).toDouble();
        _basePlatinumPer10g = (settingsBox.get('cachedPlatinum10g', defaultValue: 0.0) as num).toDouble();
      }
      if (mounted) {
        setState(() {
          lastBullionUpdateTime = "ઓફલાઇન (છેલ્લો API ડેટા)";
        });
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ ઇન્ટરનેટ કનેક્શન તપાસો. લાઈવ API ભાવ મળી શક્યા નથી.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => isBullionLoading = false);
    }
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

    _baseGold24Per10g = (settingsBox.get('cachedGold24', defaultValue: 0.0) as num).toDouble();
    _baseSilverPer1Kg = (settingsBox.get('cachedSilver1Kg', defaultValue: 0.0) as num).toDouble();
    _basePlatinumPer10g = (settingsBox.get('cachedPlatinum10g', defaultValue: 0.0) as num).toDouble();

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
      {'id': '4', 'name': 'સોનું / ચાંદી / પ્લેટિનમ રોકાણ', 'effect': 'assetIncrease', 'color': Colors.amber.toARGB32()},
      {'id': '5', 'name': 'લોન / EMI હપ્તો', 'effect': 'loanRepay', 'color': Colors.orange.toARGB32()},
      {'id': '6', 'name': 'પ્રવાસ અને ઇંધણ', 'effect': 'expenseDebit', 'color': Colors.purple.toARGB32()},
      {'id': '7', 'name': 'મિલકત ખરીદી / વેચાણ', 'effect': 'assetIncrease', 'color': Colors.teal.toARGB32()},
    ];
    for (var cat in defaultCats) {
      categoriesBox.put(cat['id'], cat);
    }
  }

  void _saveDefaultAccounts() {
    final defaultAccs = [
      {'id': 'acc_1', 'name': 'રોકડ સિલક (Cash Wallet)', 'type': 'રોકડ (Cash Wallet)', 'openingBalance': 10000.0},
      {'id': 'acc_2', 'name': 'સેવિંગ્સ બેંક એકાઉન્ટ', 'type': 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)', 'openingBalance': 50000.0},
      {'id': 'acc_3', 'name': 'સેલેરી બેંક એકાઉન્ટ', 'type': 'સેલેરી એકાઉન્ટ (Salary A/C)', 'openingBalance': 0.0},
      {'id': 'acc_4', 'name': 'મ્યુચ્યુઅલ ફંડ પોર્ટફોલિયો', 'type': 'મ્યુચ્યુઅલ ફંડ પોર્ટફોલિયો (MF Portfolio)', 'openingBalance': 0.0},
      {'id': 'acc_5', 'name': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ', 'type': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)', 'openingBalance': 0.0},
    ];
    for (var acc in defaultAccs) {
      accountsBox.put(acc['id'], acc);
    }
  }

  List<DataMap> get categories => categoriesBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
  List<DataMap> get accounts => accountsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

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
        final fromAcc = accounts.firstWhere(
          (a) => a['id'].toString() == fromAccId,
          orElse: () => <dynamic, dynamic>{'name': 'બેંક'},
        );
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

  List<DataMap> get pendingManualReminders {
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
    final fromAcc = accounts.firstWhere(
      (a) => a['id'].toString() == fromAccId,
      orElse: () => <dynamic, dynamic>{'name': 'ખાતું'},
    );

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
    final acc = accounts.firstWhere((a) => a['id'].toString() == accountId, orElse: () => <dynamic, dynamic>{});
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

  List<DataMap> get filteredTransactions {
    final now = DateTime.now();
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);
    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    final list = allTx.where((tx) {
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

    list.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));
    return list;
  }

  double _calculateTotal(String effect) {
    return filteredTransactions.where((t) => t['categoryEffect'] == effect).fold(0.0, (sum, item) {
      final amt = item['amount'];
      if (amt is num) return sum + amt.toDouble();
      return sum + (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
    });
  }

  void _checkMutualFund(String name) {
    final upper = name.trim().toUpperCase();
    setState(() {
      if (upper.contains("HDFC")) {
        currentMfNav = 100.00;
        expectedMfNav = 102.02;
        expectedMfChange = 2.02;
        mfDuration = "અંદાજિત ૧ થી ૩ મહિના (Medium Term)";
        mfSignal = "સામાન્ય તેજી (Bullish)";
      } else if (upper.contains("SBI")) {
        currentMfNav = 85.40;
        expectedMfNav = 88.15;
        expectedMfChange = 3.22;
        mfDuration = "અંદાજિત ૩ થી ૬ મહિના (Long Term)";
        mfSignal = "મજબૂત તેજી (Strong Bullish)";
      } else {
        currentMfNav = 120.50;
        expectedMfNav = 122.90;
        expectedMfChange = 1.99;
        mfDuration = "અંદાજિત ૧ થી ૩ મહિના (Medium Term)";
        mfSignal = "સામાન્ય તેજી (Bullish)";
      }
    });
  }

  void _calculateStockLevels(String stockName, double? userPrice) {
    final name = stockName.trim().toUpperCase();
    double price = userPrice ?? 0.0;

    if (price <= 0 || (userPrice == 410.0 && name != "TATA POWER")) {
      if (name.contains("RELIANCE")) {
        price = 2740.0;
        stockNewsSentiment = "તેજીમય સમાચાર (મજબૂત રિટેલ & 5G ગ્રોથ)";
      } else if (name.contains("TATA POWER")) {
        price = 410.0;
        stockNewsSentiment = "સોલાર પાર્ક અને EV ચાર્જિંગ સ્ટેશનના ઓર્ડર્સ";
      } else if (name.contains("TCS")) {
        price = 4120.0;
        stockNewsSentiment = "સ્થિર પરિણામો & AI ક્ષેત્રે મોટો ઓર્ડર";
      } else {
        price = 650.0;
        stockNewsSentiment = "સામાન્ય બજાર ટ્રેન્ડ તેજીમય જણાય છે";
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

  String _getFilterLabel(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.daily:
        return 'આજ';
      case TimeFilter.monthly:
        return 'માસિક';
      case TimeFilter.quarterly:
        return 'ત્રિમાસિક';
      case TimeFilter.halfYearly:
        return 'અર્ધવાર્ષિક';
      case TimeFilter.yearly:
        return 'વાર્ષિક';
      case TimeFilter.allFY:
      case TimeFilter.custom:
        return 'સંપૂર્ણ FY';
    }
  }

  // =========================================================
  // 2. ફોટા મુજબનું ટોપ હેડર (FY + માસિક ડ્રોપડાઉન અને ૪ સારાંશ બોક્સ)
  // =========================================================
  Widget _buildTopSummaryHeader() {
    final totalIncome = _calculateTotal('incomeCredit');
    final totalExpense = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    final totalInvest = _calculateTotal('assetIncrease');
    final netSavings = totalIncome - (totalExpense + totalInvest);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_view_month, color: Colors.teal, size: 20),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: selectedFinancialYearStart,
                    underline: const SizedBox(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    items: List.generate(5, (index) {
                      int yr = (DateTime.now().year - 2 + index).toInt();
                      return DropdownMenuItem(
                        value: yr,
                        child: Text('FY: $yr-${(yr + 1).toString().substring(2)}'),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedFinancialYearStart = val);
                    },
                  ),
                ],
              ),
              DropdownButton<TimeFilter>(
                value: selectedFilter == TimeFilter.custom ? TimeFilter.allFY : selectedFilter,
                underline: const SizedBox(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                items: [
                  TimeFilter.daily,
                  TimeFilter.monthly,
                  TimeFilter.quarterly,
                  TimeFilter.halfYearly,
                  TimeFilter.yearly,
                  TimeFilter.allFY,
                ].map((f) {
                  return DropdownMenuItem(
                    value: f,
                    child: Text(_getFilterLabel(f)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => selectedFilter = val);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _topStatBox(
                  'આવક',
                  '₹${totalIncome.toStringAsFixed(0)}',
                  const Color(0xFFE8F5E9),
                  const Color(0xFFA5D6A7),
                  Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _topStatBox(
                  'ખર્ચ',
                  '₹${totalExpense.toStringAsFixed(0)}',
                  const Color(0xFFFFEBEE),
                  const Color(0xFFEF9A9A),
                  Colors.red.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _topStatBox(
                  'રોકાણ',
                  '₹${totalInvest.toStringAsFixed(0)}',
                  const Color(0xFFE3F2FD),
                  const Color(0xFF90CAF9),
                  Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _topStatBox(
                  'નેટ બચત',
                  '₹${netSavings.toStringAsFixed(0)}',
                  const Color(0xFFE0F2F1),
                  const Color(0xFF80CBC4),
                  Colors.teal.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topStatBox(String title, String value, Color bgColor, Color borderColor, Color textColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? textColor.withValues(alpha: 0.18) : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? textColor.withValues(alpha: 0.5) : borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 3. ટેબ ૧: દૈનિક એન્ટ્રી (ફોટા ૧ મુજબ)
  // =========================================================
  Widget _buildDailyEntryTab() {
    final reminders = pendingManualReminders;
    final txList = filteredTransactions;

    return RefreshIndicator(
      onRefresh: () async {
        _processAutoPayAndSIP();
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          if (reminders.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade700),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔔 બાકી રહેલા રીમાઇન્ડર્સ (EMI / SIP / લેણું):',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  ...reminders.map((rem) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text("${rem['type']}: ${rem['toTarget']} - ₹${rem['amount']}",
                            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                        subtitle: Text("તારીખ: ${rem['day']}", style: const TextStyle(color: Colors.black54)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          onPressed: () => _confirmAndExecuteManualReminder(rem),
                          child: const Text('OK / નોંધો'),
                        ),
                      )),
                ],
              ),
            ),
          _buildNotebookStyleChart(),
          const SizedBox(height: 12),
          if (txList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28.0),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text(
                    'આ સમયગાળામાં કોઈ વ્યવહાર મળ્યો નથી.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => _openTransactionDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('પ્રથમ વ્યવહાર ઉમેરો'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ],
              ),
            )
          else
            ...txList.map((tx) {
              final isIncome = tx['categoryEffect'] == 'incomeCredit';
              final isInvest = tx['categoryEffect'] == 'assetIncrease';
              final dt = DateTime.parse(tx['date']);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(tx['categoryColor'] ?? Colors.teal.toARGB32()).withValues(alpha: 0.18),
                    child: Icon(
                      isIncome ? Icons.add_circle : (isInvest ? Icons.savings : Icons.remove_circle),
                      color: Color(tx['categoryColor'] ?? Colors.teal.toARGB32()),
                    ),
                  ),
                  title: Text(tx['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${tx['categoryName']} • ${tx['accountName']}\n${DateFormat('dd MMM yyyy').format(dt)}'),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isIncome ? '+' : '-'} ₹${(tx['amount'] as num).toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isIncome ? Colors.green : (isInvest ? Colors.blue : Colors.redAccent),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _openTransactionDialog(existingTx: tx),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.edit, size: 16, color: Colors.grey),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              transactionsBox.delete(tx['id']);
                              setState(() {});
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.delete, size: 16, color: Colors.redAccent),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildNotebookStyleChart() {
    double inc = _calculateTotal('incomeCredit');
    double exp = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    double inv = _calculateTotal('assetIncrease');
    Widget chartWidget;

    if (selectedHomeChartType == ChartType.bar) {
      double maxVal = [inc, exp, inv].reduce((a, b) => a > b ? a : b);
      chartWidget = BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal > 0 ? maxVal * 1.25 : 1000,
          barGroups: [
            BarChartGroupData(x: 0, barRods: [
              BarChartRodData(toY: inc, color: Colors.green, width: 22, borderRadius: BorderRadius.circular(4))
            ]),
            BarChartGroupData(x: 1, barRods: [
              BarChartRodData(toY: exp, color: Colors.redAccent, width: 22, borderRadius: BorderRadius.circular(4))
            ]),
            BarChartGroupData(x: 2, barRods: [
              BarChartRodData(toY: inv, color: Colors.blue, width: 22, borderRadius: BorderRadius.circular(4))
            ]),
          ],
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              axisNameWidget: Text("→ રૂપિયા",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
              sideTitles: SideTitles(showTitles: true, reservedSize: 38),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text("→ કેટેગરી",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) {
                  switch (val.toInt()) {
                    case 0:
                      return const Text("આવક", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
                    case 1:
                      return const Text("ખર્ચ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
                    case 2:
                      return const Text("રોકાણ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
                    default:
                      return const SizedBox();
                  }
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(
            show: true,
            border: const Border(
              left: BorderSide(color: Colors.red, width: 2),
              bottom: BorderSide(color: Colors.red, width: 2),
            ),
          ),
        ),
      );
    } else {
      final allTx = filteredTransactions;
      List<FlSpot> incomeSpots = [];
      List<FlSpot> expenseSpots = [];
      double cumInc = 0;
      double cumExp = 0;

      for (int i = 0; i < allTx.length; i++) {
        final tx = allTx[allTx.length - 1 - i];
        final amt = (tx['amount'] as num).toDouble();
        if (tx['categoryEffect'] == 'incomeCredit') cumInc += amt;
        if (tx['categoryEffect'] == 'expenseDebit' || tx['categoryEffect'] == 'loanRepay') cumExp += amt;
        incomeSpots.add(FlSpot(i.toDouble(), cumInc));
        expenseSpots.add(FlSpot(i.toDouble(), cumExp));
      }

      if (incomeSpots.isEmpty) {
        incomeSpots = [const FlSpot(0, 0), FlSpot(1, inc)];
        expenseSpots = [const FlSpot(0, 0), FlSpot(1, exp)];
      }

      chartWidget = LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(spots: incomeSpots, isCurved: true, color: Colors.red, barWidth: 3, dotData: const FlDotData(show: true)),
            LineChartBarData(spots: expenseSpots, isCurved: true, color: Colors.blue, barWidth: 3, dotData: const FlDotData(show: true)),
          ],
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: Text("→ રૂપિયા",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
              sideTitles: SideTitles(showTitles: true, reservedSize: 38),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget:
                  Text("→ સમય", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(
            show: true,
            border: const Border(
              left: BorderSide(color: Colors.red, width: 2),
              bottom: BorderSide(color: Colors.red, width: 2),
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text("📈 દૈનિક નાણાકીય આલેખ",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                SegmentedButton<ChartType>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  segments: const [
                    ButtonSegment(value: ChartType.bar, label: Text('સ્તંભ આલેખ', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: ChartType.line, label: Text('રૈખિક આલેખ', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {selectedHomeChartType},
                  onSelectionChanged: (s) => setState(() => selectedHomeChartType = s.first),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(height: 185, child: chartWidget),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 4. ટેબ ૨: એનાલિસિસ ચાર્ટ (ફોટા ૩ મુજબ)
  // =========================================================
  Widget _buildAnalysisChartTab() {
    Map<String, double> categoryTotals = {};
    for (var tx in filteredTransactions) {
      if (tx['categoryEffect'] == 'expenseDebit' || tx['categoryEffect'] == 'loanRepay') {
        final catName = tx['categoryName'] ?? 'અન્ય';
        categoryTotals[catName] = (categoryTotals[catName] ?? 0.0) + (tx['amount'] as num).toDouble();
      }
    }

    if (categoryTotals.isEmpty) {
      return const Center(
        child: Text(
          'વિશ્લેષણ માટે કોઈ ડેટા નથી.',
          style: TextStyle(fontSize: 15, color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              children: [
                const Text('કેટેગરી મુજબ ખર્ચ વિશ્લેષણ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 210,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 42,
                      sections: categoryTotals.entries.map((entry) {
                        final idx = categoryTotals.keys.toList().indexOf(entry.key);
                        final color = Colors.primaries[idx % Colors.primaries.length];
                        return PieChartSectionData(
                          color: color,
                          value: entry.value,
                          title: '₹${entry.value.toStringAsFixed(0)}',
                          radius: 58,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: categoryTotals.entries.map((entry) {
                    final idx = categoryTotals.keys.toList().indexOf(entry.key);
                    final color = Colors.primaries[idx % Colors.primaries.length];
                    return Chip(
                      avatar: CircleAvatar(backgroundColor: color, radius: 6),
                      label: Text('${entry.key}: ₹${entry.value.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 5. ટેબ ૩: બજેટ લક્ષ્યાંક (ફોટા ૪ મુજબ)
  // =========================================================
  Widget _buildBudgetTargetTab() {
    final expenseCats = categories.where((c) => c['effect'] == 'expenseDebit' || c['effect'] == 'loanRepay').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            DropdownButton<String>(
              value: budgetPeriod,
              underline: const SizedBox(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              items: ['માસિક બજેટ', 'ત્રિમાસિક બજેટ', 'વાર્ષિક બજેટ']
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => budgetPeriod = val);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).cardColor,
                foregroundColor: Colors.teal.shade700,
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('લક્ષ્યાંક બદલો', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _openBudgetDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...expenseCats.map((cat) {
          final catId = cat['id'].toString();
          final baseLimit = (budgetBox.get(catId, defaultValue: 0.0) as num).toDouble();
          double multiplier = budgetPeriod == 'ત્રિમાસિક બજેટ' ? 3 : (budgetPeriod == 'વાર્ષિક બજેટ' ? 12 : 1);
          final limit = baseLimit * multiplier;

          final spent = filteredTransactions
              .where((t) => t['categoryId'].toString() == catId)
              .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());

          if (limit <= 0 && spent <= 0) return const SizedBox.shrink();

          double progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
          bool isOver = limit > 0 && spent > limit;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        limit > 0
                            ? '₹${spent.toStringAsFixed(0)} / ₹${limit.toStringAsFixed(0)}'
                            : 'ખર્ચ: ₹${spent.toStringAsFixed(0)}',
                        style: TextStyle(color: isOver ? Colors.red : Colors.teal, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (limit > 0) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade300,
                      color: isOver ? Colors.red : Colors.teal,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // =========================================================
  // 6. ટેબ ૪: ઇન્વેસ્ટમેન્ટ (ફોટા ૫, ૬, ૭, ૮ મુજબ)
  // =========================================================
  Widget _buildInvestmentTab() {
    final subTabs = [
      {'icon': Icons.pie_chart, 'label': 'મ્યુચ્યુઅલ ફંડ'},
      {'icon': Icons.show_chart, 'label': 'સ્ટોક માર્કેટ'},
      {'icon': Icons.monetization_on, 'label': 'કિંમતી ધાતુઓ'},
      {'icon': Icons.home_work, 'label': 'અન્ય મિલકત (Assets)'},
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 95),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ઇન્વેસ્ટમેન્ટ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: _openAccountManager,
                tooltip: 'પોર્ટફોલિયો ખાતાઓ મેનેજ કરો',
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(subTabs.length, (index) {
              final isSelected = _investmentSubTabIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _investmentSubTabIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? Colors.teal : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        subTabs[index]['icon'] as IconData,
                        color: isSelected ? Colors.teal : Colors.grey.shade700,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subTabs[index]['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.teal : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 12),
        if (_investmentSubTabIndex == 0) _buildMutualFundSection(),
        if (_investmentSubTabIndex == 1) _buildStockMarketSection(),
        if (_investmentSubTabIndex == 2) _buildBullionSection(),
        if (_investmentSubTabIndex == 3) _buildPhysicalAssetsSection(),
      ],
    );
  }

  Widget _buildMutualFundSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _mfNameCtrl,
                decoration: InputDecoration(
                  labelText: 'મ્યુચ્યુઅલ ફંડનું નામ લખો',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: () => _checkMutualFund(_mfNameCtrl.text),
              child: const Text('ચકાસો', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_mfNameCtrl.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('વર્તમાન NAV: ₹${currentMfNav.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('સંભવિત NAV: ₹${expectedMfNav.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'સંભવિત ફેરફાર: +${expectedMfChange.toStringAsFixed(2)}%',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'સંભવિત તેજી સમયગાળો: $mfDuration',
                          style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('માર્કેટ સંકેત: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Icon(Icons.circle, color: Colors.lightGreen, size: 14),
                    const SizedBox(width: 6),
                    Text(mfSignal, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStockMarketSection() {
    return Column(
      children: [
        TextField(
          controller: _stockNameCtrl,
          decoration: InputDecoration(
            labelText: 'સ્ટોકનું નામ (દા.ત. RELIANCE, TCS)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _stockPriceCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'હાલનો ભાવ (LTP ₹)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: () => _calculateStockLevels(_stockNameCtrl.text, double.tryParse(_stockPriceCtrl.text)),
            child: const Text('ચાર્ટ અને લેવલ વિશ્લેષણ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _levelCol('સપોર્ટ', '₹${stockSupport.toStringAsFixed(1)}', Colors.green.shade700),
                    _levelCol('રેઝિસ્ટન્સ', '₹${stockResistance.toStringAsFixed(1)}', Colors.redAccent),
                    _levelCol('ટાર્ગેટ', '₹${stockTarget.toStringAsFixed(1)}', Colors.teal),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.lightGreen, size: 13),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        stockNewsSentiment,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 130,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: true),
                      lineBarsData: [
                        LineChartBarData(spots: stockChartSpots, isCurved: true, color: Colors.teal, barWidth: 3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBullionSection() {
    final rates = currentCityRates;
    final bullionList = bullionInvestmentsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ચોક્કસ શહેર પસંદ કરો:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(lastBullionUpdateTime, style: const TextStyle(fontSize: 11, color: Colors.teal)),
                      ],
                    ),
                    IconButton(
                      icon: isBullionLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, color: Colors.teal),
                      tooltip: 'રીયલ-ટાઈમ API ભાવ રિફ્રેશ કરો',
                      onPressed: () => _fetchLiveBullionRates(showFeedback: true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedCity,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: cityMultiplier.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedCity = val);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    Text('સોનું (24K - 10g)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
                    const SizedBox(height: 4),
                    Text(
                      rates['gold24']! > 0 ? '₹${rates['gold24']!.toStringAsFixed(0)}' : 'લોડ થાય છે...',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown.shade900),
                    ),
                    const Divider(),
                    Text('સોનું (22K - 10g)', style: TextStyle(fontSize: 12, color: Colors.brown.shade600)),
                    Text(
                      rates['gold22']! > 0 ? '₹${rates['gold22']!.toStringAsFixed(0)}' : '...',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.brown.shade800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rates['gold18']! > 0 ? '18K: ₹${rates['gold18']!.toStringAsFixed(0)}' : '',
                      style: TextStyle(fontSize: 11, color: Colors.brown.shade600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECEFF1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      children: [
                        Text('ચાંદી (1 Kg)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                        const SizedBox(height: 4),
                        Text(
                          rates['silver']! > 0 ? '₹${rates['silver']!.toStringAsFixed(0)}' : 'લોડ થાય છે...',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
                        ),
                        const Divider(),
                        Text(
                          '${silverChangePercent >= 0 ? '+' : ''}${silverChangePercent.toStringAsFixed(2)}% ${silverChangePercent >= 0 ? 'વધારો (તેજી)' : 'ઘટાડો'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: silverChangePercent >= 0 ? Colors.green.shade700 : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EAF6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('પ્લેટિનમ (10g)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                        Text(
                          rates['platinum']! > 0 ? '₹${rates['platinum']!.toStringAsFixed(0)}' : '...',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('મારું સોનું / ચાંદી રોકાણ:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18, color: Colors.teal),
              label: const Text('રોકાણ ઉમેરો', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
              onPressed: () => _openAddBullionDialog(),
            ),
          ],
        ),
        if (bullionList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('કોઈ સોનું, ચાંદી કે પ્લેટિનમ રોકાણ ઉમેરેલ નથી.', style: TextStyle(color: Colors.grey))),
          )
        else
          ...bullionList.map((b) => Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.diamond, color: Colors.white)),
                  title: Text("${b['title']} (${b['metalType']} ${b['karat'] ?? ''})"),
                  subtitle: Text("વજન: ${b['weight']}g • ખરીદ કિંમત: ₹${b['buyPrice']}"),
                  trailing: ElevatedButton(
                    onPressed: () => _openSellBullionDialog(b),
                    child: const Text('વેચાણ / એક્શન'),
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildPhysicalAssetsSection() {
    final assetsList = physicalAssetsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double totalAssetVal = assetsList.fold(0.0, (sum, item) => sum + ((item['value'] as num?)?.toDouble() ?? 0.0));

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'કુલ સંપત્તિ: ₹${totalAssetVal.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).cardColor,
                foregroundColor: Colors.teal.shade700,
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('મિલકત ઉમેરો', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _openAddPhysicalAssetDialog(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (assetsList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Center(
              child: Text(
                'કોઈ મકાન, પ્લોટ કે જમીન ઉમેરેલ નથી.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          )
        else
          ...assetsList.map((asset) => Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.home_work, color: Colors.white)),
                  title: Text("${asset['title']} (${asset['type']})", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("સ્થળ: ${asset['location']}\nઅંદાજિત કિંમત: ₹${asset['value']}"),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'edit') {
                        _openAddPhysicalAssetDialog(existingAsset: asset);
                      } else if (val == 'sell') {
                        _openSellPhysicalAssetDialog(asset);
                      } else if (val == 'delete') {
                        physicalAssetsBox.delete(asset['id']);
                        setState(() {});
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('સુધારો')),
                      const PopupMenuItem(value: 'sell', child: Text('વેચાણ કરો')),
                      const PopupMenuItem(value: 'delete', child: Text('કાઢી નાખો', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  // =========================================================
  // 7. દૈનિક વ્યવહાર, બુલિયન અને મિલકત ડાયલોગ્સ (સંપૂર્ણ ફીચર્સ સાથે)
  // =========================================================
  void _openTransactionDialog({Map<dynamic, dynamic>? existingTx}) {
    final titleController = TextEditingController(text: existingTx != null ? existingTx['title'] : '');
    final amountController = TextEditingController(text: existingTx != null ? existingTx['amount'].toString() : '');

    var selectedCat = existingTx != null
        ? categories.firstWhere((c) => c['id'].toString() == existingTx['categoryId'], orElse: () => categories.first)
        : categories.first;

    var selectedAcc = existingTx != null
        ? accounts.firstWhere((a) => a['id'].toString() == existingTx['accountId'], orElse: () => accounts.first)
        : accounts.first;

    DateTime pickedDate = existingTx != null ? DateTime.parse(existingTx['date']) : DateTime.now();
    TimeOfDay? pickedTime = existingTx != null && existingTx['hasTime'] == true
        ? TimeOfDay(hour: pickedDate.hour, minute: pickedDate.minute)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              children: [
                Text(
                  existingTx == null ? 'નવો વ્યવહાર નોંધો' : 'વ્યવહાર સુધારો',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'વિગત / શીર્ષક (દા.ત. કરિયાણું, પગાર, SIP)'),
                ),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'રકમ (₹)'),
                ),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setModalState(() => pickedDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(pickedTime != null ? pickedTime!.format(context) : 'સમય (વૈકલ્પિક)'),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: pickedTime ?? TimeOfDay.now());
                          if (t != null) setModalState(() => pickedTime = t);
                        },
                      ),
                    ),
                    if (pickedTime != null)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                        onPressed: () => setModalState(() => pickedTime = null),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('હિસાબ સેવ કરો', style: TextStyle(fontSize: 16)),
                    onPressed: () {
                      final enteredAmount = double.tryParse(amountController.text) ?? 0.0;
                      if (enteredAmount <= 0 || titleController.text.isEmpty) return;
                      final id = existingTx != null ? existingTx['id'] : DateTime.now().millisecondsSinceEpoch.toString();

                      DateTime finalDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime != null ? pickedTime!.hour : 0,
                        pickedTime != null ? pickedTime!.minute : 0,
                      );

                      transactionsBox.put(id, {
                        'id': id,
                        'title': titleController.text,
                        'amount': enteredAmount,
                        'date': finalDateTime.toIso8601String(),
                        'hasTime': pickedTime != null,
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

  void _openAddBullionDialog({Map<dynamic, dynamic>? existingItem}) {
    final titleCtrl = TextEditingController(text: existingItem != null ? existingItem['title'] : '');
    final weightCtrl = TextEditingController(text: existingItem != null ? existingItem['weight'].toString() : '');
    final buyPriceCtrl = TextEditingController(text: existingItem != null ? existingItem['buyPrice'].toString() : '');

    String metalType = existingItem != null ? existingItem['metalType'] : 'સોનું (Gold)';
    String selectedKarat = existingItem != null ? (existingItem['karat'] ?? '24K') : '24K';

    DateTime pickedDate = DateTime.now();
    TimeOfDay? pickedTime;
    Map<String, double> splitPayments = {};
    bool deductFromAccount = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final rates = currentCityRates;

          double getRatePerGram() {
            if (metalType.contains('Gold')) {
              if (selectedKarat == '22K') return (rates['gold22'] ?? 0.0) / 10.0;
              if (selectedKarat == '18K') return (rates['gold18'] ?? 0.0) / 10.0;
              return (rates['gold24'] ?? 0.0) / 10.0;
            } else if (metalType.contains('Silver')) {
              return (rates['silver'] ?? 0.0) / 1000.0;
            } else {
              return (rates['platinum'] ?? 0.0) / 10.0;
            }
          }

          void autoEstimatePrice() {
            final w = double.tryParse(weightCtrl.text) ?? 0.0;
            if (w > 0 && getRatePerGram() > 0) {
              final est = w * getRatePerGram();
              buyPriceCtrl.text = est.toStringAsFixed(0);
            }
          }

          return AlertDialog(
            title: const Text('સોનું / ચાંદી રોકાણ ઉમેરો'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: metalType,
                    decoration: const InputDecoration(labelText: 'ધાતુનો પ્રકાર'),
                    items: ['સોનું (Gold)', 'ચાંદી (Silver)', 'પ્લેટિનમ (Platinum)']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      setDlgState(() {
                        metalType = v!;
                        autoEstimatePrice();
                      });
                    },
                  ),
                  if (metalType.contains('Gold')) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedKarat,
                      decoration: const InputDecoration(labelText: 'સોનાના કેરેટ (Purity)'),
                      items: ['24K', '22K', '18K']
                          .map((k) => DropdownMenuItem(
                                value: k,
                                child: Text('$k શુદ્ધતા (₹${(getRatePerGram() * 10).toStringAsFixed(0)} / 10g)'),
                              ))
                          .toList(),
                      onChanged: (k) {
                        setDlgState(() {
                          selectedKarat = k!;
                          autoEstimatePrice();
                        });
                      },
                    ),
                  ],
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'વિગત (દા.ત. 10g સિક્કો / બિસ્કિટ)'),
                  ),
                  TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'વજન (ગ્રામમાં)'),
                    onChanged: (_) => autoEstimatePrice(),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: buyPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'ખરીદ કિંમત (₹)'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calculate, color: Colors.teal),
                        tooltip: 'લાઈવ API ભાવ મુજબ ગણો',
                        onPressed: autoEstimatePrice,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          child: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: pickedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setDlgState(() => pickedDate = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          child: Text(pickedTime != null ? pickedTime!.format(context) : 'સમય (વૈકલ્પિક)'),
                          onPressed: () async {
                            final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                            if (t != null) setDlgState(() => pickedTime = t);
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('શું ખાતામાંથી રકમ બાદ કરવી છે?',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    value: deductFromAccount,
                    onChanged: (v) => setDlgState(() => deductFromAccount = v),
                  ),
                  if (deductFromAccount) ...[
                    const Text('ખાતાઓ અને ચૂકવણી રકમ પસંદ કરો:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ...accounts.map((acc) {
                      final accId = acc['id'].toString();
                      return Row(
                        children: [
                          Expanded(flex: 2, child: Text(acc['name'], style: const TextStyle(fontSize: 12))),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '₹ 0', isDense: true),
                              onChanged: (val) => splitPayments[accId] = double.tryParse(val) ?? 0.0,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
              ElevatedButton(
                onPressed: () {
                  final enteredPrice = double.tryParse(buyPriceCtrl.text) ?? 0.0;
                  final id = "bullion_${DateTime.now().millisecondsSinceEpoch}";

                  DateTime finalDate = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime?.hour ?? 0,
                    pickedTime?.minute ?? 0,
                  );

                  bullionInvestmentsBox.put(id, {
                    'id': id,
                    'metalType': metalType,
                    'karat': metalType.contains('Gold') ? selectedKarat : '',
                    'title': titleCtrl.text.isEmpty ? metalType : titleCtrl.text,
                    'weight': double.tryParse(weightCtrl.text) ?? 0.0,
                    'buyPrice': enteredPrice,
                    'date': finalDate.toIso8601String(),
                    'hasTime': pickedTime != null,
                  });

                  if (deductFromAccount) {
                    splitPayments.forEach((accId, amt) {
                      if (amt > 0) {
                        final txId = "tx_bullion_${DateTime.now().millisecondsSinceEpoch}_$accId";
                        final acc = accounts.firstWhere((a) => a['id'].toString() == accId);
                        transactionsBox.put(txId, {
                          'id': txId,
                          'title': "ધાતુ ખરીદી: ${titleCtrl.text.isEmpty ? metalType : titleCtrl.text}",
                          'amount': amt,
                          'date': finalDate.toIso8601String(),
                          'categoryId': '4',
                          'categoryName': 'સોનું / ચાંદી / પ્લેટિનમ રોકાણ',
                          'categoryEffect': 'assetIncrease',
                          'categoryColor': Colors.amber.toARGB32(),
                          'accountId': accId,
                          'accountName': acc['name'],
                        });
                      }
                    });
                  }

                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('સેવ કરો'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openSellBullionDialog(Map<dynamic, dynamic> bullion) {
    String actionType = 'વેચાણ';
    final sellPriceCtrl = TextEditingController(text: bullion['buyPrice'].toString());
    final receivedAmountCtrl = TextEditingController(text: bullion['buyPrice'].toString());
    DateTime pickedDate = DateTime.now();
    TimeOfDay? pickedTime;
    String depositAccountId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${bullion['title']} - એક્શન'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: actionType,
                  decoration: const InputDecoration(labelText: 'એક્શન પસંદ કરો'),
                  items: ['વેચાણ', 'ભેટ આપવી (Gift)', 'અન્ય']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setDlgState(() => actionType = v!),
                ),
                if (actionType == 'વેચાણ') ...[
                  TextField(
                    controller: sellPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'કુલ વેચાણ કિંમત (₹)'),
                  ),
                  TextField(
                    controller: receivedAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'મળેલી રોકડ/બેંક રકમ (₹)'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: depositAccountId,
                    decoration: const InputDecoration(labelText: 'જમા થનાર ખાતું'),
                    items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                    onChanged: (v) => setDlgState(() => depositAccountId = v!),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        child: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setDlgState(() => pickedDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        child: Text(pickedTime != null ? pickedTime!.format(context) : 'સમય (વૈકલ્પિક)'),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                          if (t != null) setDlgState(() => pickedTime = t);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellPrice = double.tryParse(sellPriceCtrl.text) ?? 0.0;
                final received = double.tryParse(receivedAmountCtrl.text) ?? 0.0;
                final pending = sellPrice - received;

                DateTime finalDate = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime?.hour ?? 0,
                  pickedTime?.minute ?? 0,
                );

                if (actionType == 'વેચાણ' && received > 0) {
                  final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccountId);
                  final txId = "tx_sell_${DateTime.now().millisecondsSinceEpoch}";
                  transactionsBox.put(txId, {
                    'id': txId,
                    'title': "વેચાણ આવક: ${bullion['title']}",
                    'amount': received,
                    'date': finalDate.toIso8601String(),
                    'categoryId': '2',
                    'categoryName': 'પગાર / ધંધાકીય આવક',
                    'categoryEffect': 'incomeCredit',
                    'categoryColor': Colors.green.toARGB32(),
                    'accountId': depositAccountId,
                    'accountName': acc['name'],
                  });
                }

                if (actionType == 'વેચાણ' && pending > 0) {
                  final remId = "rem_${DateTime.now().millisecondsSinceEpoch}";
                  autoPayBox.put(remId, {
                    'id': remId,
                    'type': 'બાકી લેણું',
                    'toTarget': "${bullion['title']} વેચાણની બાકી રકમ",
                    'amount': pending,
                    'day': pickedDate.day,
                    'fromAccountId': depositAccountId,
                    'executionMode': 'manual',
                    'isActive': true,
                  });
                }

                bullionInvestmentsBox.delete(bullion['id']);
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('કન્ફર્મ કરો'),
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
    final emiCtrl = TextEditingController();
    final emiDayCtrl = TextEditingController(text: '5');

    String type = existingAsset != null ? existingAsset['type'] : 'મકાન/ફ્લેટ';
    bool isLoan = false;
    DateTime pickedDate = DateTime.now();
    TimeOfDay? pickedTime;
    Map<String, double> splitPayments = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingAsset == null ? 'નવી મિલકત ઉમેરો' : 'મિલકત સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'મિલકતનો પ્રકાર'),
                  items: ['મકાન/ફ્લેટ', 'પ્લોટ/જમીન', 'ખેતીની જમીન', 'દુકાન/ઓફિસ', 'વાહન/અન્ય']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setDlgState(() => type = v!),
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'નામ / વિગત')),
                TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'સ્થળ / શહેર')),
                TextField(controller: valueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'કુલ કિંમત (₹)')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        child: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setDlgState(() => pickedDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        child: Text(pickedTime != null ? pickedTime!.format(context) : 'સમય (વૈકલ્પિક)'),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                          if (t != null) setDlgState(() => pickedTime = t);
                        },
                      ),
                    ),
                  ],
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('શું આ મિલકત લોન પર લીધેલ છે?'),
                  value: isLoan,
                  onChanged: (v) => setDlgState(() => isLoan = v),
                ),
                if (isLoan) ...[
                  TextField(
                      controller: emiCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'માસિક EMI હપ્તાની રકમ (₹)')),
                  TextField(
                      controller: emiDayCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'હપ્તાની દર મહિનાની તારીખ (1-28)')),
                ],
                const Divider(),
                const Text('ચુકવણી માટે ખાતાવાર રકમ પસંદ કરો:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ...accounts.map((acc) {
                  final accId = acc['id'].toString();
                  return Row(
                    children: [
                      Expanded(flex: 2, child: Text(acc['name'], style: const TextStyle(fontSize: 12))),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '₹ 0', isDense: true),
                          onChanged: (val) => splitPayments[accId] = double.tryParse(val) ?? 0.0,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final id = existingAsset != null ? existingAsset['id'] : "asset_${DateTime.now().millisecondsSinceEpoch}";
                DateTime finalDate = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime?.hour ?? 0,
                  pickedTime?.minute ?? 0,
                );

                physicalAssetsBox.put(id, {
                  'id': id,
                  'title': titleCtrl.text,
                  'type': type,
                  'location': locCtrl.text,
                  'value': double.tryParse(valueCtrl.text) ?? 0.0,
                  'date': finalDate.toIso8601String(),
                });

                if (isLoan && emiCtrl.text.isNotEmpty) {
                  final autoId = "auto_${DateTime.now().millisecondsSinceEpoch}";
                  autoPayBox.put(autoId, {
                    'id': autoId,
                    'type': 'EMI',
                    'toTarget': "મિલકત લોન EMI (${titleCtrl.text})",
                    'amount': double.tryParse(emiCtrl.text) ?? 0.0,
                    'day': int.tryParse(emiDayCtrl.text) ?? 5,
                    'fromAccountId': accounts.first['id'].toString(),
                    'executionMode': 'manual',
                    'isActive': true,
                  });
                }

                splitPayments.forEach((accId, amt) {
                  if (amt > 0) {
                    final txId = "tx_asset_${DateTime.now().millisecondsSinceEpoch}_$accId";
                    final acc = accounts.firstWhere((a) => a['id'].toString() == accId);
                    transactionsBox.put(txId, {
                      'id': txId,
                      'title': "મિલકત ખરીદી: ${titleCtrl.text}",
                      'amount': amt,
                      'date': finalDate.toIso8601String(),
                      'categoryId': '7',
                      'categoryName': 'મિલકત ખરીદી / વેચાણ',
                      'categoryEffect': 'assetIncrease',
                      'categoryColor': Colors.teal.toARGB32(),
                      'accountId': accId,
                      'accountName': acc['name'],
                    });
                  }
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

  void _openSellPhysicalAssetDialog(Map<dynamic, dynamic> asset) {
    final sellPriceCtrl = TextEditingController(text: asset['value'].toString());
    final receivedAmountCtrl = TextEditingController(text: asset['value'].toString());
    DateTime pickedDate = DateTime.now();
    TimeOfDay? pickedTime;
    String depositAccountId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${asset['title']} - વેચાણ નોંધ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: sellPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'કુલ વેચાણ કિંમત (₹)')),
                TextField(
                    controller: receivedAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'મળેલી રોકડ/બેંક રકમ (₹)')),
                DropdownButtonFormField<String>(
                  initialValue: depositAccountId,
                  decoration: const InputDecoration(labelText: 'જમા થનાર ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) => setDlgState(() => depositAccountId = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        child: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: pickedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setDlgState(() => pickedDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        child: Text(pickedTime != null ? pickedTime!.format(context) : 'સમય (વૈકલ્પિક)'),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                          if (t != null) setDlgState(() => pickedTime = t);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellPrice = double.tryParse(sellPriceCtrl.text) ?? 0.0;
                final received = double.tryParse(receivedAmountCtrl.text) ?? 0.0;
                final pending = sellPrice - received;

                DateTime finalDate = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime?.hour ?? 0,
                  pickedTime?.minute ?? 0,
                );

                if (received > 0) {
                  final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccountId);
                  final txId = "tx_sell_asset_${DateTime.now().millisecondsSinceEpoch}";
                  transactionsBox.put(txId, {
                    'id': txId,
                    'title': "મિલકત વેચાણ: ${asset['title']}",
                    'amount': received,
                    'date': finalDate.toIso8601String(),
                    'categoryId': '2',
                    'categoryName': 'પગાર / ધંધાકીય આવક',
                    'categoryEffect': 'incomeCredit',
                    'categoryColor': Colors.green.toARGB32(),
                    'accountId': depositAccountId,
                    'accountName': acc['name'],
                  });
                }

                if (pending > 0) {
                  final remId = "rem_asset_${DateTime.now().millisecondsSinceEpoch}";
                  autoPayBox.put(remId, {
                    'id': remId,
                    'type': 'બાકી લેણું',
                    'toTarget': "${asset['title']} વેચાણની બાકી રકમ",
                    'amount': pending,
                    'day': pickedDate.day,
                    'fromAccountId': depositAccountId,
                    'executionMode': 'manual',
                    'isActive': true,
                  });
                }

                physicalAssetsBox.delete(asset['id']);
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('કન્ફર્મ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 8. સેટિંગ્સ અને સંપૂર્ણ મેનેજર્સ (Add / Edit / Delete સહિત)
  // =========================================================
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
                leading: Icon(
                  appThemeMode.value == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
                  color: Colors.amber,
                ),
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

              // ફિંગરપ્રિન્ટ / બાયોમેટ્રિક સુરક્ષા
              StatefulBuilder(
                builder: (ctx, setBioState) {
                  bool isBioEnabled = SecurityService.isBiometricEnabledInSettings();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.fingerprint, color: Colors.teal),
                        title: const Text('ફિંગરપ્રિન્ટ / બાયોમેટ્રિક સુરક્ષા'),
                        subtitle: Text(isBioEnabled ? 'સક્રિય (Active)' : 'બંધ (Disabled)'),
                        value: isBioEnabled,
                        activeThumbColor: Colors.teal,
                        onChanged: (bool newValue) async {
                          final available = await SecurityService.isBiometricAvailable();
                          if (!available) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('આ ડિવાઇસમાં ફિંગરપ્રિન્ટ કે સ્ક્રીન લોક સેટ કરેલ નથી.'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                            return;
                          }

                          if (newValue) {
                            final verified = await SecurityService.authenticateWithBiometrics(forceCheck: true);
                            if (!verified) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ફિંગરપ્રિન્ટ વેરિફિકેશન નિષ્ફળ ગયું. ફરી પ્રયાસ કરો.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                              return;
                            }
                          }

                          await SecurityService.setBiometricEnabled(newValue);
                          setBioState(() => isBioEnabled = newValue);
                          setState(() {});
                        },
                      ),
                      if (isBioEnabled)
                        ListTile(
                          leading: const Icon(Icons.timer_outlined, color: Colors.teal),
                          title: const Text('ઓટો-લૉક સમયગાળો (Auto-lock)'),
                          subtitle: Text(_getAutoLockLabel(SecurityService.getAutoLockTimeoutSeconds())),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openAutoLockSettingsDialog();
                          },
                        ),
                    ],
                  );
                },
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

  String _getAutoLockLabel(int seconds) {
    switch (seconds) {
      case 0:
        return 'તરત જ (Immediately)';
      case 15:
        return '૧૫ સેકન્ડ';
      case 30:
        return '૩૦ સેકન્ડ';
      case 60:
        return '૧ મિનિટ';
      case 300:
        return '૫ મિનિટ';
      case -1:
        return 'ક્યારેય નહીં (Never)';
      default:
        return '$seconds સેકન્ડ';
    }
  }

  void _openAutoLockSettingsDialog() {
    final options = [
      {'label': 'તરત જ (Immediately)', 'seconds': 0},
      {'label': '૧૫ સેકન્ડ', 'seconds': 15},
      {'label': '૩૦ સેકન્ડ (ભલામણ કરેલ)', 'seconds': 30},
      {'label': '૧ મિનિટ', 'seconds': 60},
      {'label': '૫ મિનિટ', 'seconds': 300},
      {'label': 'ક્યારેય નહીં (Disabled)', 'seconds': -1},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('ઓટો-લૉક સમય પસંદ કરો'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final val = opt['seconds'] as int;
              return RadioListTile<int>(
                dense: true,
                title: Text(opt['label'] as String),
                value: val,
                groupValue: SecurityService.getAutoLockTimeoutSeconds(),
                onChanged: (newVal) async {
                  if (newVal != null) {
                    await SecurityService.setAutoLockTimeoutSeconds(newVal);
                    setDlgState(() {});
                    setState(() {});
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('બંધ કરો')),
          ],
        ),
      ),
    );
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
          children: colors
              .map((c) => GestureDetector(
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
                  ))
              .toList(),
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

  // --- કેટેગરી મેનેજર (Add / Edit / Delete) ---
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
                    subtitle: Text(cat['effect'] == 'incomeCredit'
                        ? 'આવક'
                        : (cat['effect'] == 'assetIncrease' ? 'રોકાણ' : 'ખર્ચ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                          onPressed: () {
                            _openCategoryEditDialog(
                              category: cat,
                              onSaved: () {
                                setDlgState(() {});
                                setState(() {});
                              },
                            );
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
                _openCategoryEditDialog(
                  onSaved: () {
                    setDlgState(() {});
                    setState(() {});
                  },
                );
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

  // --- EMI / SIP / ઓટો-પે મેનેજર (Add / Edit / Delete) ---
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
                                    _openAutoPayEditDialog(
                                      existingItem: a,
                                      onSaved: () => setDlgState(() {}),
                                    );
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
                        const Text("ચૂકવણી પદ્ધતિ (Payment Mode):",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                        RadioListTile<String>(
                          dense: true,
                          title: const Text('ઓટો-પે (આપોઆપ કપાત થઈ જાય)', style: TextStyle(fontSize: 12, color: Colors.black87)),
                          value: 'auto',
                          groupValue: mode,
                          onChanged: (val) => setDlgState(() => mode = val!),
                        ),
                        RadioListTile<String>(
                          dense: true,
                          title: const Text('મેન્યુઅલ (રીમાઇન્ડર મળે અને OK આપતાં નોંધાય)',
                              style: TextStyle(fontSize: 12, color: Colors.black87)),
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
                  'lastProcessed': existingItem != null ? (existingItem['lastProcessed'] ?? '') : '',
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

  // --- ખાતાઓ (Accounts) મેનેજર (Add / Edit / Delete) ---
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
                          subtitle: Text(
                              '${a['type'] ?? 'ખાતું'}\nશરૂઆતની સિલક: ₹${a['openingBalance'] ?? 0} | હાલની સિલક: ₹${currentBal.toStringAsFixed(0)}'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
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
                _openAccountEditDialog(
                  onSaved: () {
                    setDlgState(() {});
                    setState(() {});
                  },
                );
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
    final openingBalCtrl =
        TextEditingController(text: account != null ? (account['openingBalance']?.toString() ?? '0') : '0');

    String type = account != null
        ? (account['type'] ?? 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)')
        : 'સેવિંગ્સ એકાઉન્ટ (Savings A/C)';

    final accountTypes = [
      'સેવિંગ્સ એકાઉન્ટ (Savings A/C)',
      'સેલેરી એકાઉન્ટ (Salary A/C)',
      'કરન્ટ એકાઉન્ટ (Current A/C)',
      'રોકડ (Cash Wallet)',
      'મ્યુચ્યુઅલ ફંડ પોર્ટફોલિયો (MF Portfolio)',
      'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)',
      'ક્રેડિટ કાર્ડ (Credit Card)',
      'અન્ય ખાતું (Other)',
    ];

    if (!accountTypes.contains(type)) {
      accountTypes.add(type);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(account == null ? 'નવું ખાતું ઉમેરો' : 'ખાતું સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'ખાતાનું નામ (દા.ત. SBI સેવિંગ્સ, રોકડ)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ખાતાનો પ્રકાર'),
                  items: accountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => type = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: openingBalCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'શરૂઆતની સિલક (₹)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) {
                  final id = account != null ? account['id'] : "acc_${DateTime.now().millisecondsSinceEpoch}";
                  accountsBox.put(id, {
                    'id': id,
                    'name': nameCtrl.text.trim(),
                    'type': type,
                    'openingBalance': double.tryParse(openingBalCtrl.text) ?? 0.0,
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

  void _openBudgetDialog() {
    final expenseCats = categories.where((c) => c['effect'] == 'expenseDebit' || c['effect'] == 'loanRepay').toList();
    Map<String, TextEditingController> controllers = {};
    for (var cat in expenseCats) {
      final catId = cat['id'].toString();
      final currentLimit = budgetBox.get(catId, defaultValue: 0.0);
      controllers[catId] = TextEditingController(text: currentLimit > 0 ? currentLimit.toStringAsFixed(0) : '');
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('માસિક બજેટ લક્ષ્યાંક સેટ કરો'),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
          child: ListView.builder(
            itemCount: expenseCats.length,
            itemBuilder: (context, i) {
              final cat = expenseCats[i];
              final catId = cat['id'].toString();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(cat['name'], style: const TextStyle(fontSize: 13))),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: controllers[catId],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '₹ લિમિટ', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
          ElevatedButton(
            onPressed: () {
              controllers.forEach((catId, ctrl) {
                budgetBox.put(catId, double.tryParse(ctrl.text) ?? 0.0);
              });
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  Widget _levelCol(String title, String val, Color color) {
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  // =========================================================
  // 9. મુખ્ય Build મેથડ (ફોટા મુજબનું લેઆઉટ + બાયોમેટ્રિક લોક)
  // =========================================================
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isAppLocked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, size: 80, color: Colors.teal),
              const SizedBox(height: 16),
              const Text('એપ લોક છે', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('અનલોક કરવા માટે ફિંગરપ્રિન્ટ સ્કેન કરો', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: _triggerBiometricUnlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('અનલોક કરો'),
              ),
            ],
          ),
        ),
      );
    }

    final tabs = [
      _buildDailyEntryTab(),
      _buildAnalysisChartTab(),
      _buildBudgetTargetTab(),
      _buildInvestmentTab(),
    ];

    return ValueListenableBuilder<String?>(
      valueListenable: appBackgroundImage,
      builder: (context, bgImagePath, _) {
        return Container(
          decoration: bgImagePath != null && File(bgImagePath).existsSync()
              ? BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(bgImagePath)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.25), BlendMode.darken),
                  ),
                )
              : null,
          child: Scaffold(
            backgroundColor: bgImagePath != null ? Colors.transparent : null,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.transparent,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
                  Text(
                    widget.userEmail,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                  tooltip: 'ઝડપી વ્યવહાર',
                  onPressed: () => _openTransactionDialog(),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'સેટિંગ્સ',
                  onPressed: _openSettingsDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'લોગઆઉટ',
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                _buildTopSummaryHeader(),
                Expanded(child: tabs[_selectedTabIndex]),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              onPressed: () => _openTransactionDialog(),
              icon: const Icon(Icons.add),
              label: const Text('હિસાબ નોંધો', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedTabIndex,
              onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'દૈનિક એન્ટ્રી',
                ),
                NavigationDestination(
                  icon: Icon(Icons.pie_chart_outline),
                  selectedIcon: Icon(Icons.pie_chart),
                  label: 'એનાલિસિસ ચાર્ટ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.track_changes_outlined),
                  selectedIcon: Icon(Icons.track_changes),
                  label: 'બજેટ લક્ષ્યાંક',
                ),
                NavigationDestination(
                  icon: Icon(Icons.trending_up),
                  selectedIcon: Icon(Icons.show_chart),
                  label: 'ઇન્વેસ્ટમેન્ટ',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
