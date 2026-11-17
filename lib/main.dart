import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'security_service.dart';

typedef DataMap = Map<dynamic, dynamic>;

final ValueNotifier<Color> appSeedColor = ValueNotifier<Color>(Colors.teal);
final ValueNotifier<String?> appBackgroundImage = ValueNotifier<String?>(null);
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

enum TimeFilter { daily, monthly, quarterly, halfYearly, yearly, allFY, custom }
enum AnalysisMetric { combined, income, expense, investment, taxableIncome }
enum ChartType { pie, bar, line }

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

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  late Box categoriesBox;
  late Box accountsBox;
  late Box transactionsBox;
  late Box settingsBox;
  late Box budgetBox;
  late Box autoPayBox;
  late Box physicalAssetsBox;
  late Box bullionInvestmentsBox;
  late Box mfInvestmentsBox;
  late Box stockInvestmentsBox;
  late Box fixedIncomeBox;
  late Box capitalGainsBox;

  bool _isInitialized = false;

  // (૨) બેકગ્રાઉન્ડ ઓટો-લોક અને પાસવર્ડ + બાયોમેટ્રિક અનલોક સ્ટેટ્સ
  bool _isAppLocked = false;
  bool _isAuthenticating = false;
  DateTime? _pausedTime;
  DateTime? _lastUnlockTime;
  final TextEditingController _unlockPasswordCtrl = TextEditingController();
  bool _obscureUnlockPwd = true;
  String _unlockErrorMsg = '';

  int _selectedTabIndex = 0;
  TimeFilter selectedFilter = TimeFilter.monthly;
  DateTime customStartDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime customEndDate = DateTime.now();
  AnalysisMetric selectedAnalysisMetric = AnalysisMetric.combined;
  double benchmarkInflationRate = 6.0;

  String budgetPeriod = 'માસિક';
  ChartType selectedChartType = ChartType.bar;
  ChartType selectedHomeChartType = ChartType.bar;

  late int selectedFinancialYearStart;
  String appTitle = 'નાણાકીય હિસાબો';

  // કિંમતી ધાતુઓ શહેર રેટ્સ & લાઇવ સ્ટેટ્સ
  String selectedCity = "અમદાવાદ (Ahmedabad)";
  bool isBullionLoading = false;
  String bullionLastUpdated = "લાઇવ અપડેટ ચાલુ...";
  double bullionChangePercent = 0.85;

  final Map<String, double> citySpreadMultiplier = {
    "અમદાવાદ (Ahmedabad)": 1.0000,
    "સુરત (Surat)": 1.0004,
    "રાજકોટ (Rajkot)": 0.9996,
    "વડોદરા (Vadodara)": 1.0002,
    "મુંબઈ (Mumbai)": 0.9987,
    "દિલ્હી (Delhi)": 1.0014,
  };

  Map<String, Map<String, double>> bullionCityRates = {
    "અમદાવાદ (Ahmedabad)": {"gold24": 96500.0, "gold22": 88400.0, "silver": 112000.0},
    "સુરત (Surat)": {"gold24": 96540.0, "gold22": 88430.0, "silver": 112050.0},
    "રાજકોટ (Rajkot)": {"gold24": 96460.0, "gold22": 88360.0, "silver": 111950.0},
    "વડોદરા (Vadodara)": {"gold24": 96520.0, "gold22": 88410.0, "silver": 112020.0},
    "મુંબઈ (Mumbai)": {"gold24": 96375.0, "gold22": 88280.0, "silver": 111850.0},
    "દિલ્હી (Delhi)": {"gold24": 96635.0, "gold22": 88520.0, "silver": 112150.0},
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    selectedFinancialYearStart = now.month >= 4 ? now.year : now.year - 1;
    _initBoxes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unlockPasswordCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  // (૨) સુધારેલ બેકગ્રાઉન્ડ ઓટો-લોક (પાસવર્ડ + ફિંગરપ્રિન્ટ સપોર્ટ)
  // =========================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_isAuthenticating) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedTime ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_lastUnlockTime != null &&
          DateTime.now().difference(_lastUnlockTime!).inSeconds < 3) {
        _pausedTime = null;
        return;
      }

      if (_pausedTime != null) {
        final timeout = SecurityService.getAutoLockTimeoutSeconds();
        final elapsed = DateTime.now().difference(_pausedTime!).inSeconds;
        _pausedTime = null;

        if (timeout >= 0 && elapsed >= timeout && !_isAppLocked) {
          if (mounted) {
            setState(() {
              _isAppLocked = true;
              _unlockErrorMsg = '';
              _unlockPasswordCtrl.clear();
            });
          }
          if (SecurityService.isBiometricEnabledInSettings()) {
            await _triggerBiometricUnlock();
          }
        }
      }
    }
  }

  Future<void> _triggerBiometricUnlock() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _unlockErrorMsg = '';
    });

    try {
      final success = await SecurityService.authenticateWithBiometrics(forceCheck: true);
      if (success && mounted) {
        _lastUnlockTime = DateTime.now();
        setState(() {
          _isAppLocked = false;
          _pausedTime = null;
          _unlockPasswordCtrl.clear();
        });
      }
    } catch (e) {
      debugPrint("Biometric Unlock Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  Future<void> _unlockWithMasterPassword() async {
    final pwd = _unlockPasswordCtrl.text.trim();
    if (pwd.isEmpty) {
      setState(() => _unlockErrorMsg = 'કૃપા કરીને માસ્ટર પાસવર્ડ દાખલ કરો.');
      return;
    }
    final isValid = await SecurityService.verifyPassword(widget.userEmail, pwd);
    if (isValid && mounted) {
      _lastUnlockTime = DateTime.now();
      setState(() {
        _isAppLocked = false;
        _pausedTime = null;
        _unlockPasswordCtrl.clear();
        _unlockErrorMsg = '';
      });
    } else if (mounted) {
      setState(() => _unlockErrorMsg = 'ખોટો પાસવર્ડ! ફરી પ્રયાસ કરો.');
    }
  }

  // =========================================================
  // (૧) ફોનની ઇન્ટરનલ મેમરીમાં બેકઅપ અને રિસ્ટોર સિસ્ટમ
  // =========================================================
  String get _userPrefix => widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  Future<List<Directory>> _getCandidateBackupDirectories() async {
    final List<Directory> dirs = [];
    final paths = [
      '/storage/emulated/0/Download/MyFinanceApp_Backup',
      '/storage/emulated/0/Documents/MyFinanceApp_Backup',
      '/storage/emulated/0/Download',
    ];
    for (final p in paths) {
      try {
        final d = Directory(p);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
        if (await d.exists()) dirs.add(d);
      } catch (_) {}
    }
    if (categoriesBox.path != null) {
      final parent = File(categoriesBox.path!).parent;
      dirs.add(parent);
    }
    return dirs;
  }

  Future<File?> _findExistingInternalBackupFile() async {
    final fileName = 'finance_backup_$_userPrefix.json';
    final dirs = await _getCandidateBackupDirectories();
    for (final d in dirs) {
      try {
        final f = File('${d.path}/$fileName');
        if (await f.exists()) return f;
        // જો કોઇ અન્ય બેકઅપ ફાઇલ હોય તો તે પણ તપાસો
        final entities = d.listSync();
        for (final e in entities) {
          if (e is File && e.path.endsWith('.json') && e.path.contains('finance_backup_')) {
            return e;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _backupAllDataToInternalMemory({bool showNotification = true}) async {
    try {
      final backupPayload = {
        'version': 2,
        'userEmail': widget.userEmail,
        'backupDate': DateTime.now().toIso8601String(),
        'appTitle': appTitle,
        'categories': categoriesBox.toMap(),
        'accounts': accountsBox.toMap(),
        'transactions': transactionsBox.toMap(),
        'budgets': budgetBox.toMap(),
        'autoPay': autoPayBox.toMap(),
        'physicalAssets': physicalAssetsBox.toMap(),
        'bullionInvestments': bullionInvestmentsBox.toMap(),
        'mfInvestments': mfInvestmentsBox.toMap(),
        'stockInvestments': stockInvestmentsBox.toMap(),
        'fixedIncome': fixedIncomeBox.toMap(),
        'capitalGains': capitalGainsBox.toMap(),
        'settings': {
          'primaryColor': settingsBox.get('primaryColor'),
          'isDarkMode': settingsBox.get('isDarkMode'),
          'customAppTitle': settingsBox.get('customAppTitle'),
          'customInvTitle': settingsBox.get('customInvTitle'),
          'autoGenerateCcBill': settingsBox.get('autoGenerateCcBill', defaultValue: false),
          'inflationRate': settingsBox.get('inflationRate', defaultValue: 6.0),
        },
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupPayload);
      final fileName = 'finance_backup_$_userPrefix.json';
      final timestampedName =
          'finance_backup_${_userPrefix}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';

      final dirs = await _getCandidateBackupDirectories();
      String savedPath = '';

      for (final d in dirs) {
        try {
          final mainFile = File('${d.path}/$fileName');
          await mainFile.writeAsString(jsonString, flush: true);
          final copyFile = File('${d.path}/$timestampedName');
          await copyFile.writeAsString(jsonString, flush: true);
          if (savedPath.isEmpty) savedPath = mainFile.path;
        } catch (_) {}
      }

      await settingsBox.put('lastBackupTime_$_userPrefix', DateTime.now().toIso8601String());
      await settingsBox.put('lastBackupPath_$_userPrefix', savedPath);

      if (showNotification && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.teal),
                SizedBox(width: 8),
                Expanded(child: Text('બેકઅપ સફળતાપૂર્વક સેવ થયો!')),
              ],
            ),
            content: Text(
              'તમારી તમામ નોંધો અને રોકાણોનો બેકઅપ ફોનની ઇન્ટરનલ મેમરીમાં સુરક્ષિત રીતે સેવ થઈ ગયો છે:\n\n📂 ફાઇલ પાથ:\n$savedPath\n\nએપ અનઇન્સ્ટોલ થયા પછી ફરી ઇન્સ્ટોલ કરશો ત્યારે આ ફાઇલમાંથી ડેટા આપોઆપ રિસ્ટોર કરી શકાશે.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('સમજાઈ ગયું'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted && showNotification) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('બેકઅપ લેવામાં ભૂલ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restoreDataFromBackupFile(File file) async {
    try {
      final content = await file.readAsString();
      final Map<String, dynamic> data = json.decode(content);

      Future<void> restoreBox(Box box, dynamic mapData) async {
        if (mapData is Map) {
          await box.clear();
          for (final entry in mapData.entries) {
            await box.put(entry.key.toString(), entry.value);
          }
        }
      }

      await restoreBox(categoriesBox, data['categories']);
      await restoreBox(accountsBox, data['accounts']);
      await restoreBox(transactionsBox, data['transactions']);
      await restoreBox(budgetBox, data['budgets']);
      await restoreBox(autoPayBox, data['autoPay']);
      await restoreBox(physicalAssetsBox, data['physicalAssets']);
      await restoreBox(bullionInvestmentsBox, data['bullionInvestments']);
      await restoreBox(mfInvestmentsBox, data['mfInvestments']);
      await restoreBox(stockInvestmentsBox, data['stockInvestments']);
      await restoreBox(fixedIncomeBox, data['fixedIncome']);
      await restoreBox(capitalGainsBox, data['capitalGains']);

      if (data['settings'] is Map) {
        final s = data['settings'] as Map;
        if (s['customAppTitle'] != null) {
          appTitle = s['customAppTitle'].toString();
          await settingsBox.put('customAppTitle', appTitle);
        }
        if (s['autoGenerateCcBill'] != null) {
          await settingsBox.put('autoGenerateCcBill', s['autoGenerateCcBill']);
        }
        if (s['inflationRate'] != null) {
          benchmarkInflationRate = (s['inflationRate'] as num).toDouble();
          await settingsBox.put('inflationRate', benchmarkInflationRate);
        }
      }

      if (categoriesBox.isEmpty) _saveDefaultCategories();
      if (accountsBox.isEmpty) _saveDefaultAccounts();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ બેકઅપમાંથી તમામ ડેટા સફળતાપૂર્વક રિસ્ટોર થઈ ગયો!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('રિસ્ટોર કરવામાં ભૂલ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _checkAndPromptBackupRestoreOnFreshInstall() async {
    final alreadyPrompted = settingsBox.get('reinstallRestorePrompted_$_userPrefix', defaultValue: false) == true;
    final hasNoUserTransactions = transactionsBox.isEmpty &&
        mfInvestmentsBox.isEmpty &&
        stockInvestmentsBox.isEmpty &&
        fixedIncomeBox.isEmpty;

    if (!alreadyPrompted && hasNoUserTransactions) {
      final backupFile = await _findExistingInternalBackupFile();
      if (backupFile != null && mounted) {
        await settingsBox.put('reinstallRestorePrompted_$_userPrefix', true);
        final stat = await backupFile.stat();
        final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(stat.modified);

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.restore_page, color: Colors.teal, size: 28),
                SizedBox(width: 8),
                Expanded(child: Text('જૂનો બેકઅપ મળ્યો છે!')),
              ],
            ),
            content: Text(
              'તમારા ફોનની ઇન્ટરનલ મેમરીમાં અગાઉનો બેકઅપ મળ્યો છે:\n\n📄 ફાઇલ: ${backupFile.path.split('/').last}\n🕒 તારીખ: $dateStr\n\nશું તમે આ બેકઅપમાંથી તમારો તમામ ડેટા રિસ્ટોર કરવા માંગો છો?',
              style: const TextStyle(fontSize: 13.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ના, નવેસરથી શરૂ કરો'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.cloud_download),
                label: const Text('હા, ડેટા રિસ્ટોર કરો'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _restoreDataFromBackupFile(backupFile);
                },
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _openBackupAndRestoreDialog() async {
    final dirs = await _getCandidateBackupDirectories();
    final List<File> availableBackups = [];
    final Set<String> seenPaths = {};

    for (final d in dirs) {
      try {
        final list = d.listSync();
        for (final f in list) {
          if (f is File && f.path.endsWith('.json') && f.path.contains('finance_backup')) {
            if (seenPaths.add(f.path)) {
              availableBackups.add(f);
            }
          }
        }
      } catch (_) {}
    }

    availableBackups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final lastBackupTime = settingsBox.get('lastBackupTime_$_userPrefix');

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.backup, color: Colors.teal, size: 26),
                  SizedBox(width: 10),
                  Text('ઇન્ટરનલ મેમરી બેકઅપ અને રિસ્ટોર', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              if (lastBackupTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'છેલ્લો બેકઅપ: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(lastBackupTime))}',
                    style: const TextStyle(fontSize: 12, color: Colors.teal),
                  ),
                ),
              const Divider(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('અત્યારે ફોનની ઇન્ટરનલ મેમરીમાં બેકઅપ લો', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _backupAllDataToInternalMemory(showNotification: true);
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Text('ઉપલબ્ધ બેકઅપ ફાઇલો (રિસ્ટોર કરવા માટે પસંદ કરો):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(height: 8),
              if (availableBackups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('હાલમાં ઇન્ટરનલ મેમરીમાં કોઈ બેકઅપ ફાઇલ મળી નથી.', style: TextStyle(color: Colors.grey))),
                )
              else
                ...availableBackups.take(8).map((f) {
                  final modified = f.lastModifiedSync();
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.description, color: Colors.teal),
                      title: Text(f.path.split('/').last, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      subtitle: Text('તારીખ: ${DateFormat('dd/MM/yyyy hh:mm a').format(modified)}\n${f.parent.path}', style: const TextStyle(fontSize: 11)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (confirmCtx) => AlertDialog(
                              title: const Text('ડેટા રિસ્ટોર કન્ફર્મ કરો'),
                              content: const Text('શું તમે ખરેખર આ બેકઅપ ફાઇલમાંથી ડેટા રિસ્ટોર કરવા માંગો છો?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text('રદ')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                  onPressed: () async {
                                    Navigator.pop(confirmCtx);
                                    Navigator.pop(ctx);
                                    await _restoreDataFromBackupFile(f);
                                  },
                                  child: const Text('હા, રિસ્ટોર કરો'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('રિસ્ટોર', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // કિંમતી ધાતુઓના ૧૦૦% લાઇવ બજાર ભાવ (Multi-API Fallback)
  // =========================================================
  void _applyBaseBullionRatesToAllCities(double baseGold24Per10g, double baseSilverPer1Kg) {
    for (final entry in citySpreadMultiplier.entries) {
      final city = entry.key;
      final mult = entry.value;
      final cityGold24 = (baseGold24Per10g * mult).roundToDouble();
      final cityGold22 = (cityGold24 * 0.916).roundToDouble();
      final citySilver = (baseSilverPer1Kg * mult).roundToDouble();

      bullionCityRates[city] = {
        "gold24": cityGold24,
        "gold22": cityGold22,
        "silver": citySilver,
      };
    }
  }

  Future<void> _fetchLiveBullionRates({bool showToast = false}) async {
    if (mounted) setState(() => isBullionLoading = true);

    double usdToInr = 86.40;
    double? xauUsdPerOunce;
    double? xagUsdPerOunce;

    try {
      final fxRes = await http
          .get(Uri.parse("https://open.er-api.com/v6/latest/USD"))
          .timeout(const Duration(seconds: 5));
      if (fxRes.statusCode == 200) {
        final fxData = json.decode(fxRes.body);
        usdToInr = (fxData['rates']?['INR'] as num?)?.toDouble() ?? usdToInr;
      }
    } catch (_) {}

    try {
      final goldYahoo = await http
          .get(Uri.parse("https://query1.finance.yahoo.com/v8/finance/chart/GC=F?interval=1m&range=1d"))
          .timeout(const Duration(seconds: 5));
      if (goldYahoo.statusCode == 200) {
        final data = json.decode(goldYahoo.body);
        final meta = data['chart']?['result']?[0]?['meta'];
        if (meta != null && meta['regularMarketPrice'] != null) {
          xauUsdPerOunce = (meta['regularMarketPrice'] as num).toDouble();
        }
      }
    } catch (_) {}

    try {
      final silverYahoo = await http
          .get(Uri.parse("https://query1.finance.yahoo.com/v8/finance/chart/SI=F?interval=1m&range=1d"))
          .timeout(const Duration(seconds: 5));
      if (silverYahoo.statusCode == 200) {
        final data = json.decode(silverYahoo.body);
        final meta = data['chart']?['result']?[0]?['meta'];
        if (meta != null && meta['regularMarketPrice'] != null) {
          xagUsdPerOunce = (meta['regularMarketPrice'] as num).toDouble();
          final prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ?? xagUsdPerOunce!;
          if (prevClose > 0) {
            bullionChangePercent = ((xagUsdPerOunce! - prevClose) / prevClose) * 100;
          }
        }
      }
    } catch (_) {}

    if (xauUsdPerOunce == null || xauUsdPerOunce <= 0) {
      try {
        final resGold = await http
            .get(Uri.parse("https://api.gold-api.com/price/XAU"))
            .timeout(const Duration(seconds: 5));
        if (resGold.statusCode == 200) {
          final data = json.decode(resGold.body);
          xauUsdPerOunce = (data['price'] as num?)?.toDouble();
        }
      } catch (_) {}
    }

    if (xagUsdPerOunce == null || xagUsdPerOunce <= 0) {
      try {
        final resSilver = await http
            .get(Uri.parse("https://api.gold-api.com/price/XAG"))
            .timeout(const Duration(seconds: 5));
        if (resSilver.statusCode == 200) {
          final data = json.decode(resSilver.body);
          xagUsdPerOunce = (data['price'] as num?)?.toDouble();
        }
      } catch (_) {}
    }

    const double troyOunceGrams = 31.1034768;
    const double indianDutyAndGstFactor = 1.098;

    double calculatedGold24Per10g = 0.0;
    double calculatedSilverPer1Kg = 0.0;

    if (xauUsdPerOunce != null && xauUsdPerOunce > 0) {
      calculatedGold24Per10g =
          ((xauUsdPerOunce * usdToInr) / troyOunceGrams) * 10.0 * indianDutyAndGstFactor;
    }
    if (xagUsdPerOunce != null && xagUsdPerOunce > 0) {
      calculatedSilverPer1Kg =
          ((xagUsdPerOunce * usdToInr) / troyOunceGrams) * 1000.0 * indianDutyAndGstFactor;
    } else if (calculatedGold24Per10g > 0) {
      calculatedSilverPer1Kg = (calculatedGold24Per10g * 1.18).roundToDouble();
    }

    if (calculatedGold24Per10g > 0 && calculatedSilverPer1Kg > 0) {
      _applyBaseBullionRatesToAllCities(calculatedGold24Per10g, calculatedSilverPer1Kg);
      if (Hive.isBoxOpen('settingsBox')) {
        settingsBox.put('liveGold24_10g', calculatedGold24Per10g);
        settingsBox.put('liveSilver_1kg', calculatedSilverPer1Kg);
        settingsBox.put('liveBullionTime', DateFormat('dd/MM hh:mm a').format(DateTime.now()));
      }
      if (mounted) {
        setState(() {
          bullionLastUpdated = "લાઇવ ભાવ (${DateFormat('hh:mm a').format(DateTime.now())})";
          isBullionLoading = false;
        });
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ તમામ શહેરોના સોના-ચાંદીના લાઇવ બજાર ભાવ અપડેટ થઈ ગયા!'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
    } else {
      double savedG = (settingsBox.get('liveGold24_10g', defaultValue: 96500.0) as num).toDouble();
      double savedS = (settingsBox.get('liveSilver_1kg', defaultValue: 112000.0) as num).toDouble();
      String savedT = settingsBox.get('liveBullionTime', defaultValue: 'ઓફલાઇન મોડ');
      _applyBaseBullionRatesToAllCities(savedG, savedS);
      if (mounted) {
        setState(() {
          bullionLastUpdated = "છેલ્લો અપડેટ: $savedT";
          isBullionLoading = false;
        });
      }
    }
  }

  Future<void> _initBoxes() async {
    categoriesBox = Hive.box(widget.catBoxName);
    accountsBox = Hive.box(widget.accBoxName);
    transactionsBox = Hive.box(widget.txBoxName);
    settingsBox = Hive.box('settingsBox');

    final prefix = _userPrefix;
    budgetBox = await Hive.openBox('catBudgetBox_$prefix');
    autoPayBox = await Hive.openBox('autoPayBox_$prefix');
    physicalAssetsBox = await Hive.openBox('physicalAssetsBox_$prefix');
    bullionInvestmentsBox = await Hive.openBox('bullionInvestmentsBox_$prefix');
    mfInvestmentsBox = await Hive.openBox('mfInvestmentsBox_$prefix');
    stockInvestmentsBox = await Hive.openBox('stockInvestmentsBox_$prefix');
    fixedIncomeBox = await Hive.openBox('fixedIncomeBox_$prefix');
    capitalGainsBox = await Hive.openBox('capitalGainsBox_$prefix');

    appTitle = settingsBox.get('customAppTitle', defaultValue: 'નાણાકીય હિસાબો');
    benchmarkInflationRate = (settingsBox.get('inflationRate', defaultValue: 6.0) as num).toDouble();

    double savedG = (settingsBox.get('liveGold24_10g', defaultValue: 96500.0) as num).toDouble();
    double savedS = (settingsBox.get('liveSilver_1kg', defaultValue: 112000.0) as num).toDouble();
    _applyBaseBullionRatesToAllCities(savedG, savedS);
    _fetchLiveBullionRates();

    if (categoriesBox.isEmpty) _saveDefaultCategories();
    if (accountsBox.isEmpty) _saveDefaultAccounts();

    _processAutoPayAndSIP();
    _processFixedIncomeSchedules();

    if (mounted) {
      setState(() => _isInitialized = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndPromptBackupRestoreOnFreshInstall();
      });
    }
  }

  void _saveDefaultCategories() {
    final defaultCats = [
      {'id': '1', 'name': 'ઘરખર્ચ (Groceries & Bills)', 'effect': 'expenseDebit', 'color': Colors.redAccent.toARGB32()},
      {'id': '2', 'name': 'પગાર / ધંધાકીય આવક', 'effect': 'incomeCredit', 'color': Colors.green.toARGB32()},
      {'id': '3', 'name': 'શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'effect': 'assetIncrease', 'color': Colors.blue.toARGB32()},
      {'id': '4', 'name': 'સોનું / ચાંદી રોકાણ', 'effect': 'assetIncrease', 'color': Colors.amber.toARGB32()},
      {'id': '5', 'name': 'લોન / EMI / ક્રેડિટ કાર્ડ બિલ', 'effect': 'loanRepay', 'color': Colors.orange.toARGB32()},
      {'id': '6', 'name': 'વીમા પ્રીમિયમ (PLI / Health / Term / વાહન)', 'effect': 'expenseDebit', 'color': Colors.purple.toARGB32()},
      {'id': '7', 'name': 'મિલકત / બોન્ડ / FD રોકાણ', 'effect': 'assetIncrease', 'color': Colors.teal.toARGB32()},
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
      {'id': 'acc_4', 'name': 'ક્રેડિટ કાર્ડ (Credit Card)', 'type': 'ક્રેડિટ કાર્ડ (Credit Card)', 'openingBalance': 0.0},
      {'id': 'acc_5', 'name': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ', 'type': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)', 'openingBalance': 0.0},
    ];
    for (var acc in defaultAccs) {
      accountsBox.put(acc['id'], acc);
    }
  }

  List<DataMap> get categories =>
      categoriesBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  List<DataMap> get accounts =>
      accountsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

  // =========================================================
  // (૩) EMI, SIP, વીમા પ્રીમિયમ અને દૈનિક નોંધમાંથી વૈકલ્પિક ઓટો ક્રેડિટ કાર્ડ બિલ જનરેશન
  // =========================================================
  bool get isAutoCcBillEnabled =>
      settingsBox.get('autoGenerateCcBill', defaultValue: false) == true;

  double _calculateCreditCardUnbilledAmount(String ccAccountId, int billingDay) {
    final now = DateTime.now();
    DateTime cycleStart;
    DateTime cycleEnd = DateTime(now.year, now.month, billingDay, 23, 59, 59);
    if (now.day < billingDay) {
      final prevMonth = DateTime(now.year, now.month - 1, billingDay);
      cycleEnd = DateTime(prevMonth.year, prevMonth.month, billingDay, 23, 59, 59);
    }
    cycleStart = cycleEnd.subtract(const Duration(days: 30));

    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double sum = 0.0;
    for (final tx in allTx) {
      if (tx['accountId'] == ccAccountId && tx['isCcSettlement'] != true) {
        final dt = DateTime.parse(tx['date']);
        if (!dt.isBefore(cycleStart) && !dt.isAfter(cycleEnd)) {
          final effect = tx['categoryEffect'];
          final amt = (tx['amount'] as num).toDouble();
          if (effect == 'expenseDebit' || effect == 'loanRepay') {
            sum += amt;
          }
        }
      }
    }
    return sum;
  }

  void _processAutoPayAndSIP() {
    final now = DateTime.now();
    final currentMonthKey = "${now.year}-${now.month}";
    final allAuto = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    for (var item in allAuto) {
      if (item['isActive'] != true) continue;

      final String type = item['type'] ?? 'AutoPay';
      final int day = item['day'] ?? 1;
      final int billingDay = item['billingDay'] ?? day;

      // જો ક્રેડિટ કાર્ડ હોય અને વૈકલ્પિક ઓટો-બિલ જનરેશન ON હોય તો દૈનિક વ્યવહારમાંથી બિલની રકમ ગણો
      if (type == 'CreditCard' && (item['autoGenerateFromDaily'] == true || isAutoCcBillEnabled)) {
        final String ccAccId = item['ccAccountId'] ?? '';
        if (ccAccId.isNotEmpty && now.day >= billingDay && item['lastBilledCycle'] != currentMonthKey) {
          final generatedBill = _calculateCreditCardUnbilledAmount(ccAccId, billingDay);
          if (generatedBill > 0) {
            item['amount'] = generatedBill;
            item['lastBilledCycle'] = currentMonthKey;
            autoPayBox.put(item['id'], item);
          }
        }
      }

      if (item['executionMode'] == 'manual') continue;

      final double amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
      if (amt <= 0) continue;

      final String fromAccId = item['fromAccountId'] ?? '';
      final String toTarget = item['toTarget'] ?? '';
      final String lastExecution = item['lastProcessed'] ?? '';

      if (lastExecution != currentMonthKey && now.day >= day) {
        final txId = "auto_${DateTime.now().millisecondsSinceEpoch}_${item['id']}";
        final fromAcc = accounts.firstWhere(
          (a) => a['id'].toString() == fromAccId,
          orElse: () => {'name': 'બેંક ખાતું'},
        );

        String catEffect = 'expenseDebit';
        String catId = '6';
        String catName = 'વીમા પ્રીમિયમ / ઓટો-પે';

        if (type == 'SIP' || type == 'GovScheme') {
          catEffect = 'assetIncrease';
          catId = '3';
          catName = 'શેરબજાર / મ્યુચ્યુઅલ ફંડ / સ્કીમ';
        } else if (type == 'EMI' || type == 'CreditCard') {
          catEffect = 'loanRepay';
          catId = '5';
          catName = 'લોન / EMI / ક્રેડિટ કાર્ડ બિલ';
        }

        transactionsBox.put(txId, {
          'id': txId,
          'title': "ઓટો $type: $toTarget",
          'amount': amt,
          'date': DateTime(now.year, now.month, day).toIso8601String(),
          'categoryId': catId,
          'categoryName': catName,
          'categoryEffect': catEffect,
          'categoryColor': Colors.teal.toARGB32(),
          'accountId': fromAccId,
          'accountName': fromAcc['name'],
          'isCcSettlement': type == 'CreditCard',
        });

        item['lastProcessed'] = currentMonthKey;
        autoPayBox.put(item['id'], item);
      }
    }
  }

  // (૫) બોન્ડ, FD, PLI ની સેટ કરેલ તારીખ પ્રમાણે આપોઆપ ખાતામાં જમા/ઉધાર એડજસ્ટમેન્ટ
  void _processFixedIncomeSchedules() {
    final now = DateTime.now();
    final todayDateOnly = DateTime(now.year, now.month, now.day);
    final items = fixedIncomeBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    for (var item in items) {
      if (item['autoAdjust'] != true) continue;
      if (item['isSettled'] == true) continue;

      final DateTime? targetDate = item['scheduledDate'] != null ? DateTime.tryParse(item['scheduledDate']) : null;
      if (targetDate == null) continue;

      final scheduledDayOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
      if (!todayDateOnly.isBefore(scheduledDayOnly)) {
        final String flowType = item['flowType'] ?? 'inflow_maturity'; // inflow_maturity OR outflow_installment
        final double amount = (item['scheduledAmount'] as num?)?.toDouble() ?? 0.0;
        final String accId = item['accountId'] ?? '';
        final acc = accounts.firstWhere((a) => a['id'].toString() == accId, orElse: () => {'name': 'બેંક ખાતું'});

        if (amount > 0 && accId.isNotEmpty) {
          final txId = "fi_auto_${DateTime.now().millisecondsSinceEpoch}_${item['id']}";
          final isCredit = flowType == 'inflow_maturity';

          transactionsBox.put(txId, {
            'id': txId,
            'title': isCredit
                ? "${item['schemeType']} પાકતી રકમ/વ્યાજ જમા: ${item['title']}"
                : "${item['schemeType']} હપ્તો/રોકાણ ચુકવણી: ${item['title']}",
            'amount': amount,
            'date': scheduledDayOnly.toIso8601String(),
            'categoryId': isCredit ? '2' : '7',
            'categoryName': isCredit ? 'પગાર / ધંધાકીય આવક' : 'મિલકત / બોન્ડ / FD રોકાણ',
            'categoryEffect': isCredit ? 'incomeCredit' : 'assetIncrease',
            'categoryColor': isCredit ? Colors.green.toARGB32() : Colors.teal.toARGB32(),
            'accountId': accId,
            'accountName': acc['name'],
          });

          if (isCredit) {
            final double principal = (item['principalAmount'] as num?)?.toDouble() ?? amount;
            final double gain = math.max(0.0, amount - principal);
            if (gain > 0) {
              _recordRealizedCapitalGain(
                assetType: item['schemeType'] ?? 'FD/Bond',
                title: item['title'] ?? '',
                buyDate: DateTime.tryParse(item['startDate'] ?? '') ?? scheduledDayOnly.subtract(const Duration(days: 365)),
                sellDate: scheduledDayOnly,
                buyValue: principal,
                sellValue: amount,
              );
            }
          }

          item['isSettled'] = true;
          fixedIncomeBox.put(item['id'], item);
        }
      }
    }
  }

  void _recordRealizedCapitalGain({
    required String assetType,
    required String title,
    required DateTime buyDate,
    required DateTime sellDate,
    required double buyValue,
    required double sellValue,
  }) {
    final holdingDays = math.max(1, sellDate.difference(buyDate).inDays);
    final isEquityOrMF = assetType.contains('Stock') || assetType.contains('ETF') || assetType.contains('MF') || assetType.contains('મ્યુચ્યુઅલ');
    final int ltcgThresholdDays = isEquityOrMF ? 365 : 730;
    final bool isLTCG = holdingDays >= ltcgThresholdDays;
    final double gain = sellValue - buyValue;

    final id = "cg_${DateTime.now().millisecondsSinceEpoch}";
    capitalGainsBox.put(id, {
      'id': id,
      'assetType': assetType,
      'title': title,
      'buyDate': buyDate.toIso8601String(),
      'sellDate': sellDate.toIso8601String(),
      'holdingDays': holdingDays,
      'buyValue': buyValue,
      'sellValue': sellValue,
      'gain': gain,
      'isLTCG': isLTCG,
    });
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
      return (day - now.day <= 5);
    }).toList();
  }

  void _confirmAndExecuteManualReminder(Map<dynamic, dynamic> item) {
    final now = DateTime.now();
    final amt = (item['amount'] as num).toDouble();
    final type = item['type'] ?? 'AutoPay';
    final fromAccId = item['fromAccountId'];
    final toTarget = item['toTarget'] ?? '';
    final txId = "manual_rem_${DateTime.now().millisecondsSinceEpoch}";
    final fromAcc = accounts.firstWhere(
      (a) => a['id'].toString() == fromAccId,
      orElse: () => {'name': 'ખાતું'},
    );

    String catEffect = 'expenseDebit';
    if (type == 'SIP' || type == 'GovScheme') {
      catEffect = 'assetIncrease';
    } else if (type == 'EMI' || type == 'CreditCard') {
      catEffect = 'loanRepay';
    }

    transactionsBox.put(txId, {
      'id': txId,
      'title': "$type: $toTarget",
      'amount': amt,
      'date': now.toIso8601String(),
      'categoryId': type == 'SIP' ? '3' : (type == 'EMI' || type == 'CreditCard' ? '5' : '6'),
      'categoryName': type == 'SIP' ? 'શેરબજાર / મ્યુચ્યુઅલ ફંડ' : 'EMI / વીમા / બિલ ચુકવણી',
      'categoryEffect': catEffect,
      'categoryColor': Colors.teal.toARGB32(),
      'accountId': fromAccId,
      'accountName': fromAcc['name'],
      'isCcSettlement': type == 'CreditCard',
    });

    item['lastProcessed'] = "${now.year}-${now.month}";
    autoPayBox.put(item['id'], item);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('₹${amt.toStringAsFixed(0)} નો $type વ્યવહાર સફળતાપૂર્વક નોંધાઈ ગયો!'), backgroundColor: Colors.green),
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

  List<DataMap> get entireFYTransactions {
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);
    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return allTx.where((tx) {
      final date = DateTime.parse(tx['date']);
      return !date.isBefore(fyStart) && !date.isAfter(fyEnd);
    }).toList();
  }

  List<DataMap> get filteredTransactions {
    final now = DateTime.now();
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);

    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    final list = allTx.where((tx) {
      final date = DateTime.parse(tx['date']);
      if (selectedFilter != TimeFilter.custom) {
        if (date.isBefore(fyStart) || date.isAfter(fyEnd)) return false;
      }

      switch (selectedFilter) {
        case TimeFilter.daily:
          return date.year == now.year && date.month == now.month && date.day == now.day;
        case TimeFilter.monthly:
          return date.year == now.year && date.month == now.month;
        case TimeFilter.quarterly:
          final diffDays = now.difference(date).inDays;
          return diffDays <= 90 && diffDays >= 0;
        case TimeFilter.halfYearly:
          final diffDays = now.difference(date).inDays;
          return diffDays <= 182 && diffDays >= 0;
        case TimeFilter.yearly:
          return date.year == now.year;
        case TimeFilter.allFY:
          return true;
        case TimeFilter.custom:
          final start = DateTime(customStartDate.year, customStartDate.month, customStartDate.day);
          final end = DateTime(customEndDate.year, customEndDate.month, customEndDate.day, 23, 59, 59);
          return !date.isBefore(start) && !date.isAfter(end);
      }
    }).toList();

    list.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));
    return list;
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

  // =========================================================
  // (નવું) ફોટો ૪ (New Regime FY 2026-27) અને ફોટો ૫ (Old Regime) મુજબ ટેક્સ ગણતરી
  // તથા આખી એપમાંથી આવક, રોકાણ, બચત, રિસ્ક અને સ્ટ્રેટેજી ફેચિંગ એન્જિન
  // =========================================================
  String _classifyMfSubCategory(Map<dynamic, dynamic> mf) {
    final savedCat = (mf['mfSubCategory'] ?? '').toString().trim();
    if (savedCat.isNotEmpty) return savedCat;
    final name = (mf['schemeName'] ?? '').toString().toLowerCase();
    if (name.contains('elss') || name.contains('tax') || name.contains('ટેક્સ')) {
      return 'ELSS';
    }
    if (name.contains('liquid') ||
        name.contains('debt') ||
        name.contains('bond') ||
        name.contains('gilt') ||
        name.contains('overnight') ||
        name.contains('money market') ||
        name.contains('corporate') ||
        name.contains('short') ||
        name.contains('ડેબ્ટ')) {
      return 'Debt';
    }
    if (name.contains('hybrid') ||
        name.contains('balanced') ||
        name.contains('arbitrage') ||
        name.contains('multi asset') ||
        name.contains('dynamic') ||
        name.contains('હાઇબ્રીડ')) {
      return 'Hybrid';
    }
    return 'Equity';
  }

  // ફોટો ૪ મુજબ: New Tax Regime Slabs (FY 2026-27)
  // 0-4L: 0%, 4-8L: 5%, 8-12L: 10%, 12-16L: 15%, 16-20L: 20%, 20-24L: 25%, >24L: 30%
  // Standard Deduction: ₹75,000 | Section 87A Rebate: Taxable Income <= ₹12,00,000 પર ₹0 ટેક્સ (માર્જિનલ રિલીફ સહિત)
  double _calculateIncomeTaxNewRegime(double taxableIncome) {
    if (taxableIncome <= 1200000) return 0.0;
    double tax = 0.0;
    if (taxableIncome > 400000) {
      tax += (math.min(taxableIncome, 800000.0) - 400000) * 0.05;
    }
    if (taxableIncome > 800000) {
      tax += (math.min(taxableIncome, 1200000.0) - 800000) * 0.10;
    }
    if (taxableIncome > 1200000) {
      tax += (math.min(taxableIncome, 1600000.0) - 1200000) * 0.15;
    }
    if (taxableIncome > 1600000) {
      tax += (math.min(taxableIncome, 2000000.0) - 1600000) * 0.20;
    }
    if (taxableIncome > 2000000) {
      tax += (math.min(taxableIncome, 2400000.0) - 2000000) * 0.25;
    }
    if (taxableIncome > 2400000) {
      tax += (taxableIncome - 2400000) * 0.30;
    }
    // માર્જિનલ રિલીફ: ₹12,00,000 કરતાં વધારાની આવક કરતાં બેઝ ટેક્સ વધુ ન હોવો જોઈએ
    final double excessOver12L = taxableIncome - 1200000.0;
    if (tax > excessOver12L) {
      tax = excessOver12L;
    }
    return tax * 1.04; // 4% Health & Education Cess
  }

  // ફોટો ૫ મુજબ: Old Tax Regime Slabs
  // સામાન્ય (<60 વર્ષ): ₹2,50,000 સુધી 0% | સિનિયર (60-80 વર્ષ): ₹3,00,000 સુધી 0% | સુપર સિનિયર (80+ વર્ષ): ₹5,00,000 સુધી 0%
  // ₹5,00,000 સુધી 5% | ₹5,00,001 થી ₹10,00,000: 20% | ₹10,00,000 થી વધુ: 30%
  // Standard Deduction: ₹50,000 | Section 87A Rebate: કરપાત્ર આવક ₹5,00,000 સુધી ₹0 ટેક્સ
  double _calculateIncomeTaxOldRegime(double taxableIncome, {String ageGroup = 'regular'}) {
    if (taxableIncome <= 500000) return 0.0;
    double basicExemption = 250000.0;
    if (ageGroup == 'senior') {
      basicExemption = 300000.0;
    } else if (ageGroup == 'super_senior') {
      basicExemption = 500000.0;
    }
    if (taxableIncome <= basicExemption) return 0.0;

    double tax = 0.0;
    if (taxableIncome > basicExemption && basicExemption < 500000.0) {
      tax += (math.min(taxableIncome, 500000.0) - basicExemption) * 0.05;
    }
    if (taxableIncome > 500000.0) {
      tax += (math.min(taxableIncome, 1000000.0) - 500000.0) * 0.20;
    }
    if (taxableIncome > 1000000.0) {
      tax += (taxableIncome - 1000000.0) * 0.30;
    }
    return tax * 1.04; // 4% Health & Education Cess
  }

  Map<String, double> _getCapitalGainsSummary({bool entireFY = false}) {
    final now = DateTime.now();
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);

    final allGains = capitalGainsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double stcgTotal = 0.0;
    double ltcgTotal = 0.0;

    for (final g in allGains) {
      final sellDate = DateTime.tryParse(g['sellDate'] ?? '') ?? now;
      bool include = false;
      if (entireFY) {
        include = !sellDate.isBefore(fyStart) && !sellDate.isAfter(fyEnd);
      } else {
        switch (selectedFilter) {
          case TimeFilter.daily:
            include = sellDate.year == now.year && sellDate.month == now.month && sellDate.day == now.day;
            break;
          case TimeFilter.monthly:
            include = sellDate.year == now.year && sellDate.month == now.month;
            break;
          case TimeFilter.quarterly:
            include = now.difference(sellDate).inDays <= 90;
            break;
          case TimeFilter.halfYearly:
            include = now.difference(sellDate).inDays <= 182;
            break;
          case TimeFilter.yearly:
          case TimeFilter.allFY:
            include = !sellDate.isBefore(fyStart) && !sellDate.isAfter(fyEnd);
            break;
          case TimeFilter.custom:
            final s = DateTime(customStartDate.year, customStartDate.month, customStartDate.day);
            final e = DateTime(customEndDate.year, customEndDate.month, customEndDate.day, 23, 59, 59);
            include = !sellDate.isBefore(s) && !sellDate.isAfter(e);
            break;
        }
      }
      if (include) {
        final double gain = (g['gain'] as num?)?.toDouble() ?? 0.0;
        if (g['isLTCG'] == true) {
          ltcgTotal += gain;
        } else {
          stcgTotal += gain;
        }
      }
    }

    final double stcgTax = stcgTotal > 0 ? stcgTotal * 0.20 : 0.0;
    final double taxableLtcg = math.max(0.0, ltcgTotal - 125000.0);
    final double ltcgTax = taxableLtcg * 0.125;

    return {
      'stcg': stcgTotal,
      'ltcg': ltcgTotal,
      'stcgTax': stcgTax,
      'ltcgTax': ltcgTax,
      'totalCgTax': (stcgTax + ltcgTax) * 1.04,
    };
  }

  // આખી એપમાંથી (દૈનિક નોંધ, MF, સ્ટોક, FD/બોન્ડ/PLI, ઓટો-પે, બેંક ખાતા) આવક અને ટેક્સ ડિડક્શન ફેચ કરતું ફંક્શન
  Map<String, double> _fetchComprehensiveTaxData({bool entireFY = true}) {
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);
    final txList = entireFY ? entireFYTransactions : filteredTransactions;

    double regularGrossIncome = 0.0;
    double recordedBankInterest = 0.0;
    double raw80C = 0.0;
    double raw80D = 0.0;
    double rawHomeOrEduLoan = 0.0;

    // ૧. દૈનિક વ્યવહારોમાંથી આવક અને કરબચત રોકાણો ફેચ કરો (વેચાણની મૂળ રકમ Capital Gains માં ગણાતી હોવાથી બાકાત)
    for (final tx in txList) {
      final String id = (tx['id'] ?? '').toString();
      final String title = (tx['title'] ?? '').toString().toLowerCase();
      final String catName = (tx['categoryName'] ?? '').toString().toLowerCase();
      final String effect = (tx['categoryEffect'] ?? '').toString();
      final double amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;

      final bool isAssetSaleProceeds = id.startsWith('tx_mf_sell_') ||
          id.startsWith('tx_stk_sell_') ||
          id.startsWith('tx_sell_bul_') ||
          id.startsWith('tx_sell_asset_') ||
          id.startsWith('fi_auto_');

      if (effect == 'incomeCredit' && !isAssetSaleProceeds) {
        regularGrossIncome += amt;
        if (title.contains('વ્યાજ') || title.contains('interest') || title.contains('બેંક')) {
          recordedBankInterest += amt;
        }
      }

      // જો મેન્યુઅલ વ્યવહાર હોય તો તેમાંથી 80C / 80D તપાસો
      final bool isLinkedBoxTx = id.startsWith('tx_mf_') || id.startsWith('tx_stk_') || id.startsWith('tx_fi_') || id.startsWith('tx_bullion_') || id.startsWith('tx_asset_');
      if (!isLinkedBoxTx) {
        if (title.contains('pli') ||
            title.contains('lic') ||
            title.contains('ppf') ||
            title.contains('ssy') ||
            title.contains('elss') ||
            title.contains('pf') ||
            title.contains('ટર્મ') ||
            title.contains('term') ||
            catName.contains('વીમા')) {
          if (title.contains('health') || title.contains('હેલ્થ') || title.contains('મેડિકલ')) {
            raw80D += amt;
          } else {
            raw80C += amt;
          }
        } else if (title.contains('health') || title.contains('હેલ્થ') || title.contains('મેડિકલ')) {
          raw80D += amt;
        } else if (title.contains('home loan') || title.contains('હોમ લોન') || title.contains('education loan') || title.contains('એજ્યુકેશન')) {
          rawHomeOrEduLoan += amt;
        }
      }
    }

    // ૨. મ્યુચ્યુઅલ ફંડ બોક્સમાંથી ELSS / Tax Saver ફંડ ફેચ કરો
    for (final m in mfInvestmentsBox.values) {
      final dt = DateTime.tryParse(m['date'] ?? '') ?? DateTime.now();
      if (!entireFY || (!dt.isBefore(fyStart) && !dt.isAfter(fyEnd))) {
        final subCat = _classifyMfSubCategory(Map<dynamic, dynamic>.from(m));
        final sName = (m['schemeName'] ?? '').toString().toLowerCase();
        if (subCat == 'ELSS' || sName.contains('elss') || sName.contains('tax') || sName.contains('ટેક્સ')) {
          raw80C += (m['investedAmount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    // ૩. Fixed Income બોક્સમાંથી PLI, PPF, SSY, 5-Yr FD ફેચ કરો
    for (final f in fixedIncomeBox.values) {
      final dt = DateTime.tryParse(f['startDate'] ?? '') ?? DateTime.now();
      if (!entireFY || (!dt.isBefore(fyStart) && !dt.isAfter(fyEnd))) {
        final sType = (f['schemeType'] ?? '').toString().toLowerCase();
        final title = (f['title'] ?? '').toString().toLowerCase();
        final pAmt = (f['principalAmount'] as num?)?.toDouble() ?? 0.0;
        if (sType.contains('pli') ||
            sType.contains('ppf') ||
            sType.contains('ssy') ||
            sType.contains('fd') ||
            title.contains('tax') ||
            title.contains('pli') ||
            title.contains('ppf')) {
          raw80C += pAmt;
        }
      }
    }

    // ૪. AutoPay બોક્સમાંથી સક્રિય PLI, Health Insurance, Term Insurance ફેચ કરો (જો હજુ પ્રોસેસ ન થયા હોય તો પણ વાર્ષિક અંદાજમાં ગણાય)
    for (final a in autoPayBox.values) {
      if (a['isActive'] == true) {
        final aType = (a['type'] ?? '').toString();
        final amt = (a['amount'] as num?)?.toDouble() ?? 0.0;
        if (aType == 'HealthInsurance' && raw80D == 0) {
          raw80D += amt;
        } else if ((aType == 'PLI' || aType == 'TermInsurance' || aType == 'GovScheme') && raw80C == 0) {
          raw80C += amt;
        }
      }
    }

    // ૫. બેંક બચત ખાતાનું વ્યાજ
    double bankSavingsBalance = 0.0;
    for (final acc in accounts) {
      final aType = (acc['type'] ?? '').toString().toLowerCase();
      if (!aType.contains('credit') && !aType.contains('ક્રેડિટ')) {
        final bal = getAccountCurrentBalance(acc['id'].toString());
        if (bal > 0) bankSavingsBalance += bal;
      }
    }
    final double bankIntRate = (settingsBox.get('bankInterestRate', defaultValue: 3.5) as num).toDouble();
    final double estimatedBankInterest = bankSavingsBalance * (bankIntRate / 100.0);
    final double totalBankInterest = recordedBankInterest > 0 ? recordedBankInterest : estimatedBankInterest;

    // જો દૈનિક નોંધમાં બેંક વ્યાજ અલગથી ન ઉમેર્યું હોય અને વપરાશકર્તાએ ઓટો-બેંક વ્યાજ ચાલુ રાખ્યું હોય
    final bool includeEstBankIntInTax = settingsBox.get('includeEstBankIntInTax', defaultValue: false) == true;
    final double effectiveGrossIncome = regularGrossIncome + (includeEstBankIntInTax && recordedBankInterest == 0 ? estimatedBankInterest : 0.0);

    final String ageGroup = settingsBox.get('taxAgeGroup', defaultValue: 'regular').toString();
    final double extraDeductions = (settingsBox.get('extraOldRegimeDeductions', defaultValue: 0.0) as num).toDouble() + rawHomeOrEduLoan;

    // New Regime ગણતરી (ફોટો ૪ મુજબ)
    const double stdDedNew = 75000.0;
    final double taxableNew = math.max(0.0, effectiveGrossIncome - stdDedNew);
    final double slabTaxNew = _calculateIncomeTaxNewRegime(taxableNew);

    // Old Regime ગણતરી (ફોટો ૫ મુજબ)
    const double stdDedOld = 50000.0;
    final double allowed80C = math.min(150000.0, raw80C);
    final double max80DLimit = ageGroup == 'regular' ? 25000.0 : 50000.0;
    final double allowed80D = math.min(max80DLimit, raw80D);
    final double max80TTALimit = ageGroup == 'regular' ? 10000.0 : 50000.0;
    final double allowed80TTA = math.min(max80TTALimit, totalBankInterest);

    final double totalOldDeductions = stdDedOld + allowed80C + allowed80D + allowed80TTA + extraDeductions;
    final double taxableOld = math.max(0.0, effectiveGrossIncome - totalOldDeductions);
    final double slabTaxOld = _calculateIncomeTaxOldRegime(taxableOld, ageGroup: ageGroup);

    // Capital Gains (STCG & LTCG)
    final cg = _getCapitalGainsSummary(entireFY: entireFY);
    final double stcg = cg['stcg'] ?? 0.0;
    final double ltcg = cg['ltcg'] ?? 0.0;
    final double cgTax = cg['totalCgTax'] ?? 0.0;

    final double totalTaxNew = slabTaxNew + cgTax;
    final double totalTaxOld = slabTaxOld + cgTax;

    return {
      'grossIncome': effectiveGrossIncome,
      'stdDedNew': stdDedNew,
      'taxableNew': taxableNew,
      'slabTaxNew': slabTaxNew,
      'totalTaxNew': totalTaxNew,
      'stdDedOld': stdDedOld,
      'raw80C': raw80C,
      'allowed80C': allowed80C,
      'raw80D': raw80D,
      'allowed80D': allowed80D,
      'allowed80TTA': allowed80TTA,
      'extraDeductions': extraDeductions,
      'totalOldDeductions': totalOldDeductions,
      'taxableOld': taxableOld,
      'slabTaxOld': slabTaxOld,
      'totalTaxOld': totalTaxOld,
      'stcg': stcg,
      'ltcg': ltcg,
      'cgTax': cgTax,
      'bankSavingsBalance': bankSavingsBalance,
      'totalBankInterest': totalBankInterest,
    };
  }

  // આખી એપમાંથી સંપૂર્ણ રોકાણ અને બચતનું વર્ગીકરણ (Equity, MF [Equity/Debt/Hybrid/ELSS], FD, Bond, PLI, Bullion, Bank Interest)
  Map<String, dynamic> _fetchCompletePortfolioBreakdown() {
    double directStocksVal = 0.0;
    double directEtfVal = 0.0;
    double directEquityInv = 0.0;

    // 1. Stocks & ETFs
    for (final s in stockInvestmentsBox.values) {
      final qty = (s['quantity'] as num?)?.toDouble() ?? 0.0;
      final buyP = (s['buyPrice'] as num?)?.toDouble() ?? 0.0;
      final curP = (s['currentPrice'] as num?)?.toDouble() ?? buyP;
      final val = qty * curP;
      directEquityInv += qty * buyP;
      if ((s['instrumentType'] ?? '').toString().toUpperCase().contains('ETF')) {
        directEtfVal += val;
      } else {
        directStocksVal += val;
      }
    }

    // 2. Mutual Funds (Equity, Debt, Hybrid, ELSS)
    double mfEquityVal = 0.0;
    double mfDebtVal = 0.0;
    double mfHybridVal = 0.0;
    double mfElssVal = 0.0;
    double mfTotalInv = 0.0;

    for (final raw in mfInvestmentsBox.values) {
      final m = Map<dynamic, dynamic>.from(raw);
      final inv = (m['investedAmount'] as num?)?.toDouble() ?? 0.0;
      final units = (m['units'] as num?)?.toDouble() ?? 0.0;
      final curNav = (m['currentNav'] as num?)?.toDouble() ?? (m['buyNav'] as num?)?.toDouble() ?? 0.0;
      final val = units > 0 ? (units * curNav) : inv;
      mfTotalInv += inv;

      final subCat = _classifyMfSubCategory(m);
      if (subCat == 'Debt') {
        mfDebtVal += val;
      } else if (subCat == 'Hybrid') {
        mfHybridVal += val;
      } else if (subCat == 'ELSS') {
        mfElssVal += val;
      } else {
        mfEquityVal += val;
      }
    }

    // 3. Fixed Income (FD, Bond, PLI, PPF/SSY/RD)
    double fdVal = 0.0;
    double bondVal = 0.0;
    double pliVal = 0.0;
    double ppfPostOfficeVal = 0.0;
    double fixedIncomeInv = 0.0;

    for (final f in fixedIncomeBox.values) {
      final p = (f['principalAmount'] as num?)?.toDouble() ?? 0.0;
      final mat = (f['scheduledAmount'] as num?)?.toDouble() ?? p;
      final val = mat > p ? mat : p;
      fixedIncomeInv += p;
      final sType = (f['schemeType'] ?? '').toString().toLowerCase();
      if (sType.contains('fd') || sType.contains('ફિક્સ')) {
        fdVal += val;
      } else if (sType.contains('bond') || sType.contains('બોન્ડ')) {
        bondVal += val;
      } else if (sType.contains('pli') || sType.contains('lic') || sType.contains('ઇન્સ્યોરન્સ')) {
        pliVal += val;
      } else {
        ppfPostOfficeVal += val;
      }
    }

    // 4. Bullion (Gold 24K, Gold 22K, Silver)
    final rates = bullionCityRates[selectedCity] ?? {"gold24": 96500.0, "gold22": 88400.0, "silver": 112000.0};
    double gold24Val = 0.0;
    double gold22Val = 0.0;
    double silverVal = 0.0;
    double bullionInv = 0.0;

    for (final b in bullionInvestmentsBox.values) {
      final weight = (b['weight'] as num?)?.toDouble() ?? 0.0;
      final buyP = (b['buyPrice'] as num?)?.toDouble() ?? 0.0;
      final mType = (b['metalType'] ?? '').toString();
      bullionInv += buyP;
      if (mType.contains('22K')) {
        gold22Val += weight * (rates['gold22']! / 10.0);
      } else if (mType.contains('Silver') || mType.contains('ચાંદી')) {
        silverVal += weight * (rates['silver']! / 1000.0);
      } else {
        gold24Val += weight * (rates['gold24']! / 10.0);
      }
    }

    // 5. Physical Assets
    double physicalAssetsVal = 0.0;
    double physicalAssetsInv = 0.0;
    for (final a in physicalAssetsBox.values) {
      final v = (a['value'] as num?)?.toDouble() ?? 0.0;
      final curV = (a['currentValue'] as num?)?.toDouble() ?? v;
      physicalAssetsInv += v;
      physicalAssetsVal += curV;
    }

    // 6. દૈનિક વ્યવહારો (transactionsBox) માંથી એવા રોકાણો ફેચ કરો જે સીધા હોમ ટેબ પરથી ઉમેરાયા હોય
    for (final rawTx in transactionsBox.values) {
      final tx = Map<dynamic, dynamic>.from(rawTx);
      final String id = (tx['id'] ?? '').toString();
      final String effect = (tx['categoryEffect'] ?? '').toString();
      final String title = (tx['title'] ?? '').toString().toLowerCase();
      final String catId = (tx['categoryId'] ?? '').toString();
      final double amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;

      final bool isAlreadyInBoxes = id.startsWith('tx_mf_') ||
          id.startsWith('tx_stk_') ||
          id.startsWith('tx_fi_') ||
          id.startsWith('tx_bullion_') ||
          id.startsWith('tx_asset_') ||
          id.startsWith('fi_auto_');

      if (!isAlreadyInBoxes && effect == 'assetIncrease' && amt > 0) {
        if (title.contains('stock') || title.contains('શેર') || title.contains('etf')) {
          directStocksVal += amt;
          directEquityInv += amt;
        } else if (title.contains('debt') || title.contains('ડેબ્ટ') || title.contains('liquid')) {
          mfDebtVal += amt;
          mfTotalInv += amt;
        } else if (title.contains('hybrid') || title.contains('હાઇબ્રીડ') || title.contains('balanced')) {
          mfHybridVal += amt;
          mfTotalInv += amt;
        } else if (title.contains('elss') || title.contains('tax')) {
          mfElssVal += amt;
          mfTotalInv += amt;
        } else if (title.contains('mf') || title.contains('sip') || title.contains('મ્યુચ્યુઅલ') || catId == '3') {
          mfEquityVal += amt;
          mfTotalInv += amt;
        } else if (title.contains('ચાંદી') || title.contains('silver')) {
          silverVal += amt;
          bullionInv += amt;
        } else if (title.contains('સોનું') || title.contains('gold') || catId == '4') {
          gold24Val += amt;
          bullionInv += amt;
        } else if (title.contains('fd') || title.contains('ફિક્સ')) {
          fdVal += amt;
          fixedIncomeInv += amt;
        } else if (title.contains('bond') || title.contains('બોન્ડ')) {
          bondVal += amt;
          fixedIncomeInv += amt;
        } else if (title.contains('pli') || title.contains('lic') || title.contains('વીમા')) {
          pliVal += amt;
          fixedIncomeInv += amt;
        } else if (title.contains('ppf') || title.contains('ssy') || title.contains('rd') || title.contains('પોસ્ટ')) {
          ppfPostOfficeVal += amt;
          fixedIncomeInv += amt;
        } else {
          fdVal += amt;
          fixedIncomeInv += amt;
        }
      } else if (!isAlreadyInBoxes && effect == 'expenseDebit' && (title.contains('pli') || title.contains('lic'))) {
        pliVal += amt;
        fixedIncomeInv += amt;
      }
    }

    // 7. બેંક ખાતાઓની સિલક અને મળતું વ્યાજ
    double bankSavingsBalance = 0.0;
    double cashWalletBalance = 0.0;
    final List<Map<String, dynamic>> bankAccountsBreakdown = [];

    for (final acc in accounts) {
      final String accId = acc['id'].toString();
      final String accName = (acc['name'] ?? 'ખાતું').toString();
      final String accType = (acc['type'] ?? '').toString();
      if (accType.toLowerCase().contains('credit') || accType.contains('ક્રેડિટ')) continue;

      final double bal = math.max(0.0, getAccountCurrentBalance(accId));
      final bool isCash = accType.toLowerCase().contains('cash') || accType.contains('રોકડ');
      if (isCash) {
        cashWalletBalance += bal;
      } else {
        bankSavingsBalance += bal;
      }
      bankAccountsBreakdown.add({
        'name': accName,
        'type': accType,
        'balance': bal,
        'isCash': isCash,
      });
    }

    final double bankInterestRate = (settingsBox.get('bankInterestRate', defaultValue: 3.5) as num).toDouble();
    double recordedBankInterest = 0.0;
    for (final rawTx in entireFYTransactions) {
      final tx = Map<dynamic, dynamic>.from(rawTx);
      final title = (tx['title'] ?? '').toString().toLowerCase();
      if (tx['categoryEffect'] == 'incomeCredit' && (title.contains('વ્યાજ') || title.contains('interest'))) {
        recordedBankInterest += (tx['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final double annualEstimatedBankInterest = bankSavingsBalance * (bankInterestRate / 100.0);
    final double effectiveBankInterest = recordedBankInterest > 0 ? recordedBankInterest : annualEstimatedBankInterest;

    final double directEquityTotal = directStocksVal + directEtfVal;
    final double mfTotalVal = mfEquityVal + mfDebtVal + mfHybridVal + mfElssVal;
    final double fixedIncomeTotalVal = fdVal + bondVal + pliVal + ppfPostOfficeVal;
    final double bullionTotalVal = gold24Val + gold22Val + silverVal;
    final double totalLiquidSavings = bankSavingsBalance + cashWalletBalance;

    final double totalInvestmentsVal = directEquityTotal + mfTotalVal + fixedIncomeTotalVal + bullionTotalVal + physicalAssetsVal;
    final double totalInvestedCost = directEquityInv + mfTotalInv + fixedIncomeInv + bullionInv + physicalAssetsInv;
    final double grandTotalWealth = totalInvestmentsVal + totalLiquidSavings;

    return {
      'directStocksVal': directStocksVal,
      'directEtfVal': directEtfVal,
      'directEquityTotal': directEquityTotal,
      'mfEquityVal': mfEquityVal,
      'mfDebtVal': mfDebtVal,
      'mfHybridVal': mfHybridVal,
      'mfElssVal': mfElssVal,
      'mfTotalVal': mfTotalVal,
      'fdVal': fdVal,
      'bondVal': bondVal,
      'pliVal': pliVal,
      'ppfPostOfficeVal': ppfPostOfficeVal,
      'fixedIncomeTotalVal': fixedIncomeTotalVal,
      'gold24Val': gold24Val,
      'gold22Val': gold22Val,
      'silverVal': silverVal,
      'bullionTotalVal': bullionTotalVal,
      'physicalAssetsVal': physicalAssetsVal,
      'bankSavingsBalance': bankSavingsBalance,
      'cashWalletBalance': cashWalletBalance,
      'totalLiquidSavings': totalLiquidSavings,
      'bankInterestRate': bankInterestRate,
      'annualEstimatedBankInterest': annualEstimatedBankInterest,
      'recordedBankInterest': recordedBankInterest,
      'effectiveBankInterest': effectiveBankInterest,
      'bankAccountsBreakdown': bankAccountsBreakdown,
      'totalInvestmentsVal': totalInvestmentsVal,
      'totalInvestedCost': totalInvestedCost,
      'grandTotalWealth': grandTotalWealth,
    };
  }

  Map<String, double> _calculatePortfolioReturnMetrics() {
    final data = _fetchCompletePortfolioBreakdown();
    final double totalInvested = (data['totalInvestedCost'] as num?)?.toDouble() ?? 0.0;
    final double currentValuation = (data['totalInvestmentsVal'] as num?)?.toDouble() ?? 0.0;
    final double bankInterest = (data['effectiveBankInterest'] as num?)?.toDouble() ?? 0.0;

    final cg = _getCapitalGainsSummary(entireFY: true);
    final realizedProfit = (cg['stcg'] ?? 0.0) + (cg['ltcg'] ?? 0.0);

    final netProfit = (currentValuation - totalInvested) + realizedProfit + bankInterest;
    final returnPercent = totalInvested > 0
        ? (netProfit / totalInvested) * 100.0
        : ((data['bankInterestRate'] as num?)?.toDouble() ?? 0.0);

    return {
      'invested': totalInvested,
      'currentValue': currentValuation,
      'netProfit': netProfit,
      'returnPercent': returnPercent,
    };
  }

  // =========================================================
  // AppBar માં ₹ (રૂપિયા) ના સંકેત પર ક્લિક કરતાં ખુલતી આખી નવી સ્ક્રીન:
  // ૧. સંપૂર્ણ રોકાણ અને બચતનું ટકાવારી (%) સાથે એનાલિસિસ
  // ૨. પ્રશ્નો દ્વારા રિસ્ક કેપેસિટી અને રોકાણ સરખામણી
  // ૩. પોતાની કસ્ટમ સ્ટ્રેટેજી અને વાસ્તવિક રોકાણ સરખામણી
  // =========================================================
  void _openAnnualTaxAndExpenseDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) {
          return StatefulBuilder(
            builder: (pageCtx, setPageState) {
              final data = _fetchCompletePortfolioBreakdown();
              final double grandTotal = math.max(0.0, (data['grandTotalWealth'] as num).toDouble());
              final double totalInvOnly = (data['totalInvestmentsVal'] as num).toDouble();

              final double directEquity = (data['directEquityTotal'] as num).toDouble();
              final double mfEquity = (data['mfEquityVal'] as num).toDouble();
              final double mfElss = (data['mfElssVal'] as num).toDouble();
              final double mfDebt = (data['mfDebtVal'] as num).toDouble();
              final double mfHybrid = (data['mfHybridVal'] as num).toDouble();
              final double mfTotal = (data['mfTotalVal'] as num).toDouble();

              final double fdVal = (data['fdVal'] as num).toDouble();
              final double bondVal = (data['bondVal'] as num).toDouble();
              final double pliVal = (data['pliVal'] as num).toDouble();
              final double ppfVal = (data['ppfPostOfficeVal'] as num).toDouble();
              final double fixedTotal = (data['fixedIncomeTotalVal'] as num).toDouble();

              final double gold24Val = (data['gold24Val'] as num).toDouble();
              final double gold22Val = (data['gold22Val'] as num).toDouble();
              final double silverVal = (data['silverVal'] as num).toDouble();
              final double bullionTotal = (data['bullionTotalVal'] as num).toDouble();

              final double physicalVal = (data['physicalAssetsVal'] as num).toDouble();
              final double bankSavings = (data['bankSavingsBalance'] as num).toDouble();
              final double cashBal = (data['cashWalletBalance'] as num).toDouble();
              final double liquidTotal = (data['totalLiquidSavings'] as num).toDouble();
              final double bankIntRate = (data['bankInterestRate'] as num).toDouble();
              final double annualBankIntRs = (data['effectiveBankInterest'] as num).toDouble();

              double pctOfGrand(double v) => grandTotal > 0 ? (v / grandTotal) * 100.0 : 0.0;
              double pctOfInv(double v) => totalInvOnly > 0 ? (v / totalInvOnly) * 100.0 : 0.0;

              // --- ટેબ ૨ માટે: રિસ્ક કેપેસિટી પ્રશ્નોના જવાબો (0 થી 3 સ્કોર) ---
              int q1Age = (settingsBox.get('risk_q1_age', defaultValue: 2) as num).toInt();
              int q2Horizon = (settingsBox.get('risk_q2_horizon', defaultValue: 2) as num).toInt();
              int q3DropReact = (settingsBox.get('risk_q3_drop', defaultValue: 2) as num).toInt();
              int q4IncomeStab = (settingsBox.get('risk_q4_income', defaultValue: 2) as num).toInt();
              int q5Emergency = (settingsBox.get('risk_q5_emerg', defaultValue: 2) as num).toInt();
              int q6Goal = (settingsBox.get('risk_q6_goal', defaultValue: 2) as num).toInt();

              final int totalRiskPoints = q1Age + q2Horizon + q3DropReact + q4IncomeStab + q5Emergency + q6Goal; // Max 18
              final double riskScore100 = (totalRiskPoints / 18.0) * 100.0;

              String riskProfileName;
              Color riskColor;
              Map<String, double> recommendedPct;

              if (riskScore100 >= 70) {
                riskProfileName = 'વૃદ્ધિલક્ષી / આક્રમક (Aggressive Growth)';
                riskColor = Colors.deepPurple;
                recommendedPct = {
                  'ઇક્વિટી (શેર + ઇક્વિટી MF)': 60.0,
                  'ડેબ્ટ અને હાઇબ્રીડ MF': 10.0,
                  'FD / બોન્ડ / PLI / PPF': 10.0,
                  'સોનું / ચાંદી (ધાતુઓ)': 10.0,
                  'બેંક બચત અને રોકડ': 10.0,
                };
              } else if (riskScore100 >= 42) {
                riskProfileName = 'મધ્યમ અને સંતુલિત (Moderate Balanced)';
                riskColor = Colors.teal.shade700;
                recommendedPct = {
                  'ઇક્વિટી (શેર + ઇક્વિટી MF)': 40.0,
                  'ડેબ્ટ અને હાઇબ્રીડ MF': 15.0,
                  'FD / બોન્ડ / PLI / PPF': 20.0,
                  'સોનું / ચાંદી (ધાતુઓ)': 10.0,
                  'બેંક બચત અને રોકડ': 15.0,
                };
              } else {
                riskProfileName = 'સુરક્ષિત / મૂડી રક્ષણ (Conservative)';
                riskColor = Colors.blue.shade800;
                recommendedPct = {
                  'ઇક્વિટી (શેર + ઇક્વિટી MF)': 20.0,
                  'ડેબ્ટ અને હાઇબ્રીડ MF': 15.0,
                  'FD / બોન્ડ / PLI / PPF': 35.0,
                  'સોનું / ચાંદી (ધાતુઓ)': 10.0,
                  'બેંક બચત અને રોકડ': 20.0,
                };
              }

              // પ્રશ્નોની સરખામણી માટે વાસ્તવિક ટકાવારી (સ્થાવર મિલકત સિવાયના નાણાકીય પોર્ટફોલિયો અથવા કુલ સંપત્તિના આધારે)
              final double financialBase = math.max(1.0, grandTotal - physicalVal);
              final Map<String, double> actualForRiskMap = {
                'ઇક્વિટી (શેર + ઇક્વિટી MF)': ((directEquity + mfEquity + mfElss) / financialBase) * 100.0,
                'ડેબ્ટ અને હાઇબ્રીડ MF': ((mfDebt + mfHybrid) / financialBase) * 100.0,
                'FD / બોન્ડ / PLI / PPF': (fixedTotal / financialBase) * 100.0,
                'સોનું / ચાંદી (ધાતુઓ)': (bullionTotal / financialBase) * 100.0,
                'બેંક બચત અને રોકડ': (liquidTotal / financialBase) * 100.0,
              };
              final Map<String, double> actualRsForRiskMap = {
                'ઇક્વિટી (શેર + ઇક્વિટી MF)': directEquity + mfEquity + mfElss,
                'ડેબ્ટ અને હાઇબ્રીડ MF': mfDebt + mfHybrid,
                'FD / બોન્ડ / PLI / PPF': fixedTotal,
                'સોનું / ચાંદી (ધાતુઓ)': bullionTotal,
                'બેંક બચત અને રોકડ': liquidTotal,
              };

              // --- ટેબ ૩ માટે: યુઝરની પોતાની કસ્ટમ સ્ટ્રેટેજી (%) ---
              double stDirectEq = (settingsBox.get('strat_direct_eq', defaultValue: 20.0) as num).toDouble();
              double stMfEq = (settingsBox.get('strat_mf_eq', defaultValue: 25.0) as num).toDouble();
              double stMfDebtHyb = (settingsBox.get('strat_mf_debthyb', defaultValue: 10.0) as num).toDouble();
              double stFixed = (settingsBox.get('strat_fixed', defaultValue: 20.0) as num).toDouble();
              double stBullion = (settingsBox.get('strat_bullion', defaultValue: 10.0) as num).toDouble();
              double stBank = (settingsBox.get('strat_bank', defaultValue: 15.0) as num).toDouble();
              final double totalStrategyPct = stDirectEq + stMfEq + stMfDebtHyb + stFixed + stBullion + stBank;

              return DefaultTabController(
                length: 3,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('સંપૂર્ણ રોકાણ અને બચત વિશ્લેષણ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    bottom: const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(icon: Icon(Icons.pie_chart, size: 18), text: '૧. રોકાણ & બચત (%)'),
                        Tab(icon: Icon(Icons.quiz, size: 18), text: '૨. રિસ્ક કેપેસિટી પ્રશ્નો'),
                        Tab(icon: Icon(Icons.tune, size: 18), text: '૩. મારી સ્ટ્રેટેજી સરખામણી'),
                      ],
                    ),
                  ),
                  body: TabBarView(
                    children: [
                      // =========================================================
                      // ટેબ ૧: સંપૂર્ણ રોકાણ અને બચતનું ટકાવારી પ્રમાણે વિશ્લેષણ
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // કુલ સંપત્તિ અને બચત સારાંશ કાર્ડ
                            Card(
                              color: Colors.teal.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('📊 કુલ રોકાણ અને બચત સારાંશ (આખી એપમાંથી ઓટો-ફેચ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _metricColumn('કુલ સંપત્તિ (રોકાણ+બચત)', '₹${grandTotal.toStringAsFixed(0)}', Colors.teal.shade900),
                                        _metricColumn('કુલ રોકાણ મૂલ્ય', '₹${totalInvOnly.toStringAsFixed(0)} (${pctOfGrand(totalInvOnly).toStringAsFixed(1)}%)', Colors.blue.shade900),
                                        _metricColumn('બેંક + રોકડ બચત', '₹${liquidTotal.toStringAsFixed(0)} (${pctOfGrand(liquidTotal).toStringAsFixed(1)}%)', Colors.green.shade800),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // પાઇ ચાર્ટ રજૂઆત
                            if (grandTotal > 0)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      const Text('વિવિધ એસેટ ક્લાસમાં રોકાણની ટકાવારી (%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        height: 175,
                                        child: PieChart(
                                          PieChartData(
                                            centerSpaceRadius: 34,
                                            sections: [
                                              if (directEquity > 0)
                                                PieChartSectionData(value: directEquity, title: '${pctOfGrand(directEquity).toStringAsFixed(1)}%', color: Colors.indigo, radius: 52, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              if (mfTotal > 0)
                                                PieChartSectionData(value: mfTotal, title: '${pctOfGrand(mfTotal).toStringAsFixed(1)}%', color: Colors.teal, radius: 52, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              if (fixedTotal > 0)
                                                PieChartSectionData(value: fixedTotal, title: '${pctOfGrand(fixedTotal).toStringAsFixed(1)}%', color: Colors.orange.shade800, radius: 52, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              if (bullionTotal > 0)
                                                PieChartSectionData(value: bullionTotal, title: '${pctOfGrand(bullionTotal).toStringAsFixed(1)}%', color: Colors.amber.shade700, radius: 52, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              if (liquidTotal > 0)
                                                PieChartSectionData(value: liquidTotal, title: '${pctOfGrand(liquidTotal).toStringAsFixed(1)}%', color: Colors.green, radius: 52, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              if (physicalVal > 0)
                                                PieChartSectionData(value: physicalVal, title: '${pctOfGrand(physicalVal).toStringAsFixed(1)}%', color: Colors.purple, radius: 52, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 4,
                                        children: [
                                          _legendBadge(Colors.indigo, 'ઇક્વિટી (Stocks/ETF)'),
                                          _legendBadge(Colors.teal, 'મ્યુચ્યુઅલ ફંડ'),
                                          _legendBadge(Colors.orange, 'FD / બોન્ડ / PLI'),
                                          _legendBadge(Colors.amber, 'સોનું / ચાંદી'),
                                          _legendBadge(Colors.green, 'બેંક બચત'),
                                          _legendBadge(Colors.purple, 'સ્થાવર મિલકત'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // ૧. ઇક્વિટી (Stocks & ETF)
                            _buildAssetBreakdownCard(
                              title: '૧. ડાયરેક્ટ ઇક્વિટી રોકાણ (Stocks & ETF)',
                              icon: Icons.candlestick_chart,
                              color: Colors.indigo,
                              totalAmount: directEquity,
                              pctOfTotalWealth: pctOfGrand(directEquity),
                              pctOfInvestments: pctOfInv(directEquity),
                              subItems: [
                                {'label': 'ડાયરેક્ટ શેર (Equity Stocks)', 'amt': data['directStocksVal'], 'pct': pctOfGrand((data['directStocksVal'] as num).toDouble())},
                                {'label': 'ETF (Nifty / Gold / International ETF)', 'amt': data['directEtfVal'], 'pct': pctOfGrand((data['directEtfVal'] as num).toDouble())},
                              ],
                            ),

                            // ૨. મ્યુચ્યુઅલ ફંડ (Equity, Debt, Hybrid, ELSS)
                            Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Expanded(
                                          child: Row(
                                            children: [
                                              Icon(Icons.pie_chart, color: Colors.teal, size: 20),
                                              SizedBox(width: 8),
                                              Expanded(child: Text('૨. મ્યુચ્યુઅલ ફંડ (Equity, Debt, Hybrid, ELSS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5))),
                                            ],
                                          ),
                                        ),
                                        Text('₹${mfTotal.toStringAsFixed(0)} (${pctOfGrand(mfTotal).toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13.5)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('કુલ રોકાણોમાં હિસ્સો: ${pctOfInv(mfTotal).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                                    const Divider(),
                                    _subCategoryPctRow('• ઇક્વિટી મ્યુચ્યુઅલ ફંડ (Equity MF)', mfEquity, pctOfGrand(mfEquity), mfTotal > 0 ? (mfEquity / mfTotal) * 100 : 0, Colors.teal),
                                    _subCategoryPctRow('• ડેબ્ટ મ્યુચ્યુઅલ ફંડ (Debt / Liquid MF)', mfDebt, pctOfGrand(mfDebt), mfTotal > 0 ? (mfDebt / mfTotal) * 100 : 0, Colors.blueGrey),
                                    _subCategoryPctRow('• હાઇબ્રીડ મ્યુચ્યુઅલ ફંડ (Hybrid / Balanced)', mfHybrid, pctOfGrand(mfHybrid), mfTotal > 0 ? (mfHybrid / mfTotal) * 100 : 0, Colors.purple),
                                    _subCategoryPctRow('• ELSS / ટેક્સ સેવર મ્યુચ્યુઅલ ફંડ', mfElss, pctOfGrand(mfElss), mfTotal > 0 ? (mfElss / mfTotal) * 100 : 0, Colors.indigo),
                                    if (mfInvestmentsBox.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          icon: const Icon(Icons.category, size: 15),
                                          label: const Text('ફંડ પ્રમાણે Equity/Debt/Hybrid પ્રકાર બદલો', style: TextStyle(fontSize: 11.5)),
                                          onPressed: () {
                                            showDialog(
                                              context: pageCtx,
                                              builder: (dCtx) => StatefulBuilder(
                                                builder: (dCtx, setDState) {
                                                  final list = mfInvestmentsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
                                                  return AlertDialog(
                                                    title: const Text('મ્યુચ્યુઅલ ફંડનો પેટા-પ્રકાર સેટ કરો', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                                    content: SizedBox(
                                                      width: double.maxFinite,
                                                      height: 300,
                                                      child: ListView.builder(
                                                        itemCount: list.length,
                                                        itemBuilder: (_, idx) {
                                                          final item = list[idx];
                                                          final curCat = _classifyMfSubCategory(item);
                                                          return ListTile(
                                                            dense: true,
                                                            title: Text(item['schemeName'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                            subtitle: Text('₹${item['investedAmount']}'),
                                                            trailing: DropdownButton<String>(
                                                              value: curCat,
                                                              items: const [
                                                                DropdownMenuItem(value: 'Equity', child: Text('Equity', style: TextStyle(fontSize: 12))),
                                                                DropdownMenuItem(value: 'Debt', child: Text('Debt', style: TextStyle(fontSize: 12))),
                                                                DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid', style: TextStyle(fontSize: 12))),
                                                                DropdownMenuItem(value: 'ELSS', child: Text('ELSS (80C)', style: TextStyle(fontSize: 12))),
                                                              ],
                                                              onChanged: (v) {
                                                                if (v != null) {
                                                                  item['mfSubCategory'] = v;
                                                                  mfInvestmentsBox.put(item['id'], item);
                                                                  setDState(() {});
                                                                  setPageState(() {});
                                                                  setState(() {});
                                                                }
                                                              },
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                    actions: [
                                                      ElevatedButton(onPressed: () => Navigator.pop(dCtx), child: const Text('પૂર્ણ')),
                                                    ],
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),

                            // ૩. FD, બોન્ડ, PLI, PPF/ પોસ્ટ ઓફિસ
                            _buildAssetBreakdownCard(
                              title: '૩. FD, બોન્ડ, PLI અને બચત યોજનાઓ',
                              icon: Icons.account_balance_wallet,
                              color: Colors.orange.shade800,
                              totalAmount: fixedTotal,
                              pctOfTotalWealth: pctOfGrand(fixedTotal),
                              pctOfInvestments: pctOfInv(fixedTotal),
                              subItems: [
                                {'label': 'ફિક્સ ડિપોઝિટ (FD)', 'amt': fdVal, 'pct': pctOfGrand(fdVal)},
                                {'label': 'બોન્ડ (Sovereign / Corp Bonds)', 'amt': bondVal, 'pct': pctOfGrand(bondVal)},
                                {'label': 'PLI / LIC / વીમા રોકાણ', 'amt': pliVal, 'pct': pctOfGrand(pliVal)},
                                {'label': 'PPF / SSY / RD / પોસ્ટ ઓફિસ સ્કીમ', 'amt': ppfVal, 'pct': pctOfGrand(ppfVal)},
                              ],
                            ),

                            // ૪. વિવિધ ધાતુઓમાં રોકાણ (Gold 24K, 22K, Silver)
                            _buildAssetBreakdownCard(
                              title: '૪. વિવિધ ધાતુઓમાં રોકાણ (સોનું અને ચાંદી)',
                              icon: Icons.monetization_on,
                              color: Colors.amber.shade800,
                              totalAmount: bullionTotal,
                              pctOfTotalWealth: pctOfGrand(bullionTotal),
                              pctOfInvestments: pctOfInv(bullionTotal),
                              subItems: [
                                {'label': 'સોનું 24K (Gold 24K)', 'amt': gold24Val, 'pct': pctOfGrand(gold24Val)},
                                {'label': 'સોનું 22K (Gold 22K - દાગીના)', 'amt': gold22Val, 'pct': pctOfGrand(gold22Val)},
                                {'label': 'ચાંદી (Silver)', 'amt': silverVal, 'pct': pctOfGrand(silverVal)},
                              ],
                            ),

                            // ૫. બેંકના ખાતાઓમાં બચત અને મળતું વ્યાજ (%)
                            Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Expanded(
                                          child: Row(
                                            children: [
                                              Icon(Icons.account_balance, color: Colors.green, size: 20),
                                              SizedBox(width: 8),
                                              Expanded(child: Text('૫. બેંક ખાતાઓમાં બચત અને મળતું વ્યાજ (%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5))),
                                            ],
                                          ),
                                        ),
                                        Text('₹${liquidTotal.toStringAsFixed(0)} (${pctOfGrand(liquidTotal).toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13.5)),
                                      ],
                                    ),
                                    const Divider(),
                                    _taxSummaryRow('બેંક બચત ખાતાઓની કુલ સિલક:', '₹${bankSavings.toStringAsFixed(0)} (${pctOfGrand(bankSavings).toStringAsFixed(1)}%)', Colors.green.shade800, isBold: true),
                                    const SizedBox(height: 4),
                                    _taxSummaryRow('રોકડ સિલક (Cash Wallet):', '₹${cashBal.toStringAsFixed(0)} (${pctOfGrand(cashBal).toStringAsFixed(1)}%)', Colors.teal.shade700),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('બેંક ખાતામાં મળતું વાર્ષિક વ્યાજ દર: ${bankIntRate.toStringAsFixed(2)}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.green.shade900)),
                                              InkWell(
                                                onTap: () {
                                                  final ctrl = TextEditingController(text: bankIntRate.toStringAsFixed(2));
                                                  showDialog(
                                                    context: pageCtx,
                                                    builder: (c) => AlertDialog(
                                                      title: const Text('બેંક ખાતાનો વાર્ષિક વ્યાજ દર (%)'),
                                                      content: TextField(
                                                        controller: ctrl,
                                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                        decoration: const InputDecoration(labelText: 'વાર્ષિક વ્યાજ દર % (દા.ત. 3.5 અથવા 7.0)'),
                                                      ),
                                                      actions: [
                                                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('રદ')),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            final v = double.tryParse(ctrl.text) ?? 3.5;
                                                            settingsBox.put('bankInterestRate', v);
                                                            Navigator.pop(c);
                                                            setPageState(() {});
                                                            setState(() {});
                                                          },
                                                          child: const Text('સેવ કરો'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                                child: const Text('વ્યાજ % બદલો ✎', style: TextStyle(fontSize: 11.5, color: Colors.teal, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          _taxSummaryRow('વાર્ષિક બેંક વ્યાજની રકમ:', '₹${annualBankIntRs.toStringAsFixed(0)} / વર્ષ (${bankIntRate.toStringAsFixed(1)}%)', Colors.green.shade900, isBold: true),
                                          if ((data['recordedBankInterest'] as num) > 0)
                                            Text('નોંધાયેલ બેંક વ્યાજ એન્ટ્રી: ₹${(data['recordedBankInterest'] as num).toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('ખાતાવાર સિલક અને ટકાવારી:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    ...(data['bankAccountsBreakdown'] as List<Map<String, dynamic>>).map((acc) {
                                      final double b = (acc['balance'] as num).toDouble();
                                      final bool isC = acc['isCash'] == true;
                                      final double intAmt = isC ? 0.0 : b * (bankIntRate / 100.0);
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(child: Text('• ${acc['name']}', style: const TextStyle(fontSize: 12))),
                                            Text(
                                              '₹${b.toStringAsFixed(0)} (${pctOfGrand(b).toStringAsFixed(1)}%)${!isC ? ' | વ્યાજ: ₹${intAmt.toStringAsFixed(0)}' : ''}',
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),

                            // ૬. સ્થાવર મિલકત (Physical Assets)
                            if (physicalVal > 0)
                              _buildAssetBreakdownCard(
                                title: '૬. અન્ય સ્થાવર મિલકત (જમીન / મકાન / પ્લોટ)',
                                icon: Icons.home_work,
                                color: Colors.purple,
                                totalAmount: physicalVal,
                                pctOfTotalWealth: pctOfGrand(physicalVal),
                                pctOfInvestments: pctOfInv(physicalVal),
                                subItems: [
                                  {'label': 'કુલ સ્થાવર મિલકત મૂલ્ય', 'amt': physicalVal, 'pct': pctOfGrand(physicalVal)},
                                ],
                              ),
                          ],
                        ),
                      ),

                      // =========================================================
                      // ટેબ ૨: પ્રશ્નો દ્વારા રિસ્ક કેપેસિટી અને રોકાણ સરખામણી
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: riskColor.withOpacity(0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: riskColor.withOpacity(0.4))),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text('તમારી રિસ્ક પ્રોફાઇલ: $riskProfileName', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: riskColor)),
                                        ),
                                        Chip(
                                          backgroundColor: riskColor,
                                          label: Text('સ્કોર: ${riskScore100.toStringAsFixed(0)}/100', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text('નીચેના ૬ પ્રશ્નોના જવાબ આપો; એપ આપોઆપ તમારી રિસ્ક કેપેસિટી ગણીને કયા વિભાગમાં કેટલા ટકા રોકાણ હોવું જોઈએ તેની તમારા હાલના રોકાણ સાથે સરખામણી કરશે.', style: TextStyle(fontSize: 12, color: Colors.black87)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // પ્રશ્નાવલી કાર્ડ
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('📝 રિસ્ક કેપેસિટી મૂલ્યાંકન પ્રશ્નો:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal)),
                                    const Divider(),
                                    _buildRiskQuestionDropdown(
                                      question: '૧. તમારી ઉંમરનો ગાળો શું છે?',
                                      currentVal: q1Age,
                                      options: const ['60+ વર્ષ (નિવૃત્ત)', '45 થી 60 વર્ષ', '30 થી 45 વર્ષ', '30 વર્ષથી ઓછી'],
                                      onChanged: (v) {
                                        settingsBox.put('risk_q1_age', v);
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildRiskQuestionDropdown(
                                      question: '૨. તમે કેટલા સમયગાળા માટે રોકાણ જાળવી શકો છો?',
                                      currentVal: q2Horizon,
                                      options: const ['1 થી 3 વર્ષ (ટૂંકા ગાળા)', '3 થી 5 વર્ષ (મધ્યમ ગાળા)', '5 થી 10 વર્ષ (લાંબા ગાળા)', '10+ વર્ષ (લાંબા ગાળાનું વેલ્થ ક્રિએશન)'],
                                      onChanged: (v) {
                                        settingsBox.put('risk_q2_horizon', v);
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildRiskQuestionDropdown(
                                      question: '૩. જો શેરબજાર અચાનક 15-20% ઘટે તો તમે શું કરશો?',
                                      currentVal: q3DropReact,
                                      options: const ['નુકસાનથી બચવા તરત વેચી દઈશ', 'થોડું વેચીને FD માં મૂકીશ', 'રોકાણ જાળવી રાખીશ (Hold)', 'ઘટાડામાં વધુ ખરીદી (Buy More) કરીશ'],
                                      onChanged: (v) {
                                        settingsBox.put('risk_q3_drop', v);
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildRiskQuestionDropdown(
                                      question: '૪. તમારી આવકની સ્થિરતા કેવી છે?',
                                      currentVal: q4IncomeStab,
                                      options: const ['અનિશ્ચિત આવક', 'સામાન્ય ખાનગી/ધંધાકીય આવક', 'સ્થિર માસિક પગાર / સારો વ્યવસાય', 'સરકારી/સુરક્ષિત પગાર + વધારાની આવક'],
                                      onChanged: (v) {
                                        settingsBox.put('risk_q4_income', v);
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildRiskQuestionDropdown(
                                      question: '૫. તમારી પાસે 6 મહિનાના ખર્ચ જેટલું ઇમરજન્સી ફંડ છે?',
                                      currentVal: q5Emergency,
                                      options: const ['ના, બિલકુલ નથી', '1-2 મહિના પૂરતું છે', '3-5 મહિના પૂરતું છે', 'હા, 6+ મહિનાનું સંપૂર્ણ સુરક્ષિત ફંડ છે'],
                                      onChanged: (v) {
                                        settingsBox.put('risk_q5_emerg', v);
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildRiskQuestionDropdown(
                                      question: '૬. તમારા રોકાણનો મુખ્ય હેતુ શું છે?',
                                      currentVal: q6Goal,
                                      options: const ['માત્ર મૂડીની સુરક્ષા (6-7% વળતર)', 'નિયમિત વ્યાજ અને સુરક્ષા (8-9% વળતર)', 'સંતુલિત વૃદ્ધિ અને ટેક્સ બચત (10-12% વળતર)', 'ઉચ્ચ સંપત્તિ સર્જન (13-16%+ વળતર)'],
                                      onChanged: (v) {
                                        settingsBox.put('risk_q6_goal', v);
                                        setPageState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),
                            // પ્રશ્નોના વિશ્લેષણ મુજબ ભલામણ vs વાસ્તવિક રોકાણ સરખામણી કાર્ડ
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('⚖️ પ્રશ્નોના વિશ્લેષણ મુજબ ભલામણ vs તમારું હાલનું રોકાણ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Text('કુલ નાણાકીય મૂડી (₹${financialBase.toStringAsFixed(0)}) ના આધારે સરખામણી:', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                                    const Divider(),
                                    ...recommendedPct.entries.map((entry) {
                                      final String cat = entry.key;
                                      final double recPct = entry.value;
                                      final double actPct = actualForRiskMap[cat] ?? 0.0;
                                      final double actRs = actualRsForRiskMap[cat] ?? 0.0;
                                      final double targetRs = financialBase * (recPct / 100.0);
                                      final double diffPct = actPct - recPct;
                                      final double diffRs = actRs - targetRs;
                                      final bool isAligned = diffPct.abs() <= 5.0;

                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 6),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isAligned ? Colors.green.withOpacity(0.06) : Colors.orange.withOpacity(0.07),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isAligned ? Colors.green.shade300 : Colors.orange.shade300),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(child: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isAligned ? Colors.green : (diffPct > 0 ? Colors.orange.shade800 : Colors.blue.shade700),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    isAligned
                                                        ? '✅ યોગ્ય છે'
                                                        : (diffPct > 0 ? '⬆️ +${diffPct.toStringAsFixed(1)}% વધુ' : '⬇️ ${diffPct.toStringAsFixed(1)}% ઓછું'),
                                                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('ભલામણ: ${recPct.toStringAsFixed(1)}% (₹${targetRs.toStringAsFixed(0)})', style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w600)),
                                                Text('હાલમાં: ${actPct.toStringAsFixed(1)}% (₹${actRs.toStringAsFixed(0)})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: (actPct / 100.0).clamp(0.0, 1.0),
                                                minHeight: 7,
                                                backgroundColor: Colors.grey.shade200,
                                                color: isAligned ? Colors.green : Colors.orange.shade800,
                                              ),
                                            ),
                                            if (!isAligned) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                diffRs > 0
                                                    ? '💡 સૂચન: રિસ્ક પ્રોફાઇલ મુજબ આ વિભાગમાં ₹${diffRs.abs().toStringAsFixed(0)} વધુ રોકાયેલ છે.'
                                                    : '💡 સૂચન: રિસ્ક પ્રોફાઇલ મુજબ આ વિભાગમાં હજુ ₹${diffRs.abs().toStringAsFixed(0)} નું રોકાણ વધારવું જોઈએ.',
                                                style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // =========================================================
                      // ટેબ ૩: વ્યક્તિ પોતાની સ્ટ્રેટેજી બનાવી શકે અને રોકાણ સરખાવી શકે
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: Colors.indigo.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Expanded(
                                          child: Text('🎯 મારી કસ્ટમ રોકાણ સ્ટ્રેટેજી (Target Allocation %)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
                                        ),
                                        Chip(
                                          backgroundColor: (totalStrategyPct - 100.0).abs() < 0.5 ? Colors.green : Colors.red,
                                          label: Text('કુલ: ${totalStrategyPct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                    const Text('તમે કયા વિભાગમાં કેટલા ટકા (%) રોકાણ કરવા માંગો છો તે સ્લાઇડરથી નક્કી કરો. એપ તમારા હાલના રોકાણ સાથે તેની લાઇવ સરખામણી બતાવશે.', style: TextStyle(fontSize: 11.5, color: Colors.black87)),
                                    const Divider(),
                                    _buildStrategySliderRow(
                                      label: '૧. ડાયરેક્ટ ઇક્વિટી (Stocks & ETF)',
                                      value: stDirectEq,
                                      onChanged: (v) {
                                        settingsBox.put('strat_direct_eq', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildStrategySliderRow(
                                      label: '૨. ઇક્વિટી મ્યુચ્યુઅલ ફંડ (Equity & ELSS MF)',
                                      value: stMfEq,
                                      onChanged: (v) {
                                        settingsBox.put('strat_mf_eq', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildStrategySliderRow(
                                      label: '૩. ડેબ્ટ અને હાઇબ્રીડ MF (Debt & Hybrid)',
                                      value: stMfDebtHyb,
                                      onChanged: (v) {
                                        settingsBox.put('strat_mf_debthyb', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildStrategySliderRow(
                                      label: '૪. FD / બોન્ડ / PLI / PPF (સુરક્ષિત)',
                                      value: stFixed,
                                      onChanged: (v) {
                                        settingsBox.put('strat_fixed', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildStrategySliderRow(
                                      label: '૫. સોનું અને ચાંદી (કિંમતી ધાતુઓ)',
                                      value: stBullion,
                                      onChanged: (v) {
                                        settingsBox.put('strat_bullion', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    _buildStrategySliderRow(
                                      label: '૬. બેંક બચત ખાતું અને રોકડ',
                                      value: stBank,
                                      onChanged: (v) {
                                        settingsBox.put('strat_bank', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    if ((totalStrategyPct - 100.0).abs() >= 0.5)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('⚠️ કુલ સરવાળો 100% હોવો જોઈએ (હાલ: ${totalStrategyPct.toStringAsFixed(0)}%)', style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.bold)),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                                              onPressed: () {
                                                if (totalStrategyPct > 0) {
                                                  final factor = 100.0 / totalStrategyPct;
                                                  final d1 = (stDirectEq * factor).roundToDouble();
                                                  final d2 = (stMfEq * factor).roundToDouble();
                                                  final d3 = (stMfDebtHyb * factor).roundToDouble();
                                                  final d4 = (stFixed * factor).roundToDouble();
                                                  final d5 = (stBullion * factor).roundToDouble();
                                                  final d6 = math.max(0.0, 100.0 - (d1 + d2 + d3 + d4 + d5));
                                                  settingsBox.put('strat_direct_eq', d1);
                                                  settingsBox.put('strat_mf_eq', d2);
                                                  settingsBox.put('strat_mf_debthyb', d3);
                                                  settingsBox.put('strat_fixed', d4);
                                                  settingsBox.put('strat_bullion', d5);
                                                  settingsBox.put('strat_bank', d6);
                                                  setPageState(() {});
                                                }
                                              },
                                              child: const Text('100% બેલેન્સ કરો', style: TextStyle(fontSize: 11)),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),
                            // કસ્ટમ સ્ટ્રેટેજી vs વાસ્તવિક રોકાણ સરખામણી કાર્ડ
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('📊 મારી સ્ટ્રેટેજી vs એપમાં થયેલ વાસ્તવિક રોકાણ સરખામણી:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const Divider(),
                                    ...[
                                      {'name': '૧. ડાયરેક્ટ ઇક્વિટી (Stocks & ETF)', 'targetPct': stDirectEq, 'actualRs': directEquity},
                                      {'name': '૨. ઇક્વિટી મ્યુચ્યુઅલ ફંડ (Equity & ELSS)', 'targetPct': stMfEq, 'actualRs': mfEquity + mfElss},
                                      {'name': '૩. ડેબ્ટ અને હાઇબ્રીડ મ્યુચ્યુઅલ ફંડ', 'targetPct': stMfDebtHyb, 'actualRs': mfDebt + mfHybrid},
                                      {'name': '૪. FD / બોન્ડ / PLI / PPF', 'targetPct': stFixed, 'actualRs': fixedTotal},
                                      {'name': '૫. સોનું અને ચાંદી (ધાતુઓ)', 'targetPct': stBullion, 'actualRs': bullionTotal},
                                      {'name': '૬. બેંક બચત ખાતું અને રોકડ', 'targetPct': stBank, 'actualRs': liquidTotal},
                                    ].map((item) {
                                      final String title = item['name'] as String;
                                      final double tPct = (item['targetPct'] as num).toDouble();
                                      final double aRs = (item['actualRs'] as num).toDouble();
                                      final double aPct = financialBase > 0 ? (aRs / financialBase) * 100.0 : 0.0;
                                      final double tRs = financialBase * (tPct / 100.0);
                                      final double diffRs = aRs - tRs;
                                      final double diffPct = aPct - tPct;
                                      final bool isMatch = diffPct.abs() <= 4.0;

                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 5),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isMatch ? Colors.teal.withOpacity(0.06) : Colors.deepOrange.withOpacity(0.06),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isMatch ? Colors.teal.shade300 : Colors.deepOrange.shade200),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                                                Text(
                                                  isMatch
                                                      ? '✅ સ્ટ્રેટેજી મુજબ બરાબર'
                                                      : (diffPct > 0 ? '⬆️ +${diffPct.toStringAsFixed(1)}% વધુ' : '⬇️ ${diffPct.toStringAsFixed(1)}% ઓછું'),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isMatch ? Colors.teal.shade800 : Colors.deepOrange.shade800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('મારી સ્ટ્રેટેજી: ${tPct.toStringAsFixed(1)}% (₹${tRs.toStringAsFixed(0)})', style: const TextStyle(fontSize: 11.5, color: Colors.indigo, fontWeight: FontWeight.w600)),
                                                Text('વાસ્તવિક: ${aPct.toStringAsFixed(1)}% (₹${aRs.toStringAsFixed(0)})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              isMatch
                                                  ? 'તમારું રોકાણ તમારી સ્ટ્રેટેજી પ્રમાણે સંતુલિત છે.'
                                                  : (diffRs > 0
                                                      ? 'સ્ટ્રેટેજી કરતાં ₹${diffRs.abs().toStringAsFixed(0)} વધુ રોકાયેલ છે.'
                                                      : 'સ્ટ્રેટેજી મુજબ કરવા હજુ ₹${diffRs.abs().toStringAsFixed(0)} રોકવાના બાકી છે.'),
                                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAssetBreakdownCard({
    required String title,
    required IconData icon,
    required Color color,
    required double totalAmount,
    required double pctOfTotalWealth,
    required double pctOfInvestments,
    required List<Map<String, dynamic>> subItems,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5))),
                    ],
                  ),
                ),
                Text('₹${totalAmount.toStringAsFixed(0)} (${pctOfTotalWealth.toStringAsFixed(1)}%)', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13.5)),
              ],
            ),
            const SizedBox(height: 3),
            Text('કુલ રોકાણોમાં હિસ્સો: ${pctOfInvestments.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
            const Divider(),
            ...subItems.map((s) {
              final double amt = (s['amt'] as num?)?.toDouble() ?? 0.0;
              final double pct = (s['pct'] as num?)?.toDouble() ?? 0.0;
              final double shareInGroup = totalAmount > 0 ? (amt / totalAmount) * 100.0 : 0.0;
              return _subCategoryPctRow('• ${s['label']}', amt, pct, shareInGroup, color);
            }),
          ],
        ),
      ),
    );
  }

  Widget _subCategoryPctRow(String label, double amount, double pctOfGrand, double pctInsideGroup, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
              Text('₹${amount.toStringAsFixed(0)}  (${pctOfGrand.toStringAsFixed(1)}%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (pctOfGrand / 100.0).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskQuestionDropdown({
    required String question,
    required int currentVal,
    required List<String> options,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            initialValue: currentVal.clamp(0, options.length - 1),
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            items: List.generate(options.length, (i) => DropdownMenuItem(value: i, child: Text(options[i], style: const TextStyle(fontSize: 12)))),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStrategySliderRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Text('${value.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.indigo)),
          ],
        ),
        Slider(
          value: value.clamp(0.0, 100.0),
          min: 0,
          max: 100,
          divisions: 100,
          label: '${value.toStringAsFixed(0)}%',
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _taxSummaryBox(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _legendBadge(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _taxSummaryRow(String label, String value, Color valueColor, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
        Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }


  // --- દૈનિક નોંધ ડાયલોગ ---
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(existingTx == null ? 'નવો વ્યવહાર નોંધો' : 'વ્યવહાર સુધારો', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'વિગત / શીર્ષક (દા.ત. કરિયાણું, પગાર, પેટ્રોલ)')),
                TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'રકમ (₹)')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedAcc['id'].toString(),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ખાતું પસંદ કરો (ક્રેડિટ કાર્ડ પસંદ કરતા બિલમાં ઉમેરાશે)'),
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
                          final t = await showTimePicker(
                            context: context,
                            initialTime: pickedTime ?? TimeOfDay.now(),
                          );
                          if (t != null) setModalState(() => pickedTime = t);
                        },
                      ),
                    ),
                  ],
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
                      _processAutoPayAndSIP();
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
            BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: inc, color: Colors.green, width: 22, borderRadius: BorderRadius.circular(4))]),
            BarChartGroupData(
 x: 1,
  barRods: [
    BarChartRodData(
      toY: exp,
      color: Colors.redAccent,
      width: 22,
      borderRadius: BorderRadius.circular(4),
    ),
  ],
),
            BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: inv, color: Colors.blue, width: 22, borderRadius: BorderRadius.circular(4))]),
          ],
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) {
                  switch (val.toInt()) {
                    case 0: return const Text("આવક", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
                    case 1: return const Text("ખર્ચ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
                    case 2: return const Text("રોકાણ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
                    default: return const SizedBox();
                  }
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: true, border: const Border(left: BorderSide(color: Colors.teal, width: 1.5), bottom: BorderSide(color: Colors.teal, width: 1.5))),
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
            LineChartBarData(spots: incomeSpots, isCurved: true, color: Colors.green, barWidth: 3),
            LineChartBarData(spots: expenseSpots, isCurved: true, color: Colors.redAccent, barWidth: 3),
          ],
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("📈 નાણાકીય આલેખ", style: TextStyle(fontWeight: FontWeight.bold)),
                SegmentedButton<ChartType>(
                  segments: const [
                    ButtonSegment(value: ChartType.bar, label: Text('સ્તંભ', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: ChartType.line, label: Text('રૈખિક', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {selectedHomeChartType},
                  onSelectionChanged: (s) => setState(() => selectedHomeChartType = s.first),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(height: 155, child: chartWidget),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // (૪) સંપૂર્ણ નાણાકીય વિશ્લેષણ ટેબ (ટેક્સ, STCG/LTCG, બચત, રિટર્ન અને ઇન્ફ્લેશન બીટ)
  // =========================================================
  Widget _buildAnalysisTab() {
    final double totalInc = _calculateTotal('incomeCredit');
    final double totalExp = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    final double totalInv = _calculateTotal('assetIncrease');
    final double totalSavings = totalInc - totalExp;
    final double savingsRate = totalInc > 0 ? (totalSavings / totalInc) * 100.0 : 0.0;

    // ચોથા અને પાંચમા ફોટા મુજબ આખા વર્ષની કરપાત્ર આવક અને ડિડક્શન (આખી એપમાંથી ઓટો-ફેચ)
    final taxData = _fetchComprehensiveTaxData(entireFY: true);
    final double fyGrossInc = taxData['grossIncome'] ?? 0.0;
    final double taxableNew = taxData['taxableNew'] ?? 0.0;
    final double slabTaxNew = taxData['slabTaxNew'] ?? 0.0;
    final double totalTaxNew = taxData['totalTaxNew'] ?? 0.0;

    final double taxableOld = taxData['taxableOld'] ?? 0.0;
    final double slabTaxOld = taxData['slabTaxOld'] ?? 0.0;
    final double totalTaxOld = taxData['totalTaxOld'] ?? 0.0;
    final double allowed80C = taxData['allowed80C'] ?? 0.0;
    final double allowed80D = taxData['allowed80D'] ?? 0.0;
    final double allowed80TTA = taxData['allowed80TTA'] ?? 0.0;
    final double extraDed = taxData['extraDeductions'] ?? 0.0;
    final double totalOldDed = taxData['totalOldDeductions'] ?? 0.0;

    final double stcg = taxData['stcg'] ?? 0.0;
    final double ltcg = taxData['ltcg'] ?? 0.0;
    final double cgTax = taxData['cgTax'] ?? 0.0;

    final String selectedRegime = settingsBox.get('selectedTaxRegime', defaultValue: 'new').toString(); // new, old, compare
    final String ageGroup = settingsBox.get('taxAgeGroup', defaultValue: 'regular').toString(); // regular, senior, super_senior
    final double activeTotalTax = selectedRegime == 'old' ? totalTaxOld : totalTaxNew;
    final double activeTaxableRegular = selectedRegime == 'old' ? taxableOld : taxableNew;

    final portfolioMetrics = _calculatePortfolioReturnMetrics();
    final double annualReturnPercent = portfolioMetrics['returnPercent'] ?? 0.0;
    final bool beatsInflation = annualReturnPercent >= benchmarkInflationRate;
    final double realReturn = annualReturnPercent - benchmarkInflationRate;

    // પસંદ કરેલ ડ્રોપડાઉન મેનુ મુજબ ડેટા તૈયાર કરો
    Map<String, double> breakdownMap = {};
    if (selectedAnalysisMetric == AnalysisMetric.combined) {
      breakdownMap = {
        'કુલ આવક': totalInc,
        'કુલ ખર્ચ': totalExp,
        'કુલ રોકાણ': totalInv,
        'ચોખ્ખી બચત': math.max(0.0, totalSavings),
        'કેપિટલ ગેઇન્સ (STCG+LTCG)': math.max(0.0, stcg + ltcg),
      };
    } else if (selectedAnalysisMetric == AnalysisMetric.income) {
      for (final tx in filteredTransactions.where((t) => t['categoryEffect'] == 'incomeCredit')) {
        final k = tx['categoryName'] ?? 'આવક';
        breakdownMap[k] = (breakdownMap[k] ?? 0.0) + (tx['amount'] as num).toDouble();
      }
    } else if (selectedAnalysisMetric == AnalysisMetric.expense) {
      for (final tx in filteredTransactions.where((t) => t['categoryEffect'] == 'expenseDebit' || t['categoryEffect'] == 'loanRepay')) {
        final k = tx['categoryName'] ?? 'ખર્ચ';
        breakdownMap[k] = (breakdownMap[k] ?? 0.0) + (tx['amount'] as num).toDouble();
      }
    } else if (selectedAnalysisMetric == AnalysisMetric.investment) {
      final pData = _fetchCompletePortfolioBreakdown();
      breakdownMap = {
        'ડાયરેક્ટ ઇક્વિટી (Stocks/ETF)': (pData['directEquityTotal'] as num).toDouble(),
        'મ્યુચ્યુઅલ ફંડ (MF/SIP)': (pData['mfTotalVal'] as num).toDouble(),
        'FD / બોન્ડ / PLI / PPF': (pData['fixedIncomeTotalVal'] as num).toDouble(),
        'સોનું અને ચાંદી': (pData['bullionTotalVal'] as num).toDouble(),
        'સ્થાવર મિલકત': (pData['physicalAssetsVal'] as num).toDouble(),
      };
    } else if (selectedAnalysisMetric == AnalysisMetric.taxableIncome) {
      breakdownMap = {
        'કરપાત્ર આવક (New Regime)': taxableNew,
        'કરપાત્ર આવક (Old Regime)': taxableOld,
        'Short-Term Gains (STCG)': math.max(0.0, stcg),
        'Long-Term Gains (LTCG)': math.max(0.0, ltcg),
        'અંદાજિત ટેક્સ (${selectedRegime == 'old' ? 'Old' : 'New'})': activeTotalTax,
      };
    }

    final entries = breakdownMap.entries.where((e) => e.value > 0).toList();
    final colors = [Colors.teal, Colors.blue, Colors.orange, Colors.purple, Colors.green, Colors.redAccent, Colors.amber.shade800];

    Widget analysisChart;
    if (entries.isEmpty) {
      analysisChart = const Center(child: Text('પસંદ કરેલ સમયગાળામાં કોઈ આંકડા નથી.', style: TextStyle(color: Colors.grey)));
    } else if (selectedChartType == ChartType.pie) {
      int idx = 0;
      analysisChart = PieChart(
        PieChartData(
          sections: entries.map((e) {
            final c = colors[idx++ % colors.length];
            return PieChartSectionData(
              value: e.value,
              title: '₹${e.value.toStringAsFixed(0)}',
              color: c,
              radius: 54,
              titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
            );
          }).toList(),
          centerSpaceRadius: 32,
        ),
      );
    } else if (selectedChartType == ChartType.bar) {
      final maxV = entries.map((e) => e.value).reduce(math.max);
      analysisChart = BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxV > 0 ? maxV * 1.25 : 1000,
          barGroups: List.generate(entries.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [BarChartRodData(toY: entries[i].value, color: colors[i % colors.length], width: 18, borderRadius: BorderRadius.circular(4))],
            );
          }),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) {
                  final i = val.toInt();
                  if (i < 0 || i >= entries.length) return const SizedBox();
                  final label = entries[i].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label.length > 8 ? '${label.substring(0, 8)}..' : label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      );
    } else {
      final spots = List.generate(entries.length, (i) => FlSpot(i.toDouble(), entries[i].value));
      analysisChart = LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots.length == 1 ? [const FlSpot(0, 0), FlSpot(1, spots.first.y)] : spots,
              isCurved: true,
              color: Colors.teal,
              barWidth: 3,
              belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.18)),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ડ્રોપડાઉન અને કસ્ટમ તારીખ પસંદગી કાર્ડ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.teal, size: 20),
                      const SizedBox(width: 6),
                      const Text('નાણાકીય વિશ્લેષણ પ્રકાર:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<AnalysisMetric>(
                          initialValue: selectedAnalysisMetric,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: AnalysisMetric.combined, child: Text('સંયુક્ત વિશ્લેષણ (Combined)', style: TextStyle(fontSize: 12.5))),
                            DropdownMenuItem(value: AnalysisMetric.income, child: Text('આવક વિશ્લેષણ (Income)', style: TextStyle(fontSize: 12.5))),
                            DropdownMenuItem(value: AnalysisMetric.expense, child: Text('ખર્ચ વિશ્લેષણ (Expense)', style: TextStyle(fontSize: 12.5))),
                            DropdownMenuItem(value: AnalysisMetric.investment, child: Text('ઇન્વેસ્ટમેન્ટ (Investment)', style: TextStyle(fontSize: 12.5))),
                            DropdownMenuItem(value: AnalysisMetric.taxableIncome, child: Text('કરપાત્ર આવક & STCG/LTCG', style: TextStyle(fontSize: 12.5))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => selectedAnalysisMetric = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (selectedFilter == TimeFilter.custom) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range, size: 16),
                            label: Text('શરૂઆત: ${DateFormat('dd/MM/yy').format(customStartDate)}', style: const TextStyle(fontSize: 11.5)),
                            onPressed: () async {
                              final d = await showDatePicker(context: context, initialDate: customStartDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                              if (d != null) setState(() => customStartDate = d);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event_available, size: 16),
                            label: Text('અંતિમ: ${DateFormat('dd/MM/yy').format(customEndDate)}', style: const TextStyle(fontSize: 11.5)),
                            onPressed: () async {
                              final d = await showDatePicker(context: context, initialDate: customEndDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                              if (d != null) setState(() => customEndDate = d);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // બચત, વાર્ષિક રિટર્ન અને ઇન્ફ્લેશન બીટ કાર્ડ
          Card(
            color: beatsInflation ? Colors.teal.shade50 : Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text('💰 બચત અને વાર્ષિક રિટર્ન vs મોંઘવારી (Inflation)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.black87)),
                      ),
                      InkWell(
                        onTap: () {
                          final ctrl = TextEditingController(text: benchmarkInflationRate.toStringAsFixed(1));
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('મોંઘવારી દર (Inflation Rate %) સેટ કરો'),
                              content: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'વાર્ષિક મોંઘવારી દર (%)'),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () {
                                    final v = double.tryParse(ctrl.text) ?? 6.0;
                                    settingsBox.put('inflationRate', v);
                                    setState(() => benchmarkInflationRate = v);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('સેવ'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text('મોંઘવારી: ${benchmarkInflationRate.toStringAsFixed(1)}% ✎', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _metricColumn('કુલ બચત (Savings)', '₹${totalSavings.toStringAsFixed(0)} (${savingsRate.toStringAsFixed(1)}%)', Colors.teal.shade900),
                      _metricColumn('પોર્ટફોલિયો રિટર્ન', '${annualReturnPercent.toStringAsFixed(2)}%', annualReturnPercent >= 0 ? Colors.green.shade800 : Colors.red),
                      _metricColumn('વાસ્તવિક રિટર્ન (Real)', '${realReturn >= 0 ? '+' : ''}${realReturn.toStringAsFixed(2)}%', beatsInflation ? Colors.green.shade900 : Colors.deepOrange),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: beatsInflation ? Colors.green.shade700 : Colors.deepOrange.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(beatsInflation ? Icons.verified : Icons.warning_amber_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            beatsInflation
                                ? '✅ અભિનંદન! તમારું રોકાણ રિટર્ન (${annualReturnPercent.toStringAsFixed(1)}%) મોંઘવારી (${benchmarkInflationRate.toStringAsFixed(1)}%) ને બીટ કરે છે!'
                                : '⚠️ તમારું હાલનું રિટર્ન (${annualReturnPercent.toStringAsFixed(1)}%) મોંઘવારી દર (${benchmarkInflationRate.toStringAsFixed(1)}%) કરતાં ઓછું છે.',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // =========================================================
          // ત્રીજા ફોટામાં જ દેખાતું કરપાત્ર આવક અને Capital Gains (STCG / LTCG) વિશ્લેષણ કાર્ડ
          // (ચોથા ફોટા: New Tax Regime FY 2026-27 અને પાંચમા ફોટા: Old Tax Regime + 80C/80D/Age Group મુજબ)
          // =========================================================
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '🧾 કરપાત્ર આવક અને Capital Gains (STCG / LTCG) વિશ્લેષણ',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                      Text(
                        'FY $selectedFinancialYearStart-${(selectedFinancialYearStart + 1).toString().substring(2)}',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // New vs Old Regime પસંદગી અને ઉંમર જૂથ
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedRegime,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'ટેક્સ રિજીમ (ફોટો ૪ & ૫)', isDense: true, border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'new', child: Text('New Tax Regime (FY 2026-27)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                            DropdownMenuItem(value: 'old', child: Text('Old Tax Regime (80C/80D સાથે)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              settingsBox.put('selectedTaxRegime', v);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: ageGroup,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'ઉંમર જૂથ (Age Group)', isDense: true, border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'regular', child: Text('સામાન્ય (< 60 વર્ષ)', style: TextStyle(fontSize: 11.5))),
                            DropdownMenuItem(value: 'senior', child: Text('સિનિયર (60-80 વર્ષ)', style: TextStyle(fontSize: 11.5))),
                            DropdownMenuItem(value: 'super_senior', child: Text('સુપર સિનિયર (80+ વર્ષ)', style: TextStyle(fontSize: 11.5))),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              settingsBox.put('taxAgeGroup', v);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  _taxSummaryRow('કુલ વાર્ષિક નિયમિત આવક (Gross Income):', '₹${fyGrossInc.toStringAsFixed(0)}', Colors.green.shade800, isBold: true),
                  const SizedBox(height: 4),
                  if (selectedRegime == 'new') ...[
                    _taxSummaryRow('બાદ: સ્ટાન્ડર્ડ ડિડક્શન (New Regime):', '- ₹75000', Colors.grey.shade700),
                    const SizedBox(height: 4),
                    _taxSummaryRow('નિયમિત કરપાત્ર આવક (સ્ટાન્ડર્ડ ડિડક્શન બાદ):', '₹${taxableNew.toStringAsFixed(0)}', Colors.black87, isBold: true),
                    if (taxableNew > 0 && taxableNew <= 1200000)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('✨ કલમ 87A રિબેટ લાગુ: ₹12,00,000 સુધીની કરપાત્ર આવક પર સ્લેબ ટેક્સ ₹0', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                  ] else ...[
                    _taxSummaryRow('બાદ: સ્ટાન્ડર્ડ ડિડક્શન (Old Regime):', '- ₹50000', Colors.grey.shade700),
                    _taxSummaryRow('બાદ: કલમ 80C રોકાણ (PLI/PPF/ELSS/FD ઓટો-ફેચ):', '- ₹${allowed80C.toStringAsFixed(0)}', Colors.teal.shade700),
                    _taxSummaryRow('બાદ: કલમ 80D (હેલ્થ વીમો) + 80TTA/TTB:', '- ₹${(allowed80D + allowed80TTA).toStringAsFixed(0)}', Colors.teal.shade700),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              final ctrl = TextEditingController(text: (settingsBox.get('extraOldRegimeDeductions', defaultValue: 0.0) as num).toStringAsFixed(0));
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('વધારાનું ડિડક્શન (HRA / LTA / 80E / હોમ લોન)'),
                                  content: TextField(
                                    controller: ctrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'રકમ (₹)'),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
                                    ElevatedButton(
                                      onPressed: () {
                                        settingsBox.put('extraOldRegimeDeductions', double.tryParse(ctrl.text) ?? 0.0);
                                        setState(() {});
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('સેવ કરો'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Text('બાદ: HRA / LTA / 80E / અન્ય ડિડક્શન ✎:', style: TextStyle(fontSize: 12, color: Colors.indigo, decoration: TextDecoration.underline)),
                          ),
                        ),
                        Text('- ₹${extraDed.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _taxSummaryRow('નિયમિત કરપાત્ર આવક (કુલ ₹${totalOldDed.toStringAsFixed(0)} બાદ):', '₹${taxableOld.toStringAsFixed(0)}', Colors.black87, isBold: true),
                    if (taxableOld > 0 && taxableOld <= 500000)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('✨ કલમ 87A રિબેટ લાગુ: ₹5,00,000 સુધીની કરપાત્ર આવક પર સ્લેબ ટેક્સ ₹0', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                  ],
                  const SizedBox(height: 4),
                  _taxSummaryRow('Short-Term Capital Gains (STCG @ 20%):', '₹${stcg.toStringAsFixed(0)}', Colors.indigo),
                  const SizedBox(height: 4),
                  _taxSummaryRow('Long-Term Capital Gains (LTCG @ 12.5% > ₹1.25L):', '₹${ltcg.toStringAsFixed(0)}', Colors.teal.shade800),
                  const Divider(),
                  _taxSummaryRow(
                    'કુલ અંદાજિત ટેક્સ જવાબદારી (4% સેસ સહિત):',
                    '₹${activeTotalTax.toStringAsFixed(0)}',
                    Colors.red.shade800,
                    isBold: true,
                  ),
                  const SizedBox(height: 8),
                  // New vs Old Regime સરખામણી બોક્સ
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('New Regime ટેક્સ: ₹${totalTaxNew.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                            Text('Old Regime ટેક્સ: ₹${totalTaxOld.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          totalTaxNew <= totalTaxOld
                              ? '💡 ભલામણ: તમારા માટે New Tax Regime માં ₹${(totalTaxOld - totalTaxNew).toStringAsFixed(0)} ટેક્સ બચે છે.'
                              : '💡 ભલામણ: તમારા માટે Old Tax Regime માં ₹${(totalTaxNew - totalTaxOld).toStringAsFixed(0)} ટેક્સ બચે છે.',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ચાર્ટ કાર્ડ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('📊 સંયુક્ત ચાર્ટ રજૂઆત:', style: TextStyle(fontWeight: FontWeight.bold)),
                      SegmentedButton<ChartType>(
                        segments: const [
                          ButtonSegment(value: ChartType.bar, icon: Icon(Icons.bar_chart, size: 15), label: Text('સ્તંભ', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: ChartType.pie, icon: Icon(Icons.pie_chart, size: 15), label: Text('વર્તુળ', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: ChartType.line, icon: Icon(Icons.show_chart, size: 15), label: Text('રૈખિક', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {selectedChartType},
                        onSelectionChanged: (s) => setState(() => selectedChartType = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(height: 185, child: analysisChart),
                  const Divider(),
                  ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12.5))),
                        Text('₹${e.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  Widget _metricColumn(String label, String val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: color)),
      ],
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

  // =========================================================
  // (૫) ઇન્વેસ્ટમેન્ટ પેજ (૫ પેટા-ટેબ્સ: MF/SIP, સ્ટોક/ETF, બોન્ડ/FD/PLI, કિંમતી ધાતુઓ, અન્ય મિલકત)
  // =========================================================
  Widget _buildInvestmentTab() {
    String invTitle = settingsBox.get('customInvTitle', defaultValue: 'ઇન્વેસ્ટમેન્ટ પોર્ટફોલિયો');

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(invTitle, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: "મ્યુચ્યુઅલ ફંડ & SIP", icon: Icon(Icons.pie_chart, size: 18)),
              Tab(text: "સ્ટોક & ETF", icon: Icon(Icons.candlestick_chart, size: 18)),
              Tab(text: "બોન્ડ / FD / PLI", icon: Icon(Icons.account_balance_wallet, size: 18)),
              Tab(text: "કિંમતી ધાતુઓ", icon: Icon(Icons.monetization_on, size: 18)),
              Tab(text: "અન્ય મિલકત", icon: Icon(Icons.home_work, size: 18)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMutualFundPortfolioTab(),
            _buildStockAndEtfPortfolioTab(),
            _buildBondsFdPliTab(),
            _buildBullionTab(),
            _buildAssetsTab(),
          ],
        ),
      ),
    );
  }

  // --- (૫-A) મ્યુચ્યુઅલ ફંડ અને SIP રોકાણ નોંધ (ઓટો NAV ફેચ + ઓટો/મેન્યુઅલ વિકલ્પ) ---
  Widget _buildMutualFundPortfolioTab() {
    final mfList = mfInvestmentsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double totalInv = 0.0;
    double currentVal = 0.0;
    for (final m in mfList) {
      final inv = (m['investedAmount'] as num?)?.toDouble() ?? 0.0;
      final units = (m['units'] as num?)?.toDouble() ?? 0.0;
      final curNav = (m['currentNav'] as num?)?.toDouble() ?? (m['buyNav'] as num?)?.toDouble() ?? 0.0;
      totalInv += inv;
      currentVal += units > 0 ? units * curNav : inv;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricColumn('કુલ MF રોકાણ', '₹${totalInv.toStringAsFixed(0)}', Colors.teal.shade900),
                  _metricColumn('હાલનું મૂલ્ય (NAV મુજબ)', '₹${currentVal.toStringAsFixed(0)}', Colors.blue.shade900),
                  _metricColumn('નફો / નુકસાન', '₹${(currentVal - totalInv).toStringAsFixed(0)}', currentVal >= totalInv ? Colors.green.shade800 : Colors.red),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('મારા મ્યુચ્યુઅલ ફંડ અને SIP:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('MF / SIP ઉમેરો'),
                onPressed: _openAddMutualFundDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (mfList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('કોઈ મ્યુચ્યુઅલ ફંડ કે SIP નોંધેલ નથી.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: mfList.length,
              itemBuilder: (ctx, i) {
                final m = mfList[i];
                final double units = (m['units'] as num?)?.toDouble() ?? 0.0;
                final double buyNav = (m['buyNav'] as num?)?.toDouble() ?? 0.0;
                final double curNav = (m['currentNav'] as num?)?.toDouble() ?? buyNav;
                final double inv = (m['investedAmount'] as num?)?.toDouble() ?? 0.0;
                final double val = units > 0 ? units * curNav : inv;
                final bool isSip = m['investmentMode'] == 'SIP';

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.withOpacity(0.15),
                      child: Text(isSip ? 'SIP' : 'MF', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ),
                    title: Text(m['schemeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    subtitle: Text(
                      'રોકાણ: ₹${inv.toStringAsFixed(0)} • યુનિટ્સ: ${units.toStringAsFixed(3)}\nખરીદ NAV: ₹$buyNav | હાલની NAV: ₹$curNav (${m['navMode'] == 'auto' ? 'ઓટો' : 'મેન્યુઅલ'})\nહાલનું મૂલ્ય: ₹${val.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => _openRedeemMutualFundDialog(m),
                          child: const Text('વેચો', style: TextStyle(fontSize: 11)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            mfInvestmentsBox.delete(m['id']);
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

  void _openAddMutualFundDialog() {
    final searchCtrl = TextEditingController();
    final schemeCtrl = TextEditingController();
    final navCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final sipDayCtrl = TextEditingController(text: '5');

    String navMode = 'auto'; // auto OR manual
    String investmentMode = 'SIP'; // SIP OR Lumpsum
    String executionMode = 'auto'; // auto OR manual
    String selectedAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    DateTime pickedDate = DateTime.now();
    bool isSearching = false;
    List<dynamic> searchResults = [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('મ્યુચ્યુઅલ ફંડ / SIP રોકાણ ઉમેરો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'auto', label: Text('ઓટો NAV ફેચ', style: TextStyle(fontSize: 11.5))),
                    ButtonSegment(value: 'manual', label: Text('મેન્યુઅલ NAV', style: TextStyle(fontSize: 11.5))),
                  ],
                  selected: {navMode},
                  onSelectionChanged: (s) => setDlgState(() => navMode = s.first),
                ),
                const SizedBox(height: 10),
                if (navMode == 'auto') ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'સ્કીમ સર્ચ કરો (દા.ત. HDFC, Parag Parikh)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () async {
                          if (searchCtrl.text.trim().isEmpty) return;
                          setDlgState(() => isSearching = true);
                          try {
                            final res = await http
                                .get(Uri.parse("https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(searchCtrl.text.trim())}"))
                                .timeout(const Duration(seconds: 7));
                            if (res.statusCode == 200) {
                              searchResults = (json.decode(res.body) as List).take(6).toList();
                            }
                          } catch (_) {}
                          setDlgState(() => isSearching = false);
                        },
                        child: const Text('શોધો'),
                      ),
                    ],
                  ),
                  if (isSearching) const LinearProgressIndicator(),
                  if (searchResults.isNotEmpty)
                    Container(
                      height: 120,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (c, idx) {
                          final item = searchResults[idx];
                          return ListTile(
                            dense: true,
                            title: Text(item['schemeName'].toString(), style: const TextStyle(fontSize: 11.5)),
                            onTap: () async {
                              schemeCtrl.text = item['schemeName'].toString();
                              final code = item['schemeCode'];
                              setDlgState(() {
                                searchResults = [];
                                isSearching = true;
                              });
                              try {
                                final dRes = await http
                                    .get(Uri.parse("https://api.mfapi.in/mf/$code"))
                                    .timeout(const Duration(seconds: 7));
                                if (dRes.statusCode == 200) {
                                  final dData = json.decode(dRes.body);
                                  final list = dData['data'] as List?;
                                  if (list != null && list.isNotEmpty) {
                                    navCtrl.text = list[0]['nav'].toString();
                                  }
                                }
                              } catch (_) {}
                              setDlgState(() => isSearching = false);
                            },
                          );
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                TextField(controller: schemeCtrl, decoration: const InputDecoration(labelText: 'મ્યુચ્યુઅલ ફંડ સ્કીમનું નામ')),
                TextField(
                  controller: navCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'NAV (₹)'),
                ),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'રોકાણ રકમ (₹)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: investmentMode,
                  decoration: const InputDecoration(labelText: 'રોકાણ પ્રકાર'),
                  items: const [
                    DropdownMenuItem(value: 'SIP', child: Text('માસિક SIP')),
                    DropdownMenuItem(value: 'Lumpsum', child: Text('વન-ટાઇમ (Lumpsum)')),
                  ],
                  onChanged: (v) => setDlgState(() => investmentMode = v!),
                ),
                if (investmentMode == 'SIP') ...[
                  TextField(
                    controller: sipDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'દર મહિનાની SIP તારીખ (1-28)'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: executionMode,
                    decoration: const InputDecoration(labelText: 'SIP કપાત મોડ (ઓટો / મેન્યુઅલ)'),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('ઓટોમેટિક ખાતામાંથી કપાત')),
                      DropdownMenuItem(value: 'manual', child: Text('મેન્યુઅલ (રીમાઇન્ડર પૂછીને)')),
                    ],
                    onChanged: (v) => setDlgState(() => executionMode = v!),
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: selectedAccId,
                  decoration: const InputDecoration(labelText: 'કપાત થનાર બેંક ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) => setDlgState(() => selectedAccId = v!),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('તારીખ: ${DateFormat('dd/MM/yyyy').format(pickedDate)}'),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: pickedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setDlgState(() => pickedDate = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amtCtrl.text) ?? 0.0;
                final nav = double.tryParse(navCtrl.text) ?? 100.0;
                if (amt <= 0 || schemeCtrl.text.trim().isEmpty) return;

                final units = nav > 0 ? amt / nav : 0.0;
                final id = "mf_${DateTime.now().millisecondsSinceEpoch}";

                mfInvestmentsBox.put(id, {
                  'id': id,
                  'schemeName': schemeCtrl.text.trim(),
                  'buyNav': nav,
                  'currentNav': nav,
                  'investedAmount': amt,
                  'units': units,
                  'navMode': navMode,
                  'investmentMode': investmentMode,
                  'executionMode': executionMode,
                  'accountId': selectedAccId,
                  'date': pickedDate.toIso8601String(),
                });

                final acc = accounts.firstWhere((a) => a['id'].toString() == selectedAccId, orElse: () => {'name': 'બેંક'});
                final txId = "tx_mf_${DateTime.now().millisecondsSinceEpoch}";
                transactionsBox.put(txId, {
                  'id': txId,
                  'title': "MF ${investmentMode}: ${schemeCtrl.text.trim()}",
                  'amount': amt,
                  'date': pickedDate.toIso8601String(),
                  'categoryId': '3',
                  'categoryName': 'શેરબજાર / મ્યુચ્યુઅલ ફંડ',
                  'categoryEffect': 'assetIncrease',
                  'categoryColor': Colors.blue.toARGB32(),
                  'accountId': selectedAccId,
                  'accountName': acc['name'],
                });

                if (investmentMode == 'SIP') {
                  final autoId = "auto_mf_${DateTime.now().millisecondsSinceEpoch}";
                  autoPayBox.put(autoId, {
                    'id': autoId,
                    'type': 'SIP',
                    'toTarget': schemeCtrl.text.trim(),
                    'amount': amt,
                    'day': int.tryParse(sipDayCtrl.text) ?? 5,
                    'fromAccountId': selectedAccId,
                    'executionMode': executionMode,
                    'isActive': true,
                    'lastProcessed': "${pickedDate.year}-${pickedDate.month}",
                  });
                }

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

  void _openRedeemMutualFundDialog(Map<dynamic, dynamic> mf) {
    final sellValCtrl = TextEditingController(text: mf['investedAmount'].toString());
    String depositAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    DateTime sellDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${mf['schemeName']} - રિડીમ / વેચાણ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: sellValCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'મળેલ કુલ વેચાણ રકમ (₹)')),
              DropdownButtonFormField<String>(
                initialValue: depositAccId,
                decoration: const InputDecoration(labelText: 'જમા થનાર બેંક ખાતું'),
                items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                onChanged: (v) => setDlgState(() => depositAccId = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellAmt = double.tryParse(sellValCtrl.text) ?? 0.0;
                final buyAmt = (mf['investedAmount'] as num?)?.toDouble() ?? 0.0;
                final buyDate = DateTime.tryParse(mf['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 100));

                _recordRealizedCapitalGain(
                  assetType: 'Mutual Fund',
                  title: mf['schemeName'] ?? '',
                  buyDate: buyDate,
                  sellDate: sellDate,
                  buyValue: buyAmt,
                  sellValue: sellAmt,
                );

                final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccId);
                final txId = "tx_mf_sell_${DateTime.now().millisecondsSinceEpoch}";
                transactionsBox.put(txId, {
                  'id': txId,
                  'title': "MF વેચાણ જમા: ${mf['schemeName']}",
                  'amount': sellAmt,
                  'date': sellDate.toIso8601String(),
                  'categoryId': '2',
                  'categoryName': 'પગાર / ધંધાકીય આવક',
                  'categoryEffect': 'incomeCredit',
                  'categoryColor': Colors.green.toARGB32(),
                  'accountId': depositAccId,
                  'accountName': acc['name'],
                });

                mfInvestmentsBox.delete(mf['id']);
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

  // --- (૫-B) સ્ટોક અને ETF રોકાણ નોંધ (દિવસ અને સમય પ્રમાણે એન્ટ્રી) ---
  Widget _buildStockAndEtfPortfolioTab() {
    final stockList = stockInvestmentsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double totalInv = 0.0;
    double currentVal = 0.0;

    for (final s in stockList) {
      final qty = (s['quantity'] as num?)?.toDouble() ?? 0.0;
      final buyP = (s['buyPrice'] as num?)?.toDouble() ?? 0.0;
      final curP = (s['currentPrice'] as num?)?.toDouble() ?? buyP;
      totalInv += qty * buyP;
      currentVal += qty * curP;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricColumn('કુલ સ્ટોક/ETF રોકાણ', '₹${totalInv.toStringAsFixed(0)}', Colors.blue.shade900),
                  _metricColumn('હાલનું બજાર મૂલ્ય', '₹${currentVal.toStringAsFixed(0)}', Colors.teal.shade900),
                  _metricColumn('કુલ નફો / નુકસાન', '₹${(currentVal - totalInv).toStringAsFixed(0)}', currentVal >= totalInv ? Colors.green.shade800 : Colors.red),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('મારા સ્ટોક અને ETF રોકાણો:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('સ્ટોક / ETF ઉમેરો'),
                onPressed: _openAddStockOrEtfDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (stockList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('કોઈ સ્ટોક કે ETF રોકાણ નોંધેલ નથી.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stockList.length,
              itemBuilder: (ctx, i) {
                final s = stockList[i];
                final dt = DateTime.tryParse(s['date'] ?? '') ?? DateTime.now();
                final qty = (s['quantity'] as num?)?.toDouble() ?? 0.0;
                final buyP = (s['buyPrice'] as num?)?.toDouble() ?? 0.0;
                final totalCost = qty * buyP;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.withOpacity(0.15),
                      child: Text(s['instrumentType'] ?? 'STK', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ),
                    title: Text("${s['symbol']} (${s['instrumentType']})", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      "Qty: $qty × ₹$buyP = ₹${totalCost.toStringAsFixed(0)}\nતારીખ: ${DateFormat('dd/MM/yyyy hh:mm a').format(dt)}",
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => _openSellStockOrEtfDialog(s),
                          child: const Text('વેચો', style: TextStyle(fontSize: 11)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            stockInvestmentsBox.delete(s['id']);
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

  void _openAddStockOrEtfDialog() {
    String instrumentType = 'Stock';
    final symbolCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final buyPriceCtrl = TextEditingController();
    String selectedAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    DateTime pickedDate = DateTime.now();
    TimeOfDay pickedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('સ્ટોક અથવા ETF રોકાણ નોંધો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: instrumentType,
                  decoration: const InputDecoration(labelText: 'પ્રકાર (Stock / ETF)'),
                  items: const [
                    DropdownMenuItem(value: 'Stock', child: Text('શેર (Equity Stock)')),
                    DropdownMenuItem(value: 'ETF', child: Text('ETF (Gold / Nifty / US ETF)')),
                  ],
                  onChanged: (v) => setDlgState(() => instrumentType = v!),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: symbolCtrl,
                        decoration: const InputDecoration(labelText: 'નામ / સિમ્બોલ (દા.ત. RELIANCE, NIFTYBEES)'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cloud_download, color: Colors.teal),
                      tooltip: 'લાઇવ ભાવ ફેચ કરો',
                      onPressed: () async {
                        final sym = symbolCtrl.text.trim().toUpperCase();
                        if (sym.isEmpty) return;
                        try {
                          final ticker = sym.endsWith('.NS') ? sym : '$sym.NS';
                          final res = await http
                              .get(Uri.parse("https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=1d&range=1d"))
                              .timeout(const Duration(seconds: 5));
                          if (res.statusCode == 200) {
                            final data = json.decode(res.body);
                            final p = (data['chart']?['result']?[0]?['meta']?['regularMarketPrice'] as num?)?.toDouble();
                            if (p != null && p > 0) {
                              setDlgState(() => buyPriceCtrl.text = p.toStringAsFixed(2));
                            }
                          }
                        } catch (_) {}
                      },
                    ),
                  ],
                ),
                TextField(controller: qtyCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'સંખ્યા (Quantity)')),
                TextField(controller: buyPriceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'ખરીદ ભાવ પ્રતિ યુનિટ (₹)')),
                DropdownButtonFormField<String>(
                  initialValue: selectedAccId,
                  decoration: const InputDecoration(labelText: 'કપાત થનાર ખાતું (Demat / Bank)'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) => setDlgState(() => selectedAccId = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: pickedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                          if (d != null) setDlgState(() => pickedDate = d);
                        },
                        child: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: pickedTime);
                          if (t != null) setDlgState(() => pickedTime = t);
                        },
                        child: Text(pickedTime.format(context)),
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
                final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
                final price = double.tryParse(buyPriceCtrl.text) ?? 0.0;
                if (qty <= 0 || price <= 0 || symbolCtrl.text.trim().isEmpty) return;

                final totalAmt = qty * price;
                final dt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
                final id = "stk_${DateTime.now().millisecondsSinceEpoch}";

                stockInvestmentsBox.put(id, {
                  'id': id,
                  'instrumentType': instrumentType,
                  'symbol': symbolCtrl.text.trim().toUpperCase(),
                  'quantity': qty,
                  'buyPrice': price,
                  'currentPrice': price,
                  'totalInvested': totalAmt,
                  'accountId': selectedAccId,
                  'date': dt.toIso8601String(),
                });

                final acc = accounts.firstWhere((a) => a['id'].toString() == selectedAccId);
                final txId = "tx_stk_${DateTime.now().millisecondsSinceEpoch}";
                transactionsBox.put(txId, {
                  'id': txId,
                  'title': "$instrumentType ખરીદી: ${symbolCtrl.text.trim().toUpperCase()} ($qty Qty)",
                  'amount': totalAmt,
                  'date': dt.toIso8601String(),
                  'hasTime': true,
                  'categoryId': '3',
                  'categoryName': 'શેરબજાર / મ્યુચ્યુઅલ ફંડ',
                  'categoryEffect': 'assetIncrease',
                  'categoryColor': Colors.blue.toARGB32(),
                  'accountId': selectedAccId,
                  'accountName': acc['name'],
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

  void _openSellStockOrEtfDialog(Map<dynamic, dynamic> stk) {
    final qty = (stk['quantity'] as num?)?.toDouble() ?? 1.0;
    final buyP = (stk['buyPrice'] as num?)?.toDouble() ?? 0.0;
    final sellPriceCtrl = TextEditingController(text: buyP.toString());
    String depositAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${stk['symbol']} - વેચાણ નોંધ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: sellPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'વેચાણ ભાવ પ્રતિ યુનિટ (₹)')),
              DropdownButtonFormField<String>(
                initialValue: depositAccId,
                decoration: const InputDecoration(labelText: 'જમા થનાર ખાતું'),
                items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                onChanged: (v) => setDlgState(() => depositAccId = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellP = double.tryParse(sellPriceCtrl.text) ?? buyP;
                final totalSell = qty * sellP;
                final totalBuy = qty * buyP;
                final buyDate = DateTime.tryParse(stk['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 90));

                _recordRealizedCapitalGain(
                  assetType: stk['instrumentType'] ?? 'Stock',
                  title: stk['symbol'] ?? '',
                  buyDate: buyDate,
                  sellDate: DateTime.now(),
                  buyValue: totalBuy,
                  sellValue: totalSell,
                );

                final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccId);
                final txId = "tx_stk_sell_${DateTime.now().millisecondsSinceEpoch}";
                transactionsBox.put(txId, {
                  'id': txId,
                  'title': "${stk['instrumentType']} વેચાણ: ${stk['symbol']}",
                  'amount': totalSell,
                  'date': DateTime.now().toIso8601String(),
                  'categoryId': '2',
                  'categoryName': 'પગાર / ધંધાકીય આવક',
                  'categoryEffect': 'incomeCredit',
                  'categoryColor': Colors.green.toARGB32(),
                  'accountId': depositAccId,
                  'accountName': acc['name'],
                });

                stockInvestmentsBox.delete(stk['id']);
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

  // --- (૫-C) બોન્ડ, FD, PLI અને અન્ય સ્કીમ ટેબ (તારીખ પ્રમાણે ખાતામાં આપોઆપ જમા/ઉધાર) ---
  Widget _buildBondsFdPliTab() {
    final list = fixedIncomeBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    double totalPrincipal = list.fold(0.0, (sum, i) => sum + ((i['principalAmount'] as num?)?.toDouble() ?? 0.0));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('કુલ FD / બોન્ડ / PLI રોકાણ: ₹${totalPrincipal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 14)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('નવી એન્ટ્રી'),
                onPressed: _openAddFixedIncomeDialog,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('કોઈ બોન્ડ, FD કે PLI ની નોંધ કરેલ નથી.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final item = list[i];
                final targetDate = DateTime.tryParse(item['scheduledDate'] ?? '') ?? DateTime.now();
                final isCredit = item['flowType'] == 'inflow_maturity';
                final acc = accounts.firstWhere((a) => a['id'].toString() == item['accountId'], orElse: () => {'name': 'ખાતું'});

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCredit ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                      child: Icon(isCredit ? Icons.call_received : Icons.call_made, color: isCredit ? Colors.green : Colors.orange, size: 18),
                    ),
                    title: Text("${item['schemeType']}: ${item['title']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      "રોકાણ: ₹${item['principalAmount']} • નિર્ધારિત રકમ: ₹${item['scheduledAmount']}\n${isCredit ? 'જમા થશે' : 'ચૂકવવાના'}: ${DateFormat('dd/MM/yyyy').format(targetDate)} (${acc['name']})\nસ્થિતિ: ${item['isSettled'] == true ? '✅ ખાતામાં એડજસ્ટ થયેલ' : '⏳ બાકી (ઓટો એડજસ્ટ)'}",
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item['isSettled'] != true)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: () {
                              item['scheduledDate'] = DateTime.now().toIso8601String();
                              item['autoAdjust'] = true;
                              fixedIncomeBox.put(item['id'], item);
                              _processFixedIncomeSchedules();
                              setState(() {});
                            },
                            child: const Text('અત્યારે એડજસ્ટ', style: TextStyle(fontSize: 10)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            fixedIncomeBox.delete(item['id']);
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

  void _openAddFixedIncomeDialog() {
    String schemeType = 'FD (ફિક્સ ડિપોઝિટ)';
    final titleCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    final scheduledAmtCtrl = TextEditingController();
    String flowType = 'inflow_maturity'; // inflow_maturity OR outflow_installment
    String selectedAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    DateTime startDate = DateTime.now();
    DateTime scheduledDate = DateTime.now().add(const Duration(days: 365));
    bool deductInitialNow = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('બોન્ડ / FD / PLI / સ્કીમ ઉમેરો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: schemeType,
                  decoration: const InputDecoration(labelText: 'પ્રકાર પસંદ કરો'),
                  items: ['FD (ફિક્સ ડિપોઝિટ)', 'બોન્ડ ( Sovereign / Corp Bond)', 'PLI (પોસ્ટલ લાઇફ ઇન્સ્યોરન્સ)', 'RD / પોસ્ટ ઓફિસ સ્કીમ', 'PPF / SSY / અન્ય']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12.5)))).toList(),
                  onChanged: (v) => setDlgState(() => schemeType = v!),
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'નામ / પોલિસી / FD વિગત')),
                TextField(controller: principalCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'રોકાણ / મૂળ રકમ (₹)')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: flowType,
                  decoration: const InputDecoration(labelText: 'નિર્ધારિત તારીખે વ્યવહારનો પ્રકાર'),
                  items: const [
                    DropdownMenuItem(value: 'inflow_maturity', child: Text('રૂપિયા ખાતામાં જમા થવાના છે (Maturity/Payout)', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'outflow_installment', child: Text('રૂપિયા ખાતામાંથી ચૂકવવાના છે (Installment/Pay)', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setDlgState(() => flowType = v!),
                ),
                TextField(controller: scheduledAmtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'નિર્ધારિત તારીખે જમા/ચૂકવવાની રકમ (₹)')),
                DropdownButtonFormField<String>(
                  initialValue: selectedAccId,
                  decoration: const InputDecoration(labelText: 'કયા બેંક ખાતામાં એડજસ્ટ કરવા?'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) => setDlgState(() => selectedAccId = v!),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: Text('નિર્ધારિત તારીખ: ${DateFormat('dd/MM/yyyy').format(scheduledDate)}'),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: scheduledDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setDlgState(() => scheduledDate = d);
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('શરૂઆતની મૂળ રકમ અત્યારે ખાતામાંથી બાદ કરવી છે?', style: TextStyle(fontSize: 12)),
                  value: deductInitialNow,
                  onChanged: (v) => setDlgState(() => deductInitialNow = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final pAmt = double.tryParse(principalCtrl.text) ?? 0.0;
                final sAmt = double.tryParse(scheduledAmtCtrl.text) ?? pAmt;
                if (pAmt <= 0 || titleCtrl.text.trim().isEmpty) return;

                final id = "fi_${DateTime.now().millisecondsSinceEpoch}";
                fixedIncomeBox.put(id, {
                  'id': id,
                  'schemeType': schemeType,
                  'title': titleCtrl.text.trim(),
                  'principalAmount': pAmt,
                  'scheduledAmount': sAmt,
                  'flowType': flowType,
                  'accountId': selectedAccId,
                  'startDate': startDate.toIso8601String(),
                  'scheduledDate': scheduledDate.toIso8601String(),
                  'autoAdjust': true,
                  'isSettled': false,
                });

                if (deductInitialNow) {
                  final acc = accounts.firstWhere((a) => a['id'].toString() == selectedAccId);
                  final txId = "tx_fi_${DateTime.now().millisecondsSinceEpoch}";
                  transactionsBox.put(txId, {
                    'id': txId,
                    'title': "$schemeType રોકાણ: ${titleCtrl.text.trim()}",
                    'amount': pAmt,
                    'date': startDate.toIso8601String(),
                    'categoryId': '7',
                    'categoryName': 'મિલકત / બોન્ડ / FD રોકાણ',
                    'categoryEffect': 'assetIncrease',
                    'categoryColor': Colors.teal.toARGB32(),
                    'accountId': selectedAccId,
                    'accountName': acc['name'],
                  });
                }

                _processFixedIncomeSchedules();
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

  // --- (૫-D) કિંમતી ધાતુઓ (Gold 24K, Gold 22K, Silver - વિસંગતતા સંપૂર્ણ દૂર) ---
  void _openAddBullionDialog({Map<dynamic, dynamic>? existingItem}) {
    final titleCtrl = TextEditingController(text: existingItem != null ? existingItem['title'] : '');
    final weightCtrl = TextEditingController(text: existingItem != null ? existingItem['weight'].toString() : '');
    final buyPriceCtrl = TextEditingController(text: existingItem != null ? existingItem['buyPrice'].toString() : '');
    String metalType = existingItem != null ? existingItem['metalType'] : 'સોનું 24K (Gold 24K)';
    String selectedAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    DateTime pickedDate = existingItem != null ? DateTime.parse(existingItem['date']) : DateTime.now();
    bool deductFromAccount = existingItem == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final rates = bullionCityRates[selectedCity] ?? {"gold24": 96500.0, "gold22": 88400.0, "silver": 112000.0};
          double currentPerGram = rates['gold24']! / 10.0;
          if (metalType.contains('22K')) {
            currentPerGram = rates['gold22']! / 10.0;
          } else if (metalType.contains('Silver') || metalType.contains('ચાંદી')) {
            currentPerGram = rates['silver']! / 1000.0;
          }

          void autoEstimatePrice() {
            final w = double.tryParse(weightCtrl.text) ?? 0.0;
            if (w > 0) {
              buyPriceCtrl.text = (w * currentPerGram).toStringAsFixed(0);
            }
          }

          return AlertDialog(
            title: Text(existingItem == null ? 'સોનું / ચાંદી રોકાણ ઉમેરો' : 'સોનું / ચાંદી સુધારો'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: metalType,
                    decoration: const InputDecoration(labelText: 'ધાતુ અને શુદ્ધતા પસંદ કરો'),
                    items: ['સોનું 24K (Gold 24K)', 'સોનું 22K (Gold 22K)', 'ચાંદી (Silver)'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) {
                      setDlgState(() {
                        metalType = v!;
                        autoEstimatePrice();
                      });
                    },
                  ),
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'વિગત (દા.ત. 10g લગડી / સિક્કો / દાગીના)')),
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
                          decoration: const InputDecoration(labelText: 'કુલ ખરીદ કિંમત (₹)'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calculate, color: Colors.teal),
                        tooltip: 'લાઇવ ભાવ મુજબ ગણતરી કરો',
                        onPressed: autoEstimatePrice,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    title: const Text('ખાતામાંથી રકમ બાદ કરી કુલ ઇન્વેસ્ટમેન્ટમાં ઉમેરવી?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: deductFromAccount,
                    onChanged: (v) => setDlgState(() => deductFromAccount = v),
                  ),
                  if (deductFromAccount)
                    DropdownButtonFormField<String>(
                      initialValue: selectedAccId,
                      decoration: const InputDecoration(labelText: 'ચુકવણી કરેલ બેંક / રોકડ ખાતું'),
                      items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                      onChanged: (v) => setDlgState(() => selectedAccId = v!),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
              ElevatedButton(
                onPressed: () {
                  final enteredPrice = double.tryParse(buyPriceCtrl.text) ?? 0.0;
                  final weight = double.tryParse(weightCtrl.text) ?? 0.0;
                  if (enteredPrice <= 0 || weight <= 0) return;

                  final id = existingItem != null ? existingItem['id'] : "bullion_${DateTime.now().millisecondsSinceEpoch}";

                  bullionInvestmentsBox.put(id, {
                    'id': id,
                    'metalType': metalType,
                    'title': titleCtrl.text.trim().isEmpty ? metalType : titleCtrl.text.trim(),
                    'weight': weight,
                    'buyPrice': enteredPrice,
                    'accountId': selectedAccId,
                    'date': pickedDate.toIso8601String(),
                  });

                  if (deductFromAccount && selectedAccId.isNotEmpty) {
                    final txId = "tx_bullion_${DateTime.now().millisecondsSinceEpoch}";
                    final acc = accounts.firstWhere((a) => a['id'].toString() == selectedAccId);
                    transactionsBox.put(txId, {
                      'id': txId,
                      'title': "ધાતુ ખરીદી: ${titleCtrl.text.trim().isEmpty ? metalType : titleCtrl.text.trim()} (${weight}g)",
                      'amount': enteredPrice,
                      'date': pickedDate.toIso8601String(),
                      'categoryId': '4',
                      'categoryName': 'સોનું / ચાંદી રોકાણ',
                      'categoryEffect': 'assetIncrease',
                      'categoryColor': Colors.amber.toARGB32(),
                      'accountId': selectedAccId,
                      'accountName': acc['name'],
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
    final sellPriceCtrl = TextEditingController(text: bullion['buyPrice'].toString());
    String depositAccountId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${bullion['title']} - વેચાણ નોંધ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: sellPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'કુલ વેચાણ કિંમત (₹)')),
              DropdownButtonFormField<String>(
                initialValue: depositAccountId,
                decoration: const InputDecoration(labelText: 'જમા થનાર ખાતું'),
                items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                onChanged: (v) => setDlgState(() => depositAccountId = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellPrice = double.tryParse(sellPriceCtrl.text) ?? 0.0;
                final buyPrice = (bullion['buyPrice'] as num?)?.toDouble() ?? 0.0;
                final buyDate = DateTime.tryParse(bullion['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 180));

                _recordRealizedCapitalGain(
                  assetType: 'Bullion (${bullion['metalType']})',
                  title: bullion['title'] ?? '',
                  buyDate: buyDate,
                  sellDate: DateTime.now(),
                  buyValue: buyPrice,
                  sellValue: sellPrice,
                );

                if (sellPrice > 0) {
                  final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccountId);
                  final txId = "tx_sell_bul_${DateTime.now().millisecondsSinceEpoch}";
                  transactionsBox.put(txId, {
                    'id': txId,
                    'title': "ધાતુ વેચાણ આવક: ${bullion['title']}",
                    'amount': sellPrice,
                    'date': DateTime.now().toIso8601String(),
                    'categoryId': '2',
                    'categoryName': 'પગાર / ધંધાકીય આવક',
                    'categoryEffect': 'incomeCredit',
                    'categoryColor': Colors.green.toARGB32(),
                    'accountId': depositAccountId,
                    'accountName': acc['name'],
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

  Widget _buildBullionTab() {
    final rates = bullionCityRates[selectedCity] ?? {"gold24": 96500.0, "gold22": 88400.0, "silver": 112000.0};
    final bullionList = bullionInvestmentsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    double totalBuyCost = 0.0;
    double totalLiveValue = 0.0;

    for (final b in bullionList) {
      final w = (b['weight'] as num?)?.toDouble() ?? 0.0;
      final buyP = (b['buyPrice'] as num?)?.toDouble() ?? 0.0;
      final mType = (b['metalType'] ?? '').toString();
      double perGram = rates['gold24']! / 10.0;
      if (mType.contains('22K')) {
        perGram = rates['gold22']! / 10.0;
      } else if (mType.contains('Silver') || mType.contains('ચાંદી')) {
        perGram = rates['silver']! / 1000.0;
      }
      totalBuyCost += buyP;
      totalLiveValue += w * perGram;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("શહેર પ્રમાણે લાઇવ બજાર ભાવ:", style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(bullionLastUpdated, style: const TextStyle(fontSize: 11, color: Colors.teal)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.teal),
                        onPressed: () => _fetchLiveBullionRates(showToast: true),
                      ),
                    ],
                  ),
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
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        const Text("સોનું 24K (10g)", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("₹${rates['gold24']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.brown)),
                        const Divider(height: 10),
                        Text("22K (10g): ₹${rates['gold22']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.brown)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  color: Colors.blueGrey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        const Text("ચાંદી (1 Kg)", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("₹${rates['silver']!.toStringAsFixed(0)}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const Divider(height: 10),
                        Text("1g: ₹${(rates['silver']! / 1000).toStringAsFixed(1)}", style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricColumn('ખરીદ કિંમત', '₹${totalBuyCost.toStringAsFixed(0)}', Colors.black87),
                  _metricColumn('લાઇવ મૂલ્ય', '₹${totalLiveValue.toStringAsFixed(0)}', Colors.teal.shade900),
                  _metricColumn('નફો / તફાવત', '₹${(totalLiveValue - totalBuyCost).toStringAsFixed(0)}', totalLiveValue >= totalBuyCost ? Colors.green.shade800 : Colors.red),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("મારું સોનું / ચાંદી રોકાણ:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('રોકાણ ઉમેરો'),
                onPressed: () => _openAddBullionDialog(),
              ),
            ],
          ),
          if (bullionList.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("કોઈ સોનું કે ચાંદીનું રોકાણ નોંધેલ નથી.")))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bullionList.length,
              itemBuilder: (ctx, i) {
                final b = bullionList[i];
                final w = (b['weight'] as num?)?.toDouble() ?? 0.0;
                final buyP = (b['buyPrice'] as num?)?.toDouble() ?? 0.0;
                final mType = (b['metalType'] ?? '').toString();
                double perGram = rates['gold24']! / 10.0;
                if (mType.contains('22K')) {
                  perGram = rates['gold22']! / 10.0;
                } else if (mType.contains('Silver') || mType.contains('ચાંદી')) {
                  perGram = rates['silver']! / 1000.0;
                }
                final liveVal = w * perGram;

                return Card(
                  child: ListTile(
                    leading: Icon(Icons.monetization_on, color: mType.contains('Gold') || mType.contains('સોનું') ? Colors.amber.shade800 : Colors.blueGrey),
                    title: Text("${b['title']} (${b['weight']}g)", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("$mType\nખરીદ: ₹${buyP.toStringAsFixed(0)} | હાલનું મૂલ્ય: ₹${liveVal.toStringAsFixed(0)}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.teal), onPressed: () => _openAddBullionDialog(existingItem: b)),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => _openSellBullionDialog(b),
                          child: const Text('વેચો', style: TextStyle(fontSize: 11)),
                        ),
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

  // --- (૫-E) અન્ય મિલકત (Physical Assets) ---
  void _openAddPhysicalAssetDialog({Map<dynamic, dynamic>? existingAsset}) {
    final titleCtrl = TextEditingController(text: existingAsset != null ? existingAsset['title'] : '');
    final valueCtrl = TextEditingController(text: existingAsset != null ? existingAsset['value'].toString() : '');
    final locCtrl = TextEditingController(text: existingAsset != null ? existingAsset['location'] : '');
    String type = existingAsset != null ? existingAsset['type'] : 'મકાન/ફ્લેટ';
    String selectedAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    bool deductFromAcc = existingAsset == null;

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
                      .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDlgState(() => type = v!),
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'નામ / વિગત')),
                TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'સ્થળ / શહેર')),
                TextField(controller: valueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'કુલ કિંમત (₹)')),
                SwitchListTile(
                  dense: true,
                  title: const Text('ખાતામાંથી રકમ બાદ કરી રોકાણમાં ઉમેરવી?', style: TextStyle(fontSize: 12)),
                  value: deductFromAcc,
                  onChanged: (v) => setDlgState(() => deductFromAcc = v),
                ),
                if (deductFromAcc)
                  DropdownButtonFormField<String>(
                    initialValue: selectedAccId,
                    decoration: const InputDecoration(labelText: 'બેંક ખાતું'),
                    items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                    onChanged: (v) => setDlgState(() => selectedAccId = v!),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(valueCtrl.text) ?? 0.0;
                if (val <= 0 || titleCtrl.text.isEmpty) return;
                final id = existingAsset != null ? existingAsset['id'] : "asset_${DateTime.now().millisecondsSinceEpoch}";

                physicalAssetsBox.put(id, {
                  'id': id,
                  'title': titleCtrl.text,
                  'type': type,
                  'location': locCtrl.text,
                  'value': val,
                  'date': DateTime.now().toIso8601String(),
                });

                if (deductFromAcc) {
                  final acc = accounts.firstWhere((a) => a['id'].toString() == selectedAccId);
                  final txId = "tx_asset_${DateTime.now().millisecondsSinceEpoch}";
                  transactionsBox.put(txId, {
                    'id': txId,
                    'title': "મિલકત ખરીદી: ${titleCtrl.text}",
                    'amount': val,
                    'date': DateTime.now().toIso8601String(),
                    'categoryId': '7',
                    'categoryName': 'મિલકત / બોન્ડ / FD રોકાણ',
                    'categoryEffect': 'assetIncrease',
                    'categoryColor': Colors.teal.toARGB32(),
                    'accountId': selectedAccId,
                    'accountName': acc['name'],
                  });
                }

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
    String depositAccountId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${asset['title']} - વેચાણ નોંધ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: sellPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'કુલ વેચાણ કિંમત (₹)')),
              DropdownButtonFormField<String>(
                initialValue: depositAccountId,
                decoration: const InputDecoration(labelText: 'જમા થનાર ખાતું'),
                items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                onChanged: (v) => setDlgState(() => depositAccountId = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellPrice = double.tryParse(sellPriceCtrl.text) ?? 0.0;
                final buyPrice = (asset['value'] as num?)?.toDouble() ?? 0.0;
                final buyDate = DateTime.tryParse(asset['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 800));

                _recordRealizedCapitalGain(
                  assetType: 'Physical Asset (${asset['type']})',
                  title: asset['title'] ?? '',
                  buyDate: buyDate,
                  sellDate: DateTime.now(),
                  buyValue: buyPrice,
                  sellValue: sellPrice,
                );

                final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccountId);
                final txId = "tx_sell_asset_${DateTime.now().millisecondsSinceEpoch}";
                transactionsBox.put(txId, {
                  'id': txId,
                  'title': "મિલકત વેચાણ: ${asset['title']}",
                  'amount': sellPrice,
                  'date': DateTime.now().toIso8601String(),
                  'categoryId': '2',
                  'categoryName': 'પગાર / ધંધાકીય આવક',
                  'categoryEffect': 'incomeCredit',
                  'categoryColor': Colors.green.toARGB32(),
                  'accountId': depositAccountId,
                  'accountName': acc['name'],
                });

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
              Text("કુલ સ્થાવર સંપત્તિ: ₹${totalVal.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
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
                        leading: const Icon(Icons.home_work, color: Colors.teal),
                        title: Text(a['title']),
                        subtitle: Text("${a['type']} • ${a['location']}\nકિંમત: ₹${a['value']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                              onPressed: () => _openSellPhysicalAssetDialog(a),
                              child: const Text('વેચો', style: TextStyle(fontSize: 11)),
                            ),
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

  // --- સેટિંગ્સ ડાયલોગ (બેકઅપ/રિસ્ટોર, ઓટો-લોક સમય, ક્રેડિટ કાર્ડ ઓટો બિલ વગેરે) ---
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
                leading: const Icon(Icons.backup, color: Colors.teal),
                title: const Text('ઇન્ટરનલ મેમરીમાં બેકઅપ અને રિસ્ટોર', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('ફોનમાં બેકઅપ લો અથવા જૂના બેકઅપમાંથી ડેટા રિસ્ટોર કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBackupAndRestoreDialog();
                },
              ),
              StatefulBuilder(
                builder: (ctx, setCcState) {
                  bool autoCc = isAutoCcBillEnabled;
                  return SwitchListTile(
                    secondary: const Icon(Icons.credit_card, color: Colors.deepOrange),
                    title: const Text('દૈનિક વ્યવહારમાંથી ઓટો ક્રેડિટ કાર્ડ બિલ'),
                    subtitle: const Text('ON રાખશો તો જ દૈનિક નોંધમાંથી ક્રેડિટ કાર્ડનું બિલ ઓટો જનરેટ થશે'),
                    value: autoCc,
                    onChanged: (val) {
                      settingsBox.put('autoGenerateCcBill', val);
                      setCcState(() => autoCc = val);
                      setState(() {});
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_clock, color: Colors.indigo),
                title: const Text('બેકગ્રાઉન્ડ ઓટો-લોક સમયગાળો'),
                subtitle: Text('હાલનો સમય: ${SecurityService.getAutoLockTimeoutSeconds()} સેકન્ડ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAutoLockTimeoutDialog();
                },
              ),
              StatefulBuilder(
                builder: (ctx, setBioState) {
                  bool isBioEnabled = SecurityService.isBiometricEnabledInSettings();
                  return SwitchListTile(
                    secondary: const Icon(Icons.fingerprint, color: Colors.teal),
                    title: const Text('ફિંગરપ્રિન્ટ / બાયોમેટ્રિક અનલોક'),
                    subtitle: Text(isBioEnabled ? 'સક્રિય (પાસવર્ડ + ફિંગરપ્રિન્ટ)' : 'માત્ર માસ્ટર પાસવર્ડથી અનલોક'),
                    value: isBioEnabled,
                    onChanged: (bool newValue) async {
                      await SecurityService.setBiometricEnabled(newValue);
                      setBioState(() => isBioEnabled = newValue);
                      setState(() {});
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.autorenew, color: Colors.indigo),
                title: const Text('EMI / ક્રેડિટ કાર્ડ / વીમા (PLI, Health, Term) મેનેજર'),
                subtitle: const Text('ક્રેડિટ કાર્ડ બિલિંગ ડેટ, પ્રીમિયમ અને ઓટો-પે સેટિંગ્સ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAutoPayManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance, color: Colors.green),
                title: const Text('બેંક અને ક્રેડિટ કાર્ડ ખાતાઓ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAccountManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category, color: Colors.orange),
                title: const Text('કેટેગરી મેનેજર (Add / Edit / Delete)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCategoryManager();
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
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('સંપૂર્ણ હિસાબ એક્સપોર્ટ (PDF)'),
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

  void _openAutoLockTimeoutDialog() {
    final options = [0, 10, 15, 30, 60, 120];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('બેકગ્રાઉન્ડ ઓટો-લોક સમય પસંદ કરો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((sec) {
            return ListTile(
              title: Text(sec == 0 ? 'તરત જ (0 સેકન્ડ)' : '$sec સેકન્ડ પછી'),
              trailing: SecurityService.getAutoLockTimeoutSeconds() == sec ? const Icon(Icons.check, color: Colors.teal) : null,
              onTap: () async {
                await SecurityService.setAutoLockTimeoutSeconds(sec);
                setState(() {});
                if (context.mounted) Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- (૩) વિસ્તૃત EMI / ક્રેડિટ કાર્ડ / વીમા પ્રીમિયમ (PLI, Health, Term, Vehicle) મેનેજર ---
  void _openAutoPayManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final list = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
          return AlertDialog(
            title: const Text('EMI / ક્રેડિટ કાર્ડ / વીમા મેનેજર'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: list.isEmpty
                  ? const Center(child: Text('કોઈ EMI, ક્રેડિટ કાર્ડ કે વીમા પ્રીમિયમ સેટ કરેલ નથી.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final a = list[i];
                        final isAuto = (a['executionMode'] ?? 'auto') == 'auto';
                        final isCc = a['type'] == 'CreditCard';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              isCc ? Icons.credit_card : Icons.security,
                              color: isAuto ? Colors.teal : Colors.orange,
                            ),
                            title: Text("${a['type']}: ${a['toTarget'] ?? ''} (₹${(a['amount'] as num).toStringAsFixed(0)})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(
                              isCc
                                  ? "બિલિંગ તારીખ: ${a['billingDay'] ?? 1} | ડ્યુ તારીખ: ${a['day']} • [${a['autoGenerateFromDaily'] == true ? 'દૈનિકમાંથી ઓટો બિલ' : 'ફિક્સ'}]"
                                  : "ચુકવણી તારીખ: ${a['day']} • [${isAuto ? 'ઓટો-કપાત' : 'મેન્યુઅલ રીમાઇન્ડર'}]",
                              style: const TextStyle(fontSize: 11.5),
                            ),
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
    final amtCtrl = TextEditingController(text: existingItem != null ? existingItem['amount'].toString() : '0');
    final dayCtrl = TextEditingController(text: existingItem != null ? existingItem['day'].toString() : '5');
    final billingDayCtrl = TextEditingController(text: existingItem != null ? (existingItem['billingDay']?.toString() ?? '1') : '1');

    String type = existingItem != null ? existingItem['type'] : 'CreditCard';
    String mode = existingItem != null ? (existingItem['executionMode'] ?? 'auto') : 'auto';
    bool autoGenFromDaily = existingItem != null ? (existingItem['autoGenerateFromDaily'] == true) : isAutoCcBillEnabled;

    String fromAccId = existingItem != null
        ? existingItem['fromAccountId']
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');
    String ccAccId = existingItem != null && existingItem['ccAccountId'] != null
        ? existingItem['ccAccountId']
        : (accounts.firstWhere((a) => a['type'].toString().contains('Credit'), orElse: () => accounts.first)['id'].toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingItem == null ? 'નવું EMI / કાર્ડ / વીમો ઉમેરો' : 'સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'પ્રકાર પસંદ કરો'),
                  items: const [
                    DropdownMenuItem(value: 'CreditCard', child: Text('ક્રેડિટ કાર્ડ બિલ (Credit Card)')),
                    DropdownMenuItem(value: 'EMI', child: Text('લોન EMI હપ્તો')),
                    DropdownMenuItem(value: 'SIP', child: Text('મ્યુચ્યુઅલ ફંડ / શેર SIP')),
                    DropdownMenuItem(value: 'PLI', child: Text('PLI / LIC પ્રીમિયમ')),
                    DropdownMenuItem(value: 'HealthInsurance', child: Text('હેલ્થ વીમો (Health Insurance)')),
                    DropdownMenuItem(value: 'TermInsurance', child: Text('ટર્મ ઇન્સ્યોરન્સ (Term Plan)')),
                    DropdownMenuItem(value: 'VehicleInsurance', child: Text('વાહન વીમો (Vehicle Insurance)')),
                    DropdownMenuItem(value: 'GovScheme', child: Text('અન્ય સ્કીમ (PPF / SSY / બચત)')),
                    DropdownMenuItem(value: 'AutoPay', child: Text('અન્ય ઓટો-પે બિલ')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => type = v);
                  },
                ),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'નામ / વિગત (દા.ત. HDFC CC, PLI પોલિસી, કાર વીમો)')),
                if (type == 'CreditCard') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: ccAccId,
                    decoration: const InputDecoration(labelText: 'કયું ક્રેડિટ કાર્ડ ખાતું?'),
                    items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                    onChanged: (v) => setDlgState(() => ccAccId = v!),
                  ),
                  TextField(
                    controller: billingDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ક્રેડિટ કાર્ડ બિલ બનવાની તારીખ (Billing Date 1-28)'),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('દૈનિક નોંધમાંથી ક્રેડિટ કાર્ડ બિલ ઓટો જનરેટ કરો', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: const Text('જો ON હશે તો જ દૈનિક વ્યવહારોમાંથી બિલ બનશે', style: TextStyle(fontSize: 11)),
                    value: autoGenFromDaily,
                    onChanged: (val) => setDlgState(() => autoGenFromDaily = val),
                  ),
                ],
                TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'રકમ / પ્રીમિયમ (₹)')),
                TextField(controller: dayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ચુકવણી / કપાત તારીખ (Due Date 1-28)')),
                DropdownButtonFormField<String>(
                  initialValue: fromAccId,
                  decoration: const InputDecoration(labelText: 'ચુકવણી થનાર બેંક ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) {
                    if (v != null) fromAccId = v;
                  },
                ),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  dense: true,
                  title: const Text('ઓટો-પે (તારીખે આપોઆપ ખાતામાંથી કપાત)', style: TextStyle(fontSize: 12)),
                  value: 'auto',
                  groupValue: mode,
                  onChanged: (val) => setDlgState(() => mode = val!),
                ),
                RadioListTile<String>(
                  dense: true,
                  title: const Text('મેન્યુઅલ (ડેશબોર્ડ પર રીમાઇન્ડર આપે)', style: TextStyle(fontSize: 12)),
                  value: 'manual',
                  groupValue: mode,
                  onChanged: (val) => setDlgState(() => mode = val!),
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
                  'toTarget': targetCtrl.text.trim(),
                  'amount': double.tryParse(amtCtrl.text) ?? 0.0,
                  'day': int.tryParse(dayCtrl.text) ?? 5,
                  'billingDay': int.tryParse(billingDayCtrl.text) ?? 1,
                  'ccAccountId': ccAccId,
                  'autoGenerateFromDaily': autoGenFromDaily,
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

  void _openCategoryManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('કેટેગરી મેનેજર'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                return ListTile(
                  dense: true,
                  title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () {
                      categoriesBox.delete(cat['id']);
                      setDlgState(() {});
                      setState(() {});
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
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
            height: 360,
            child: ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final a = accounts[i];
                final currentBal = getAccountCurrentBalance(a['id'].toString());
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(a['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${a['type']}\nહાલની સિલક: ₹${currentBal.toStringAsFixed(0)}'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
          ],
        ),
      ),
    );
  }

  void _openCategoryBudgetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$budgetPeriod બજેટ લક્ષ્યાંક ગોઠવો'),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
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
                  width: 95,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '₹ 0', isDense: true, border: OutlineInputBorder()),
                    onChanged: (val) => budgetBox.put(budgetKey, double.tryParse(val) ?? 0.0),
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
    );
  }

  // --- ટેબ ૧: દૈનિક એન્ટ્રી અને રીમાઇન્ડર ---
  Widget _buildTransactionsTab() {
    final pendingReminders = pendingManualReminders;

    return Column(
      children: [
        if (pendingReminders.isNotEmpty)
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
                    Icon(Icons.notifications_active, color: Colors.amber.shade900, size: 18),
                    const SizedBox(width: 8),
                    Text("બાકી હપ્તા / બિલ રીમાઇન્ડર (${pendingReminders.length})", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
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
                          "${rem['type']}: ${rem['toTarget']} - ₹${(rem['amount'] as num).toStringAsFixed(0)} (${rem['day']} તારીખ)",
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
        _buildNotebookStyleChart(),
        Expanded(
          child: filteredTransactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long, size: 42, color: Colors.grey),
                      const SizedBox(height: 6),
                      const Text('આ સમયગાળામાં કોઈ વ્યવહાર મળ્યો નથી.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('પ્રથમ વ્યવહાર ઉમેરો'),
                        onPressed: () => _openTransactionDialog(),
                      ),
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
                    final dt = DateTime.parse(tx['date']);
                    final timeStr = tx['hasTime'] == true ? DateFormat(' hh:mm a').format(dt) : '';

                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: amountColor.withOpacity(0.15),
                          child: Icon(isIncome ? Icons.arrow_downward : (isExpense ? Icons.arrow_upward : Icons.trending_up), color: amountColor, size: 18),
                        ),
                        title: Text(tx['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        subtitle: Text('${tx['categoryName']} • ${tx['accountName'] ?? ''}\n${DateFormat('dd MMM yyyy').format(dt)}$timeStr', style: const TextStyle(fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('₹${(tx['amount'] as num).toStringAsFixed(0)}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: amountColor)),
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

    // (૨) સુધારેલી બેકગ્રાઉન્ડ અનલૉક સ્ક્રીન (માસ્ટર પાસવર્ડ + ફિંગરપ્રિન્ટ બંને વિકલ્પ)
    if (_isAppLocked) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_person, size: 68, color: Colors.teal),
                    const SizedBox(height: 12),
                    const Text('નાણાકીય વૉલ્ટ સુરક્ષિત રીતે લૉક છે', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(widget.userEmail, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _unlockPasswordCtrl,
                      obscureText: _obscureUnlockPwd,
                      onSubmitted: (_) => _unlockWithMasterPassword(),
                      decoration: InputDecoration(
                        labelText: 'માસ્ટર પાસવર્ડ નાખો',
                        prefixIcon: const Icon(Icons.password, color: Colors.teal),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureUnlockPwd ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureUnlockPwd = !_obscureUnlockPwd),
                        ),
                        errorText: _unlockErrorMsg.isEmpty ? null : _unlockErrorMsg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _unlockWithMasterPassword,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('પાસવર્ડથી અનલૉક કરો', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          side: const BorderSide(color: Colors.teal, width: 1.4),
                        ),
                        onPressed: _triggerBiometricUnlock,
                        icon: const Icon(Icons.fingerprint, color: Colors.teal),
                        label: const Text('ફિંગરપ્રિન્ટ / ફોન PIN વડે અનલૉક કરો', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
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
            Text(appTitle, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
            Text(widget.userEmail, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup, color: Colors.teal),
            tooltip: 'બેકઅપ અને રિસ્ટોર',
            onPressed: _openBackupAndRestoreDialog,
          ),
          IconButton(
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.teal,
              child: const Icon(Icons.currency_rupee, color: Colors.white, size: 17),
            ),
            tooltip: 'સંપૂર્ણ રોકાણ, બચત, રિસ્ક અને સ્ટ્રેટેજી વિશ્લેષણ',
            onPressed: _openAnnualTaxAndExpenseDialog,
          ),
          IconButton(icon: const Icon(Icons.settings), tooltip: 'સેટિંગ્સ', onPressed: _openSettingsDialog),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'અત્યારે લૉક કરો',
            onPressed: () => setState(() => _isAppLocked = true),
          ),
        ],
      ),
      floatingActionButton: _selectedTabIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              onPressed: () => _openTransactionDialog(),
              icon: const Icon(Icons.add),
              label: const Text('હિસાબ નોંધો'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'દૈનિક એન્ટ્રી'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'નાણાકીય વિશ્લેષણ'),
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
                      DropdownMenuItem(value: TimeFilter.daily, child: Text('દૈનિક')),
                      DropdownMenuItem(value: TimeFilter.monthly, child: Text('માસિક')),
                      DropdownMenuItem(value: TimeFilter.quarterly, child: Text('ત્રિમાસિક')),
                      DropdownMenuItem(value: TimeFilter.halfYearly, child: Text('છ માસિક')),
                      DropdownMenuItem(value: TimeFilter.yearly, child: Text('વાર્ષિક')),
                      DropdownMenuItem(value: TimeFilter.allFY, child: Text('આખું FY')),
                      DropdownMenuItem(value: TimeFilter.custom, child: Text('ચોક્કસ તારીખ')),
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
