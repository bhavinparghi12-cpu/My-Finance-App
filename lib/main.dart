import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
final ValueNotifier<String> appLanguage = ValueNotifier<String>('gu'); // 'gu' = ગુજરાતી, 'en' = English

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

    final dynamic rawLang = settings.get('appLanguage', defaultValue: 'gu');
    if (rawLang is String && (rawLang == 'gu' || rawLang == 'en')) {
      appLanguage.value = rawLang;
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
    return ValueListenableBuilder<String>(
      valueListenable: appLanguage,
      builder: (context, currentLang, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeMode,
          builder: (context, currentMode, _) {
            return ValueListenableBuilder<Color>(
              valueListenable: appSeedColor,
              builder: (context, primaryColor, _) {
            final lightScheme = ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.light,
            );
            final darkScheme = ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.dark,
            );
            return MaterialApp(
              title: currentLang == 'en' ? 'Finance Manager' : 'નાણાકીય મેનેજર',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorScheme: lightScheme,
                scaffoldBackgroundColor: Colors.grey.shade100,
                cardTheme: const CardThemeData(color: Colors.white, elevation: 1.5),
                appBarTheme: AppBarTheme(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 0.5,
                  iconTheme: IconThemeData(color: primaryColor),
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: darkScheme,
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardTheme: const CardThemeData(color: Color(0xFF1E1E1E), elevation: 2),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  elevation: 0.5,
                ),
                textTheme: const TextTheme(
                  displayLarge: TextStyle(color: Colors.white),
                  displayMedium: TextStyle(color: Colors.white),
                  displaySmall: TextStyle(color: Colors.white),
                  headlineLarge: TextStyle(color: Colors.white),
                  headlineMedium: TextStyle(color: Colors.white),
                  headlineSmall: TextStyle(color: Colors.white),
                  bodyLarge: TextStyle(color: Colors.white),
                  bodyMedium: TextStyle(color: Colors.white),
                  bodySmall: TextStyle(color: Colors.white70),
                  titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  titleMedium: TextStyle(color: Colors.white),
                  titleSmall: TextStyle(color: Colors.white70),
                  labelLarge: TextStyle(color: Colors.white),
                  labelMedium: TextStyle(color: Colors.white70),
                  labelSmall: TextStyle(color: Colors.white60),
                ),
                iconTheme: const IconThemeData(color: Colors.white70),
                listTileTheme: const ListTileThemeData(
                  textColor: Colors.white,
                  iconColor: Colors.white70,
                ),
                inputDecorationTheme: const InputDecorationTheme(
                  labelStyle: TextStyle(color: Colors.white70),
                  hintStyle: TextStyle(color: Colors.white54),
                ),
                dialogTheme: const DialogThemeData(
                  backgroundColor: Color(0xFF1E1E1E),
                  titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  contentTextStyle: TextStyle(color: Colors.white),
                ),
                bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF1E1E1E)),
              ),
              home: const AuthGate(),
            );
          },
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
  late Box goalsBox;

  bool _isInitialized = false;

  // રિંગટોન સ્ટોપ, સ્નૂઝ, સોર્ટિંગ અને વોઇસ કમાન્ડ સ્ટેટ્સ
  bool _isRingtonePlaying = false;
  final Map<String, Timer> _snoozeTimers = {};
  String _txSortMode = 'date_desc'; // date_desc, date_asc, amount_desc, amount_asc
  bool _isListeningVoice = false;
  String _lastVoiceTranscript = '';
  String _voiceStatusText = '';

  // ભાષા હેલ્પર્સ (ગુજરાતી / English)
  bool get isEn => appLanguage.value == 'en';
  String _t(String gu, String en) => isEn ? en : gu;

  // બેકગ્રાઉન્ડ ઓટો-લોક અને પાસવર્ડ + બાયોમેટ્રિક અનલોક સ્ટેટ્સ
  bool _isAppLocked = false;
  bool _isAuthenticating = false;
  DateTime? _pausedTime;
  DateTime? _lastUnlockTime;
  final TextEditingController _unlockPasswordCtrl = TextEditingController();
  bool _obscureUnlockPwd = true;
  String _unlockErrorMsg = '';

  // રીમાઇન્ડર અને ફ્લેશ મેસેજ ટાઇમર
  Timer? _reminderTimer;
  final Set<String> _shownFlashIdsThisSession = {};
  bool _isFlashPopupOpen = false;

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

  static const MethodChannel _nativeChannel = MethodChannel('com.example.my_finance_app/native');

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

  // ડાર્ક અને લાઇટ મોડ માટે એડેપ્ટિવ કલર હેલ્પર્સ (ડાર્ક મોડમાં કાળા અક્ષરો ન દેખાય તે માટે)
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Color get primaryTextColor => isDark ? Colors.white : Colors.black87;
  Color get secondaryTextColor => isDark ? Colors.white70 : Colors.black54;
  Color get mutedTextColor => isDark ? Colors.white60 : Colors.grey.shade700;

  Color adaptiveTintBg(MaterialColor color) =>
      isDark ? color.shade900.withOpacity(0.32) : color.shade50;

  Color adaptiveAccentText(MaterialColor color) =>
      isDark ? color.shade200 : color.shade900;

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
    _reminderTimer?.cancel();
    for (final t in _snoozeTimers.values) {
      t.cancel();
    }
    _snoozeTimers.clear();
    _stopRingtone();
    _unlockPasswordCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  // બેકગ્રાઉન્ડ ઓટો-લોક (પાસવર્ડ + ફિંગરપ્રિન્ટ સપોર્ટ)
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
      _checkAndTriggerFlashReminders();
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
  // (PathAccessException errno = 13 નું નિવારણ + દર વખતે અલગ નામથી સેવ)
  // =========================================================
  String get _userPrefix => widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  Future<List<Directory>> _getCandidateBackupDirectories() async {
    final List<Directory> dirs = [];
    // પ્રથમ એપની પોતાની પ્રાઇવેટ ડિરેક્ટરી (જ્યાં ક્યારેય Permission Denied આવતું નથી)
    if (categoriesBox.path != null) {
      try {
        final internalBackupDir = Directory('${File(categoriesBox.path!).parent.path}/MyFinanceApp_Backup');
        if (!await internalBackupDir.exists()) {
          await internalBackupDir.create(recursive: true);
        }
        if (await internalBackupDir.exists()) dirs.add(internalBackupDir);
        dirs.add(File(categoriesBox.path!).parent);
      } catch (_) {}
    }

    final externalPaths = [
      '/storage/emulated/0/Download/MyFinanceApp_Backup',
      '/storage/emulated/0/Documents/MyFinanceApp_Backup',
      '/storage/emulated/0/Download',
    ];
    for (final p in externalPaths) {
      try {
        final d = Directory(p);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
        if (await d.exists()) dirs.add(d);
      } catch (_) {}
    }
    return dirs;
  }

  Future<bool> _canReadFileSafely(File file) async {
    try {
      final content = await file.readAsString();
      return content.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<File>> _listAllAvailableBackupFiles() async {
    final dirs = await _getCandidateBackupDirectories();
    final List<File> availableBackups = [];
    final Set<String> seenPaths = {};

    for (final d in dirs) {
      try {
        final list = d.listSync();
        for (final f in list) {
          if (f is File &&
              (f.path.endsWith('.json') || f.path.endsWith('.txt')) &&
              f.path.contains('finance_backup')) {
            if (seenPaths.add(f.path)) {
              availableBackups.add(f);
            }
          }
        }
      } catch (_) {}
    }

    availableBackups.sort((a, b) {
      DateTime ma = DateTime.fromMillisecondsSinceEpoch(0);
      DateTime mb = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        ma = a.lastModifiedSync();
      } catch (_) {}
      try {
        mb = b.lastModifiedSync();
      } catch (_) {}
      return mb.compareTo(ma);
    });
    return availableBackups;
  }

  Future<File?> _findExistingInternalBackupFile() async {
    final allFiles = await _listAllAvailableBackupFiles();
    // પ્રથમ એવી ફાઇલ શોધો જે સીધી વાંચી શકાય છે (Permission Denied વગર)
    for (final f in allFiles) {
      if (await _canReadFileSafely(f)) {
        return f;
      }
    }
    // જો કોઈ ફાઇલ મળી હોય પણ Scoped Storage પરમિશન માંગતી હોય તો પહેલી ફાઇલ પરત કરો
    return allFiles.isNotEmpty ? allFiles.first : null;
  }

  Map<String, dynamic> _buildCompleteBackupPayload() {
    return {
      'version': 3,
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
      'goals': goalsBox.toMap(),
      'settings': {
        'primaryColor': settingsBox.get('primaryColor'),
        'isDarkMode': settingsBox.get('isDarkMode'),
        'backgroundImage': settingsBox.get('backgroundImage'),
        'customAppTitle': settingsBox.get('customAppTitle'),
        'customInvTitle': settingsBox.get('customInvTitle'),
        'autoGenerateCcBill': settingsBox.get('autoGenerateCcBill', defaultValue: false),
        'inflationRate': settingsBox.get('inflationRate', defaultValue: 6.0),
        'customMetalsList': settingsBox.get('customMetalsList'),
        'lockedRiskStrategy': settingsBox.get('lockedRiskStrategy'),
        'isRiskStrategyLocked': settingsBox.get('isRiskStrategyLocked'),
      },
    };
  }

  Future<void> _backupAllDataToInternalMemory({
    bool showNotification = true,
    String? customFileTag,
  }) async {
    try {
      final backupPayload = _buildCompleteBackupPayload();
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupPayload);

      // દર વખતે અલગ-અલગ (Unique) નામથી સેવ થાય જેથી જૂની ફાઇલ ઓવરરાઇટ કરતા errno = 13 ન આવે
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final cleanTag = (customFileTag ?? '').trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\u0A80-\u0AFF]'), '_');
      final uniqueFileName = cleanTag.isNotEmpty
          ? 'finance_backup_${_userPrefix}_${cleanTag}_$timestamp.json'
          : 'finance_backup_${_userPrefix}_$timestamp.json';

      final dirs = await _getCandidateBackupDirectories();
      final List<String> savedPaths = [];

      for (final d in dirs) {
        try {
          File targetFile = File('${d.path}/$uniqueFileName');
          if (await targetFile.exists()) {
            final ms = DateTime.now().millisecondsSinceEpoch % 10000;
            targetFile = File('${d.path}/finance_backup_${_userPrefix}_${timestamp}_$ms.json');
          }
          await targetFile.writeAsString(jsonString, flush: true);
          savedPaths.add(targetFile.path);
        } catch (_) {}
      }

      // છેલ્લા બેકઅપની કોપી Hive settingsBox માં પણ સુરક્ષિત રાખો
      await settingsBox.put('lastBackupJson_$_userPrefix', jsonString);
      await settingsBox.put('lastBackupTime_$_userPrefix', DateTime.now().toIso8601String());
      final displayPath = savedPaths.isNotEmpty
          ? savedPaths.firstWhere((p) => p.contains('/storage/emulated/0'), orElse: () => savedPaths.first)
          : uniqueFileName;
      await settingsBox.put('lastBackupPath_$_userPrefix', displayPath);

      if (showNotification && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.teal),
                SizedBox(width: 8),
                Expanded(child: Text('નવા નામથી બેકઅપ સેવ થયો!')),
              ],
            ),
            content: Text(
              'તમારો બેકઅપ અલગ નામથી સુરક્ષિત રીતે સેવ થઈ ગયો છે:\n\n📄 ફાઇલનું નામ:\n$uniqueFileName\n\n📂 ફાઇલ પાથ:\n$displayPath',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('JSON કોપી કરો'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonString));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('બેકઅપ ડેટા ક્લિપબોર્ડમાં કોપી થયો!'), backgroundColor: Colors.teal),
                  );
                },
              ),
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

  Future<void> _restoreFromDecodedJsonMap(Map<String, dynamic> data) async {
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
    await restoreBox(goalsBox, data['goals']);

    if (data['settings'] is Map) {
      final s = data['settings'] as Map;
      if (s['customAppTitle'] != null) {
        appTitle = s['customAppTitle'].toString();
        await settingsBox.put('customAppTitle', appTitle);
      }
      if (s['customInvTitle'] != null) {
        await settingsBox.put('customInvTitle', s['customInvTitle'].toString());
      }
      if (s['primaryColor'] is int) {
        await settingsBox.put('primaryColor', s['primaryColor']);
        appSeedColor.value = Color(s['primaryColor'] as int);
      }
      if (s['isDarkMode'] is bool) {
        await settingsBox.put('isDarkMode', s['isDarkMode']);
        appThemeMode.value = (s['isDarkMode'] == true) ? ThemeMode.dark : ThemeMode.light;
      }
      if (s['autoGenerateCcBill'] != null) {
        await settingsBox.put('autoGenerateCcBill', s['autoGenerateCcBill']);
      }
      if (s['inflationRate'] != null) {
        benchmarkInflationRate = (s['inflationRate'] as num).toDouble();
        await settingsBox.put('inflationRate', benchmarkInflationRate);
      }
      if (s['customMetalsList'] != null) {
        await settingsBox.put('customMetalsList', s['customMetalsList']);
      }
      if (s['lockedRiskStrategy'] != null) {
        await settingsBox.put('lockedRiskStrategy', s['lockedRiskStrategy']);
      }
      if (s['isRiskStrategyLocked'] != null) {
        await settingsBox.put('isRiskStrategyLocked', s['isRiskStrategyLocked']);
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
  }

  Future<void> _requestAllFilesAccessPermission() async {
    try {
      await _nativeChannel.invokeMethod('requestAllFilesAccess');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ફોનના Settings -> Apps -> My Finance App -> Permissions -> Files and Media (All Files) ચાલુ કરો.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _openPasteBackupJsonDialog({String? failedFilePath}) {
    final pasteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restore_page, color: Colors.teal),
            SizedBox(width: 8),
            Expanded(child: Text('બેકઅપ ફાઇલ પરમિશન / મેન્યુઅલ રિસ્ટોર', style: TextStyle(fontSize: 15))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failedFilePath != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Text(
                    '⚠️ Android 11+ સુરક્ષા નિયમ (errno = 13) ને કારણે અગાઉના ઇન્સ્ટોલેશનની ફાઇલ સીધી ખોલવા માટે "All Files Access" પરમિશન આપવી પડે છે, અથવા તમે ફાઇલ મેનેજરમાંથી બેકઅપ ફાઇલનું લખાણ (JSON) અહીં પેસ્ટ કરીને તરત રિસ્ટોર કરી શકો છો.\n\nફાઇલ: ${failedFilePath.split('/').last}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, color: Colors.teal),
                    label: const Text('૧. સ્ટોરેજ પરમિશન (All Files Access) ચાલુ કરો'),
                    onPressed: () {
                      _requestAllFilesAccessPermission();
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const Text('અથવા બેકઅપ JSON ટેક્સ્ટ અહીં પેસ્ટ કરો:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              const SizedBox(height: 6),
              TextField(
                controller: pasteCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: '{"version": 3, "userEmail": ...}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            icon: const Icon(Icons.check),
            label: const Text('રિસ્ટોર કરો'),
            onPressed: () async {
              final raw = pasteCtrl.text.trim();
              if (raw.isEmpty) return;
              try {
                final decoded = json.decode(raw) as Map<String, dynamic>;
                Navigator.pop(ctx);
                await _restoreFromDecodedJsonMap(decoded);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('JSON ફોર્મેટ ખોટું છે: $e'), backgroundColor: Colors.red),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _restoreDataFromBackupFile(File file) async {
    try {
      String? content;
      try {
        content = await file.readAsString();
      } on FileSystemException catch (_) {
        // જો અગાઉના ઇન્સ્ટોલેશનની ફાઇલ પર errno = 13 (Permission denied) આવે, તો અન્ય વાંચી શકાય તેવી ફાઇલ અથવા કેશ તપાસો
        final allFiles = await _listAllAvailableBackupFiles();
        for (final altFile in allFiles) {
          if (altFile.path != file.path && await _canReadFileSafely(altFile)) {
            content = await altFile.readAsString();
            break;
          }
        }
        content ??= settingsBox.get('lastBackupJson_$_userPrefix')?.toString();
      }

      if (content == null || content.trim().isEmpty) {
        if (mounted) {
          _openPasteBackupJsonDialog(failedFilePath: file.path);
        }
        return;
      }

      final Map<String, dynamic> data = json.decode(content) as Map<String, dynamic>;
      await _restoreFromDecodedJsonMap(data);
    } catch (e) {
      if (mounted) {
        _openPasteBackupJsonDialog(failedFilePath: file.path);
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
        DateTime modifiedDate = DateTime.now();
        try {
          final stat = await backupFile.stat();
          modifiedDate = stat.modified;
        } catch (_) {}
        final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(modifiedDate);

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
    final availableBackups = await _listAllAvailableBackupFiles();
    final Map<String, bool> readableMap = {};
    for (final f in availableBackups) {
      readableMap[f.path] = await _canReadFileSafely(f);
    }

    final lastBackupTime = settingsBox.get('lastBackupTime_$_userPrefix');
    final customNameCtrl = TextEditingController();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(ctx).viewInsets.bottom + 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.backup, color: Colors.teal, size: 26),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ઇન્ટરનલ મેમરી બેકઅપ અને રિસ્ટોર',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (lastBackupTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'છેલ્લો બેકઅપ: ${DateFormat('dd MMM yyyy, hh:mm:ss a').format(DateTime.parse(lastBackupTime))}',
                    style: const TextStyle(fontSize: 12, color: Colors.teal),
                  ),
                ),
              const Divider(height: 20),
              TextField(
                controller: customNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'બેકઅપ ફાઇલનું નામ / નોંધ (વૈકલ્પિક - દર વખતે તારીખ-સમય સાથે અલગ સેવ થશે)',
                  hintText: 'દા.ત. Nov_2026 અથવા Diwali_Backup',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('નવા નામથી બેકઅપ સેવ કરો', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final tag = customNameCtrl.text.trim();
                        Navigator.pop(ctx);
                        await _backupAllDataToInternalMemory(showNotification: true, customFileTag: tag);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.paste, size: 16),
                    label: const Text('JSON પેસ્ટ', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openPasteBackupJsonDialog();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'ઉપલબ્ધ તમામ બેકઅપ ફાઇલો (દરેક ફાઇલ અલગ નામથી સેવ થયેલ છે):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              if (availableBackups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'હાલમાં ઇન્ટરનલ મેમરીમાં કોઈ બેકઅપ ફાઇલ મળી નથી.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...availableBackups.take(15).map((f) {
                  DateTime modified = DateTime.now();
                  try {
                    modified = f.lastModifiedSync();
                  } catch (_) {}
                  final bool isReadable = readableMap[f.path] ?? false;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        isReadable ? Icons.description : Icons.lock_person,
                        color: isReadable ? Colors.teal : Colors.orange,
                      ),
                      title: Text(
                        f.path.split('/').last,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      subtitle: Text(
                        'તારીખ: ${DateFormat('dd/MM/yyyy hh:mm:ss a').format(modified)}\n${f.parent.path}${isReadable ? '' : '\n⚠️ જૂના ઇન્સ્ટોલની ફાઇલ (પરમિશન/પેસ્ટ જરૂરી)'}',
                        style: const TextStyle(fontSize: 10.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (confirmCtx) => AlertDialog(
                                  title: const Text('ડેટા રિસ્ટોર કન્ફર્મ કરો'),
                                  content: Text(
                                    'શું તમે "${f.path.split('/').last}" ફાઇલમાંથી ડેટા રિસ્ટોર કરવા માંગો છો?',
                                  ),
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
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            onPressed: () async {
                              try {
                                await f.delete();
                              } catch (_) {}
                              if (ctx.mounted) Navigator.pop(ctx);
                              _openBackupAndRestoreDialog();
                            },
                          ),
                        ],
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
  // કિંમતી ધાતુઓના ૧૦૦% લાઇવ બજાર ભાવ + કસ્ટમ ધાતુઓ સપોર્ટ
  // =========================================================
  List<Map<String, dynamic>> get customMetals {
    final raw = settingsBox.get('customMetalsList');
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [
      {'name': 'સોનું 18K (Gold 18K)', 'ratePerGram': 7230.0},
      {'name': 'પ્લેટિનમ (Platinum)', 'ratePerGram': 3450.0},
    ];
  }

  double _getMetalLiveRatePerGram(String metalType) {
    final rates = bullionCityRates[selectedCity] ?? {"gold24": 96500.0, "gold22": 88400.0, "silver": 112000.0};
    if (metalType.contains('24K')) {
      return rates['gold24']! / 10.0;
    } else if (metalType.contains('22K')) {
      return rates['gold22']! / 10.0;
    } else if (metalType.contains('18K')) {
      return (rates['gold24']! * 0.75) / 10.0;
    } else if (metalType.contains('Silver') || metalType.contains('ચાંદી')) {
      return rates['silver']! / 1000.0;
    }
    for (final cm in customMetals) {
      if (cm['name'].toString() == metalType) {
        return (cm['ratePerGram'] as num?)?.toDouble() ?? 1000.0;
      }
    }
    return rates['gold24']! / 10.0;
  }

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
    goalsBox = await Hive.openBox('goalsBox_$prefix');

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
    _startReminderCheckTimer();

    if (mounted) {
      setState(() => _isInitialized = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndPromptBackupRestoreOnFreshInstall();
        _checkAndTriggerFlashReminders();
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
      {
        'id': 'acc_1',
        'name': 'રોકડ સિલક (Cash Wallet)',
        'type': 'રોકડ (Cash Wallet)',
        'accountCategory': 'Cash',
        'bankName': '',
        'branchName': '',
        'accountSubType': 'રોકડ ખાતું',
        'interestRate': 0.0,
        'openingBalance': 10000.0,
      },
      {
        'id': 'acc_2',
        'name': 'સેવિંગ્સ બેંક એકાઉન્ટ',
        'type': 'સેવિંગ એકાઉન્ટ (Savings A/C)',
        'accountCategory': 'Bank',
        'bankName': 'State Bank of India',
        'branchName': 'મેઈન બ્રાન્ચ',
        'accountSubType': 'સેવિંગ એકાઉન્ટ (Savings A/C)',
        'interestRate': 3.5,
        'openingBalance': 50000.0,
      },
      {
        'id': 'acc_3',
        'name': 'સેલેરી બેંક એકાઉન્ટ',
        'type': 'સેલેરી એકાઉન્ટ (Salary A/C)',
        'accountCategory': 'Bank',
        'bankName': 'HDFC Bank',
        'branchName': 'સિટી બ્રાન્ચ',
        'accountSubType': 'સેલેરી એકાઉન્ટ (Salary A/C)',
        'interestRate': 3.5,
        'openingBalance': 0.0,
      },
      {
        'id': 'acc_4',
        'name': 'ક્રેડિટ કાર્ડ (Credit Card)',
        'type': 'ક્રેડિટ કાર્ડ (Credit Card)',
        'accountCategory': 'CreditCard',
        'issuerName': 'HDFC Bank',
        'cardType': 'Visa Platinum',
        'maxLimit': 100000.0,
        'warningLimit': 75000.0,
        'openingBalance': 0.0,
      },
      {
        'id': 'acc_5',
        'name': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ',
        'type': 'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)',
        'accountCategory': 'Demat',
        'bankName': 'Zerodha / Groww',
        'branchName': 'ઓનલાઇન',
        'accountSubType': 'ડીમેટ એકાઉન્ટ',
        'interestRate': 0.0,
        'openingBalance': 0.0,
      },
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
  // ક્રેડિટ કાર્ડ લિમિટ અને ઓવર-સ્પેન્ડ વોર્નિંગ સિસ્ટમ
  // =========================================================
  bool _isCreditCardAccount(Map<dynamic, dynamic> acc) {
    final cat = (acc['accountCategory'] ?? '').toString().toLowerCase();
    final t = (acc['type'] ?? '').toString().toLowerCase();
    return cat == 'creditcard' || t.contains('credit') || t.contains('ક્રેડિટ');
  }

  double getCreditCardUsedAmount(String ccAccountId) {
    final acc = accounts.firstWhere((a) => a['id'].toString() == ccAccountId, orElse: () => {});
    double used = (acc['openingBalance'] as num?)?.toDouble() ?? 0.0;
    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    for (var tx in allTx) {
      if (tx['accountId'] == ccAccountId) {
        final amt = (tx['amount'] as num).toDouble();
        final effect = tx['categoryEffect'];
        if (effect == 'expenseDebit' || effect == 'loanRepay' || effect == 'assetIncrease') {
          used += amt;
        } else if (effect == 'incomeCredit') {
          used = math.max(0.0, used - amt);
        }
      }
    }
    return used;
  }

  void _checkAndShowCreditCardLimitWarning(String accountId) {
    final acc = accounts.firstWhere((a) => a['id'].toString() == accountId, orElse: () => {});
    if (acc.isEmpty || !_isCreditCardAccount(acc)) return;

    final double maxLimit = (acc['maxLimit'] as num?)?.toDouble() ?? 0.0;
    final double warningLimit = (acc['warningLimit'] as num?)?.toDouble() ?? (maxLimit > 0 ? maxLimit * 0.8 : 0.0);
    if (maxLimit <= 0 && warningLimit <= 0) return;

    final double currentUsed = getCreditCardUsedAmount(accountId);
    final bool overMax = maxLimit > 0 && currentUsed >= maxLimit;
    final bool overWarn = warningLimit > 0 && currentUsed >= warningLimit;

    if ((overMax || overWarn) && mounted) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C1515) : Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.red.shade700, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overMax ? '🚨 ક્રેડિટ કાર્ડ મહત્તમ લિમિટ પૂર્ણ!' : '⚠️ ક્રેડિટ કાર્ડ ખર્ચ વોર્નિંગ!',
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            'તમારા ક્રેડિટ કાર્ડ "${acc['name']}" (${acc['issuerName'] ?? ''}) માં કુલ વપરાશ ₹${currentUsed.toStringAsFixed(0)} થયો છે!\n\n'
            '• વોર્નિંગ લિમિટ: ₹${warningLimit.toStringAsFixed(0)}\n'
            '• મહત્તમ કાર્ડ લિમિટ: ₹${maxLimit.toStringAsFixed(0)}\n\n'
            '${overMax ? 'તમારો ખર્ચ કાર્ડની મહત્તમ લિમિટ કરતાં વધી ગયો છે!' : 'તમારો ખર્ચ નિર્ધારિત વોર્નિંગ લિમિટ કરતાં વધી ગયો છે. કૃપા કરીને ખર્ચ પર નિયંત્રણ રાખો.'}',
            style: TextStyle(fontSize: 13.5, color: primaryTextColor),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('સમજાઈ ગયું'),
            ),
          ],
        ),
      );
    }
  }

  // =========================================================
  // ઓટો-પે / SIP માટે રીમાઇન્ડર સમય, રીંગટોન અને મોબાઇલ ફ્લેશ મેસેજ એન્જિન
  // =========================================================
  void _startReminderCheckTimer() {
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _checkAndTriggerFlashReminders();
    });
  }

  // =========================================================
  // (સુધારો ૫) SIP ફ્રીક્વન્સી હેલ્પર્સ (માસિક, અઠવાડિક, પંદર દિવસની, દૈનિક + કસ્ટમ)
  // =========================================================
  List<Map<String, dynamic>> _getSipFrequencyOptions() {
    final List<Map<String, dynamic>> defaults = [
      {'name': 'માસિક (Monthly)', 'days': 30},
      {'name': 'અઠવાડિક (Weekly)', 'days': 7},
      {'name': 'પંદર દિવસની (Fortnightly - 15 Days)', 'days': 15},
      {'name': 'દૈનિક (Daily)', 'days': 1},
    ];
    final dynamic rawCustom = settingsBox.get('customSipFrequencies');
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map && item['name'] != null) {
          defaults.add({
            'name': item['name'].toString(),
            'days': (item['days'] as num?)?.toInt() ?? 30,
          });
        }
      }
    }
    return defaults;
  }

  int _getIntervalDaysForFrequency(String freqName) {
    final all = _getSipFrequencyOptions();
    for (final f in all) {
      if (f['name'].toString() == freqName) {
        return (f['days'] as num?)?.toInt() ?? 30;
      }
    }
    if (freqName.contains('દૈનિક') || freqName.contains('Daily')) return 1;
    if (freqName.contains('અઠવાડિક') || freqName.contains('Weekly')) return 7;
    if (freqName.contains('પંદર') || freqName.contains('Fortnightly')) return 15;
    return 30;
  }

  Future<String?> _openAddCustomSipFrequencyDialog() async {
    final nameCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '90');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('નવી SIP ફ્રીક્વન્સી ઉમેરો', 'Add Custom SIP Frequency')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: _t('ફ્રીક્વન્સીનું નામ (દા.ત. ત્રિમાસિક / દર 10 દિવસે)', 'Frequency Name (e.g. Quarterly / Every 10 Days)'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: daysCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _t('દિવસોનો ગાળો (Interval Days)', 'Interval in Days'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('રદ', 'Cancel'))),
          ElevatedButton(
            onPressed: () {
              final nm = nameCtrl.text.trim();
              final d = int.tryParse(daysCtrl.text.trim()) ?? 0;
              if (nm.isEmpty || d <= 0) return;
              final dynamic raw = settingsBox.get('customSipFrequencies');
              final List<Map<String, dynamic>> list = raw is List
                  ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                  : [];
              final formatted = '$nm ($d ${_t("દિવસ", "Days")})';
              list.add({'name': formatted, 'days': d});
              settingsBox.put('customSipFrequencies', list);
              Navigator.pop(ctx, formatted);
            },
            child: Text(_t('ઉમેરો', 'Add')),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // (સુધારો ૫) ઇન્વેસ્ટમેન્ટની નોંધ આપમેળે દૈનિક નોંધમાં ઉમેરવા / અપડેટ કરવા માટે
  // =========================================================
  void _syncInvestmentToDailyTransaction({
    required String linkedInvestmentId,
    required String title,
    required double amount,
    required DateTime date,
    required String categoryId,
    required String categoryName,
    required int categoryColor,
    required String accountId,
    bool hasTime = false,
  }) {
    if (amount <= 0) return;
    final acc = accounts.firstWhere(
      (a) => a['id'].toString() == accountId,
      orElse: () => accounts.isNotEmpty ? accounts.first : {'id': '', 'name': _t('બેંક ખાતું', 'Bank Account')},
    );

    // પહેલેથી લિંક થયેલ દૈનિક એન્ટ્રી હોય તો ડબલ એન્ટ્રી વગર અપડેટ કરો
    String? existingTxId;
    for (final entry in transactionsBox.values) {
      final m = Map<dynamic, dynamic>.from(entry);
      if (m['linkedInvestmentId']?.toString() == linkedInvestmentId) {
        existingTxId = m['id']?.toString();
        break;
      }
    }

    final txId = existingTxId ?? "tx_inv_${DateTime.now().millisecondsSinceEpoch}_$linkedInvestmentId";
    transactionsBox.put(txId, {
      'id': txId,
      'linkedInvestmentId': linkedInvestmentId,
      'title': title,
      'amount': amount,
      'date': date.toIso8601String(),
      'hasTime': hasTime,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'categoryEffect': 'assetIncrease',
      'categoryColor': categoryColor,
      'accountId': acc['id']?.toString() ?? accountId,
      'accountName': acc['name'] ?? '',
    });
  }

  // =========================================================
  // (સુધારો ૧) રિંગટોન પ્લે / સ્ટોપ અને ઇન્ટરનલ મેમરી ઓડિયો ફાઇલ પિકર
  // =========================================================
  Future<void> _playSelectedRingtone(String ringtoneName, {String? customPath}) async {
    await _stopRingtone();
    _isRingtonePlaying = true;
    try {
      await _nativeChannel.invokeMethod('playRingtone', {
        'ringtone': ringtoneName,
        'customPath': customPath ?? '',
      });
      return;
    } catch (_) {}

    // Pure Flutter fallback ringtone & vibration pattern (respects _isRingtonePlaying so Stop works!)
    int count = 3;
    if (ringtoneName.contains('ઇમરજન્સી') || ringtoneName.contains('Urgent')) {
      count = 5;
    } else if (ringtoneName.contains('સોફ્ટ') || ringtoneName.contains('Soft')) {
      count = 1;
    }
    for (int i = 0; i < count; i++) {
      if (!_isRingtonePlaying) break;
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 350));
    }
    _isRingtonePlaying = false;
  }

  Future<void> _stopRingtone() async {
    _isRingtonePlaying = false;
    try {
      await _nativeChannel.invokeMethod('stopRingtone');
    } catch (_) {}
  }

  Future<Map<String, String>?> _pickAudioFileFromInternalMemory() async {
    // ૧. પ્રથમ નેટિવ Android Audio File Picker (ACTION_OPEN_DOCUMENT) અજમાવો
    try {
      final dynamic res = await _nativeChannel.invokeMethod('pickAudioFile');
      if (res is Map && res['path'] != null && res['path'].toString().isNotEmpty) {
        return {
          'path': res['path'].toString(),
          'name': (res['name'] ?? res['path'].toString().split('/').last).toString(),
        };
      } else if (res is String && res.isNotEmpty) {
        return {'path': res, 'name': res.split('/').last};
      }
    } catch (_) {}

    // ૨. Pure Dart Fallback: ઇન્ટરનલ મેમરીના ઓડિયો ફોલ્ડર્સ સ્કેન કરી પસંદ કરવાનો વિકલ્પ
    final List<File> foundAudioFiles = [];
    final List<String> scanDirs = [
      '/storage/emulated/0/Ringtones',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Notifications',
      '/storage/emulated/0/Alarms',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Audio',
    ];
    const audioExts = ['.mp3', '.wav', '.m4a', '.ogg', '.aac', '.flac'];
    for (final dirPath in scanDirs) {
      try {
        final d = Directory(dirPath);
        if (await d.exists()) {
          await for (final entity in d.list(recursive: false, followLinks: false)) {
            if (entity is File) {
              final lower = entity.path.toLowerCase();
              if (audioExts.any((ext) => lower.endsWith(ext))) {
                foundAudioFiles.add(entity);
              }
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return null;
    final manualPathCtrl = TextEditingController();
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('ઇન્ટરનલ મેમરીમાંથી ઓડિયો ફાઇલ પસંદ કરો', 'Select Audio File from Internal Storage')),
        content: SizedBox(
          width: double.maxFinite,
          height: 330,
          child: Column(
            children: [
              Expanded(
                child: foundAudioFiles.isEmpty
                    ? Center(
                        child: Text(
                          _t(
                            'ફોલ્ડરમાં ઓડિયો ફાઇલ ન મળી. નીચે ઓડિયો ફાઇલનો પાથ લખો અથવા Storage પરમિશન આપો.',
                            'No audio files found in Music/Ringtones/Download. Enter file path below or grant Storage/Audio permission.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        itemCount: foundAudioFiles.length,
                        itemBuilder: (c, i) {
                          final f = foundAudioFiles[i];
                          final fname = f.path.split('/').last;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.audio_file, color: Colors.teal),
                            title: Text(fname, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            subtitle: Text(f.path, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(ctx, {'path': f.path, 'name': fname}),
                          );
                        },
                      ),
              ),
              const Divider(),
              TextField(
                controller: manualPathCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _t('અથવા ઓડિયો ફાઇલ પાથ લખો (.mp3 / .wav)', 'Or enter audio file path (.mp3 / .wav)'),
                  hintText: '/storage/emulated/0/Music/tone.mp3',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('રદ', 'Cancel'))),
          ElevatedButton(
            onPressed: () {
              final p = manualPathCtrl.text.trim();
              if (p.isNotEmpty) {
                Navigator.pop(ctx, {'path': p, 'name': p.split('/').last});
              }
            },
            child: Text(_t('પસંદ કરો', 'Select')),
          ),
        ],
      ),
    );
  }

  // રિમાઇન્ડર માટે વર્તમાન સાઇકલ કી (માસિક / અઠવાડિક / પંદર દિવસ / દૈનિક / કસ્ટમ)
  String _getReminderCycleKey(Map<dynamic, dynamic> item, DateTime now) {
    final String freq = (item['sipFrequency'] ?? 'માસિક (Monthly)').toString();
    final int intervalDays = (item['sipIntervalDays'] as num?)?.toInt() ?? _getIntervalDaysForFrequency(freq);
    if (intervalDays == 1) {
      return "${now.year}-${now.month}-${now.day}";
    } else if (intervalDays == 7) {
      final weekNum = ((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).floor();
      return "${now.year}-W$weekNum";
    } else if (intervalDays == 15) {
      final half = now.day <= 15 ? 1 : 2;
      return "${now.year}-${now.month}-H$half";
    } else if (intervalDays != 30) {
      final bucket = (now.difference(DateTime(2020, 1, 1)).inDays / intervalDays).floor();
      return "C$intervalDays-$bucket";
    }
    return "${now.year}-${now.month}";
  }

  // તપાસો કે આ રિમાઇન્ડરની એન્ટ્રી વર્તમાન સાઇકલમાં એપમાં પહેલેથી જ થઈ ગઈ છે કે નહીં (ડબલ એન્ટ્રી રોકવા અને બિનજરૂરી રિંગટોન અટકાવવા)
  bool _hasExistingEntryForReminder(Map<dynamic, dynamic> item, {DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    final String remId = (item['id'] ?? '').toString();
    final String target = (item['toTarget'] ?? '').toString().trim().toLowerCase();
    final double amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final String cycleKey = _getReminderCycleKey(item, now);
    final int intervalDays = (item['sipIntervalDays'] as num?)?.toInt() ??
        _getIntervalDaysForFrequency((item['sipFrequency'] ?? 'માસિક (Monthly)').toString());

    final allTx = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
    for (final tx in allTx) {
      final txDate = DateTime.tryParse((tx['date'] ?? '').toString());
      if (txDate == null) continue;

      // ૧. સીધો reminderId + cycleKey મેચ
      if (tx['reminderId']?.toString() == remId && tx['reminderCycleKey']?.toString() == cycleKey) {
        return true;
      }

      // ૨. સમયગાળાની અંદર સમાન નામ/લક્ષ્ય અને રકમની એન્ટ્રી પહેલેથી નોંધાયેલ હોય તો
      bool withinCycle = false;
      if (intervalDays == 1) {
        withinCycle = txDate.year == now.year && txDate.month == now.month && txDate.day == now.day;
      } else if (intervalDays == 30) {
        withinCycle = txDate.year == now.year && txDate.month == now.month;
      } else {
        withinCycle = now.difference(txDate).inDays.abs() < intervalDays;
      }

      if (withinCycle) {
        final txAmt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final txTitle = (tx['title'] ?? '').toString().trim().toLowerCase();
        if (target.isNotEmpty && txTitle.contains(target) && (amt <= 0 || (txAmt - amt).abs() <= 1.0)) {
          return true;
        }
      }
    }
    return false;
  }

  void _scheduleSnoozeForReminder(Map<dynamic, dynamic> item, Duration delay) {
    final String id = item['id'].toString();
    final DateTime snoozeTarget = DateTime.now().add(delay);
    item['snoozeUntil'] = snoozeTarget.toIso8601String();
    autoPayBox.put(id, item);

    _snoozeTimers[id]?.cancel();
    _snoozeTimers[id] = Timer(delay, () {
      if (!mounted) return;
      final latestRaw = autoPayBox.get(id);
      if (latestRaw == null) return;
      final latest = Map<dynamic, dynamic>.from(latestRaw);
      final currentCycleKey = _getReminderCycleKey(latest, DateTime.now());
      if (latest['lastProcessed'] == currentCycleKey) return;
      if (_hasExistingEntryForReminder(latest)) {
        latest['lastProcessed'] = currentCycleKey;
        latest['snoozeUntil'] = null;
        autoPayBox.put(id, latest);
        return;
      }
      _shownFlashIdsThisSession.remove(id);
      _showFlashReminderPopup(latest);
    });

    try {
      _nativeChannel.invokeMethod('scheduleFlashReminder', {
        ...item,
        'snoozeEpochMs': snoozeTarget.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  void _checkAndTriggerFlashReminders() {
    if (!mounted || _isAppLocked || _isFlashPopupOpen) return;
    final now = DateTime.now();
    final allAuto = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    for (final item in allAuto) {
      if (item['isActive'] != true) continue;
      final String id = item['id'].toString();
      final String currentCycleKey = _getReminderCycleKey(item, now);
      if (item['lastProcessed'] == currentCycleKey) continue;

      // જો રિમાઇન્ડર પહેલા જ એપમાં આ વ્યવહારની એન્ટ્રી થઈ ગઈ હોય, તો રિંગટોન બિલકુલ ન વાગવી જોઈએ!
      if (_hasExistingEntryForReminder(item, referenceDate: now)) {
        item['lastProcessed'] = currentCycleKey;
        item['snoozeUntil'] = null;
        autoPayBox.put(id, item);
        continue;
      }

      // સ્નૂઝ સમય પૂરો થયો હોય તો ફરી રિંગ વગાડો
      if (item['snoozeUntil'] != null) {
        final snoozeDt = DateTime.tryParse(item['snoozeUntil'].toString());
        if (snoozeDt != null) {
          if (!now.isBefore(snoozeDt)) {
            item['snoozeUntil'] = null;
            autoPayBox.put(id, item);
            _showFlashReminderPopup(item);
            break;
          } else {
            continue;
          }
        }
      }

      if (_shownFlashIdsThisSession.contains(id)) continue;
      final bool enableFlash = item['enableFlashMessage'] ?? true;
      if (!enableFlash) continue;

      final int dueDay = (item['day'] as num?)?.toInt() ?? 1;
      final int remHour = (item['reminderHour'] as num?)?.toInt() ?? 9;
      final int remMin = (item['reminderMinute'] as num?)?.toInt() ?? 0;
      final int intervalDays = (item['sipIntervalDays'] as num?)?.toInt() ??
          _getIntervalDaysForFrequency((item['sipFrequency'] ?? 'માસિક (Monthly)').toString());

      bool isDateMatch = false;
      if (intervalDays == 1) {
        isDateMatch = true;
      } else if (intervalDays == 7) {
        isDateMatch = (now.weekday == (dueDay.clamp(1, 7)));
      } else if (intervalDays == 15) {
        isDateMatch = (now.day == dueDay || now.day == ((dueDay + 15) > 28 ? (dueDay - 15).abs().clamp(1, 28) : dueDay + 15));
      } else {
        isDateMatch = (now.day == dueDay);
      }

      if (item['specificReminderDate'] != null) {
        final sp = DateTime.tryParse(item['specificReminderDate'].toString());
        if (sp != null && sp.year == now.year && sp.month == now.month && sp.day == now.day) {
          isDateMatch = true;
        }
      }

      if (isDateMatch) {
        final scheduledToday = DateTime(now.year, now.month, now.day, remHour, remMin);
        if (!now.isBefore(scheduledToday)) {
          _shownFlashIdsThisSession.add(id);
          _showFlashReminderPopup(item);
          break;
        }
      }
    }
  }

  void _showFlashReminderPopup(Map<dynamic, dynamic> item) {
    if (!mounted) return;
    _isFlashPopupOpen = true;
    final String ringtone = (item['ringtoneName'] ?? 'ડિફોલ્ટ અલાર્મ ટોન (Default Alarm)').toString();
    final String customPath = (item['customRingtonePath'] ?? '').toString();
    _playSelectedRingtone(ringtone, customPath: customPath);

    final int h = (item['reminderHour'] as num?)?.toInt() ?? 9;
    final int m = (item['reminderMinute'] as num?)?.toInt() ?? 0;
    final timeFormatted = TimeOfDay(hour: h, minute: m).format(context);
    final customSnoozeCtrl = TextEditingController(text: '15');
    String snoozeUnit = 'min'; // min or hour
    bool ringMuted = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.amber, width: 2.5),
          ),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade800, Colors.amber.shade800],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.flash_on, color: Colors.yellowAccent, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('⚡ મોબાઇલ ફ્લેશ મેસેજ રીમાઇન્ડર!', '⚡ Mobile Flash Reminder!'),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_t("સમય", "Time")}: $timeFormatted • ${_t("ટોન", "Tone")}: $ringtone',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _t('રિંગટોન બંધ કરો', 'Stop Ringtone'),
                  icon: Icon(ringMuted ? Icons.volume_off : Icons.stop_circle, color: Colors.white, size: 26),
                  onPressed: () async {
                    await _stopRingtone();
                    setDlgState(() => ringMuted = true);
                  },
                ),
              ],
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!ringMuted)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                      icon: const Icon(Icons.volume_off, size: 18),
                      label: Text(_t('🔇 રિંગટોન અત્યારે જ બંધ કરો', '🔇 Stop Ringtone Now')),
                      onPressed: () async {
                        await _stopRingtone();
                        setDlgState(() => ringMuted = true);
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${item['type']}: ${item['toTarget']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_t("ચૂકવવાની / રોકાણ રકમ", "Amount Due")}: ₹${((item['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                Text(
                  '${_t("ફ્રીક્વન્સી", "Frequency")}: ${item['sipFrequency'] ?? _t("માસિક (Monthly)", "Monthly")} • ${_t("તારીખ", "Day")}: ${item['day']}',
                  style: const TextStyle(fontSize: 12),
                ),
                const Divider(height: 18),
                Text(
                  _t('એક્શન પસંદ કરો:', 'Choose Action:'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                // ૧. પેમેન્ટ કમ્પલિટ થઈ ગયું
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(_t('✅ પેમેન્ટ કમ્પલિટ થઈ ગયું (ઓટો એન્ટ્રી / નો-ડબલ)', '✅ Payment Completed (Auto Entry / No Duplicate)'), style: const TextStyle(fontSize: 12)),
                    onPressed: () async {
                      await _stopRingtone();
                      _isFlashPopupOpen = false;
                      if (ctx.mounted) Navigator.pop(ctx);
                      _confirmAndExecuteManualReminder(item);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // ૨. થોડા સમય પછી ફરી યાદ કરાવો (Snooze)
                Text(
                  _t('⏰ થોડી વાર પછી કરવું છે / ફરી યાદ કરાવો:', '⏰ Do Later / Remind Again After:'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final mins in [5, 10, 15, 30, 60, 120])
                      ActionChip(
                        label: Text(mins >= 60 ? '${mins ~/ 60} ${_t("કલાક", "hr")}' : '$mins ${_t("મિનિટ", "min")}', style: const TextStyle(fontSize: 11)),
                        onPressed: () async {
                          await _stopRingtone();
                          _scheduleSnoozeForReminder(item, Duration(minutes: mins));
                          _isFlashPopupOpen = false;
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_t('⏰ $mins મિનિટ પછી ફરી રિંગટોન સાથે યાદ કરાવશે!', '⏰ Will remind again in $mins minutes!')),
                                backgroundColor: Colors.amber.shade800,
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: customSnoozeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: _t('કસ્ટમ સમય', 'Custom Time'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: snoozeUnit,
                      items: [
                        DropdownMenuItem(value: 'min', child: Text(_t('મિનિટ', 'Min'))),
                        DropdownMenuItem(value: 'hour', child: Text(_t('કલાક', 'Hr'))),
                      ],
                      onChanged: (v) => setDlgState(() => snoozeUnit = v!),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: () async {
                        final val = int.tryParse(customSnoozeCtrl.text.trim()) ?? 15;
                        if (val <= 0) return;
                        await _stopRingtone();
                        final dur = snoozeUnit == 'hour' ? Duration(hours: val) : Duration(minutes: val);
                        _scheduleSnoozeForReminder(item, dur);
                        _isFlashPopupOpen = false;
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_t(
                                '⏰ $val ${snoozeUnit == "hour" ? "કલાક" : "મિનિટ"} પછી ફરી રિમાઇન્ડર વાગશે!',
                                '⏰ Reminder snoozed for $val ${snoozeUnit == "hour" ? "hour(s)" : "minute(s)"}!',
                              )),
                              backgroundColor: Colors.amber.shade800,
                            ),
                          );
                        }
                      },
                      child: Text(_t('સેટ કરો', 'Set')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _stopRingtone();
                _isFlashPopupOpen = false;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(_t('બંધ કરો', 'Close')),
            ),
          ],
        ),
      ),
    ).then((_) {
      _stopRingtone();
      _isFlashPopupOpen = false;
    });
  }

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
      final String cycleKey = _getReminderCycleKey(item, now);
      final int intervalDays = (item['sipIntervalDays'] as num?)?.toInt() ??
          _getIntervalDaysForFrequency((item['sipFrequency'] ?? 'માસિક (Monthly)').toString());

      // જો આ સાઇકલમાં એન્ટ્રી પહેલેથી થઈ ગઈ હોય તો ડબલ એન્ટ્રી ન કરો
      if (_hasExistingEntryForReminder(item, referenceDate: now)) {
        item['lastProcessed'] = cycleKey;
        autoPayBox.put(item['id'], item);
        continue;
      }

      bool isDueNow = false;
      if (intervalDays == 1) {
        isDueNow = true;
      } else if (intervalDays == 7) {
        isDueNow = (now.weekday >= day.clamp(1, 7));
      } else if (intervalDays == 15) {
        isDueNow = (now.day >= day || now.day >= ((day + 15) > 28 ? 15 : day + 15));
      } else {
        isDueNow = (now.day >= day);
      }

      if (lastExecution != cycleKey && isDueNow) {
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
          'reminderId': item['id'].toString(),
          'reminderCycleKey': cycleKey,
        });

        item['lastProcessed'] = cycleKey;
        autoPayBox.put(item['id'], item);
      }
    }
  }

  // બોન્ડ, FD, PLI ની સેટ કરેલ મેચ્યુરિટી તારીખ પ્રમાણે આપોઆપ ખાતામાં વ્યાજ સહિત રકમ જમા/ઉધાર
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
        final String flowType = item['flowType'] ?? 'inflow_maturity';
        final double amount = (item['scheduledAmount'] as num?)?.toDouble() ?? 0.0;
        final String accId = item['accountId'] ?? '';
        final acc = accounts.firstWhere((a) => a['id'].toString() == accId, orElse: () => {'name': 'બેંક ખાતું'});

        if (amount > 0 && accId.isNotEmpty) {
          final txId = "fi_auto_${DateTime.now().millisecondsSinceEpoch}_${item['id']}";
          final isCredit = flowType == 'inflow_maturity';
          final String bankOrIssuer = (item['issuerBankName'] ?? '').toString();
          final String issuerLabel = bankOrIssuer.isNotEmpty ? ' ($bankOrIssuer)' : '';

          transactionsBox.put(txId, {
            'id': txId,
            'title': isCredit
                ? "${item['schemeType']}$issuerLabel પાકતી રકમ જમા: ${item['title']}"
                : "${item['schemeType']}$issuerLabel હપ્તો/રોકાણ ચુકવણી: ${item['title']}",
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
    final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final type = item['type'] ?? 'AutoPay';
    final fromAccId = item['fromAccountId'];
    final toTarget = item['toTarget'] ?? '';
    final String cycleKey = _getReminderCycleKey(item, now);
    final String remId = item['id'].toString();

    // સ્નૂઝ ટાઇમર અને રિંગટોન કાયમ માટે બંધ કરો (આ સાઇકલ માટે ફરી રિંગ નહીં વાગે)
    _stopRingtone();
    _snoozeTimers[remId]?.cancel();
    _snoozeTimers.remove(remId);

    final bool alreadyExists = _hasExistingEntryForReminder(item, referenceDate: now);
    if (!alreadyExists) {
      final txId = "manual_rem_${DateTime.now().millisecondsSinceEpoch}";
      final fromAcc = accounts.firstWhere(
        (a) => a['id'].toString() == fromAccId,
        orElse: () => {'name': _t('ખાતું', 'Account')},
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
        'categoryName': type == 'SIP' ? _t('શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'Stocks / Mutual Fund') : _t('EMI / વીમા / બિલ ચુકવણી', 'EMI / Insurance / Bill'),
        'categoryEffect': catEffect,
        'categoryColor': Colors.teal.toARGB32(),
        'accountId': fromAccId,
        'accountName': fromAcc['name'],
        'isCcSettlement': type == 'CreditCard',
        'reminderId': remId,
        'reminderCycleKey': cycleKey,
      });
    }

    item['lastProcessed'] = cycleKey;
    item['snoozeUntil'] = null;
    autoPayBox.put(item['id'], item);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alreadyExists
              ? _t('✅ પેમેન્ટ કમ્પલિટ માર્ક થયું (એન્ટ્રી પહેલેથી હાજર હોવાથી ડબલ એન્ટ્રી ટાળવામાં આવી).', '✅ Marked Completed (Entry already exists, duplicate avoided).')
              : _t('✅ ₹${amt.toStringAsFixed(0)} નો $type વ્યવહાર ઓટોમેટિક નોંધાઈ ગયો!', '✅ ₹${amt.toStringAsFixed(0)} $type entry added automatically!'),
        ),
        backgroundColor: Colors.green,
      ),
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

    if (_txSortMode == 'date_asc') {
      list.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
    } else if (_txSortMode == 'amount_desc') {
      list.sort((a, b) => ((b['amount'] as num?)?.toDouble() ?? 0.0).compareTo(((a['amount'] as num?)?.toDouble() ?? 0.0)));
    } else if (_txSortMode == 'amount_asc') {
      list.sort((a, b) => ((a['amount'] as num?)?.toDouble() ?? 0.0).compareTo(((b['amount'] as num?)?.toDouble() ?? 0.0)));
    } else {
      list.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));
    }
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
  // ટેક્સ ગણતરી અને આખી એપમાંથી આવક, રોકાણ, બચત, રિસ્ક અને સ્ટ્રેટેજી ફેચિંગ એન્જિન
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
    final double excessOver12L = taxableIncome - 1200000.0;
    if (tax > excessOver12L) {
      tax = excessOver12L;
    }
    return tax * 1.04;
  }

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
    return tax * 1.04;
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

  Map<String, double> _fetchComprehensiveTaxData({bool entireFY = true}) {
    final fyStart = DateTime(selectedFinancialYearStart, 4, 1);
    final fyEnd = DateTime(selectedFinancialYearStart + 1, 3, 31, 23, 59, 59);
    final txList = entireFY ? entireFYTransactions : filteredTransactions;

    double regularGrossIncome = 0.0;
    double recordedBankInterest = 0.0;
    double raw80C = 0.0;
    double raw80D = 0.0;
    double rawHomeOrEduLoan = 0.0;

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

    double bankSavingsBalance = 0.0;
    double estimatedBankInterest = 0.0;
    final double defaultBankIntRate = (settingsBox.get('bankInterestRate', defaultValue: 3.5) as num).toDouble();

    for (final acc in accounts) {
      if (!_isCreditCardAccount(acc)) {
        final bal = getAccountCurrentBalance(acc['id'].toString());
        if (bal > 0) {
          bankSavingsBalance += bal;
          final aType = (acc['type'] ?? '').toString().toLowerCase();
          final isCash = aType.contains('cash') || aType.contains('રોકડ');
          if (!isCash) {
            final accRate = (acc['interestRate'] as num?)?.toDouble() ?? defaultBankIntRate;
            estimatedBankInterest += bal * (accRate / 100.0);
          }
        }
      }
    }

    final double totalBankInterest = recordedBankInterest > 0 ? recordedBankInterest : estimatedBankInterest;
    final bool includeEstBankIntInTax = settingsBox.get('includeEstBankIntInTax', defaultValue: false) == true;
    final double effectiveGrossIncome = regularGrossIncome + (includeEstBankIntInTax && recordedBankInterest == 0 ? estimatedBankInterest : 0.0);

    final String ageGroup = settingsBox.get('taxAgeGroup', defaultValue: 'regular').toString();
    final double extraDeductions = (settingsBox.get('extraOldRegimeDeductions', defaultValue: 0.0) as num).toDouble() + rawHomeOrEduLoan;

    const double stdDedNew = 75000.0;
    final double taxableNew = math.max(0.0, effectiveGrossIncome - stdDedNew);
    final double slabTaxNew = _calculateIncomeTaxNewRegime(taxableNew);

    const double stdDedOld = 50000.0;
    final double allowed80C = math.min(150000.0, raw80C);
    final double max80DLimit = ageGroup == 'regular' ? 25000.0 : 50000.0;
    final double allowed80D = math.min(max80DLimit, raw80D);
    final double max80TTALimit = ageGroup == 'regular' ? 10000.0 : 50000.0;
    final double allowed80TTA = math.min(max80TTALimit, totalBankInterest);

    final double totalOldDeductions = stdDedOld + allowed80C + allowed80D + allowed80TTA + extraDeductions;
    final double taxableOld = math.max(0.0, effectiveGrossIncome - totalOldDeductions);
    final double slabTaxOld = _calculateIncomeTaxOldRegime(taxableOld, ageGroup: ageGroup);

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

  // આખી એપમાંથી સંપૂર્ણ રોકાણ અને બચતનું વર્ગીકરણ (૬ મુખ્ય કેટેગરીઓ + પેટા કેટેગરીઓ)
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
      if (f['isSettled'] == true && f['isPrematureClosed'] == true) continue;
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

    // 4. Bullion (Gold 24K, Gold 22K, Silver, Custom Metals)
    double gold24Val = 0.0;
    double gold22Val = 0.0;
    double silverVal = 0.0;
    double otherMetalsVal = 0.0;
    double bullionInv = 0.0;

    for (final b in bullionInvestmentsBox.values) {
      final weight = (b['weight'] as num?)?.toDouble() ?? 0.0;
      final buyP = (b['buyPrice'] as num?)?.toDouble() ?? 0.0;
      final mType = (b['metalType'] ?? '').toString();
      bullionInv += buyP;
      final perG = _getMetalLiveRatePerGram(mType);
      final liveVal = weight * perG;
      if (mType.contains('24K')) {
        gold24Val += liveVal;
      } else if (mType.contains('22K')) {
        gold22Val += liveVal;
      } else if (mType.contains('Silver') || mType.contains('ચાંદી')) {
        silverVal += liveVal;
      } else {
        otherMetalsVal += liveVal;
      }
    }

    // 5. Physical Assets / Real Estate (મકાન, ખેતર, દુકાનો, પ્લોટ, અન્ય)
    double houseFlatVal = 0.0;
    double farmLandVal = 0.0;
    double shopOfficeVal = 0.0;
    double plotLandVal = 0.0;
    double otherPhysicalVal = 0.0;
    double physicalAssetsInv = 0.0;

    for (final a in physicalAssetsBox.values) {
      final v = (a['value'] as num?)?.toDouble() ?? 0.0;
      final curV = (a['currentValue'] as num?)?.toDouble() ?? v;
      final aType = (a['type'] ?? '').toString();
      physicalAssetsInv += v;
      if (aType.contains('મકાન') || aType.contains('ફ્લેટ')) {
        houseFlatVal += curV;
      } else if (aType.contains('ખેત')) {
        farmLandVal += curV;
      } else if (aType.contains('દુકાન') || aType.contains('ઓફિસ')) {
        shopOfficeVal += curV;
      } else if (aType.contains('પ્લોટ') || aType.contains('જમીન')) {
        plotLandVal += curV;
      } else {
        otherPhysicalVal += curV;
      }
    }
    final double physicalAssetsVal = houseFlatVal + farmLandVal + shopOfficeVal + plotLandVal + otherPhysicalVal;

    // 6. દૈનિક વ્યવહારોમાંથી સીધા ઉમેરાયેલા રોકાણો
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

    // 7. બેંક ખાતાઓની સિલક અને ખાતાવાર વ્યાજ દર
    double bankSavingsBalance = 0.0;
    double cashWalletBalance = 0.0;
    double annualEstimatedBankInterest = 0.0;
    final double defaultBankInterestRate = (settingsBox.get('bankInterestRate', defaultValue: 3.5) as num).toDouble();
    final List<Map<String, dynamic>> bankAccountsBreakdown = [];

    for (final acc in accounts) {
      if (_isCreditCardAccount(acc)) continue;
      final String accId = acc['id'].toString();
      final String accName = (acc['name'] ?? 'ખાતું').toString();
      final String accType = (acc['type'] ?? '').toString();
      final String bankName = (acc['bankName'] ?? '').toString();
      final String branchName = (acc['branchName'] ?? '').toString();
      final double accIntRate = (acc['interestRate'] as num?)?.toDouble() ?? defaultBankInterestRate;

      final double bal = math.max(0.0, getAccountCurrentBalance(accId));
      final bool isCash = accType.toLowerCase().contains('cash') || accType.contains('રોકડ') || acc['accountCategory'] == 'Cash';
      if (isCash) {
        cashWalletBalance += bal;
      } else {
        bankSavingsBalance += bal;
        annualEstimatedBankInterest += bal * (accIntRate / 100.0);
      }
      bankAccountsBreakdown.add({
        'name': accName,
        'bankName': bankName,
        'branchName': branchName,
        'type': accType,
        'interestRate': isCash ? 0.0 : accIntRate,
        'balance': bal,
        'isCash': isCash,
      });
    }

    double recordedBankInterest = 0.0;
    for (final rawTx in entireFYTransactions) {
      final tx = Map<dynamic, dynamic>.from(rawTx);
      final title = (tx['title'] ?? '').toString().toLowerCase();
      if (tx['categoryEffect'] == 'incomeCredit' && (title.contains('વ્યાજ') || title.contains('interest'))) {
        recordedBankInterest += (tx['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final double effectiveBankInterest = recordedBankInterest > 0 ? recordedBankInterest : annualEstimatedBankInterest;
    final double weightedBankRate = bankSavingsBalance > 0
        ? (annualEstimatedBankInterest / bankSavingsBalance) * 100.0
        : defaultBankInterestRate;

    final double directEquityTotal = directStocksVal + directEtfVal;
    final double mfTotalVal = mfEquityVal + mfDebtVal + mfHybridVal + mfElssVal;
    final double fixedIncomeTotalVal = fdVal + bondVal + pliVal + ppfPostOfficeVal;
    final double bullionTotalVal = gold24Val + gold22Val + silverVal + otherMetalsVal;
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
      'otherMetalsVal': otherMetalsVal,
      'bullionTotalVal': bullionTotalVal,
      'houseFlatVal': houseFlatVal,
      'farmLandVal': farmLandVal,
      'shopOfficeVal': shopOfficeVal,
      'plotLandVal': plotLandVal,
      'otherPhysicalVal': otherPhysicalVal,
      'physicalAssetsVal': physicalAssetsVal,
      'bankSavingsBalance': bankSavingsBalance,
      'cashWalletBalance': cashWalletBalance,
      'totalLiquidSavings': totalLiquidSavings,
      'bankInterestRate': weightedBankRate,
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
  // AppBar માં ₹ (રૂપિયા) ના સંકેત પર ક્લિક કરતાં ખુલતી ૫ ટેબની સ્ક્રીન:
  // ૧. રોકાણ & બચત (%) - દરેક કેટેગરી નીચે + નિશાની અને ૬ઠ્ઠી કેટેગરી સ્થાવર સંપત્તિ (મકાન, ખેતર, દુકાનો)
  // ૨. રિસ્ક કેપેસિટી પ્રશ્નો - રિયલ એસ્ટેટ પ્રશ્નો, રીસેટ બટન, એક પછી એક પ્રશ્નો (Step-by-step), લોક/અનલોક & કન્ટીન્યુ
  // ૩. રિસ્ક સ્ટ્રેટેજી સરખામણી - ટેબ ૨ માં લોક કરેલ સ્ટ્રેટેજી અને હાલના રોકાણની સરખામણી
  // ૪. મારી કસ્ટમ સ્ટ્રેટેજી - સ્લાઇડર વડે કસ્ટમ સ્ટ્રેટેજી અને સરખામણી
  // ૫. ભવિષ્યનું મૂલ્ય (1, 5, 10, 20, 30 વર્ષ) - ઓટો અથવા મેન્યુઅલ વૃદ્ધિ દર સાથે પ્રોજેક્શન
  // =========================================================
  void _openAnnualTaxAndExpenseDialog() {
    // કઈ મુખ્ય કેટેગરીની પેટા-કેટેગરી (+) ખુલ્લી છે તેનો સેટ
    final Set<int> expandedCategories = {};
    final Set<int> expandedProjectionYears = {};

    // ટેબ ૨ માટે એક-પછી-એક પ્રશ્નનો ઇન્ડેક્સ (0 થી 7 પ્રશ્નો, 8 = અંતિમ મૂલ્યાંકન અને સ્ટ્રેટેજી)
    bool isLockedInit = settingsBox.get('isRiskStrategyLocked', defaultValue: false) == true;
    int currentQuestionStep = isLockedInit ? 8 : 0;

    // ટેબ ૫ માટે પ્રોજેક્શન સેટિંગ્સ
    String projectionGrowthMode = settingsBox.get('proj_growth_mode', defaultValue: 'auto').toString(); // 'auto' OR 'manual'
    double manualAnnualGrowthRate = (settingsBox.get('proj_manual_rate', defaultValue: 12.0) as num).toDouble();
    String projectionStrategySource = settingsBox.get('proj_strategy_source', defaultValue: 'locked_risk').toString(); // 'locked_risk' OR 'custom_strat'
    double monthlySipAddition = (settingsBox.get('proj_monthly_sip', defaultValue: 0.0) as num).toDouble();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) {
          return DefaultTabController(
            length: 5,
            child: StatefulBuilder(
              builder: (tabCtx, setPageState) {
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
                final double otherMetalsVal = (data['otherMetalsVal'] as num).toDouble();
                final double bullionTotal = (data['bullionTotalVal'] as num).toDouble();

                final double houseFlatVal = (data['houseFlatVal'] as num).toDouble();
                final double farmLandVal = (data['farmLandVal'] as num).toDouble();
                final double shopOfficeVal = (data['shopOfficeVal'] as num).toDouble();
                final double plotLandVal = (data['plotLandVal'] as num).toDouble();
                final double otherPhysicalVal = (data['otherPhysicalVal'] as num).toDouble();
                final double physicalVal = (data['physicalAssetsVal'] as num).toDouble();

                final double bankSavings = (data['bankSavingsBalance'] as num).toDouble();
                final double cashBal = (data['cashWalletBalance'] as num).toDouble();
                final double liquidTotal = (data['totalLiquidSavings'] as num).toDouble();
                final double bankIntRate = (data['bankInterestRate'] as num).toDouble();
                final double annualBankIntRs = (data['effectiveBankInterest'] as num).toDouble();

                double pctOfGrand(double v) => grandTotal > 0 ? (v / grandTotal) * 100.0 : 0.0;
                double pctOfInv(double v) => totalInvOnly > 0 ? (v / totalInvOnly) * 100.0 : 0.0;

                // --- ટેબ ૨ માટે: ૮ રિસ્ક કેપેસિટી પ્રશ્નો (રિયલ એસ્ટેટ સહિત) ---
                int q1Age = (settingsBox.get('risk_q1_age', defaultValue: 2) as num).toInt();
                int q2Horizon = (settingsBox.get('risk_q2_horizon', defaultValue: 2) as num).toInt();
                int q3DropReact = (settingsBox.get('risk_q3_drop', defaultValue: 2) as num).toInt();
                int q4IncomeStab = (settingsBox.get('risk_q4_income', defaultValue: 2) as num).toInt();
                int q5Emergency = (settingsBox.get('risk_q5_emerg', defaultValue: 2) as num).toInt();
                int q6Goal = (settingsBox.get('risk_q6_goal', defaultValue: 2) as num).toInt();
                int q7RealEstatePref = (settingsBox.get('risk_q7_realestate_pref', defaultValue: 2) as num).toInt();
                int q8RealEstateHorizon = (settingsBox.get('risk_q8_realestate_horizon', defaultValue: 2) as num).toInt();

                final List<Map<String, dynamic>> riskQuestions = [
                  {
                    'key': 'risk_q1_age',
                    'val': q1Age,
                    'icon': Icons.person_outline,
                    'question': '૧. તમારી ઉંમરનો ગાળો શું છે?',
                    'options': ['60+ વર્ષ (નિવૃત્ત)', '45 થી 60 વર્ષ', '30 થી 45 વર્ષ', '30 વર્ષથી ઓછી'],
                  },
                  {
                    'key': 'risk_q2_horizon',
                    'val': q2Horizon,
                    'icon': Icons.timelapse,
                    'question': '૨. તમે કેટલા સમયગાળા માટે રોકાણ જાળવી શકો છો?',
                    'options': ['1 થી 3 વર્ષ (ટૂંકા ગાળા)', '3 થી 5 વર્ષ (મધ્યમ ગાળા)', '5 થી 10 વર્ષ (લાંબા ગાળા)', '10+ વર્ષ (લાંબા ગાળાનું વેલ્થ ક્રિએશન)'],
                  },
                  {
                    'key': 'risk_q3_drop',
                    'val': q3DropReact,
                    'icon': Icons.trending_down,
                    'question': '૩. જો શેરબજાર અચાનક 15-20% ઘટે તો તમે શું કરશો?',
                    'options': ['નુકસાનથી બચવા તરત વેચી દઈશ', 'થોડું વેચીને FD માં મૂકીશ', 'રોકાણ જાળવી રાખીશ (Hold)', 'ઘટાડામાં વધુ ખરીદી (Buy More) કરીશ'],
                  },
                  {
                    'key': 'risk_q4_income',
                    'val': q4IncomeStab,
                    'icon': Icons.work_outline,
                    'question': '૪. તમારી આવકની સ્થિરતા કેવી છે?',
                    'options': ['અનિશ્ચિત આવક', 'સામાન્ય ખાનગી/ધંધાકીય આવક', 'સ્થિર માસિક પગાર / સારો વ્યવસાય', 'સરકારી/સુરક્ષિત પગાર + વધારાની આવક'],
                  },
                  {
                    'key': 'risk_q5_emerg',
                    'val': q5Emergency,
                    'icon': Icons.health_and_safety_outlined,
                    'question': '૫. તમારી પાસે 6 મહિનાના ખર્ચ જેટલું ઇમરજન્સી ફંડ છે?',
                    'options': ['ના, બિલકુલ નથી', '1-2 મહિના પૂરતું છે', '3-5 મહિના પૂરતું છે', 'હા, 6+ મહિનાનું સંપૂર્ણ સુરક્ષિત ફંડ છે'],
                  },
                  {
                    'key': 'risk_q6_goal',
                    'val': q6Goal,
                    'icon': Icons.flag_outlined,
                    'question': '૬. તમારા રોકાણનો મુખ્ય હેતુ શું છે?',
                    'options': ['માત્ર મૂડીની સુરક્ષા (6-7% વળતર)', 'નિયમિત વ્યાજ અને સુરક્ષા (8-9% વળતર)', 'સંતુલિત વૃદ્ધિ અને ટેક્સ બચત (10-12% વળતર)', 'ઉચ્ચ સંપત્તિ સર્જન (13-16%+ વળતર)'],
                  },
                  {
                    'key': 'risk_q7_realestate_pref',
                    'val': q7RealEstatePref,
                    'icon': Icons.home_work_outlined,
                    'question': '૭. મકાન, ખેતર કે દુકાન (રિયલ એસ્ટેટ) જેવી સ્થાવર સંપત્તિમાં રોકાણ અંગે તમારો અભિગમ શું છે?',
                    'options': [
                      'હું માત્ર લિક્વિડ નાણાકીય રોકાણ (FD/MF) જ પસંદ કરું છું (0-5%)',
                      'રહેઠાણ પૂરતું મકાન / થોડું રોકાણ રાખવું ગમે છે (10-15%)',
                      'મકાન, ખેતર કે દુકાનમાંથી ભાડા/મૂડી વૃદ્ધિ માટે સંતુલિત રોકાણ (18-25%)',
                      'લાંબા ગાળે જમીન, ખેતર અને કોમર્શિયલ દુકાનોમાં મોટું રોકાણ પસંદ છે (28-35%)',
                    ],
                  },
                  {
                    'key': 'risk_q8_realestate_horizon',
                    'val': q8RealEstateHorizon,
                    'icon': Icons.landscape_outlined,
                    'question': '૮. સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાન) માં રોકાયેલ મૂડી તરત રોકડમાં ન ફેરવી શકાય (Illiquidity) તો તમને ચાલે?',
                    'options': [
                      'ના, મને ગમે ત્યારે તરત રોકડ મળે તેવું જ રોકાણ જોઈએ',
                      'થોડી મૂડી 3-5 વર્ષ બ્લોક રહે તો વાંધો નથી',
                      'હા, 5-10 વર્ષ સુધી સ્થાવર સંપત્તિ જાળવી શકું છું',
                      'હા, પેઢીગત સંપત્તિ અને ભાડાની આવક માટે 10-20+ વર્ષ રાખી શકું છું',
                    ],
                  },
                ];

                final int finPoints = q1Age + q2Horizon + q3DropReact + q4IncomeStab + q5Emergency + q6Goal; // Max 18
                final int rePoints = q7RealEstatePref + q8RealEstateHorizon; // Max 6
                final int totalRiskPoints = finPoints + rePoints; // Max 24
                final double riskScore100 = (totalRiskPoints / 24.0) * 100.0;

                // રિયલ એસ્ટેટ ટકાવારી (પ્રશ્ન 7 અને 8 ના આધારે 5% થી 30%)
                final double calcRealEstatePct = (5.0 + (rePoints * 4.0)).roundToDouble(); // 5% to 29%
                final double remPctPool = 100.0 - calcRealEstatePct;

                String riskProfileName;
                Color riskColor;
                Map<String, double> evaluatedPct;

                if (finPoints >= 13) {
                  riskProfileName = 'વૃદ્ધિલક્ષી / આક્રમક (Aggressive Growth)';
                  riskColor = Colors.deepPurple;
                  final eq = (remPctPool * 0.52).roundToDouble();
                  final debt = (remPctPool * 0.12).roundToDouble();
                  final fd = (remPctPool * 0.12).roundToDouble();
                  final gold = (remPctPool * 0.12).roundToDouble();
                  final bank = math.max(0.0, 100.0 - (eq + debt + fd + gold + calcRealEstatePct));
                  evaluatedPct = {
                    'ઇક્વિટી (શેર + ઇક્વિટી MF)': eq,
                    'ડેબ્ટ અને હાઇબ્રીડ MF': debt,
                    'FD / બોન્ડ / PLI / PPF': fd,
                    'સોનું / ચાંદી (ધાતુઓ)': gold,
                    'બેંક બચત અને રોકડ': bank,
                    'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': calcRealEstatePct,
                  };
                } else if (finPoints >= 8) {
                  riskProfileName = 'મધ્યમ અને સંતુલિત (Moderate Balanced)';
                  riskColor = Colors.teal.shade700;
                  final eq = (remPctPool * 0.36).roundToDouble();
                  final debt = (remPctPool * 0.16).roundToDouble();
                  final fd = (remPctPool * 0.22).roundToDouble();
                  final gold = (remPctPool * 0.12).roundToDouble();
                  final bank = math.max(0.0, 100.0 - (eq + debt + fd + gold + calcRealEstatePct));
                  evaluatedPct = {
                    'ઇક્વિટી (શેર + ઇક્વિટી MF)': eq,
                    'ડેબ્ટ અને હાઇબ્રીડ MF': debt,
                    'FD / બોન્ડ / PLI / PPF': fd,
                    'સોનું / ચાંદી (ધાતુઓ)': gold,
                    'બેંક બચત અને રોકડ': bank,
                    'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': calcRealEstatePct,
                  };
                } else {
                  riskProfileName = 'સુરક્ષિત / મૂડી રક્ષણ (Conservative)';
                  riskColor = Colors.blue.shade800;
                  final eq = (remPctPool * 0.18).roundToDouble();
                  final debt = (remPctPool * 0.16).roundToDouble();
                  final fd = (remPctPool * 0.34).roundToDouble();
                  final gold = (remPctPool * 0.12).roundToDouble();
                  final bank = math.max(0.0, 100.0 - (eq + debt + fd + gold + calcRealEstatePct));
                  evaluatedPct = {
                    'ઇક્વિટી (શેર + ઇક્વિટી MF)': eq,
                    'ડેબ્ટ અને હાઇબ્રીડ MF': debt,
                    'FD / બોન્ડ / PLI / PPF': fd,
                    'સોનું / ચાંદી (ધાતુઓ)': gold,
                    'બેંક બચત અને રોકડ': bank,
                    'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': calcRealEstatePct,
                  };
                }

                final bool isRiskStrategyLocked = settingsBox.get('isRiskStrategyLocked', defaultValue: false) == true;
                Map<String, double> activeLockedRiskStrategy = Map<String, double>.from(evaluatedPct);
                final rawSavedLocked = settingsBox.get('lockedRiskStrategy');
                if (isRiskStrategyLocked && rawSavedLocked is Map) {
                  activeLockedRiskStrategy = rawSavedLocked.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
                }

                // કુલ સંપત્તિના આધારે વાસ્તવિક રોકાણ (૬ કેટેગરીઓ)
                final double wealthBase = math.max(1.0, grandTotal);
                final Map<String, double> actualRsForRiskMap = {
                  'ઇક્વિટી (શેર + ઇક્વિટી MF)': directEquity + mfEquity + mfElss,
                  'ડેબ્ટ અને હાઇબ્રીડ MF': mfDebt + mfHybrid,
                  'FD / બોન્ડ / PLI / PPF': fixedTotal,
                  'સોનું / ચાંદી (ધાતુઓ)': bullionTotal,
                  'બેંક બચત અને રોકડ': liquidTotal,
                  'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': physicalVal,
                };
                final Map<String, double> actualPctForRiskMap = actualRsForRiskMap.map(
                  (k, v) => MapEntry(k, (v / wealthBase) * 100.0),
                );

                // --- ટેબ ૪ માટે: યુઝરની પોતાની કસ્ટમ સ્ટ્રેટેજી (%) ---
                double stDirectEq = (settingsBox.get('strat_direct_eq', defaultValue: 15.0) as num).toDouble();
                double stMfEq = (settingsBox.get('strat_mf_eq', defaultValue: 20.0) as num).toDouble();
                double stMfDebtHyb = (settingsBox.get('strat_mf_debthyb', defaultValue: 10.0) as num).toDouble();
                double stFixed = (settingsBox.get('strat_fixed', defaultValue: 15.0) as num).toDouble();
                double stBullion = (settingsBox.get('strat_bullion', defaultValue: 10.0) as num).toDouble();
                double stBank = (settingsBox.get('strat_bank', defaultValue: 10.0) as num).toDouble();
                double stRealEstate = (settingsBox.get('strat_real_estate', defaultValue: 20.0) as num).toDouble();
                final double totalStrategyPct = stDirectEq + stMfEq + stMfDebtHyb + stFixed + stBullion + stBank + stRealEstate;

                // --- ટેબ ૫ માટે: એસેટ ક્લાસ પ્રમાણે અંદાજિત વાર્ષિક વળતર દર (Auto CAGR %) ---
                final Map<String, double> defaultCategoryCagr = {
                  'ઇક્વિટી (શેર + ઇક્વિટી MF)': 14.0,
                  'ડેબ્ટ અને હાઇબ્રીડ MF': 8.5,
                  'FD / બોન્ડ / PLI / PPF': 7.2,
                  'સોનું / ચાંદી (ધાતુઓ)': 10.5,
                  'બેંક બચત અને રોકડ': bankIntRate > 0 ? bankIntRate : 3.5,
                  'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': 11.5,
                };

                final Map<String, double> strategyForProjection = projectionStrategySource == 'custom_strat'
                    ? {
                        'ઇક્વિટી (શેર + ઇક્વિટી MF)': stDirectEq + stMfEq,
                        'ડેબ્ટ અને હાઇબ્રીડ MF': stMfDebtHyb,
                        'FD / બોન્ડ / PLI / PPF': stFixed,
                        'સોનું / ચાંદી (ધાતુઓ)': stBullion,
                        'બેંક બચત અને રોકડ': stBank,
                        'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': stRealEstate,
                      }
                    : activeLockedRiskStrategy;

                double autoWeightedRate = 0.0;
                double sumStratWeights = 0.0;
                strategyForProjection.forEach((catName, weightPct) {
                  final r = defaultCategoryCagr[catName] ?? 10.0;
                  autoWeightedRate += weightPct * r;
                  sumStratWeights += weightPct;
                });
                if (sumStratWeights > 0) {
                  autoWeightedRate = autoWeightedRate / sumStratWeights;
                } else {
                  autoWeightedRate = 11.0;
                }

                final double effectiveProjectionRate =
                    projectionGrowthMode == 'auto' ? autoWeightedRate : manualAnnualGrowthRate;

                double calculateFutureWealth(double presentVal, double annualRatePct, int years, double monthlySip) {
                  final double r = annualRatePct / 100.0;
                  final double fvLumpsum = presentVal * math.pow(1.0 + r, years);
                  double fvSip = 0.0;
                  if (monthlySip > 0 && r > 0) {
                    final double mr = r / 12.0;
                    final int months = years * 12;
                    fvSip = monthlySip * ((math.pow(1.0 + mr, months) - 1.0) / mr) * (1.0 + mr);
                  } else if (monthlySip > 0) {
                    fvSip = monthlySip * years * 12;
                  }
                  return fvLumpsum + fvSip;
                }

                final double baseProjectionCapital = grandTotal > 0 ? grandTotal : 100000.0;
                final List<int> milestoneYears = [1, 5, 10, 20, 30];

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('સંપૂર્ણ રોકાણ અને બચત વિશ્લેષણ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    bottom: const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(icon: Icon(Icons.pie_chart, size: 18), text: '૧. રોકાણ & બચત (%)'),
                        Tab(icon: Icon(Icons.quiz, size: 18), text: '૨. રિસ્ક કેપેસિટી પ્રશ્નો'),
                        Tab(icon: Icon(Icons.compare_arrows, size: 18), text: '૩. રિસ્ક સ્ટ્રેટેજી સરખામણી'),
                        Tab(icon: Icon(Icons.tune, size: 18), text: '૪. મારી કસ્ટમ સ્ટ્રેટેજી'),
                        Tab(icon: Icon(Icons.auto_graph, size: 18), text: '૫. ભવિષ્યનું મૂલ્ય (1-30 વર્ષ)'),
                      ],
                    ),
                  ),
                  body: TabBarView(
                    children: [
                      // =========================================================
                      // ટેબ ૧: સંપૂર્ણ રોકાણ અને બચતનું ટકાવારી પ્રમાણે વિશ્લેષણ (+ નિશાની સાથે)
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: adaptiveTintBg(Colors.teal),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '📊 કુલ રોકાણ અને બચત સારાંશ (૬ મુખ્ય કેટેગરીઓ)',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
                                    ),
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _metricColumn('કુલ સંપત્તિ (રોકાણ+બચત)', '₹${grandTotal.toStringAsFixed(0)}', adaptiveAccentText(Colors.teal)),
                                        _metricColumn('કુલ રોકાણ મૂલ્ય', '₹${totalInvOnly.toStringAsFixed(0)} (${pctOfGrand(totalInvOnly).toStringAsFixed(1)}%)', adaptiveAccentText(Colors.blue)),
                                        _metricColumn('બેંક + રોકડ બચત', '₹${liquidTotal.toStringAsFixed(0)} (${pctOfGrand(liquidTotal).toStringAsFixed(1)}%)', adaptiveAccentText(Colors.green)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (grandTotal > 0)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      const Text('વિવિધ ૬ એસેટ ક્લાસમાં રોકાણની ટકાવારી (%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
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
                                          _legendBadge(Colors.indigo, '૧. ઇક્વિટી'),
                                          _legendBadge(Colors.teal, '૨. મ્યુચ્યુઅલ ફંડ'),
                                          _legendBadge(Colors.orange, '૩. FD/બોન્ડ/PLI'),
                                          _legendBadge(Colors.amber, '૪. સોનું/ચાંદી'),
                                          _legendBadge(Colors.green, '૫. બેંક બચત'),
                                          _legendBadge(Colors.purple, '૬. સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાન)'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              child: Text(
                                '💡 દરેક મુખ્ય કેટેગરી નીચે આપેલ [+] નિશાની પર ક્લિક કરીને તેની પેટા-કેટેગરીઓ જોઈ શકાશે:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal),
                              ),
                            ),

                            // ૧. ડાયરેક્ટ ઇક્વિટી
                            _buildExpandableCategoryCard(
                              catIndex: 1,
                              isExpanded: expandedCategories.contains(1),
                              onToggle: () => setPageState(() {
                                if (expandedCategories.contains(1)) {
                                  expandedCategories.remove(1);
                                } else {
                                  expandedCategories.add(1);
                                }
                              }),
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

                            // ૨. મ્યુચ્યુઅલ ફંડ
                            _buildExpandableCategoryCard(
                              catIndex: 2,
                              isExpanded: expandedCategories.contains(2),
                              onToggle: () => setPageState(() {
                                if (expandedCategories.contains(2)) {
                                  expandedCategories.remove(2);
                                } else {
                                  expandedCategories.add(2);
                                }
                              }),
                              title: '૨. મ્યુચ્યુઅલ ફંડ (Equity, Debt, Hybrid, ELSS)',
                              icon: Icons.pie_chart,
                              color: Colors.teal,
                              totalAmount: mfTotal,
                              pctOfTotalWealth: pctOfGrand(mfTotal),
                              pctOfInvestments: pctOfInv(mfTotal),
                              subItems: [
                                {'label': 'ઇક્વિટી મ્યુચ્યુઅલ ફંડ (Equity MF)', 'amt': mfEquity, 'pct': pctOfGrand(mfEquity)},
                                {'label': 'ડેબ્ટ મ્યુચ્યુઅલ ફંડ (Debt / Liquid MF)', 'amt': mfDebt, 'pct': pctOfGrand(mfDebt)},
                                {'label': 'હાઇબ્રીડ મ્યુચ્યુઅલ ફંડ (Hybrid / Balanced)', 'amt': mfHybrid, 'pct': pctOfGrand(mfHybrid)},
                                {'label': 'ELSS / ટેક્સ સેવર મ્યુચ્યુઅલ ફંડ', 'amt': mfElss, 'pct': pctOfGrand(mfElss)},
                              ],
                              extraBottomWidget: mfInvestmentsBox.isNotEmpty
                                  ? Align(
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
                                    )
                                  : null,
                            ),

                            // ૩. FD, બોન્ડ, PLI, PPF
                            _buildExpandableCategoryCard(
                              catIndex: 3,
                              isExpanded: expandedCategories.contains(3),
                              onToggle: () => setPageState(() {
                                if (expandedCategories.contains(3)) {
                                  expandedCategories.remove(3);
                                } else {
                                  expandedCategories.add(3);
                                }
                              }),
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

                            // ૪. કિંમતી ધાતુઓ
                            _buildExpandableCategoryCard(
                              catIndex: 4,
                              isExpanded: expandedCategories.contains(4),
                              onToggle: () => setPageState(() {
                                if (expandedCategories.contains(4)) {
                                  expandedCategories.remove(4);
                                } else {
                                  expandedCategories.add(4);
                                }
                              }),
                              title: '૪. વિવિધ ધાતુઓમાં રોકાણ (સોનું, ચાંદી અને અન્ય)',
                              icon: Icons.monetization_on,
                              color: Colors.amber.shade800,
                              totalAmount: bullionTotal,
                              pctOfTotalWealth: pctOfGrand(bullionTotal),
                              pctOfInvestments: pctOfInv(bullionTotal),
                              subItems: [
                                {'label': 'સોનું 24K (Gold 24K)', 'amt': gold24Val, 'pct': pctOfGrand(gold24Val)},
                                {'label': 'સોનું 22K (Gold 22K - દાગીના)', 'amt': gold22Val, 'pct': pctOfGrand(gold22Val)},
                                {'label': 'ચાંદી (Silver)', 'amt': silverVal, 'pct': pctOfGrand(silverVal)},
                                if (otherMetalsVal > 0)
                                  {'label': 'અન્ય કિંમતી ધાતુઓ (Platinum / 18K / Custom)', 'amt': otherMetalsVal, 'pct': pctOfGrand(otherMetalsVal)},
                              ],
                            ),

                            // ૫. બેંક ખાતાઓમાં બચત અને મળતું વ્યાજ
                            _buildExpandableCategoryCard(
                              catIndex: 5,
                              isExpanded: expandedCategories.contains(5),
                              onToggle: () => setPageState(() {
                                if (expandedCategories.contains(5)) {
                                  expandedCategories.remove(5);
                                } else {
                                  expandedCategories.add(5);
                                }
                              }),
                              title: '૫. બેંક ખાતાઓમાં બચત અને મળતું વ્યાજ (%)',
                              icon: Icons.account_balance,
                              color: Colors.green,
                              totalAmount: liquidTotal,
                              pctOfTotalWealth: pctOfGrand(liquidTotal),
                              pctOfInvestments: 0.0,
                              subtitleOverride: 'સરેરાશ બેંક વ્યાજ દર: ${bankIntRate.toStringAsFixed(2)}% | વાર્ષિક વ્યાજ: ₹${annualBankIntRs.toStringAsFixed(0)}',
                              subItems: [
                                {'label': 'બેંક બચત ખાતાઓની કુલ સિલક', 'amt': bankSavings, 'pct': pctOfGrand(bankSavings)},
                                {'label': 'રોકડ સિલક (Cash Wallet)', 'amt': cashBal, 'pct': pctOfGrand(cashBal)},
                                ...(data['bankAccountsBreakdown'] as List<Map<String, dynamic>>).map((acc) {
                                  final double b = (acc['balance'] as num).toDouble();
                                  final bool isC = acc['isCash'] == true;
                                  final double r = (acc['interestRate'] as num?)?.toDouble() ?? bankIntRate;
                                  return {
                                    'label': '${acc['name']}${!isC ? ' (વ્યાજ: ${r.toStringAsFixed(1)}%)' : ''}',
                                    'amt': b,
                                    'pct': pctOfGrand(b),
                                  };
                                }),
                              ],
                            ),

                            // ૬. છઠ્ઠી નવી મુખ્ય કેટેગરી: સ્થાવર સંપત્તિ / રિયલ એસ્ટેટ (મકાન, ખેતર, દુકાનો, પ્લોટ)
                            _buildExpandableCategoryCard(
                              catIndex: 6,
                              isExpanded: expandedCategories.contains(6),
                              onToggle: () => setPageState(() {
                                if (expandedCategories.contains(6)) {
                                  expandedCategories.remove(6);
                                } else {
                                  expandedCategories.add(6);
                                }
                              }),
                              title: '૬. સ્થાવર સંપત્તિ અને રિયલ એસ્ટેટ (મકાન, ખેતર, દુકાનો)',
                              icon: Icons.home_work,
                              color: Colors.purple,
                              totalAmount: physicalVal,
                              pctOfTotalWealth: pctOfGrand(physicalVal),
                              pctOfInvestments: pctOfInv(physicalVal),
                              subItems: [
                                {'label': 'મકાન / ફ્લેટ / રહેઠાણ (House / Flat)', 'amt': houseFlatVal, 'pct': pctOfGrand(houseFlatVal)},
                                {'label': 'ખેતર / ખેતીની જમીન (Agricultural Land)', 'amt': farmLandVal, 'pct': pctOfGrand(farmLandVal)},
                                {'label': 'દુકાનો / ઓફિસ / કોમર્શિયલ મિલકત (Shops / Office)', 'amt': shopOfficeVal, 'pct': pctOfGrand(shopOfficeVal)},
                                {'label': 'પ્લોટ / બિન-ખેતી જમીન (Plots / Land)', 'amt': plotLandVal, 'pct': pctOfGrand(plotLandVal)},
                                {'label': 'વાહન / અન્ય સ્થાવર મિલકત', 'amt': otherPhysicalVal, 'pct': pctOfGrand(otherPhysicalVal)},
                              ],
                            ),
                          ],
                        ),
                      ),

                      // =========================================================
                      // ટેબ ૨: રિસ્ક કેપેસિટી પ્રશ્નો (એક પછી એક પ્રશ્નો + રીસેટ + લોક/અનલોક & કન્ટીન્યુ)
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ટોપ હેડર + રીસેટ બટન
                            Card(
                              color: riskColor.withOpacity(isDark ? 0.25 : 0.10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: riskColor.withOpacity(0.5)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '🎯 રિસ્ક કેપેસિટી અને સ્ટ્રેટેજી મૂલ્યાંકન',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: isDark ? Colors.white : riskColor),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(color: Colors.redAccent),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          ),
                                          icon: const Icon(Icons.refresh, size: 16),
                                          label: const Text('રીસેટ કરો', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                          onPressed: () {
                                            for (final q in riskQuestions) {
                                              settingsBox.put(q['key'].toString(), 2);
                                            }
                                            settingsBox.put('isRiskStrategyLocked', false);
                                            setPageState(() {
                                              currentQuestionStep = 0;
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('🔄 તમામ પ્રશ્નો રીસેટ થઈ ગયા છે. હવે ફરીથી મૂલ્યાંકન કરો!'),
                                                backgroundColor: Colors.teal,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isRiskStrategyLocked
                                          ? '🔒 તમારી સ્ટ્રેટેજી હાલમાં લોક કરેલ છે. જો નવી સ્ટ્રેટેજી બનાવવી હોય તો નીચે "અનલોક" બટન દબાવી ફરીથી પ્રશ્નોના જવાબ આપો.'
                                          : 'નીચે એક પછી એક આવતા ૮ પ્રશ્નો (નાણાકીય + મકાન/ખેતર/દુકાન રિયલ એસ્ટેટ) ના જવાબ આપો અને અંતે સ્ટ્રેટેજી લોક કરો.',
                                      style: TextStyle(fontSize: 12, color: primaryTextColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // જો હજુ પ્રશ્નો ચાલુ હોય (Step 0 થી 7) અને લોક ન હોય
                            if (currentQuestionStep < riskQuestions.length && !isRiskStrategyLocked) ...[
                              Card(
                                elevation: 3,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Chip(
                                            backgroundColor: Colors.teal.withOpacity(0.15),
                                            label: Text(
                                              'પ્રશ્ન ${currentQuestionStep + 1} / ${riskQuestions.length}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => setPageState(() => currentQuestionStep = riskQuestions.length),
                                            child: const Text('સીધું પરિણામ જુઓ ⏭️', style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: (currentQuestionStep + 1) / riskQuestions.length,
                                          minHeight: 8,
                                          backgroundColor: Colors.grey.withOpacity(0.25),
                                          color: Colors.teal,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(riskQuestions[currentQuestionStep]['icon'] as IconData, color: Colors.teal, size: 26),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              riskQuestions[currentQuestionStep]['question'].toString(),
                                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      ...List.generate(
                                        (riskQuestions[currentQuestionStep]['options'] as List).length,
                                        (optIdx) {
                                          final String optText = (riskQuestions[currentQuestionStep]['options'] as List)[optIdx].toString();
                                          final int selectedVal = (riskQuestions[currentQuestionStep]['val'] as num).toInt();
                                          final bool isSelected = selectedVal == optIdx;
                                          final String qKey = riskQuestions[currentQuestionStep]['key'].toString();

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 5),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(12),
                                              onTap: () {
                                                settingsBox.put(qKey, optIdx);
                                                setPageState(() {
                                                  if (currentQuestionStep < riskQuestions.length - 1) {
                                                    currentQuestionStep++;
                                                  } else {
                                                    currentQuestionStep = riskQuestions.length;
                                                  }
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? Colors.teal.withOpacity(isDark ? 0.35 : 0.14)
                                                      : Colors.grey.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: isSelected ? Colors.teal : Colors.grey.withOpacity(0.35),
                                                    width: isSelected ? 2 : 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                                      color: isSelected ? Colors.teal : Colors.grey,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        optText,
                                                        style: TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: currentQuestionStep > 0
                                                ? () => setPageState(() => currentQuestionStep--)
                                                : null,
                                            icon: const Icon(Icons.arrow_back, size: 16),
                                            label: const Text('પાછળ'),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                            onPressed: () {
                                              setPageState(() {
                                                if (currentQuestionStep < riskQuestions.length - 1) {
                                                  currentQuestionStep++;
                                                } else {
                                                  currentQuestionStep = riskQuestions.length;
                                                }
                                              });
                                            },
                                            icon: const Icon(Icons.arrow_forward, size: 16),
                                            label: Text(currentQuestionStep < riskQuestions.length - 1 ? 'આગળનો પ્રશ્ન' : 'મૂલ્યાંકન કરો'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ] else ...[
                              // છેલ્લે મૂલ્યાંકન કરી સ્ટ્રેટેજી બતાવે + લોક / અનલોક અને કન્ટીન્યુ વિકલ્પ
                              Card(
                                elevation: 3,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '✅ મૂલ્યાંકન પરિણામ: $riskProfileName',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.tealAccent : riskColor),
                                            ),
                                          ),
                                          Chip(
                                            backgroundColor: riskColor,
                                            label: Text(
                                              'સ્કોર: ${riskScore100.toStringAsFixed(0)}/100',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(),
                                      const Text(
                                        'તમારા જવાબો (નાણાકીય + રિયલ એસ્ટેટ) ના આધારે સૂચિત સ્ટ્રેટેજી પ્રમાણ (%):',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 8),
                                      ...(isRiskStrategyLocked ? activeLockedRiskStrategy : evaluatedPct).entries.map((e) {
                                        final double targetAmt = wealthBase * (e.value / 100.0);
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(child: Text('• ${e.key}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                                              Text(
                                                '${e.value.toStringAsFixed(1)}% (₹${targetAmt.toStringAsFixed(0)})',
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                      const SizedBox(height: 14),
                                      if (!isRiskStrategyLocked)
                                        Row(
                                          children: [
                                            OutlinedButton.icon(
                                              icon: const Icon(Icons.edit_note, size: 18),
                                              label: const Text('પ્રશ્નો બદલો'),
                                              onPressed: () => setPageState(() => currentQuestionStep = 0),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.teal,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                ),
                                                icon: const Icon(Icons.lock),
                                                label: const Text('લોક અને કન્ટીન્યુ (Lock & Continue)', style: TextStyle(fontWeight: FontWeight.bold)),
                                                onPressed: () {
                                                  // જૂની સ્ટ્રેટેજી કાઢી નવી સ્ટ્રેટેજી સેવ અને લોક કરો, અને ટેબ ૩ પર જાઓ
                                                  settingsBox.put('lockedRiskStrategy', evaluatedPct);
                                                  settingsBox.put('isRiskStrategyLocked', true);
                                                  setPageState(() {});
                                                  DefaultTabController.of(tabCtx).animateTo(2);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('🔒 નવી સ્ટ્રેટેજી લોક થઈ ગઈ છે! હવે ટેબ ૩ માં હાલના રોકાણ સાથે સરખામણી જુઓ.'),
                                                      backgroundColor: Colors.teal,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        Column(
                                          children: [
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.green),
                                              ),
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.lock_clock, color: Colors.green),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'આ સ્ટ્રેટેજી લોક કરેલ છે. જો સ્ટ્રેટેજી બદલવી હોય તો "અનલોક કરો" દબાવી ફરીથી પ્રશ્નોના જવાબ આપો.',
                                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.orange.shade800,
                                                      side: BorderSide(color: Colors.orange.shade800),
                                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                                    ),
                                                    icon: const Icon(Icons.lock_open),
                                                    label: const Text('અનલોક કરી નવી બનાવો', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                    onPressed: () {
                                                      settingsBox.put('isRiskStrategyLocked', false);
                                                      setPageState(() {
                                                        currentQuestionStep = 0;
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.teal,
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                                    ),
                                                    icon: const Icon(Icons.compare_arrows),
                                                    label: const Text('ટેબ ૩ સરખામણી જુઓ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                    onPressed: () {
                                                      DefaultTabController.of(tabCtx).animateTo(2);
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // =========================================================
                      // ટેબ ૩: લોક કરેલ રિસ્ક સ્ટ્રેટેજી અને હાલના રોકાણની સરખામણી
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: adaptiveTintBg(Colors.teal),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isRiskStrategyLocked
                                                ? '🔒 લોક કરેલ રિસ્ક સ્ટ્રેટેજી vs હાલનું રોકાણ'
                                                : '⚠️ સ્ટ્રેટેજી હજુ ટેબ ૨ માં લોક કરેલ નથી (હાલનો પ્રિવ્યુ)',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'કુલ સંપત્તિ (₹${wealthBase.toStringAsFixed(0)}) ના આધારે સરખામણી (રિયલ એસ્ટેટ સહિત)',
                                            style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      icon: Icon(isRiskStrategyLocked ? Icons.lock_open : Icons.quiz, size: 16),
                                      label: Text(isRiskStrategyLocked ? 'અનલોક / બદલો' : 'ટેબ ૨ માં લોક કરો', style: const TextStyle(fontSize: 11.5)),
                                      onPressed: () {
                                        if (isRiskStrategyLocked) {
                                          settingsBox.put('isRiskStrategyLocked', false);
                                          setPageState(() => currentQuestionStep = 0);
                                        }
                                        DefaultTabController.of(tabCtx).animateTo(1);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('⚖️ સ્ટ્રેટેજી અને હાલના રોકાણની વિભાગવાર સરખામણી:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const Divider(),
                                    ...activeLockedRiskStrategy.entries.map((entry) {
                                      final String cat = entry.key;
                                      final double recPct = entry.value;
                                      final double actPct = actualPctForRiskMap[cat] ?? 0.0;
                                      final double actRs = actualRsForRiskMap[cat] ?? 0.0;
                                      final double targetRs = wealthBase * (recPct / 100.0);
                                      final double diffPct = actPct - recPct;
                                      final double diffRs = actRs - targetRs;
                                      final bool isAligned = diffPct.abs() <= 5.0;

                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 6),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isAligned
                                              ? Colors.green.withOpacity(isDark ? 0.18 : 0.06)
                                              : Colors.orange.withOpacity(isDark ? 0.18 : 0.07),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isAligned ? Colors.green.shade400 : Colors.orange.shade400),
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
                                                Text(
                                                  'સ્ટ્રેટેજી: ${recPct.toStringAsFixed(1)}% (₹${targetRs.toStringAsFixed(0)})',
                                                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w600),
                                                ),
                                                Text(
                                                  'હાલમાં: ${actPct.toStringAsFixed(1)}% (₹${actRs.toStringAsFixed(0)})',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: (actPct / 100.0).clamp(0.0, 1.0),
                                                minHeight: 7,
                                                backgroundColor: Colors.grey.withOpacity(0.25),
                                                color: isAligned ? Colors.green : Colors.orange.shade800,
                                              ),
                                            ),
                                            if (!isAligned) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                diffRs > 0
                                                    ? '💡 સૂચન: સ્ટ્રેટેજી મુજબ આ વિભાગમાં ₹${diffRs.abs().toStringAsFixed(0)} વધુ રોકાયેલ છે.'
                                                    : '💡 સૂચન: સ્ટ્રેટેજી મુજબ આ વિભાગમાં હજુ ₹${diffRs.abs().toStringAsFixed(0)} નું રોકાણ વધારવું જોઈએ.',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: isDark ? Colors.amberAccent : Colors.orange.shade900,
                                                  fontWeight: FontWeight.w600,
                                                ),
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
                      // ટેબ ૪: મારી કસ્ટમ સ્ટ્રેટેજી (અગાઉની ટેબ ૩ હવે ટેબ ૪ માં + રિયલ એસ્ટેટ સ્લાઇડર)
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: adaptiveTintBg(Colors.indigo),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '🎯 મારી કસ્ટમ રોકાણ સ્ટ્રેટેજી (Target Allocation %)',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: adaptiveAccentText(Colors.indigo)),
                                          ),
                                        ),
                                        Chip(
                                          backgroundColor: (totalStrategyPct - 100.0).abs() < 0.5 ? Colors.green : Colors.red,
                                          label: Text(
                                            'કુલ: ${totalStrategyPct.toStringAsFixed(0)}%',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'તમે કયા વિભાગમાં કેટલા ટકા (%) રોકાણ કરવા માંગો છો તે સ્લાઇડરથી નક્કી કરો. એપ તમારા હાલના રોકાણ સાથે તેની લાઇવ સરખામણી બતાવશે.',
                                      style: TextStyle(fontSize: 11.5, color: primaryTextColor),
                                    ),
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
                                    _buildStrategySliderRow(
                                      label: '૭. સ્થાવર સંપત્તિ (મકાન / ખેતર / દુકાનો)',
                                      value: stRealEstate,
                                      onChanged: (v) {
                                        settingsBox.put('strat_real_estate', v.roundToDouble());
                                        setPageState(() {});
                                      },
                                    ),
                                    if ((totalStrategyPct - 100.0).abs() >= 0.5)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '⚠️ કુલ સરવાળો 100% હોવો જોઈએ (હાલ: ${totalStrategyPct.toStringAsFixed(0)}%)',
                                                style: const TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                                              ),
                                            ),
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
                                                  final d6 = (stBank * factor).roundToDouble();
                                                  final d7 = math.max(0.0, 100.0 - (d1 + d2 + d3 + d4 + d5 + d6));
                                                  settingsBox.put('strat_direct_eq', d1);
                                                  settingsBox.put('strat_mf_eq', d2);
                                                  settingsBox.put('strat_mf_debthyb', d3);
                                                  settingsBox.put('strat_fixed', d4);
                                                  settingsBox.put('strat_bullion', d5);
                                                  settingsBox.put('strat_bank', d6);
                                                  settingsBox.put('strat_real_estate', d7);
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
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('📊 મારી કસ્ટમ સ્ટ્રેટેજી vs વાસ્તવિક રોકાણ સરખામણી:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const Divider(),
                                    ...[
                                      {'name': '૧. ડાયરેક્ટ ઇક્વિટી (Stocks & ETF)', 'targetPct': stDirectEq, 'actualRs': directEquity},
                                      {'name': '૨. ઇક્વિટી મ્યુચ્યુઅલ ફંડ (Equity & ELSS)', 'targetPct': stMfEq, 'actualRs': mfEquity + mfElss},
                                      {'name': '૩. ડેબ્ટ અને હાઇબ્રીડ મ્યુચ્યુઅલ ફંડ', 'targetPct': stMfDebtHyb, 'actualRs': mfDebt + mfHybrid},
                                      {'name': '૪. FD / બોન્ડ / PLI / PPF', 'targetPct': stFixed, 'actualRs': fixedTotal},
                                      {'name': '૫. સોનું અને ચાંદી (ધાતુઓ)', 'targetPct': stBullion, 'actualRs': bullionTotal},
                                      {'name': '૬. બેંક બચત ખાતું અને રોકડ', 'targetPct': stBank, 'actualRs': liquidTotal},
                                      {'name': '૭. સ્થાવર સંપત્તિ (મકાન / ખેતર / દુકાનો)', 'targetPct': stRealEstate, 'actualRs': physicalVal},
                                    ].map((item) {
                                      final String title = item['name'] as String;
                                      final double tPct = (item['targetPct'] as num).toDouble();
                                      final double aRs = (item['actualRs'] as num).toDouble();
                                      final double aPct = wealthBase > 0 ? (aRs / wealthBase) * 100.0 : 0.0;
                                      final double tRs = wealthBase * (tPct / 100.0);
                                      final double diffRs = aRs - tRs;
                                      final double diffPct = aPct - tPct;
                                      final bool isMatch = diffPct.abs() <= 4.0;

                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 5),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isMatch
                                              ? Colors.teal.withOpacity(isDark ? 0.18 : 0.06)
                                              : Colors.deepOrange.withOpacity(isDark ? 0.18 : 0.06),
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
                                                    color: isMatch
                                                        ? (isDark ? Colors.tealAccent : Colors.teal.shade800)
                                                        : (isDark ? Colors.orangeAccent : Colors.deepOrange.shade800),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'મારી સ્ટ્રેટેજી: ${tPct.toStringAsFixed(1)}% (₹${tRs.toStringAsFixed(0)})',
                                                  style: TextStyle(fontSize: 11.5, color: isDark ? Colors.indigo.shade200 : Colors.indigo, fontWeight: FontWeight.w600),
                                                ),
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
                                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
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

                      // =========================================================
                      // ટેબ ૫: સ્ટ્રેટેજી પ્રમાણે જુદા જુદા સમયે (1, 5, 10, 20, 30 વર્ષ) રોકાણની કુલ કિંમત (ઓટો / મેન્યુઅલ દર)
                      // =========================================================
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: adaptiveTintBg(Colors.teal),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '🚀 ભવિષ્યનું રોકાણ મૂલ્ય અંદાજ (1, 5, 10, 20, 30 વર્ષ)',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            initialValue: projectionStrategySource,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              labelText: 'કઈ સ્ટ્રેટેજી મુજબ ગણતરી કરવી?',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'locked_risk', child: Text('રિસ્ક સ્ટ્રેટેજી (ટેબ ૨/૩)', style: TextStyle(fontSize: 12))),
                                              DropdownMenuItem(value: 'custom_strat', child: Text('મારી કસ્ટમ સ્ટ્રેટેજી (ટેબ ૪)', style: TextStyle(fontSize: 12))),
                                            ],
                                            onChanged: (v) {
                                              if (v != null) {
                                                settingsBox.put('proj_strategy_source', v);
                                                setPageState(() => projectionStrategySource = v);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('વાર્ષિક વધવાનો દર (Growth Rate):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                        SegmentedButton<String>(
                                          segments: const [
                                            ButtonSegment(value: 'auto', label: Text('ઓટો દર', style: TextStyle(fontSize: 11.5))),
                                            ButtonSegment(value: 'manual', label: Text('મેન્યુઅલ દર', style: TextStyle(fontSize: 11.5))),
                                          ],
                                          selected: {projectionGrowthMode},
                                          onSelectionChanged: (s) {
                                            settingsBox.put('proj_growth_mode', s.first);
                                            setPageState(() => projectionGrowthMode = s.first);
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (projectionGrowthMode == 'auto')
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '✨ ઓટો સ્ટ્રેટેજી વેઇટેડ વાર્ષિક વૃદ્ધિ દર: ${autoWeightedRate.toStringAsFixed(2)}% પ્રતિ વર્ષ\n'
                                          '(ઇક્વિટી 14%, મકાન/ખેતર/દુકાન 11.5%, સોનું 10.5%, ડેબ્ટ 8.5%, FD 7.2%, બેંક ${bankIntRate.toStringAsFixed(1)}% ના આધારે)',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      )
                                    else
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('મેન્યુઅલ વાર્ષિક વધવાનો દર (%):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                              Text('${manualAnnualGrowthRate.toStringAsFixed(1)}% પ્રતિ વર્ષ', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                                            ],
                                          ),
                                          Slider(
                                            value: manualAnnualGrowthRate.clamp(1.0, 35.0),
                                            min: 1.0,
                                            max: 35.0,
                                            divisions: 68,
                                            label: '${manualAnnualGrowthRate.toStringAsFixed(1)}%',
                                            onChanged: (v) {
                                              settingsBox.put('proj_manual_rate', v);
                                              setPageState(() => manualAnnualGrowthRate = v);
                                            },
                                          ),
                                        ],
                                      ),
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('હાલની કુલ મૂડી: ₹${baseProjectionCapital.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                        TextButton.icon(
                                          icon: const Icon(Icons.add_chart, size: 16),
                                          label: Text('માસિક SIP ઉમેરો: ₹${monthlySipAddition.toStringAsFixed(0)} ✎', style: const TextStyle(fontSize: 12)),
                                          onPressed: () {
                                            final ctrl = TextEditingController(text: monthlySipAddition.toStringAsFixed(0));
                                            showDialog(
                                              context: pageCtx,
                                              builder: (c) => AlertDialog(
                                                title: const Text('નિયમિત માસિક નવું રોકાણ (SIP)'),
                                                content: TextField(
                                                  controller: ctrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(labelText: 'દર મહિને ઉમેરાતી રકમ (₹)'),
                                                ),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('રદ')),
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      final v = double.tryParse(ctrl.text) ?? 0.0;
                                                      settingsBox.put('proj_monthly_sip', v);
                                                      setPageState(() => monthlySipAddition = v);
                                                      Navigator.pop(c);
                                                    },
                                                    child: const Text('સેવ કરો'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 1, 5, 10, 20, 30 વર્ષ માટે ગ્રોથ બાર ચાર્ટ
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '📈 1, 5, 10, 20 અને 30 વર્ષમાં સંપત્તિ વૃદ્ધિ આલેખ (@ ${effectiveProjectionRate.toStringAsFixed(1)}%):',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 180,
                                      child: BarChart(
                                        BarChartData(
                                          alignment: BarChartAlignment.spaceAround,
                                          maxY: calculateFutureWealth(baseProjectionCapital, effectiveProjectionRate, 30, monthlySipAddition) * 1.15,
                                          barGroups: List.generate(milestoneYears.length, (idx) {
                                            final y = milestoneYears[idx];
                                            final fv = calculateFutureWealth(baseProjectionCapital, effectiveProjectionRate, y, monthlySipAddition);
                                            return BarChartGroupData(
                                              x: idx,
                                              barRods: [
                                                BarChartRodData(
                                                  toY: fv,
                                                  color: Colors.teal,
                                                  width: 22,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                              ],
                                            );
                                          }),
                                          titlesData: FlTitlesData(
                                            leftTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                reservedSize: 52,
                                                getTitlesWidget: (val, _) => Text(
                                                  _formatCompactRupees(val),
                                                  style: const TextStyle(fontSize: 9.5),
                                                ),
                                              ),
                                            ),
                                            bottomTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                getTitlesWidget: (val, _) {
                                                  final i = val.toInt();
                                                  if (i < 0 || i >= milestoneYears.length) return const SizedBox();
                                                  return Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text('${milestoneYears[i]} વર્ષ', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                                  );
                                                },
                                              ),
                                            ),
                                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          ),
                                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                                          borderData: FlBorderData(show: false),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 1 વર્ષ, 5 વર્ષ, 10 વર્ષ, 20 વર્ષ, 30 વર્ષ ના વિગતવાર કાર્ડ્સ
                            ...milestoneYears.map((yrs) {
                              final double projectedTotal = calculateFutureWealth(
                                baseProjectionCapital,
                                effectiveProjectionRate,
                                yrs,
                                monthlySipAddition,
                              );
                              final double totalInvestedInPeriod = baseProjectionCapital + (monthlySipAddition * 12 * yrs);
                              final double netGain = projectedTotal - totalInvestedInPeriod;
                              final bool isExp = expandedProjectionYears.contains(yrs);

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor: Colors.teal.withOpacity(0.15),
                                                child: Text('$yrs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
                                              ),
                                              const SizedBox(width: 10),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('$yrs વર્ષ પછી કુલ અંદાજિત કિંમત', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                  Text(
                                                    'કુલ નફો/વૃદ્ધિ: +₹${netGain.toStringAsFixed(0)} (${_formatCompactRupees(netGain)})',
                                                    style: const TextStyle(fontSize: 11.5, color: Colors.green, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '₹${projectedTotal.toStringAsFixed(0)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal),
                                              ),
                                              Text(
                                                '(${_formatCompactRupees(projectedTotal)})',
                                                style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: () => setPageState(() {
                                          if (isExp) {
                                            expandedProjectionYears.remove(yrs);
                                          } else {
                                            expandedProjectionYears.add(yrs);
                                          }
                                        }),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(isExp ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 16, color: Colors.teal),
                                            const SizedBox(width: 4),
                                            Text(
                                              isExp ? 'સ્ટ્રેટેજી મુજબ કેટેગરી વિભાજન છુપાવો' : '+ સ્ટ્રેટેજી મુજબ કેટેગરી વિભાજન જુઓ',
                                              style: const TextStyle(fontSize: 11.5, color: Colors.teal, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isExp) ...[
                                        const Divider(),
                                        ...strategyForProjection.entries.map((e) {
                                          final double shareVal = projectedTotal * (e.value / 100.0);
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(child: Text('• ${e.key} (${e.value.toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12))),
                                                Text('₹${shareVal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatCompactRupees(double val) {
    if (val >= 10000000) {
      return '₹${(val / 10000000).toStringAsFixed(2)} Cr';
    } else if (val >= 100000) {
      return '₹${(val / 100000).toStringAsFixed(2)} L';
    } else if (val >= 1000) {
      return '₹${(val / 1000).toStringAsFixed(1)} K';
    }
    return '₹${val.toStringAsFixed(0)}';
  }

  // દરેક મુખ્ય કેટેગરી નીચે + નિશાની વાળું કાર્ડ (ક્લિક કરવાથી પેટા કેટેગરીઓ દેખાય)
  Widget _buildExpandableCategoryCard({
    required int catIndex,
    required bool isExpanded,
    required VoidCallback onToggle,
    required String title,
    required IconData icon,
    required Color color,
    required double totalAmount,
    required double pctOfTotalWealth,
    required double pctOfInvestments,
    required List<Map<String, dynamic>> subItems,
    String? subtitleOverride,
    Widget? extraBottomWidget,
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
                      Icon(icon, color: color, size: 22),
                      const SizedBox(width: 8),
                      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5))),
                    ],
                  ),
                ),
                Text(
                  '₹${totalAmount.toStringAsFixed(0)} (${pctOfTotalWealth.toStringAsFixed(1)}%)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13.5),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitleOverride ?? 'કુલ રોકાણોમાં હિસ્સો: ${pctOfInvestments.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.22 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isExpanded ? Icons.remove_circle : Icons.add_circle, color: color, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      isExpanded ? 'પેટા કેટેગરીઓ છુપાવો (-)' : '+ પેટા કેટેગરીઓ જુઓ (${subItems.length})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : color),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 16),
              ...subItems.map((s) {
                final double amt = (s['amt'] as num?)?.toDouble() ?? 0.0;
                final double pct = (s['pct'] as num?)?.toDouble() ?? 0.0;
                final double shareInGroup = totalAmount > 0 ? (amt / totalAmount) * 100.0 : 0.0;
                return _subCategoryPctRow('• ${s['label']}', amt, pct, shareInGroup, color);
              }),
              if (extraBottomWidget != null) extraBottomWidget,
            ],
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
              backgroundColor: Colors.grey.withOpacity(0.25),
              color: color,
            ),
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
            Text('${value.toStringAsFixed(0)}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.indigo.shade200 : Colors.indigo)),
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


  // =========================================================
  // દૈનિક નોંધ ડાયલોગ (તારીખ પસંદગી 01/01/1800 થી 31/12/2100 + ક્રેડિટ કાર્ડ લિમિટ વોર્નિંગ)
  // =========================================================
  DateTime _clampDate1800To2100(DateTime d) {
    final minD = DateTime(1800, 1, 1);
    final maxD = DateTime(2100, 12, 31);
    if (d.isBefore(minD)) return minD;
    if (d.isAfter(maxD)) return maxD;
    return d;
  }

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
                  decoration: const InputDecoration(labelText: 'ખાતું પસંદ કરો (ક્રેડિટ કાર્ડ પર લિમિટ વોર્નિંગ મળશે)'),
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
                            initialDate: _clampDate1800To2100(pickedDate),
                            firstDate: DateTime(1800, 1, 1),
                            lastDate: DateTime(2100, 12, 31),
                            helpText: 'તારીખ પસંદ કરો (01/01/1800 - 31/12/2100)',
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

                      final String accIdStr = selectedAcc['id'].toString();
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
                        'accountId': accIdStr,
                        'accountName': selectedAcc['name'],
                      });
                      _processAutoPayAndSIP();
                      setState(() {});
                      Navigator.pop(ctx);
                      // જો ક્રેડિટ કાર્ડમાં લિમિટ કરતાં વધુ ખર્ચ થતો હોય તો વોર્નિંગ મેસેજ બતાવો
                      _checkAndShowCreditCardLimitWarning(accIdStr);
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

  // =========================================================
  // પ્રથમ સ્ક્રીન પર રહેલ આલેખ:
  // રૈખિક આલેખમાં કુલ ૩ અલગ રેખાઓ (૧. આવક, ૨. ખર્ચ, ૩. રોકાણ/ખર્ચ)
  // આડી અક્ષ પર તારીખ, ઉભી અક્ષ પર રૂપિયા અંકમાં, જે તારીખે નોંધ થાય તે તારીખ પર કિંમત ઉમેરાઈને રેખા આગળ વધે
  // =========================================================
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
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 46)),
            bottomTitles: AxisTitles(
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
              left: BorderSide(color: Colors.teal, width: 1.5),
              bottom: BorderSide(color: Colors.teal, width: 1.5),
            ),
          ),
        ),
      );
    } else {
      // રૈખિક આલેખ (Line Chart): તારીખ પ્રમાણે ક્રમમાં ગોઠવીને ૩ અલગ રેખાઓ
      final ascTx = List<DataMap>.from(filteredTransactions);
      ascTx.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));

      // તારીખ પ્રમાણે ગ્રુપિંગ જેથી જે તારીખે નોંધ થાય તે જ તારીખ આડી અક્ષ પર આવે અને દરેક નોંધની કિંમત ઉમેરાઈને રેખા આગળ વધે
      final List<String> dateLabels = [];
      final List<FlSpot> incomeSpots = [];
      final List<FlSpot> expenseSpots = [];
      final List<FlSpot> investSpots = [];

      double cumInc = 0.0;
      double cumExp = 0.0;
      double cumInv = 0.0;

      final Map<String, List<DataMap>> groupedByDate = {};
      for (final tx in ascTx) {
        final dt = DateTime.parse(tx['date']);
        final key = DateFormat('dd/MM/yy').format(dt);
        groupedByDate.putIfAbsent(key, () => []).add(tx);
      }

      if (groupedByDate.isEmpty) {
        dateLabels.add(DateFormat('dd/MM').format(DateTime.now()));
        incomeSpots.add(const FlSpot(0, 0));
        expenseSpots.add(const FlSpot(0, 0));
        investSpots.add(const FlSpot(0, 0));
      } else {
        int xIdx = 0;
        groupedByDate.forEach((dateStr, txOnDate) {
          for (final tx in txOnDate) {
            final double amt = (tx['amount'] as num).toDouble();
            final String effect = (tx['categoryEffect'] ?? '').toString();
            if (effect == 'incomeCredit') {
              cumInc += amt;
            } else if (effect == 'expenseDebit' || effect == 'loanRepay') {
              cumExp += amt;
            } else if (effect == 'assetIncrease') {
              cumInv += amt;
            }
          }
          dateLabels.add(dateStr);
          incomeSpots.add(FlSpot(xIdx.toDouble(), cumInc));
          expenseSpots.add(FlSpot(xIdx.toDouble(), cumExp));
          investSpots.add(FlSpot(xIdx.toDouble(), cumInv));
          xIdx++;
        });
      }

      // જો માત્ર ૧ જ તારીખ હોય તો શરૂઆતનો (0,0) બિંદુ ઉમેરો જેથી રેખા સ્પષ્ટ દેખાય
      List<FlSpot> plotInc = incomeSpots;
      List<FlSpot> plotExp = expenseSpots;
      List<FlSpot> plotInv = investSpots;
      List<String> plotLabels = dateLabels;

      if (plotLabels.length == 1 && ascTx.isNotEmpty) {
        plotLabels = ['શરૂઆત', plotLabels.first];
        plotInc = [const FlSpot(0, 0), FlSpot(1, incomeSpots.first.y)];
        plotExp = [const FlSpot(0, 0), FlSpot(1, expenseSpots.first.y)];
        plotInv = [const FlSpot(0, 0), FlSpot(1, investSpots.first.y)];
      }

      final double maxLineY = [cumInc, cumExp, cumInv, 100.0].reduce(math.max) * 1.2;

      chartWidget = Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendBadge(Colors.green, '૧. આવક (₹${cumInc.toStringAsFixed(0)})'),
              const SizedBox(width: 12),
              _legendBadge(Colors.redAccent, '૨. ખર્ચ (₹${cumExp.toStringAsFixed(0)})'),
              const SizedBox(width: 12),
              _legendBadge(Colors.blue, '૩. રોકાણ (₹${cumInv.toStringAsFixed(0)})'),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxLineY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.x.toInt().clamp(0, plotLabels.length - 1);
                        final dLabel = plotLabels[idx];
                        String catLabel = 'રોકાણ';
                        if (spot.barIndex == 0) catLabel = 'આવક';
                        if (spot.barIndex == 1) catLabel = 'ખર્ચ';
                        return LineTooltipItem(
                          '$dLabel\n$catLabel: ₹${spot.y.toStringAsFixed(0)}',
                          const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: plotInc,
                    isCurved: false,
                    color: Colors.green,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: plotExp,
                    isCurved: false,
                    color: Colors.redAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: plotInv,
                    isCurved: false,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('રૂપિયા (₹)', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                    axisNameSize: 14,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      getTitlesWidget: (val, _) => Text(
                        val >= 100000
                            ? '${(val / 1000).toStringAsFixed(0)}K'
                            : val.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 9.5),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('તારીખ (Date)', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                    axisNameSize: 14,
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 24,
                      getTitlesWidget: (val, _) {
                        final i = val.toInt();
                        if (i < 0 || i >= plotLabels.length) return const SizedBox();
                        final step = (plotLabels.length / 5).ceil().clamp(1, 999);
                        if (i % step != 0 && i != plotLabels.length - 1) return const SizedBox();
                        final shortDate = plotLabels[i].length > 5 ? plotLabels[i].substring(0, 5) : plotLabels[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(shortDate, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: true, drawVerticalLine: true),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: Colors.teal, width: 1.5),
                    bottom: BorderSide(color: Colors.teal, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
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
            SizedBox(height: 175, child: chartWidget),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // (૪) સંપૂર્ણ નાણાકીય વિશ્લેષણ ટેબ (ડાર્ક મોડ સુધારા સાથે)
  // =========================================================
  Widget _buildAnalysisTab() {
    final double totalInc = _calculateTotal('incomeCredit');
    final double totalExp = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
    final double totalInv = _calculateTotal('assetIncrease');
    final double totalSavings = totalInc - totalExp;
    final double savingsRate = totalInc > 0 ? (totalSavings / totalInc) * 100.0 : 0.0;

    final taxData = _fetchComprehensiveTaxData(entireFY: true);
    final double fyGrossInc = taxData['grossIncome'] ?? 0.0;
    final double taxableNew = taxData['taxableNew'] ?? 0.0;
    final double totalTaxNew = taxData['totalTaxNew'] ?? 0.0;

    final double taxableOld = taxData['taxableOld'] ?? 0.0;
    final double totalTaxOld = taxData['totalTaxOld'] ?? 0.0;
    final double allowed80C = taxData['allowed80C'] ?? 0.0;
    final double allowed80D = taxData['allowed80D'] ?? 0.0;
    final double allowed80TTA = taxData['allowed80TTA'] ?? 0.0;
    final double extraDed = taxData['extraDeductions'] ?? 0.0;
    final double totalOldDed = taxData['totalOldDeductions'] ?? 0.0;

    final double stcg = taxData['stcg'] ?? 0.0;
    final double ltcg = taxData['ltcg'] ?? 0.0;

    final String selectedRegime = settingsBox.get('selectedTaxRegime', defaultValue: 'new').toString();
    final String ageGroup = settingsBox.get('taxAgeGroup', defaultValue: 'regular').toString();
    final double activeTotalTax = selectedRegime == 'old' ? totalTaxOld : totalTaxNew;

    final portfolioMetrics = _calculatePortfolioReturnMetrics();
    final double annualReturnPercent = portfolioMetrics['returnPercent'] ?? 0.0;
    final bool beatsInflation = annualReturnPercent >= benchmarkInflationRate;
    final double realReturn = annualReturnPercent - benchmarkInflationRate;

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
        'સ્થાવર સંપત્તિ (મકાન/ખેતર/દુકાનો)': (pData['physicalAssetsVal'] as num).toDouble(),
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
                            label: Text('શરૂઆત: ${DateFormat('dd/MM/yyyy').format(customStartDate)}', style: const TextStyle(fontSize: 11.5)),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _clampDate1800To2100(customStartDate),
                                firstDate: DateTime(1800, 1, 1),
                                lastDate: DateTime(2100, 12, 31),
                              );
                              if (d != null) setState(() => customStartDate = d);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event_available, size: 16),
                            label: Text('અંતિમ: ${DateFormat('dd/MM/yyyy').format(customEndDate)}', style: const TextStyle(fontSize: 11.5)),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _clampDate1800To2100(customEndDate),
                                firstDate: DateTime(1800, 1, 1),
                                lastDate: DateTime(2100, 12, 31),
                              );
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

          Card(
            color: beatsInflation ? adaptiveTintBg(Colors.teal) : adaptiveTintBg(Colors.amber),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '💰 બચત અને વાર્ષિક રિટર્ન vs મોંઘવારી (Inflation)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: primaryTextColor),
                        ),
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
                      _metricColumn('કુલ બચત (Savings)', '₹${totalSavings.toStringAsFixed(0)} (${savingsRate.toStringAsFixed(1)}%)', adaptiveAccentText(Colors.teal)),
                      _metricColumn('પોર્ટફોલિયો રિટર્ન', '${annualReturnPercent.toStringAsFixed(2)}%', annualReturnPercent >= 0 ? adaptiveAccentText(Colors.green) : Colors.redAccent),
                      _metricColumn('વાસ્તવિક રિટર્ન (Real)', '${realReturn >= 0 ? '+' : ''}${realReturn.toStringAsFixed(2)}%', beatsInflation ? adaptiveAccentText(Colors.green) : Colors.deepOrangeAccent),
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedRegime,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'ટેક્સ રિજીમ', isDense: true, border: OutlineInputBorder()),
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
                  _taxSummaryRow('કુલ વાર્ષિક નિયમિત આવક (Gross Income):', '₹${fyGrossInc.toStringAsFixed(0)}', adaptiveAccentText(Colors.green), isBold: true),
                  const SizedBox(height: 4),
                  if (selectedRegime == 'new') ...[
                    _taxSummaryRow('બાદ: સ્ટાન્ડર્ડ ડિડક્શન (New Regime):', '- ₹75000', secondaryTextColor),
                    const SizedBox(height: 4),
                    _taxSummaryRow('નિયમિત કરપાત્ર આવક (સ્ટાન્ડર્ડ ડિડક્શન બાદ):', '₹${taxableNew.toStringAsFixed(0)}', primaryTextColor, isBold: true),
                    if (taxableNew > 0 && taxableNew <= 1200000)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('✨ કલમ 87A રિબેટ લાગુ: ₹12,00,000 સુધીની કરપાત્ર આવક પર સ્લેબ ટેક્સ ₹0', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                  ] else ...[
                    _taxSummaryRow('બાદ: સ્ટાન્ડર્ડ ડિડક્શન (Old Regime):', '- ₹50000', secondaryTextColor),
                    _taxSummaryRow('બાદ: કલમ 80C રોકાણ (PLI/PPF/ELSS/FD ઓટો-ફેચ):', '- ₹${allowed80C.toStringAsFixed(0)}', Colors.teal),
                    _taxSummaryRow('બાદ: કલમ 80D (હેલ્થ વીમો) + 80TTA/TTB:', '- ₹${(allowed80D + allowed80TTA).toStringAsFixed(0)}', Colors.teal),
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
                            child: Text('બાદ: HRA / LTA / 80E / અન્ય ડિડક્શન ✎:', style: TextStyle(fontSize: 12, color: isDark ? Colors.indigo.shade200 : Colors.indigo, decoration: TextDecoration.underline)),
                          ),
                        ),
                        Text('- ₹${extraDed.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.indigo.shade200 : Colors.indigo)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _taxSummaryRow('નિયમિત કરપાત્ર આવક (કુલ ₹${totalOldDed.toStringAsFixed(0)} બાદ):', '₹${taxableOld.toStringAsFixed(0)}', primaryTextColor, isBold: true),
                    if (taxableOld > 0 && taxableOld <= 500000)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('✨ કલમ 87A રિબેટ લાગુ: ₹5,00,000 સુધીની કરપાત્ર આવક પર સ્લેબ ટેક્સ ₹0', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                  ],
                  const SizedBox(height: 4),
                  _taxSummaryRow('Short-Term Capital Gains (STCG @ 20%):', '₹${stcg.toStringAsFixed(0)}', isDark ? Colors.indigo.shade200 : Colors.indigo),
                  const SizedBox(height: 4),
                  _taxSummaryRow('Long-Term Capital Gains (LTCG @ 12.5% > ₹1.25L):', '₹${ltcg.toStringAsFixed(0)}', Colors.teal),
                  const Divider(),
                  _taxSummaryRow(
                    'કુલ અંદાજિત ટેક્સ જવાબદારી (4% સેસ સહિત):',
                    '₹${activeTotalTax.toStringAsFixed(0)}',
                    Colors.redAccent,
                    isBold: true,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(isDark ? 0.22 : 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('New Regime ટેક્સ: ₹${totalTaxNew.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                            Text('Old Regime ટેક્સ: ₹${totalTaxOld.toStringAsFixed(0)}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.purple.shade200 : Colors.deepPurple)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          totalTaxNew <= totalTaxOld
                              ? '💡 ભલામણ: તમારા માટે New Tax Regime માં ₹${(totalTaxOld - totalTaxNew).toStringAsFixed(0)} ટેક્સ બચે છે.'
                              : '💡 ભલામણ: તમારા માટે Old Tax Regime માં ₹${(totalTaxNew - totalTaxOld).toStringAsFixed(0)} ટેક્સ બચે છે.',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

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
        Text(label, style: TextStyle(fontSize: 11, color: secondaryTextColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // --- ટેબ ૩: બજેટ લક્ષ્યાંક (₹ અને % બંનેમાં + ફાઇનાન્સિયલ ગોલ / રિટાયરમેન્ટ પ્લાનર) ---
  double _getBudgetReferenceIncome() {
    final double savedRef = (budgetBox.get('refIncome_$budgetPeriod', defaultValue: 0.0) as num).toDouble();
    if (savedRef > 0) return savedRef;
    final double actualInc = _calculateTotal('incomeCredit');
    return actualInc > 0 ? actualInc : 50000.0;
  }

  double _calculateRequiredMonthlySip(double targetGap, double annualReturnPct, int months) {
    if (targetGap <= 0) return 0.0;
    if (months <= 1) return targetGap;
    final double r = (annualReturnPct / 100.0) / 12.0;
    if (r <= 0) return targetGap / months;
    final double factor = (math.pow(1 + r, months) - 1) / r * (1 + r);
    return factor > 0 ? targetGap / factor : targetGap / months;
  }

  double _calculateFutureValue({
    required double currentSaved,
    required double monthlySip,
    required double annualReturnPct,
    required int months,
  }) {
    if (months <= 0) return currentSaved;
    final double r = (annualReturnPct / 100.0) / 12.0;
    if (r <= 0) return currentSaved + (monthlySip * months);
    final double fvLump = currentSaved * math.pow(1 + r, months);
    final double fvSip = monthlySip * ((math.pow(1 + r, months) - 1) / r) * (1 + r);
    return fvLump + fvSip;
  }

  void _openAddOrEditGoalDialog({Map<dynamic, dynamic>? existingGoal}) {
    final nameCtrl = TextEditingController(text: existingGoal != null ? (existingGoal['name'] ?? '') : '');
    final targetCtrl = TextEditingController(text: existingGoal != null ? (existingGoal['targetAmount'] ?? 0).toString() : '');
    final savedCtrl = TextEditingController(text: existingGoal != null ? (existingGoal['savedAmount'] ?? 0).toString() : '0');
    final monthlyPlanCtrl = TextEditingController(text: existingGoal != null ? (existingGoal['monthlyContribution'] ?? 0).toString() : '0');
    final rateCtrl = TextEditingController(text: existingGoal != null ? (existingGoal['expectedReturn'] ?? 12.0).toString() : '12.0');
    final planCtrl = TextEditingController(text: existingGoal != null ? (existingGoal['investmentPlan'] ?? '') : '');
    String goalType = existingGoal != null ? (existingGoal['goalType'] ?? 'રિટાયરમેન્ટ પ્લાન') : 'રિટાયરમેન્ટ પ્લાન';
    DateTime targetDate = existingGoal != null && existingGoal['targetDate'] != null
        ? (DateTime.tryParse(existingGoal['targetDate'].toString()) ?? DateTime.now().add(const Duration(days: 365 * 5)))
        : DateTime.now().add(const Duration(days: 365 * 5));
    bool enableReminder = existingGoal != null ? (existingGoal['enableReminder'] ?? true) : true;

    final List<String> goalTypes = [
      'રિટાયરમેન્ટ પ્લાન',
      'બાળકોનું શિક્ષણ / લગ્ન',
      'નવું ઘર / પ્રોપર્ટી',
      'કાર / વાહન ખરીદી',
      'ઇમરજન્સી ફંડ',
      'પ્રવાસ / ખાસ ઘટના',
      'અન્ય ફાઇનાન્સિયલ લક્ષ્યાંક',
    ];
    if (!goalTypes.contains(goalType)) goalTypes.add(goalType);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingGoal == null
              ? _t('નવું લક્ષ્યાંક / રિટાયરમેન્ટ પ્લાન ઉમેરો', 'Add Goal / Event / Retirement Plan')
              : _t('લક્ષ્યાંક પ્લાન સુધારો', 'Edit Goal Plan')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: goalType,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: _t('લક્ષ્યાંક / ઘટનાનો પ્રકાર', 'Goal / Event Type')),
                  items: goalTypes.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12.5)))).toList(),
                  onChanged: (v) => setDlgState(() => goalType = v!),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: _t('લક્ષ્યાંકનું નામ (દા.ત. રિટાયરમેન્ટ 2045)', 'Goal Name (e.g. Retirement 2045)')),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: _t('લક્ષ્ય રકમ (₹)', 'Target Amount (₹)')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: savedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: _t('હાલ ભેગી થયેલ (₹)', 'Currently Saved (₹)')),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: monthlyPlanCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: _t('માસિક રોકાણ પ્લાન (₹)', 'Monthly Plan (₹)')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: _t('અંદાજિત વળતર (% p.a.)', 'Expected Return (%)')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: Text('${_t("લક્ષ્ય તારીખ", "Target Date")}: ${DateFormat("dd/MM/yyyy").format(targetDate)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _clampDate1800To2100(targetDate),
                      firstDate: DateTime(1800, 1, 1),
                      lastDate: DateTime(2100, 12, 31),
                    );
                    if (d != null) setDlgState(() => targetDate = d);
                  },
                ),
                TextField(
                  controller: planCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _t('પ્લાનિંગ વિગત (ક્યાં રોકાણ કરવું / કયા ખાતામાં બચત કરવી)', 'Planning Notes (Where to invest / Save in which account)'),
                    hintText: _t('દા.ત. Nifty 50 Index Fund SIP + PPF + SBI Savings Account', 'e.g. Nifty 50 SIP + PPF + SBI Account'),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('લક્ષ્યાંક પ્રગતિ રિમાઇન્ડર ચાલુ રાખો', 'Enable Goal Progress Reminder'), style: const TextStyle(fontSize: 12)),
                  value: enableReminder,
                  onChanged: (v) => setDlgState(() => enableReminder = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('રદ', 'Cancel'))),
            ElevatedButton(
              onPressed: () {
                final tAmt = double.tryParse(targetCtrl.text) ?? 0.0;
                if (nameCtrl.text.trim().isEmpty || tAmt <= 0) return;
                final id = existingGoal != null ? existingGoal['id'].toString() : "goal_${DateTime.now().millisecondsSinceEpoch}";
                goalsBox.put(id, {
                  'id': id,
                  'goalType': goalType,
                  'name': nameCtrl.text.trim(),
                  'targetAmount': tAmt,
                  'savedAmount': double.tryParse(savedCtrl.text) ?? 0.0,
                  'monthlyContribution': double.tryParse(monthlyPlanCtrl.text) ?? 0.0,
                  'expectedReturn': double.tryParse(rateCtrl.text) ?? 12.0,
                  'targetDate': targetDate.toIso8601String(),
                  'investmentPlan': planCtrl.text.trim(),
                  'enableReminder': enableReminder,
                });
                setState(() {});
                Navigator.pop(ctx);
              },
              child: Text(_t('સેવ કરો', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetTab() {
    final double refIncome = _getBudgetReferenceIncome();
    final goalsList = goalsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: budgetPeriod,
                items: ['દૈનિક', 'માસિક', 'ત્રિમાસિક', 'છ માસિક', 'વાર્ષિક']
                    .map((p) => DropdownMenuItem(value: p, child: Text('$p ${_t("બજેટ", "Budget")}')))
                    .toList(),
                onChanged: (v) => setState(() => budgetPeriod = v!),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.tune, size: 16),
                label: Text(_t('લક્ષ્યાંક બદલો', 'Edit Targets')),
                onPressed: _openCategoryBudgetDialog,
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: adaptiveTintBg(Colors.teal),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_t("આધાર આવક (% ગણતરી માટે)", "Base Income (for %)")}: ₹${refIncome.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: adaptiveAccentText(Colors.teal)),
                ),
                InkWell(
                  onTap: _openCategoryBudgetDialog,
                  child: Text(_t('સુધારો ✎', 'Edit ✎'), style: const TextStyle(fontSize: 11.5, color: Colors.teal, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          ...categories.map((cat) {
            final budgetKey = 'budget_${budgetPeriod}_${cat['id']}';
            final pctKey = 'budgetPct_${budgetPeriod}_${cat['id']}';
            final modeKey = 'budgetMode_${budgetPeriod}_${cat['id']}';
            final String mode = (budgetBox.get(modeKey, defaultValue: 'rs') ?? 'rs').toString();
            double target = (budgetBox.get(budgetKey, defaultValue: 0.0) as num).toDouble();
            double targetPct = (budgetBox.get(pctKey, defaultValue: 0.0) as num).toDouble();

            if (mode == 'pct' && targetPct > 0) {
              target = (refIncome * targetPct) / 100.0;
            } else if (target > 0 && refIncome > 0) {
              targetPct = (target / refIncome) * 100.0;
            }

            final actual = filteredTransactions
                .where((t) => t['categoryId'].toString() == cat['id'].toString())
                .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());

            if (target <= 0 && actual <= 0) return const SizedBox();
            final double usedPct = target > 0 ? (actual / target) * 100.0 : 100.0;
            final double progressVal = target > 0 ? (actual / target).clamp(0.0, 1.0) : 1.0;
            final bool isOver = target > 0 && actual > target;

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
                        Expanded(
                          child: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        ),
                        Text(
                          '₹${actual.toStringAsFixed(0)} / ₹${target.toStringAsFixed(0)} (${targetPct.toStringAsFixed(1)}%)',
                          style: TextStyle(color: isOver ? Colors.redAccent : Colors.teal, fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_t("બજેટ વપરાશ", "Used")}: ${usedPct.toStringAsFixed(1)}% • ${_t("આવકના %", "% of Income")}: ${targetPct.toStringAsFixed(1)}% • ${isOver ? _t("⚠️ બજેટ કરતાં વધારે!", "⚠️ Over Budget!") : _t("બાકી", "Remaining") + ": ₹" + math.max(0.0, target - actual).toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, color: isOver ? Colors.redAccent : secondaryTextColor),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: progressVal, color: isOver ? Colors.redAccent : Colors.teal, minHeight: 8),
                  ],
                ),
              ),
            );
          }),

          const Divider(height: 26),
          // ફાઇનાન્સિયલ લક્ષ્યાંક / ઘટના / રિટાયરમેન્ટ પ્લાનર
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _t('🎯 લક્ષ્યાંક / ઘટના / રિટાયરમેન્ટ પ્લાનર', '🎯 Goals / Event / Retirement Planner'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                icon: const Icon(Icons.flag, size: 16),
                label: Text(_t('નવો પ્લાન', 'Add Goal')),
                onPressed: () => _openAddOrEditGoalDialog(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (goalsList.isEmpty)
            Card(
              color: adaptiveTintBg(Colors.indigo),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Text(
                  _t(
                    'કોઈ રિટાયરમેન્ટ કે ઘટના માટેનો લક્ષ્યાંક પ્લાન ઉમેરેલ નથી. "નવો પ્લાન" પર ક્લિક કરી કેટલા રૂપિયા ભેગા કરવા છે અને ક્યાં રોકાણ/બચત કરવી છે તે ગોઠવો.',
                    'No financial goal or retirement plan added yet. Tap "Add Goal" to set target corpus, investment plan, and progress reminders.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
          else
            ...goalsList.map((g) {
              final double target = (g['targetAmount'] as num?)?.toDouble() ?? 0.0;
              final double saved = (g['savedAmount'] as num?)?.toDouble() ?? 0.0;
              final double monthlyPlan = (g['monthlyContribution'] as num?)?.toDouble() ?? 0.0;
              final double retRate = (g['expectedReturn'] as num?)?.toDouble() ?? 12.0;
              final DateTime tDate = DateTime.tryParse((g['targetDate'] ?? '').toString()) ?? DateTime.now().add(const Duration(days: 365));
              final int monthsLeft = math.max(1, ((tDate.difference(DateTime.now()).inDays) / 30.44).round());
              final double remaining = math.max(0.0, target - saved);
              final double pctDone = target > 0 ? ((saved / target) * 100.0).clamp(0.0, 100.0) : 0.0;
              final bool achieved = saved >= target && target > 0;
              final double reqMonthlySip = _calculateRequiredMonthlySip(remaining, retRate, monthsLeft);
              final double projectedFv = _calculateFutureValue(
                currentSaved: saved,
                monthlySip: monthlyPlan > 0 ? monthlyPlan : reqMonthlySip,
                annualReturnPct: retRate,
                months: monthsLeft,
              );

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: achieved ? Colors.green : Colors.indigo.shade200, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(achieved ? Icons.emoji_events : Icons.flag_circle, color: achieved ? Colors.green : Colors.indigo),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${g['name']} (${g['goalType']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(
                                  '${_t("લક્ષ્ય તારીખ", "Target")}: ${DateFormat("dd/MM/yyyy").format(tDate)} ($monthsLeft ${_t("મહિના બાકી", "months left")})',
                                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                            onPressed: () => _openAddOrEditGoalDialog(existingGoal: g),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            onPressed: () {
                              goalsBox.delete(g['id']);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: achieved ? adaptiveTintBg(Colors.green) : adaptiveTintBg(Colors.amber),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          achieved
                              ? _t('🎉 અભિનંદન! તમારું લક્ષ્યાંક (₹${target.toStringAsFixed(0)}) પ્રાપ્ત થઈ ગયું છે!', '🎉 Congratulations! Your goal (₹${target.toStringAsFixed(0)}) has been achieved!')
                              : _t('🔔 રિમાઇન્ડર: તમે લક્ષ્યાંકથી હજી ₹${remaining.toStringAsFixed(0)} (${(100 - pctDone).toStringAsFixed(1)}%) દૂર છો.', '🔔 Reminder: You are ₹${remaining.toStringAsFixed(0)} (${(100 - pctDone).toStringAsFixed(1)}%) away from your target.'),
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: achieved ? adaptiveAccentText(Colors.green) : adaptiveAccentText(Colors.amber)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_t("ભેગી થયેલ", "Saved")}: ₹${saved.toStringAsFixed(0)} (${pctDone.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('${_t("લક્ષ્ય", "Target")}: ₹${target.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: (pctDone / 100.0).clamp(0.0, 1.0), color: achieved ? Colors.green : Colors.indigo, minHeight: 8),
                      const SizedBox(height: 6),
                      Text(
                        '${_t("જરૂરી માસિક SIP", "Required Monthly SIP")} (@${retRate.toStringAsFixed(1)}%): ₹${reqMonthlySip.toStringAsFixed(0)} • ${_t("અંદાજિત ભવિષ્યની મૂડી", "Projected Corpus")}: ₹${projectedFv.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11.5, color: Colors.teal, fontWeight: FontWeight.bold),
                      ),
                      if ((g['investmentPlan'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '📌 ${_t("રોકાણ / બચત પ્લાન", "Investment / Savings Plan")}: ${g['investmentPlan']}',
                            style: TextStyle(fontSize: 11.5, color: primaryTextColor),
                          ),
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


  // =========================================================
  // (૫) ઇન્વેસ્ટમેન્ટ પેજ (૫ પેટા-ટેબ્સ: MF/SIP, સ્ટોક/ETF, બોન્ડ/FD/PLI, કિંમતી ધાતુઓ, અન્ય મિલકત)
  // =========================================================
  Widget _buildInvestmentTab() {
    String invTitle = settingsBox.get('customInvTitle', defaultValue: 'ઇન્વેસ્ટમેન્ટ પોર્ટફોલિયો');

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
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

  // --- (૫-A) મ્યુચ્યુઅલ ફંડ અને SIP (તારીખ પ્રમાણે ઓટો NAV ફેચ + મેન્યુઅલ + Lumpsum/SIP + Edit + વેચાણ મર્યાદા) ---
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
            color: adaptiveTintBg(Colors.teal),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricColumn('કુલ MF રોકાણ', '₹${totalInv.toStringAsFixed(0)}', adaptiveAccentText(Colors.teal)),
                  _metricColumn('હાલનું મૂલ્ય (NAV મુજબ)', '₹${currentVal.toStringAsFixed(0)}', adaptiveAccentText(Colors.blue)),
                  _metricColumn('નફો / નુકસાન', '₹${(currentVal - totalInv).toStringAsFixed(0)}', currentVal >= totalInv ? adaptiveAccentText(Colors.green) : Colors.redAccent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('મારા મ્યુચ્યુઅલ ફંડ (Lumpsum & SIP):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('MF / SIP ઉમેરો'),
                onPressed: () => _openAddMutualFundDialog(),
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
                final DateTime dt = DateTime.tryParse(m['date'] ?? '') ?? DateTime.now();

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.withOpacity(0.15),
                      child: Text(isSip ? 'SIP' : 'Lump', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ),
                    title: Text(m['schemeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                      '${_t("પ્રકાર", "Mode")}: ${isSip ? (m['sipFrequency'] ?? _t('માસિક SIP', 'Monthly SIP')) : _t('વન-ટાઇમ Lumpsum', 'One-Time Lumpsum')} • ${_t("તારીખ", "Date")}: ${DateFormat('dd/MM/yyyy').format(dt)}\n'
                      'રોકાણ: ₹${inv.toStringAsFixed(0)} • યુનિટ્સ: ${units.toStringAsFixed(3)}\n'
                      'ખરીદ NAV: ₹${buyNav.toStringAsFixed(2)} | હાલની NAV: ₹${curNav.toStringAsFixed(2)} | મૂલ્ય: ₹${val.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                          tooltip: 'સુધારો',
                          onPressed: () => _openAddMutualFundDialog(existingItem: m),
                        ),
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

  // ખરીદીની તારીખ પ્રમાણે ઐતિહાસિક NAV શોધતું ફંક્શન
  double? _findHistoricalNavForDate(List<dynamic> navDataList, DateTime targetDate) {
    if (navDataList.isEmpty) return null;
    final targetOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
    for (final entry in navDataList) {
      final dStr = (entry['date'] ?? '').toString(); // format: dd-MM-yyyy
      final parts = dStr.split('-');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]) ?? 1;
        final m = int.tryParse(parts[1]) ?? 1;
        final y = int.tryParse(parts[2]) ?? 2026;
        final entryDate = DateTime(y, m, d);
        // ખરીદીની તારીખ અથવા તેની તરત અગાઉના ચાલુ બજાર દિવસની NAV
        if (!entryDate.isAfter(targetOnly)) {
          return double.tryParse(entry['nav'].toString());
        }
      }
    }
    return double.tryParse(navDataList.first['nav'].toString());
  }

  void _openAddMutualFundDialog({Map<dynamic, dynamic>? existingItem}) {
    final searchCtrl = TextEditingController();
    final schemeCtrl = TextEditingController(text: existingItem != null ? existingItem['schemeName'] : '');
    final navCtrl = TextEditingController(text: existingItem != null ? existingItem['buyNav'].toString() : '');
    final curNavCtrl = TextEditingController(text: existingItem != null ? (existingItem['currentNav'] ?? existingItem['buyNav']).toString() : '');
    final amtCtrl = TextEditingController(text: existingItem != null ? existingItem['investedAmount'].toString() : '');
    final sipDayCtrl = TextEditingController(text: existingItem != null ? (existingItem['sipDay']?.toString() ?? '5') : '5');

    String navMode = existingItem != null ? (existingItem['navMode'] ?? 'auto') : 'auto';
    String investmentMode = existingItem != null ? (existingItem['investmentMode'] ?? 'Lumpsum') : 'Lumpsum';
    String executionMode = existingItem != null ? (existingItem['executionMode'] ?? 'auto') : 'auto';
    List<Map<String, dynamic>> sipFreqList = _getSipFrequencyOptions();
    String sipFrequency = existingItem != null && existingItem['sipFrequency'] != null
        ? existingItem['sipFrequency'].toString()
        : sipFreqList.first['name'].toString();
    if (!sipFreqList.any((f) => f['name'] == sipFrequency)) {
      sipFreqList.add({'name': sipFrequency, 'days': _getIntervalDaysForFrequency(sipFrequency)});
    }
    String selectedAccId = existingItem != null && existingItem['accountId'] != null
        ? existingItem['accountId'].toString()
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');
    DateTime pickedDate = existingItem != null ? (DateTime.tryParse(existingItem['date'] ?? '') ?? DateTime.now()) : DateTime.now();

    bool isSearching = false;
    List<dynamic> searchResults = [];
    List<dynamic> cachedNavHistory = [];
    String navDateStatus = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> applyNavForPickedDate() async {
            if (navMode != 'auto' || cachedNavHistory.isEmpty) return;
            final foundNav = _findHistoricalNavForDate(cachedNavHistory, pickedDate);
            final latestNav = double.tryParse(cachedNavHistory.first['nav'].toString());
            if (foundNav != null && foundNav > 0) {
              navCtrl.text = foundNav.toStringAsFixed(4);
              curNavCtrl.text = (latestNav ?? foundNav).toStringAsFixed(4);
              navDateStatus = '✅ ${DateFormat('dd/MM/yyyy').format(pickedDate)} ની NAV: ₹${foundNav.toStringAsFixed(4)} ઓટો ફેચ થઈ';
            }
          }

          return AlertDialog(
            title: Text(existingItem == null ? 'મ્યુચ્યુઅલ ફંડ (Lumpsum / SIP) ઉમેરો' : 'મ્યુચ્યુઅલ ફંડ સુધારો'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('રોકાણ પ્રકાર પસંદ કરો:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Lumpsum', icon: Icon(Icons.looks_one, size: 16), label: Text('લમસમ (Lumpsum)', style: TextStyle(fontSize: 11.5))),
                      ButtonSegment(value: 'SIP', icon: Icon(Icons.autorenew, size: 16), label: Text('માસિક SIP', style: TextStyle(fontSize: 11.5))),
                    ],
                    selected: {investmentMode},
                    onSelectionChanged: (s) => setDlgState(() => investmentMode = s.first),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'auto', label: Text('તારીખ મુજબ ઓટો NAV ફેચ', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'manual', label: Text('મેન્યુઅલ NAV ઉમેરો', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {navMode},
                    onSelectionChanged: (s) => setDlgState(() => navMode = s.first),
                  ),
                  const SizedBox(height: 10),
                  // ખરીદીની તારીખ પસંદગી (જે તારીખે લેવામાં આવે તે તારીખની NAV ઓટો ફેચ થાય)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16, color: Colors.teal),
                    label: Text('ખરીદી તારીખ: ${DateFormat('dd/MM/yyyy').format(pickedDate)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _clampDate1800To2100(pickedDate),
                        firstDate: DateTime(1800, 1, 1),
                        lastDate: DateTime(2100, 12, 31),
                      );
                      if (d != null) {
                        pickedDate = d;
                        await applyNavForPickedDate();
                        setDlgState(() {});
                      }
                    },
                  ),
                  if (navDateStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(navDateStatus, style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 8),
                  if (navMode == 'auto') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'સ્કીમ સર્ચ કરો (દા.ત. HDFC, Nippon, Parag Parikh)',
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
                                searchResults = (json.decode(res.body) as List).take(8).toList();
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
                        height: 130,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
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
                                      .timeout(const Duration(seconds: 8));
                                  if (dRes.statusCode == 200) {
                                    final dData = json.decode(dRes.body);
                                    final list = dData['data'] as List?;
                                    if (list != null && list.isNotEmpty) {
                                      cachedNavHistory = list;
                                      await applyNavForPickedDate();
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: navCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'ખરીદી તારીખની NAV (₹)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: curNavCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'હાલની NAV (₹)'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'રોકાણ રકમ (₹)'),
                  ),
                  if (investmentMode == 'SIP') ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: sipFrequency,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: _t('SIP ફ્રીક્વન્સી (માસિક/અઠવાડિક/15 દિવસ/દૈનિક)', 'SIP Frequency')),
                            items: sipFreqList
                                .map((f) => DropdownMenuItem(value: f['name'].toString(), child: Text(f['name'].toString(), style: const TextStyle(fontSize: 12))))
                                .toList(),
                            onChanged: (v) => setDlgState(() => sipFrequency = v!),
                          ),
                        ),
                        IconButton(
                          tooltip: _t('નવી ફ્રીક્વન્સી ઉમેરો', 'Add Custom Frequency'),
                          icon: const Icon(Icons.add_circle, color: Colors.teal),
                          onPressed: () async {
                            final added = await _openAddCustomSipFrequencyDialog();
                            if (added != null) {
                              setDlgState(() {
                                sipFreqList = _getSipFrequencyOptions();
                                sipFrequency = added;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: sipDayCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: _t('SIP તારીખ / વાર (1-28)', 'SIP Day (1-28)')),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: executionMode,
                      decoration: InputDecoration(labelText: _t('SIP કપાત મોડ (ઓટો / મેન્યુઅલ)', 'SIP Execution Mode')),
                      items: [
                        DropdownMenuItem(value: 'auto', child: Text(_t('ઓટોમેટિક ખાતામાંથી કપાત', 'Automatic Deduction'))),
                        DropdownMenuItem(value: 'manual', child: Text(_t('મેન્યુઅલ (રીમાઇન્ડર પૂછીને)', 'Manual (Ask via Reminder)'))),
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
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
              ElevatedButton(
                onPressed: () {
                  final amt = double.tryParse(amtCtrl.text) ?? 0.0;
                  final nav = double.tryParse(navCtrl.text) ?? 100.0;
                  final curNav = double.tryParse(curNavCtrl.text) ?? nav;
                  if (amt <= 0 || schemeCtrl.text.trim().isEmpty) return;

                  final units = nav > 0 ? amt / nav : 0.0;
                  final id = existingItem != null ? existingItem['id'].toString() : "mf_${DateTime.now().millisecondsSinceEpoch}";

                  final int sipInterval = _getIntervalDaysForFrequency(sipFrequency);
                  mfInvestmentsBox.put(id, {
                    'id': id,
                    'schemeName': schemeCtrl.text.trim(),
                    'buyNav': nav,
                    'currentNav': curNav,
                    'investedAmount': amt,
                    'units': units,
                    'navMode': navMode,
                    'investmentMode': investmentMode,
                    'sipFrequency': sipFrequency,
                    'sipIntervalDays': sipInterval,
                    'executionMode': executionMode,
                    'sipDay': int.tryParse(sipDayCtrl.text) ?? 5,
                    'accountId': selectedAccId,
                    'date': pickedDate.toIso8601String(),
                    'mfSubCategory': existingItem?['mfSubCategory'] ?? '',
                  });

                  // દૈનિક નોંધમાં આપમેળે એડ/અપડેટ કરો
                  _syncInvestmentToDailyTransaction(
                    linkedInvestmentId: id,
                    title: "MF $investmentMode${investmentMode == 'SIP' ? ' ($sipFrequency)' : ''}: ${schemeCtrl.text.trim()}",
                    amount: amt,
                    date: pickedDate,
                    categoryId: '3',
                    categoryName: _t('શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'Stocks / Mutual Fund'),
                    categoryColor: Colors.blue.toARGB32(),
                    accountId: selectedAccId,
                  );

                  if (existingItem == null && investmentMode == 'SIP') {
                    final autoId = "auto_mf_${DateTime.now().millisecondsSinceEpoch}";
                    autoPayBox.put(autoId, {
                      'id': autoId,
                      'type': 'SIP',
                      'toTarget': schemeCtrl.text.trim(),
                      'amount': amt,
                      'day': int.tryParse(sipDayCtrl.text) ?? 5,
                      'sipFrequency': sipFrequency,
                      'sipIntervalDays': sipInterval,
                      'fromAccountId': selectedAccId,
                      'executionMode': executionMode,
                      'isActive': true,
                      'enableFlashMessage': true,
                      'reminderHour': 9,
                      'reminderMinute': 0,
                      'ringtoneName': 'ડિફોલ્ટ અલાર્મ ટોન (Default Alarm)',
                      'lastProcessed': _getReminderCycleKey({'sipFrequency': sipFrequency, 'sipIntervalDays': sipInterval}, pickedDate),
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

  // મ્યુચ્યુઅલ ફંડ વેચાણ (જેટલું રોકાણ/યુનિટ્સ થયેલ છે તેનાથી વધારે ન વેચી શકાય)
  void _openRedeemMutualFundDialog(Map<dynamic, dynamic> mf) {
    final double maxUnits = (mf['units'] as num?)?.toDouble() ?? 0.0;
    final double maxInvested = (mf['investedAmount'] as num?)?.toDouble() ?? 0.0;
    final double curNav = (mf['currentNav'] as num?)?.toDouble() ?? (mf['buyNav'] as num?)?.toDouble() ?? 100.0;

    final unitsCtrl = TextEditingController(text: maxUnits > 0 ? maxUnits.toStringAsFixed(3) : '1');
    final sellValCtrl = TextEditingController(text: (maxUnits > 0 ? maxUnits * curNav : maxInvested).toStringAsFixed(0));
    String depositAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    DateTime sellDate = DateTime.now();
    String errorText = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${mf['schemeName']} - રિડીમ / વેચાણ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ઉપલબ્ધ યુનિટ્સ: ${maxUnits.toStringAsFixed(3)} | મૂળ રોકાણ: ₹${maxInvested.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: unitsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'વેચવાના યુનિટ્સ (મહત્તમ: ${maxUnits.toStringAsFixed(3)})',
                    errorText: errorText.isEmpty ? null : errorText,
                  ),
                  onChanged: (v) {
                    final u = double.tryParse(v) ?? 0.0;
                    if (u > 0 && curNav > 0) {
                      sellValCtrl.text = (u * curNav).toStringAsFixed(0);
                    }
                  },
                ),
                TextField(
                  controller: sellValCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'મળેલ કુલ વેચાણ રકમ (₹)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: depositAccId,
                  decoration: const InputDecoration(labelText: 'જમા થનાર બેંક ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) => setDlgState(() => depositAccId = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final sellUnits = double.tryParse(unitsCtrl.text) ?? 0.0;
                final sellAmt = double.tryParse(sellValCtrl.text) ?? 0.0;
                if (sellUnits <= 0 || sellAmt <= 0) return;

                if (maxUnits > 0 && sellUnits > maxUnits + 0.001) {
                  setDlgState(() {
                    errorText = '❌ તમારા ઉપલબ્ધ ${maxUnits.toStringAsFixed(3)} યુનિટ્સ કરતાં વધારે વેચી શકાય નહીં!';
                  });
                  return;
                }
                if (maxUnits <= 0 && sellAmt > maxInvested) {
                  setDlgState(() {
                    errorText = '❌ તમારા રોકાણ ₹${maxInvested.toStringAsFixed(0)} કરતાં વધારે વેચી શકાય નહીં!';
                  });
                  return;
                }

                final double fractionSold = maxUnits > 0 ? (sellUnits / maxUnits).clamp(0.0, 1.0) : 1.0;
                final double proportionalBuyCost = maxInvested * fractionSold;
                final buyDate = DateTime.tryParse(mf['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 100));

                _recordRealizedCapitalGain(
                  assetType: 'Mutual Fund',
                  title: mf['schemeName'] ?? '',
                  buyDate: buyDate,
                  sellDate: sellDate,
                  buyValue: proportionalBuyCost,
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

                if (fractionSold >= 0.999) {
                  mfInvestmentsBox.delete(mf['id']);
                } else {
                  mf['units'] = math.max(0.0, maxUnits - sellUnits);
                  mf['investedAmount'] = math.max(0.0, maxInvested - proportionalBuyCost);
                  mfInvestmentsBox.put(mf['id'], mf);
                }

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

  // --- (૫-B) સ્ટોક અને ETF રોકાણ નોંધ (Lumpsum/SIP + Edit + વેચાણ મર્યાદા) ---
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
            color: adaptiveTintBg(Colors.blue),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricColumn('કુલ સ્ટોક/ETF રોકાણ', '₹${totalInv.toStringAsFixed(0)}', adaptiveAccentText(Colors.blue)),
                  _metricColumn('હાલનું બજાર મૂલ્ય', '₹${currentVal.toStringAsFixed(0)}', adaptiveAccentText(Colors.teal)),
                  _metricColumn('કુલ નફો / નુકસાન', '₹${(currentVal - totalInv).toStringAsFixed(0)}', currentVal >= totalInv ? adaptiveAccentText(Colors.green) : Colors.redAccent),
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
                onPressed: () => _openAddStockOrEtfDialog(),
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
                final mode = (s['investmentMode'] ?? 'Lumpsum').toString();

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.withOpacity(0.15),
                      child: Text(s['instrumentType'] ?? 'STK', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ),
                    title: Text("${s['symbol']} (${s['instrumentType']} • $mode)", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      "Qty: $qty × ₹$buyP = ₹${totalCost.toStringAsFixed(0)}\nતારીખ: ${DateFormat('dd/MM/yyyy hh:mm a').format(dt)}",
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                          tooltip: 'સુધારો',
                          onPressed: () => _openAddStockOrEtfDialog(existingItem: s),
                        ),
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

  void _openAddStockOrEtfDialog({Map<dynamic, dynamic>? existingItem}) {
    String instrumentType = existingItem != null ? (existingItem['instrumentType'] ?? 'Stock') : 'Stock';
    String investmentMode = existingItem != null ? (existingItem['investmentMode'] ?? 'Lumpsum') : 'Lumpsum';
    List<Map<String, dynamic>> sipFreqList = _getSipFrequencyOptions();
    String sipFrequency = existingItem != null && existingItem['sipFrequency'] != null
        ? existingItem['sipFrequency'].toString()
        : sipFreqList.first['name'].toString();
    final symbolCtrl = TextEditingController(text: existingItem != null ? existingItem['symbol'] : '');
    final qtyCtrl = TextEditingController(text: existingItem != null ? existingItem['quantity'].toString() : '1');
    final buyPriceCtrl = TextEditingController(text: existingItem != null ? existingItem['buyPrice'].toString() : '');
    String selectedAccId = existingItem != null && existingItem['accountId'] != null
        ? existingItem['accountId'].toString()
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');
    DateTime pickedDate = existingItem != null ? (DateTime.tryParse(existingItem['date'] ?? '') ?? DateTime.now()) : DateTime.now();
    TimeOfDay pickedTime = TimeOfDay.fromDateTime(pickedDate);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingItem == null ? 'સ્ટોક અથવા ETF રોકાણ નોંધો' : 'સ્ટોક / ETF સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'Lumpsum', label: Text(_t('લમસમ (Lumpsum)', 'Lumpsum'), style: const TextStyle(fontSize: 11.5))),
                    ButtonSegment(value: 'SIP', label: Text(_t('Stock SIP', 'Stock SIP'), style: const TextStyle(fontSize: 11.5))),
                  ],
                  selected: {investmentMode},
                  onSelectionChanged: (s) => setDlgState(() => investmentMode = s.first),
                ),
                if (investmentMode == 'SIP') ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: sipFrequency,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: _t('SIP ફ્રીક્વન્સી', 'SIP Frequency')),
                          items: sipFreqList.map((f) => DropdownMenuItem(value: f['name'].toString(), child: Text(f['name'].toString(), style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) => setDlgState(() => sipFrequency = v!),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.teal),
                        onPressed: () async {
                          final added = await _openAddCustomSipFrequencyDialog();
                          if (added != null) {
                            setDlgState(() {
                              sipFreqList = _getSipFrequencyOptions();
                              sipFrequency = added;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
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
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _clampDate1800To2100(pickedDate),
                            firstDate: DateTime(1800, 1, 1),
                            lastDate: DateTime(2100, 12, 31),
                          );
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
                final id = existingItem != null ? existingItem['id'].toString() : "stk_${DateTime.now().millisecondsSinceEpoch}";

                final int sipInterval = _getIntervalDaysForFrequency(sipFrequency);
                stockInvestmentsBox.put(id, {
                  'id': id,
                  'instrumentType': instrumentType,
                  'investmentMode': investmentMode,
                  'sipFrequency': sipFrequency,
                  'sipIntervalDays': sipInterval,
                  'symbol': symbolCtrl.text.trim().toUpperCase(),
                  'quantity': qty,
                  'buyPrice': price,
                  'currentPrice': price,
                  'totalInvested': totalAmt,
                  'accountId': selectedAccId,
                  'date': dt.toIso8601String(),
                });

                _syncInvestmentToDailyTransaction(
                  linkedInvestmentId: id,
                  title: "$instrumentType ($investmentMode${investmentMode == 'SIP' ? ' - $sipFrequency' : ''}): ${symbolCtrl.text.trim().toUpperCase()} ($qty Qty)",
                  amount: totalAmt,
                  date: dt,
                  hasTime: true,
                  categoryId: '3',
                  categoryName: _t('શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'Stocks / Mutual Fund'),
                  categoryColor: Colors.blue.toARGB32(),
                  accountId: selectedAccId,
                );

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

  // સ્ટોક/ETF વેચાણ (જેટલી સંખ્યા હોય તેનાથી વધારે ન વેચી શકાય)
  void _openSellStockOrEtfDialog(Map<dynamic, dynamic> stk) {
    final double maxQty = (stk['quantity'] as num?)?.toDouble() ?? 1.0;
    final double buyP = (stk['buyPrice'] as num?)?.toDouble() ?? 0.0;
    final sellQtyCtrl = TextEditingController(text: maxQty.toString());
    final sellPriceCtrl = TextEditingController(text: buyP.toString());
    String depositAccId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    String errorMsg = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${stk['symbol']} - વેચાણ નોંધ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ઉપલબ્ધ શેર/યુનિટ્સ: $maxQty (ખરીદ ભાવ: ₹$buyP)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 8),
              TextField(
                controller: sellQtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'વેચવાની સંખ્યા (મહત્તમ: $maxQty)',
                  errorText: errorMsg.isEmpty ? null : errorMsg,
                ),
              ),
              TextField(
                controller: sellPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'વેચાણ ભાવ પ્રતિ યુનિટ (₹)'),
              ),
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
                final sellQty = double.tryParse(sellQtyCtrl.text) ?? 0.0;
                final sellP = double.tryParse(sellPriceCtrl.text) ?? buyP;
                if (sellQty <= 0 || sellP <= 0) return;

                if (sellQty > maxQty + 0.0001) {
                  setDlgState(() {
                    errorMsg = '❌ તમારી પાસે માત્ર $maxQty યુનિટ્સ છે, તેનાથી વધારે વેચી શકાય નહીં!';
                  });
                  return;
                }

                final totalSell = sellQty * sellP;
                final totalBuy = sellQty * buyP;
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
                  'title': "${stk['instrumentType']} વેચાણ: ${stk['symbol']} ($sellQty Qty)",
                  'amount': totalSell,
                  'date': DateTime.now().toIso8601String(),
                  'categoryId': '2',
                  'categoryName': 'પગાર / ધંધાકીય આવક',
                  'categoryEffect': 'incomeCredit',
                  'categoryColor': Colors.green.toARGB32(),
                  'accountId': depositAccId,
                  'accountName': acc['name'],
                });

                if ((maxQty - sellQty).abs() <= 0.0001) {
                  stockInvestmentsBox.delete(stk['id']);
                } else {
                  stk['quantity'] = maxQty - sellQty;
                  stk['totalInvested'] = (maxQty - sellQty) * buyP;
                  stockInvestmentsBox.put(stk['id'], stk);
                }
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

  // --- (૫-C) બોન્ડ, FD, PLI ટેબ (બેંક/બોન્ડ આપનારનું નામ, વ્યાજ દર, મેચ્યુરિટી તારીખ, ઓટો મેચ્યુરિટી જમા, પ્રિ-મેચ્યોર અને પેનલ્ટી વિકલ્પ + Edit) ---
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
                label: const Text('નવી FD/બોન્ડ'),
                onPressed: () => _openAddFixedIncomeDialog(),
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
                final startDate = DateTime.tryParse(item['startDate'] ?? '') ?? DateTime.now();
                final targetDate = DateTime.tryParse(item['scheduledDate'] ?? '') ?? DateTime.now();
                final isCredit = item['flowType'] == 'inflow_maturity';
                final acc = accounts.firstWhere((a) => a['id'].toString() == item['accountId'], orElse: () => {'name': 'ખાતું'});
                final String issuer = (item['issuerBankName'] ?? '').toString();
                final double intRate = (item['interestRate'] as num?)?.toDouble() ?? 0.0;
                final bool isPremature = item['isPrematureClosed'] == true;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "${item['schemeType']}: ${item['title']}${issuer.isNotEmpty ? ' ($issuer)' : ''}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                                  tooltip: 'સુધારો',
                                  onPressed: () => _openAddFixedIncomeDialog(existingItem: item),
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
                          ],
                        ),
                        Text(
                          "મૂળ રકમ: ₹${(item['principalAmount'] as num).toStringAsFixed(0)} • વ્યાજ દર: ${intRate.toStringAsFixed(2)}% • પાકતી રકમ: ₹${(item['scheduledAmount'] as num).toStringAsFixed(0)}\n"
                          "શરૂઆત: ${DateFormat('dd/MM/yyyy').format(startDate)} → મેચ્યુરિટી: ${DateFormat('dd/MM/yyyy').format(targetDate)} (${acc['name']})\n"
                          "સ્થિતિ: ${item['isSettled'] == true ? (isPremature ? '⚠️ પ્રિ-મેચ્યોર ક્લોઝ (પેનલ્ટી: ₹${item['prematurePenalty'] ?? 0})' : '✅ મેચ્યુરિટી ખાતામાં જમા થયેલ') : '⏳ ચાલુ (મેચ્યુરિટી તારીખે ઓટો જમા થશે)'}",
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        if (item['isSettled'] != true) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.deepOrange,
                                  side: const BorderSide(color: Colors.deepOrange),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                icon: const Icon(Icons.warning_amber, size: 15),
                                label: const Text('પ્રિ-મેચ્યોર (Premature)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () => _openPrematureCloseFixedIncomeDialog(item),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                icon: const Icon(Icons.check_circle_outline, size: 15),
                                label: Text(isCredit ? 'મેચ્યુરિટી જમા કરો' : 'હપ્તો ચૂકવો', style: const TextStyle(fontSize: 11)),
                                onPressed: () {
                                  item['scheduledDate'] = DateTime.now().toIso8601String();
                                  item['autoAdjust'] = true;
                                  fixedIncomeBox.put(item['id'], item);
                                  _processFixedIncomeSchedules();
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        ],
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

  double _calculateMaturityAmount(double principal, double ratePct, DateTime start, DateTime maturity, bool isCompound) {
    if (principal <= 0 || ratePct <= 0) return principal;
    final int days = math.max(1, maturity.difference(start).inDays);
    final double years = days / 365.0;
    if (isCompound) {
      // ભારતીય બેંક FD પ્રમાણે ત્રિમાસિક ચક્રવૃદ્ધિ વ્યાજ (Quarterly Compounding)
      return principal * math.pow(1.0 + (ratePct / 100.0) / 4.0, 4.0 * years);
    } else {
      return principal + (principal * (ratePct / 100.0) * years);
    }
  }

  void _openAddFixedIncomeDialog({Map<dynamic, dynamic>? existingItem}) {
    String schemeType = existingItem != null ? (existingItem['schemeType'] ?? 'FD (ફિક્સ ડિપોઝિટ)') : 'FD (ફિક્સ ડિપોઝિટ)';
    String investmentMode = existingItem != null ? (existingItem['investmentMode'] ?? 'Lumpsum') : 'Lumpsum';
    final issuerCtrl = TextEditingController(text: existingItem != null ? (existingItem['issuerBankName'] ?? '') : '');
    final titleCtrl = TextEditingController(text: existingItem != null ? (existingItem['title'] ?? '') : '');
    final principalCtrl = TextEditingController(text: existingItem != null ? existingItem['principalAmount'].toString() : '');
    final rateCtrl = TextEditingController(text: existingItem != null ? (existingItem['interestRate']?.toString() ?? '7.25') : '7.25');
    final scheduledAmtCtrl = TextEditingController(text: existingItem != null ? existingItem['scheduledAmount'].toString() : '');

    String flowType = existingItem != null ? (existingItem['flowType'] ?? 'inflow_maturity') : 'inflow_maturity';
    String selectedAccId = existingItem != null && existingItem['accountId'] != null
        ? existingItem['accountId'].toString()
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');
    DateTime startDate = existingItem != null ? (DateTime.tryParse(existingItem['startDate'] ?? '') ?? DateTime.now()) : DateTime.now();
    DateTime scheduledDate = existingItem != null
        ? (DateTime.tryParse(existingItem['scheduledDate'] ?? '') ?? DateTime.now().add(const Duration(days: 365)))
        : DateTime.now().add(const Duration(days: 365));
    bool isCompoundInterest = existingItem != null ? (existingItem['isCompound'] ?? true) : true;
    bool deductInitialNow = existingItem == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          void recalculateMaturity() {
            final p = double.tryParse(principalCtrl.text) ?? 0.0;
            final r = double.tryParse(rateCtrl.text) ?? 0.0;
            if (p > 0) {
              final mat = _calculateMaturityAmount(p, r, startDate, scheduledDate, isCompoundInterest);
              scheduledAmtCtrl.text = mat.toStringAsFixed(0);
            }
          }

          return AlertDialog(
            title: Text(existingItem == null ? 'બોન્ડ / FD / PLI / સ્કીમ ઉમેરો' : 'FD / બોન્ડ વિગત સુધારો'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Lumpsum', label: Text('વન-ટાઇમ (Lumpsum)', style: TextStyle(fontSize: 11.5))),
                      ButtonSegment(value: 'SIP', label: Text('નિયમિત હપ્તો (RD/SIP)', style: TextStyle(fontSize: 11.5))),
                    ],
                    selected: {investmentMode},
                    onSelectionChanged: (s) => setDlgState(() => investmentMode = s.first),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: schemeType,
                    decoration: const InputDecoration(labelText: 'પ્રકાર પસંદ કરો'),
                    items: ['FD (ફિક્સ ડિપોઝિટ)', 'બોન્ડ (Sovereign / Corp Bond)', 'PLI (પોસ્ટલ લાઇફ ઇન્સ્યોરન્સ)', 'RD / પોસ્ટ ઓફિસ સ્કીમ', 'PPF / SSY / અન્ય']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12.5)))).toList(),
                    onChanged: (v) => setDlgState(() => schemeType = v!),
                  ),
                  TextField(
                    controller: issuerCtrl,
                    decoration: const InputDecoration(labelText: 'બેંક અથવા બોન્ડ આપનાર સંસ્થાનું નામ (દા.ત. SBI, HDFC, RBI)'),
                  ),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'સ્કીમ નામ / FD નંબર / પોલિસી વિગત'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: principalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'રોકાણ મૂળ રકમ (₹)'),
                          onChanged: (_) => recalculateMaturity(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'વાર્ષિક વ્યાજ દર (%)'),
                          onChanged: (_) => recalculateMaturity(),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ત્રિમાસિક ચક્રવૃદ્ધિ વ્યાજ (Quarterly Compounding)', style: TextStyle(fontSize: 11.5)),
                    value: isCompoundInterest,
                    onChanged: (v) {
                      setDlgState(() {
                        isCompoundInterest = v;
                        recalculateMaturity();
                      });
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range, size: 15),
                          label: Text('શરૂ: ${DateFormat('dd/MM/yy').format(startDate)}', style: const TextStyle(fontSize: 11)),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _clampDate1800To2100(startDate),
                              firstDate: DateTime(1800, 1, 1),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (d != null) {
                              setDlgState(() {
                                startDate = d;
                                recalculateMaturity();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event_available, size: 15),
                          label: Text('મેચ્યુરિટી: ${DateFormat('dd/MM/yy').format(scheduledDate)}', style: const TextStyle(fontSize: 11)),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _clampDate1800To2100(scheduledDate),
                              firstDate: DateTime(1800, 1, 1),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (d != null) {
                              setDlgState(() {
                                scheduledDate = d;
                                recalculateMaturity();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: scheduledAmtCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'મેચ્યુરિટી તારીખે જમા થનાર કુલ રકમ (₹)'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calculate, color: Colors.teal),
                        tooltip: 'વ્યાજ દર પ્રમાણે મેચ્યુરિટી ગણો',
                        onPressed: () => setDlgState(recalculateMaturity),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: flowType,
                    decoration: const InputDecoration(labelText: 'મેચ્યુરિટી તારીખે વ્યવહારનો પ્રકાર'),
                    items: const [
                      DropdownMenuItem(value: 'inflow_maturity', child: Text('મેચ્યુરિટી રકમ ખાતામાં જમા થશે (Maturity Credit)', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'outflow_installment', child: Text('રૂપિયા ખાતામાંથી ચૂકવવાના છે (Installment)', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) => setDlgState(() => flowType = v!),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAccId,
                    decoration: const InputDecoration(labelText: 'કયા બેંક ખાતામાં મેચ્યુરિટી જમા/એડજસ્ટ કરવી?'),
                    items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                    onChanged: (v) => setDlgState(() => selectedAccId = v!),
                  ),
                  if (existingItem == null)
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
                  final rPct = double.tryParse(rateCtrl.text) ?? 0.0;
                  if (scheduledAmtCtrl.text.trim().isEmpty && pAmt > 0) {
                    recalculateMaturity();
                  }
                  final sAmt = double.tryParse(scheduledAmtCtrl.text) ?? pAmt;
                  if (pAmt <= 0 || titleCtrl.text.trim().isEmpty) return;

                  final id = existingItem != null ? existingItem['id'].toString() : "fi_${DateTime.now().millisecondsSinceEpoch}";
                  fixedIncomeBox.put(id, {
                    'id': id,
                    'schemeType': schemeType,
                    'investmentMode': investmentMode,
                    'issuerBankName': issuerCtrl.text.trim(),
                    'title': titleCtrl.text.trim(),
                    'principalAmount': pAmt,
                    'interestRate': rPct,
                    'isCompound': isCompoundInterest,
                    'scheduledAmount': sAmt,
                    'flowType': flowType,
                    'accountId': selectedAccId,
                    'startDate': startDate.toIso8601String(),
                    'scheduledDate': scheduledDate.toIso8601String(),
                    'autoAdjust': true,
                    'isSettled': existingItem != null ? (existingItem['isSettled'] ?? false) : false,
                  });

                  if (deductInitialNow || existingItem != null) {
                    _syncInvestmentToDailyTransaction(
                      linkedInvestmentId: id,
                      title: "$schemeType રોકાણ: ${titleCtrl.text.trim()} (${issuerCtrl.text.trim()})",
                      amount: pAmt,
                      date: startDate,
                      categoryId: '7',
                      categoryName: _t('મિલકત / બોન્ડ / FD રોકાણ', 'Assets / Bond / FD Investment'),
                      categoryColor: Colors.teal.toARGB32(),
                      accountId: selectedAccId,
                    );
                  }

                  _processFixedIncomeSchedules();
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

  // FD / બોન્ડ પ્રિ-મેચ્યોર (Premature Withdrawal) અને પેનલ્ટી ગણતરી ડાયલોગ
  void _openPrematureCloseFixedIncomeDialog(Map<dynamic, dynamic> item) {
    final double principal = (item['principalAmount'] as num?)?.toDouble() ?? 0.0;
    final double origRate = (item['interestRate'] as num?)?.toDouble() ?? 7.0;
    final DateTime startDate = DateTime.tryParse(item['startDate'] ?? '') ?? DateTime.now().subtract(const Duration(days: 180));
    DateTime prematureDate = DateTime.now();

    final penaltyRateCtrl = TextEditingController(text: '1.0'); // 1% penalty on interest rate
    final penaltyFixedCtrl = TextEditingController(text: '0'); // Fixed rupee penalty
    final netPayoutCtrl = TextEditingController();
    String depositAccId = (item['accountId'] ?? (accounts.isNotEmpty ? accounts.first['id'] : '')).toString();

    void recalcPremature() {
      final double penRate = double.tryParse(penaltyRateCtrl.text) ?? 0.0;
      final double penFixed = double.tryParse(penaltyFixedCtrl.text) ?? 0.0;
      final double effectiveRate = math.max(0.0, origRate - penRate);
      final double grossVal = _calculateMaturityAmount(principal, effectiveRate, startDate, prematureDate, item['isCompound'] ?? true);
      final double netVal = math.max(0.0, grossVal - penFixed);
      netPayoutCtrl.text = netVal.toStringAsFixed(0);
    }

    recalcPremature();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final int heldDays = math.max(1, prematureDate.difference(startDate).inDays);
          return AlertDialog(
            title: Text('પ્રિ-મેચ્યોર ક્લોઝર: ${item['title']}', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'મૂળ રોકાણ: ₹${principal.toStringAsFixed(0)} | મૂળ વ્યાજ દર: ${origRate.toStringAsFixed(2)}%\n'
                    'રોકાણ સમયગાળો: $heldDays દિવસ (${DateFormat('dd/MM/yyyy').format(startDate)} થી)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 16),
                    label: Text('પ્રિ-મેચ્યોર તારીખ: ${DateFormat('dd/MM/yyyy').format(prematureDate)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _clampDate1800To2100(prematureDate),
                        firstDate: DateTime(1800, 1, 1),
                        lastDate: DateTime(2100, 12, 31),
                      );
                      if (d != null) {
                        setDlgState(() {
                          prematureDate = d;
                          recalcPremature();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: penaltyRateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'પેનલ્ટી વ્યાજ કાપ (%)'),
                          onChanged: (_) => setDlgState(recalcPremature),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: penaltyFixedCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'સીધી પેનલ્ટી ચાર્જ (₹)'),
                          onChanged: (_) => setDlgState(recalcPremature),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: netPayoutCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'પેનલ્ટી બાદ ખાતામાં જમા થનાર ચોખ્ખી રકમ (₹)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: depositAccId,
                    decoration: const InputDecoration(labelText: 'જમા થનાર બેંક ખાતું'),
                    items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                    onChanged: (v) => setDlgState(() => depositAccId = v!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                onPressed: () {
                  final double netPayout = double.tryParse(netPayoutCtrl.text) ?? principal;
                  final double penFixed = double.tryParse(penaltyFixedCtrl.text) ?? 0.0;
                  final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccId, orElse: () => {'name': 'બેંક ખાતું'});

                  final txId = "fi_auto_premature_${DateTime.now().millisecondsSinceEpoch}";
                  transactionsBox.put(txId, {
                    'id': txId,
                    'title': "${item['schemeType']} પ્રિ-મેચ્યોર જમા: ${item['title']}",
                    'amount': netPayout,
                    'date': prematureDate.toIso8601String(),
                    'categoryId': '2',
                    'categoryName': 'પગાર / ધંધાકીય આવક',
                    'categoryEffect': 'incomeCredit',
                    'categoryColor': Colors.green.toARGB32(),
                    'accountId': depositAccId,
                    'accountName': acc['name'],
                  });

                  _recordRealizedCapitalGain(
                    assetType: item['schemeType'] ?? 'FD/Bond',
                    title: "${item['title']} (Premature)",
                    buyDate: startDate,
                    sellDate: prematureDate,
                    buyValue: principal,
                    sellValue: netPayout,
                  );

                  item['isSettled'] = true;
                  item['isPrematureClosed'] = true;
                  item['prematurePenalty'] = penFixed;
                  item['scheduledAmount'] = netPayout;
                  fixedIncomeBox.put(item['id'], item);

                  setState(() {});
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ પ્રિ-મેચ્યોર રકમ ₹${netPayout.toStringAsFixed(0)} ખાતામાં જમા થઈ ગઈ!'),
                      backgroundColor: Colors.teal,
                    ),
                  );
                },
                child: const Text('પ્રિ-મેચ્યોર જમા કરો'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- (૫-D) કિંમતી ધાતુઓ (આપેલ ધાતુઓ સિવાય નવી ધાતુ ઉમેરવાનો વિકલ્પ + Lumpsum/SIP + Edit + વેચાણ મર્યાદા) ---
  void _openAddCustomMetalTypeDialog(VoidCallback onUpdated) {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('નવી કિંમતી ધાતુ ઉમેરો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'ધાતુનું નામ (દા.ત. પ્લેટિનમ, રોઝ ગોલ્ડ, તાંબુ, ડાયમંડ)'),
            ),
            TextField(
              controller: rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '૧ ગ્રામનો બજાર ભાવ (₹)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
          ElevatedButton(
            onPressed: () {
              final n = nameCtrl.text.trim();
              final r = double.tryParse(rateCtrl.text) ?? 0.0;
              if (n.isEmpty || r <= 0) return;
              final list = customMetals;
              list.removeWhere((e) => e['name'] == n);
              list.add({'name': n, 'ratePerGram': r});
              settingsBox.put('customMetalsList', list);
              onUpdated();
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('ઉમેરો'),
          ),
        ],
      ),
    );
  }

  void _openAddBullionDialog({Map<dynamic, dynamic>? existingItem}) {
    final titleCtrl = TextEditingController(text: existingItem != null ? existingItem['title'] : '');
    final weightCtrl = TextEditingController(text: existingItem != null ? existingItem['weight'].toString() : '');
    final buyPriceCtrl = TextEditingController(text: existingItem != null ? existingItem['buyPrice'].toString() : '');

    List<String> getAvailableMetalNames() {
      final base = ['સોનું 24K (Gold 24K)', 'સોનું 22K (Gold 22K)', 'ચાંદી (Silver)'];
      for (final cm in customMetals) {
        final n = cm['name'].toString();
        if (!base.contains(n)) base.add(n);
      }
      return base;
    }

    String metalType = existingItem != null ? existingItem['metalType'] : 'સોનું 24K (Gold 24K)';
    String investmentMode = existingItem != null ? (existingItem['investmentMode'] ?? 'Lumpsum') : 'Lumpsum';
    String selectedAccId = existingItem != null && existingItem['accountId'] != null
        ? existingItem['accountId'].toString()
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');

    DateTime pickedDate = existingItem != null ? DateTime.parse(existingItem['date']) : DateTime.now();
    bool deductFromAccount = existingItem == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final allMetalOptions = getAvailableMetalNames();
          if (!allMetalOptions.contains(metalType)) {
            allMetalOptions.add(metalType);
          }
          final double currentPerGram = _getMetalLiveRatePerGram(metalType);

          void autoEstimatePrice() {
            final w = double.tryParse(weightCtrl.text) ?? 0.0;
            if (w > 0) {
              buyPriceCtrl.text = (w * currentPerGram).toStringAsFixed(0);
            }
          }

          return AlertDialog(
            title: Text(existingItem == null ? 'કિંમતી ધાતુ રોકાણ ઉમેરો' : 'કિંમતી ધાતુ સુધારો'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Lumpsum', label: Text('વન-ટાઇમ ખરીદી', style: TextStyle(fontSize: 11.5))),
                      ButtonSegment(value: 'SIP', label: Text('ગોલ્ડ/સિલ્વર SIP', style: TextStyle(fontSize: 11.5))),
                    ],
                    selected: {investmentMode},
                    onSelectionChanged: (s) => setDlgState(() => investmentMode = s.first),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: metalType,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'ધાતુ અને શુદ્ધતા પસંદ કરો'),
                          items: allMetalOptions.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12.5)))).toList(),
                          onChanged: (v) {
                            setDlgState(() {
                              metalType = v!;
                              autoEstimatePrice();
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.teal),
                        tooltip: 'અન્ય નવી ધાતુ ઉમેરો',
                        onPressed: () {
                          _openAddCustomMetalTypeDialog(() {
                            setDlgState(() {
                              final updated = getAvailableMetalNames();
                              metalType = updated.last;
                            });
                          });
                        },
                      ),
                    ],
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
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 15),
                    label: Text('તારીખ: ${DateFormat('dd/MM/yyyy').format(pickedDate)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _clampDate1800To2100(pickedDate),
                        firstDate: DateTime(1800, 1, 1),
                        lastDate: DateTime(2100, 12, 31),
                      );
                      if (d != null) setDlgState(() => pickedDate = d);
                    },
                  ),
                  if (existingItem == null) ...[
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
                    'investmentMode': investmentMode,
                    'title': titleCtrl.text.trim().isEmpty ? metalType : titleCtrl.text.trim(),
                    'weight': weight,
                    'buyPrice': enteredPrice,
                    'accountId': selectedAccId,
                    'date': pickedDate.toIso8601String(),
                  });

                  if ((deductFromAccount || existingItem != null) && selectedAccId.isNotEmpty) {
                    _syncInvestmentToDailyTransaction(
                      linkedInvestmentId: id,
                      title: "ધાતુ ખરીદી ($investmentMode): ${titleCtrl.text.trim().isEmpty ? metalType : titleCtrl.text.trim()} (${weight}g)",
                      amount: enteredPrice,
                      date: pickedDate,
                      categoryId: '4',
                      categoryName: _t('સોનું / ચાંદી રોકાણ', 'Gold / Silver Investment'),
                      categoryColor: Colors.amber.toARGB32(),
                      accountId: selectedAccId,
                    );
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

  // ધાતુ વેચાણ (જેટલું વજન/રોકાણ હોય તેનાથી વધારે ન વેચી શકાય)
  void _openSellBullionDialog(Map<dynamic, dynamic> bullion) {
    final double maxWeight = (bullion['weight'] as num?)?.toDouble() ?? 1.0;
    final double totalBuyPrice = (bullion['buyPrice'] as num?)?.toDouble() ?? 0.0;
    final double livePerG = _getMetalLiveRatePerGram((bullion['metalType'] ?? '').toString());

    final sellWeightCtrl = TextEditingController(text: maxWeight.toString());
    final sellPriceCtrl = TextEditingController(text: (maxWeight * livePerG).toStringAsFixed(0));
    String depositAccountId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    String errorText = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${bullion['title']} - વેચાણ નોંધ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ઉપલબ્ધ વજન: ${maxWeight}g (ખરીદ કિંમત: ₹${totalBuyPrice.toStringAsFixed(0)})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 8),
              TextField(
                controller: sellWeightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'વેચવાનું વજન ગ્રામમાં (મહત્તમ: ${maxWeight}g)',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
                onChanged: (v) {
                  final w = double.tryParse(v) ?? 0.0;
                  if (w > 0) {
                    sellPriceCtrl.text = (w * livePerG).toStringAsFixed(0);
                  }
                },
              ),
              TextField(
                controller: sellPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'કુલ વેચાણ કિંમત (₹)'),
              ),
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
                final sellW = double.tryParse(sellWeightCtrl.text) ?? 0.0;
                final sellPrice = double.tryParse(sellPriceCtrl.text) ?? 0.0;
                if (sellW <= 0 || sellPrice <= 0) return;

                if (sellW > maxWeight + 0.001) {
                  setDlgState(() {
                    errorText = '❌ તમારી પાસે માત્ર ${maxWeight}g જથ્થો છે, તેનાથી વધારે વેચી શકાય નહીં!';
                  });
                  return;
                }

                final double fraction = (sellW / maxWeight).clamp(0.0, 1.0);
                final double proportionalBuyCost = totalBuyPrice * fraction;
                final buyDate = DateTime.tryParse(bullion['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 180));

                _recordRealizedCapitalGain(
                  assetType: 'Bullion (${bullion['metalType']})',
                  title: bullion['title'] ?? '',
                  buyDate: buyDate,
                  sellDate: DateTime.now(),
                  buyValue: proportionalBuyCost,
                  sellValue: sellPrice,
                );

                final acc = accounts.firstWhere((a) => a['id'].toString() == depositAccountId);
                final txId = "tx_sell_bul_${DateTime.now().millisecondsSinceEpoch}";
                transactionsBox.put(txId, {
                  'id': txId,
                  'title': "ધાતુ વેચાણ આવક: ${bullion['title']} (${sellW}g)",
                  'amount': sellPrice,
                  'date': DateTime.now().toIso8601String(),
                  'categoryId': '2',
                  'categoryName': 'પગાર / ધંધાકીય આવક',
                  'categoryEffect': 'incomeCredit',
                  'categoryColor': Colors.green.toARGB32(),
                  'accountId': depositAccountId,
                  'accountName': acc['name'],
                });

                if (fraction >= 0.999) {
                  bullionInvestmentsBox.delete(bullion['id']);
                } else {
                  bullion['weight'] = maxWeight - sellW;
                  bullion['buyPrice'] = math.max(0.0, totalBuyPrice - proportionalBuyCost);
                  bullionInvestmentsBox.put(bullion['id'], bullion);
                }

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
      final perGram = _getMetalLiveRatePerGram(mType);
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
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add_circle_outline, size: 16),
                            label: const Text('નવી ધાતુ ઉમેરો', style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _openAddCustomMetalTypeDialog(() {}),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.teal),
                            onPressed: () => _fetchLiveBullionRates(showToast: true),
                          ),
                        ],
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
                  color: adaptiveTintBg(Colors.amber),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Text("સોનું 24K (10g)", style: TextStyle(color: adaptiveAccentText(Colors.amber), fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("₹${rates['gold24']!.toStringAsFixed(0)}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: adaptiveAccentText(Colors.amber))),
                        const Divider(height: 10),
                        Text("22K (10g): ₹${rates['gold22']!.toStringAsFixed(0)}", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: adaptiveAccentText(Colors.amber))),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  color: adaptiveTintBg(Colors.blueGrey),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Text("ચાંદી (1 Kg)", style: TextStyle(color: adaptiveAccentText(Colors.blueGrey), fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("₹${rates['silver']!.toStringAsFixed(0)}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: adaptiveAccentText(Colors.blueGrey))),
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
            color: adaptiveTintBg(Colors.teal),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricColumn('ખરીદ કિંમત', '₹${totalBuyCost.toStringAsFixed(0)}', primaryTextColor),
                  _metricColumn('લાઇવ મૂલ્ય', '₹${totalLiveValue.toStringAsFixed(0)}', adaptiveAccentText(Colors.teal)),
                  _metricColumn('નફો / તફાવત', '₹${(totalLiveValue - totalBuyCost).toStringAsFixed(0)}', totalLiveValue >= totalBuyCost ? adaptiveAccentText(Colors.green) : Colors.redAccent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("મારું કિંમતી ધાતુ રોકાણ:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('રોકાણ ઉમેરો'),
                onPressed: () => _openAddBullionDialog(),
              ),
            ],
          ),
          if (bullionList.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("કોઈ સોનું, ચાંદી કે અન્ય ધાતુનું રોકાણ નોંધેલ નથી.")))
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
                final perGram = _getMetalLiveRatePerGram(mType);
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
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            bullionInvestmentsBox.delete(b['id']);
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

  // --- (૫-E) અન્ય મિલકત / સ્થાવર સંપત્તિ (મકાન, ખેતર, દુકાનો, પ્લોટ + Edit + વેચાણ મર્યાદા) ---
  void _openAddPhysicalAssetDialog({Map<dynamic, dynamic>? existingAsset}) {
    final titleCtrl = TextEditingController(text: existingAsset != null ? existingAsset['title'] : '');
    final valueCtrl = TextEditingController(text: existingAsset != null ? existingAsset['value'].toString() : '');
    final curValueCtrl = TextEditingController(text: existingAsset != null ? (existingAsset['currentValue'] ?? existingAsset['value']).toString() : '');
    final locCtrl = TextEditingController(text: existingAsset != null ? existingAsset['location'] : '');
    String type = existingAsset != null ? existingAsset['type'] : 'મકાન/ફ્લેટ';
    String investmentMode = existingAsset != null ? (existingAsset['investmentMode'] ?? 'Lumpsum') : 'Lumpsum';
    String selectedAccId = existingAsset != null && existingAsset['accountId'] != null
        ? existingAsset['accountId'].toString()
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');
    bool deductFromAcc = existingAsset == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingAsset == null ? 'નવી સ્થાવર મિલકત ઉમેરો' : 'સ્થાવર મિલકત સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Lumpsum', label: Text('વન-ટાઇમ ખરીદી', style: TextStyle(fontSize: 11.5))),
                    ButtonSegment(value: 'Installment', label: Text('હપ્તેથી (Installment)', style: TextStyle(fontSize: 11.5))),
                  ],
                  selected: {investmentMode},
                  onSelectionChanged: (s) => setDlgState(() => investmentMode = s.first),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'મિલકતનો પ્રકાર'),
                  items: ['મકાન/ફ્લેટ', 'ખેતીની જમીન', 'દુકાન/ઓફિસ', 'પ્લોટ/જમીન', 'વાહન/અન્ય']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDlgState(() => type = v!),
                ),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'નામ / વિગત (દા.ત. ૨ BHK ફ્લેટ, ખેતર, દુકાન)')),
                TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'સ્થળ / શહેર / ગામ')),
                TextField(
                  controller: valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'ખરીદ રોકાણ કિંમત (₹)'),
                  onChanged: (v) {
                    if (existingAsset == null) curValueCtrl.text = v;
                  },
                ),
                TextField(
                  controller: curValueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'હાલનું અંદાજિત બજાર મૂલ્ય (₹)'),
                ),
                if (existingAsset == null) ...[
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(valueCtrl.text) ?? 0.0;
                final curVal = double.tryParse(curValueCtrl.text) ?? val;
                if (val <= 0 || titleCtrl.text.isEmpty) return;
                final id = existingAsset != null ? existingAsset['id'] : "asset_${DateTime.now().millisecondsSinceEpoch}";

                physicalAssetsBox.put(id, {
                  'id': id,
                  'title': titleCtrl.text,
                  'type': type,
                  'investmentMode': investmentMode,
                  'location': locCtrl.text,
                  'value': val,
                  'currentValue': curVal,
                  'accountId': selectedAccId,
                  'date': existingAsset != null ? existingAsset['date'] : DateTime.now().toIso8601String(),
                });

                if (deductFromAcc || existingAsset != null) {
                  _syncInvestmentToDailyTransaction(
                    linkedInvestmentId: id,
                    title: "મિલકત ખરીદી ($type): ${titleCtrl.text}",
                    amount: val,
                    date: existingAsset != null ? (DateTime.tryParse(existingAsset['date'] ?? '') ?? DateTime.now()) : DateTime.now(),
                    categoryId: '7',
                    categoryName: _t('મિલકત / બોન્ડ / FD રોકાણ', 'Assets / Bond / FD Investment'),
                    categoryColor: Colors.teal.toARGB32(),
                    accountId: selectedAccId,
                  );
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
    final double buyVal = (asset['value'] as num?)?.toDouble() ?? 0.0;
    final sellSharePctCtrl = TextEditingController(text: '100');
    final sellPriceCtrl = TextEditingController(text: (asset['currentValue'] ?? asset['value']).toString());
    String depositAccountId = accounts.isNotEmpty ? accounts.first['id'].toString() : '';
    String errorText = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('${asset['title']} - વેચાણ નોંધ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('મૂળ રોકાણ કિંમત: ₹${buyVal.toStringAsFixed(0)} (મહત્તમ હિસ્સો: 100%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 8),
              TextField(
                controller: sellSharePctCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'વેચાણ હિસ્સો % (મહત્તમ 100%)',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
              ),
              TextField(
                controller: sellPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'મળેલ વેચાણ કિંમત (₹)'),
              ),
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
                final sharePct = double.tryParse(sellSharePctCtrl.text) ?? 0.0;
                final sellPrice = double.tryParse(sellPriceCtrl.text) ?? 0.0;
                if (sharePct <= 0 || sellPrice <= 0) return;
                if (sharePct > 100.0) {
                  setDlgState(() {
                    errorText = '❌ તમારા 100% રોકાણ હિસ્સા કરતાં વધારે વેચી શકાય નહીં!';
                  });
                  return;
                }

                final double fraction = (sharePct / 100.0).clamp(0.0, 1.0);
                final double costSold = buyVal * fraction;
                final buyDate = DateTime.tryParse(asset['date'] ?? '') ?? DateTime.now().subtract(const Duration(days: 800));

                _recordRealizedCapitalGain(
                  assetType: 'Physical Asset (${asset['type']})',
                  title: asset['title'] ?? '',
                  buyDate: buyDate,
                  sellDate: DateTime.now(),
                  buyValue: costSold,
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

                if (fraction >= 0.999) {
                  physicalAssetsBox.delete(asset['id']);
                } else {
                  asset['value'] = math.max(0.0, buyVal - costSold);
                  asset['currentValue'] = math.max(0.0, ((asset['currentValue'] as num?)?.toDouble() ?? buyVal) * (1.0 - fraction));
                  physicalAssetsBox.put(asset['id'], asset);
                }

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
    double totalVal = assets.fold(0.0, (sum, i) => sum + ((i['currentValue'] ?? i['value']) as num).toDouble());

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
              ? const Padding(padding: EdgeInsets.all(30.0), child: Text("કોઈ મકાન, ખેતર, દુકાન કે પ્લોટ ઉમેરેલ નથી."))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: assets.length,
                  itemBuilder: (ctx, i) {
                    final a = assets[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.home_work, color: Colors.teal),
                        title: Text(a['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${a['type']} • ${a['location']}\nખરીદ: ₹${a['value']} | હાલનું મૂલ્ય: ₹${a['currentValue'] ?? a['value']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                              tooltip: 'સુધારો',
                              onPressed: () => _openAddPhysicalAssetDialog(existingAsset: a),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                              onPressed: () => _openSellPhysicalAssetDialog(a),
                              child: const Text('વેચો', style: TextStyle(fontSize: 11)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () {
                                physicalAssetsBox.delete(a['id']);
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


  // =========================================================
  // સેટિંગ્સ ડાયલોગ:
  // - થીમ કલર બદલો
  // - ગેલેરીમાંથી ફોટો સિલેક્ટ કરી બેકગ્રાઉન્ડમાં સેટ કરો
  // - પ્રથમ સ્ક્રીનનું શીર્ષક બદલો
  // - કેટેગરી મેનેજર (સુધારો + પ્રકાર: ખર્ચ, આવક, રોકાણ)
  // - બેંક અને ક્રેડિટ કાર્ડ ખાતા મેનેજર (બેંકનું નામ, બ્રાન્ચ, પ્રકાર, વ્યાજ દર, પ્રારંભિક કિંમત, કાર્ડ બેંક/NBFC, કાર્ડ પ્રકાર, લિમિટ અને વોર્નિંગ)
  // - ઓટો-પે / SIP રીમાઇન્ડર (તારીખ, સમય, રીંગટોન, ફ્લેશ મેસેજ)
  // - PDF + Excel (.xls / .csv) રિપોર્ટ એક્સપોર્ટ
  // =========================================================
  void _openThemeColorPickerDialog() {
    final List<Map<String, dynamic>> palette = [
      {'name': 'ટીલ (Teal)', 'color': Colors.teal},
      {'name': 'ઇન્ડિગો (Indigo)', 'color': Colors.indigo},
      {'name': 'બ્લુ (Blue)', 'color': Colors.blue},
      {'name': 'ગ્રીન (Green)', 'color': Colors.green},
      {'name': 'ડીપ પર્પલ (Purple)', 'color': Colors.deepPurple},
      {'name': 'ઓરેન્જ (Deep Orange)', 'color': Colors.deepOrange},
      {'name': 'પિંક (Pink)', 'color': Colors.pink},
      {'name': 'રેડ (Red)', 'color': Colors.red},
      {'name': 'ગોલ્ડ / એમ્બર (Amber)', 'color': Colors.amber.shade800},
      {'name': 'બ્રાઉન (Brown)', 'color': Colors.brown},
      {'name': 'સિયાન (Cyan)', 'color': Colors.cyan.shade700},
      {'name': 'બ્લુ ગ્રે (Blue Grey)', 'color': Colors.blueGrey},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('થીમ કલર પસંદ કરો'),
        content: SizedBox(
          width: double.maxFinite,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: palette.map((item) {
              final Color c = item['color'] as Color;
              final bool isSel = appSeedColor.value.toARGB32() == c.toARGB32();
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  appSeedColor.value = c;
                  settingsBox.put('primaryColor', c.toARGB32());
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 130,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c, width: isSel ? 2.5 : 1),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 12, backgroundColor: c, child: isSel ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item['name'].toString(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSetBackgroundImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked != null && picked.path.isNotEmpty) {
        appBackgroundImage.value = picked.path;
        await settingsBox.put('backgroundImage', picked.path);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ ગેલેરીમાંથી બેકગ્રાઉન્ડ ફોટો સેટ થઈ ગયો!'), backgroundColor: Colors.teal),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ફોટો પસંદ કરવામાં ભૂલ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openChangeScreenTitleDialog() {
    final homeTitleCtrl = TextEditingController(text: appTitle);
    final invTitleCtrl = TextEditingController(text: settingsBox.get('customInvTitle', defaultValue: 'ઇન્વેસ્ટમેન્ટ પોર્ટફોલિયો'));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('સ્ક્રીનનું શીર્ષક બદલો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: homeTitleCtrl,
              decoration: const InputDecoration(labelText: 'પ્રથમ સ્ક્રીનનું શીર્ષક (દા.ત. નાણાકીય હિસાબો)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: invTitleCtrl,
              decoration: const InputDecoration(labelText: 'ઇન્વેસ્ટમેન્ટ સ્ક્રીનનું શીર્ષક'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
          ElevatedButton(
            onPressed: () {
              final newTitle = homeTitleCtrl.text.trim();
              if (newTitle.isNotEmpty) {
                appTitle = newTitle;
                settingsBox.put('customAppTitle', appTitle);
              }
              final newInv = invTitleCtrl.text.trim();
              if (newInv.isNotEmpty) {
                settingsBox.put('customInvTitle', newInv);
              }
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PDF ની સાથે Excel ફાઇલ (.xls અને .csv) માં પણ રિપોર્ટ બનાવતું ફંક્શન
  // =========================================================
  Future<void> _exportReportToExcelFile() async {
    try {
      final inc = _calculateTotal('incomeCredit');
      final exp = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
      final inv = _calculateTotal('assetIncrease');
      final net = inc - (exp + inv);
      final txList = filteredTransactions;

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final dirs = await _getCandidateBackupDirectories();
      final targetDir = dirs.firstWhere((d) => d.path.contains('/storage/emulated/0'), orElse: () => dirs.first);

      // ૧. Microsoft Excel (.xls SpreadsheetML XML) જેથી ગુજરાતી જોડાક્ષરો અને ફોર્મેટિંગ ૧૦૦% પરફેક્ટ ખૂલે
      final StringBuffer xlsXml = StringBuffer();
      xlsXml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      xlsXml.writeln('<?mso-application progid="Excel.Sheet"?>');
      xlsXml.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
      xlsXml.writeln('<Worksheet ss:Name="નાણાકીય રિપોર્ટ"><Table>');
      xlsXml.writeln('<Row><Cell><Data ss:Type="String">$appTitle - નાણાકીય હિસાબ રિપોર્ટ (${selectedFilter.name.toUpperCase()})</Data></Cell></Row>');
      xlsXml.writeln('<Row><Cell><Data ss:Type="String">કુલ આવક</Data></Cell><Cell><Data ss:Type="Number">$inc</Data></Cell></Row>');
      xlsXml.writeln('<Row><Cell><Data ss:Type="String">કુલ ખર્ચ</Data></Cell><Cell><Data ss:Type="Number">$exp</Data></Cell></Row>');
      xlsXml.writeln('<Row><Cell><Data ss:Type="String">કુલ રોકાણ</Data></Cell><Cell><Data ss:Type="Number">$inv</Data></Cell></Row>');
      xlsXml.writeln('<Row><Cell><Data ss:Type="String">નેટ બચત</Data></Cell><Cell><Data ss:Type="Number">$net</Data></Cell></Row>');
      xlsXml.writeln('<Row></Row>');
      xlsXml.writeln('<Row><Cell><Data ss:Type="String">તારીખ</Data></Cell><Cell><Data ss:Type="String">વિગત / શીર્ષક</Data></Cell><Cell><Data ss:Type="String">કેટેગરી</Data></Cell><Cell><Data ss:Type="String">પ્રકાર</Data></Cell><Cell><Data ss:Type="String">ખાતું</Data></Cell><Cell><Data ss:Type="String">રકમ (₹)</Data></Cell></Row>');

      // ૨. UTF-8 BOM સાથે CSV ફાઇલ
      final StringBuffer csvBuf = StringBuffer('\uFEFF');
      csvBuf.writeln('તારીખ,વિગત / શીર્ષક,કેટેગરી,પ્રકાર,ખાતું,રકમ (₹)');

      String escapeXml(String s) => s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');

      for (final tx in txList) {
        final dt = DateFormat('dd/MM/yyyy').format(DateTime.parse(tx['date']));
        final title = (tx['title'] ?? '').toString();
        final cat = (tx['categoryName'] ?? '').toString();
        final eff = tx['categoryEffect'] == 'incomeCredit'
            ? 'આવક'
            : (tx['categoryEffect'] == 'assetIncrease' ? 'રોકાણ' : 'ખર્ચ');
        final acc = (tx['accountName'] ?? '').toString();
        final amt = ((tx['amount'] as num?)?.toDouble() ?? 0.0);

        xlsXml.writeln(
          '<Row>'
          '<Cell><Data ss:Type="String">${escapeXml(dt)}</Data></Cell>'
          '<Cell><Data ss:Type="String">${escapeXml(title)}</Data></Cell>'
          '<Cell><Data ss:Type="String">${escapeXml(cat)}</Data></Cell>'
          '<Cell><Data ss:Type="String">${escapeXml(eff)}</Data></Cell>'
          '<Cell><Data ss:Type="String">${escapeXml(acc)}</Data></Cell>'
          '<Cell><Data ss:Type="Number">$amt</Data></Cell>'
          '</Row>',
        );

        final safeTitle = title.replaceAll('"', '""');
        final safeCat = cat.replaceAll('"', '""');
        final safeAcc = acc.replaceAll('"', '""');
        csvBuf.writeln('"$dt","$safeTitle","$safeCat","$eff","$safeAcc",$amt');
      }

      xlsXml.writeln('</Table></Worksheet></Workbook>');

      final xlsFile = File('${targetDir.path}/Finance_Report_$timestamp.xls');
      final csvFile = File('${targetDir.path}/Finance_Report_$timestamp.csv');
      await xlsFile.writeAsString(xlsXml.toString(), flush: true);
      await csvFile.writeAsString(csvBuf.toString(), flush: true);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.table_view, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('Excel રિપોર્ટ તૈયાર થઈ ગયો!')),
              ],
            ),
            content: Text(
              'તમારો સંપૂર્ણ હિસાબ એક્સેલ ફાઇલ તરીકે સેવ થઈ ગયો છે (જેમાં ગુજરાતી જોડાક્ષરો ૧૦૦% સ્પષ્ટ દેખાશે):\n\n'
              '📊 Excel ફાઇલ:\n${xlsFile.path}\n\n'
              '📄 CSV ફાઇલ:\n${csvFile.path}',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('સમજાઈ ગયું')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel બનાવવામાં ભૂલ: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
              Row(
                children: [
                  const Icon(Icons.settings, color: Colors.teal),
                  const SizedBox(width: 8),
                  Text(_t('એપ્લિકેશન સેટિંગ્સ', 'Application Settings'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.backup, color: Colors.teal),
                title: Text(_t('ઇન્ટરનલ મેમરીમાં બેકઅપ અને રિસ્ટોર', 'Internal Storage Backup & Restore'), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('દર વખતે અલગ નામથી બેકઅપ સેવ કરો અને રિસ્ટોર કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBackupAndRestoreDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.color_lens, color: appSeedColor.value),
                title: Text(_t('એપ્લિકેશન થીમ કલર બદલો', 'Change App Theme Color')),
                subtitle: const Text('તમારી પસંદગીનો રંગ પસંદ કરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openThemeColorPickerDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper, color: Colors.purple),
                title: Text(_t('ગેલેરીમાંથી ફોટો બેકગ્રાઉન્ડમાં સેટ કરો', 'Set Background Photo from Gallery')),
                subtitle: Text(appBackgroundImage.value != null ? 'બેકગ્રાઉન્ડ ફોટો સક્રિય છે' : 'કોઈ ફોટો સેટ કરેલ નથી'),
                trailing: appBackgroundImage.value != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        tooltip: 'ફોટો દૂર કરો',
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
                  _pickAndSetBackgroundImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.title, color: Colors.blue),
                title: Text(_t('પ્રથમ સ્ક્રીનનું શીર્ષક બદલો', 'Change Home Screen Title')),
                subtitle: Text('હાલનું શીર્ષક: $appTitle'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openChangeScreenTitleDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category, color: Colors.orange),
                title: Text(_t('કેટેગરી મેનેજર (સુધારો / પ્રકાર બદલો)', 'Category Manager (Edit / Change Type)')),
                subtitle: const Text('ખર્ચ, આવક કે રોકાણ પ્રકાર બદલો અને નવી ઉમેરો'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCategoryManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance, color: Colors.green),
                title: Text(_t('બેંક અને ક્રેડિટ કાર્ડ ખાતાઓ સુધારો', 'Manage Bank & Credit Card Accounts')),
                subtitle: const Text('બેંક નામ, બ્રાન્ચ, પ્રકાર, વ્યાજ દર, કાર્ડ લિમિટ અને વોર્નિંગ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAccountManager();
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active, color: Colors.indigo),
                title: Text(_t('ઓટો-પે / SIP / ક્રેડિટ કાર્ડ / વીમા રીમાઇન્ડર', 'Auto-Pay / SIP / Credit Card / Insurance Reminders')),
                subtitle: const Text('તારીખ, સમય, રીંગટોન અને મોબાઇલ ફ્લેશ મેસેજ સેટિંગ્સ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAutoPayManager();
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
                leading: Icon(appThemeMode.value == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode, color: Colors.amber),
                title: Text(_t('લાઇટ / ડાર્ક મોડ', 'Light / Dark Mode')),
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
                leading: const Icon(Icons.language, color: Colors.blue),
                title: Text(_t('એપ્લિકેશનની ભાષા બદલો (ગુજરાતી / English)', 'App Language (Gujarati / English)'), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(isEn ? 'Current: English (Tap to switch to ગુજરાતી)' : 'હાલની ભાષા: ગુજરાતી (English કરવા માટે ક્લિક કરો)'),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gu', label: Text('ગુજરાતી', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'en', label: Text('English', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {appLanguage.value},
                  onSelectionChanged: (s) {
                    appLanguage.value = s.first;
                    settingsBox.put('appLanguage', s.first);
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.record_voice_over, color: Colors.deepPurple),
                title: Text(_t('વોઇસ કમાન્ડ અને સ્પીકર પ્રોફાઇલ સેટિંગ્સ', 'Voice Commands & Speaker Profile'), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_t('ચોક્કસ વ્યક્તિનો અવાજ સેટ કરો અને વોઇસ કમાન્ડથી એપ ચલાવો', 'Configure authorized speaker voice & run app by voice')),
                onTap: () {
                  Navigator.pop(ctx);
                  _openVoiceProfileSettingsDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download, color: Colors.teal),
                title: Text(_t('સંપૂર્ણ હિસાબ એક્સપોર્ટ', 'Full Account Export'), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_t('PDF, Excel/CSV, ખર્ચ/આવક/રોકાણ, SIP અને ફાઇનાન્સિયલ પ્લાનિંગ રિપોર્ટ્સ', 'PDF, Excel/CSV, Filtered, SIP & Financial Planning Reports')),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFullExportPage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }


  // =========================================================
  // (સુધારો ૨) સંપૂર્ણ હિસાબ એક્સપોર્ટ અને વિશ્લેષણ પેજ
  // =========================================================
  Future<void> _exportCustomReport({
    required String reportTitle,
    required List<DataMap> rows,
    required String format, // 'pdf', 'excel', 'both'
    List<Map<String, String>>? extraSummaryLines,
  }) async {
    try {
      final double inc = rows.where((t) => t['categoryEffect'] == 'incomeCredit').fold(0.0, (s, i) => s + ((i['amount'] as num?)?.toDouble() ?? 0.0));
      final double exp = rows.where((t) => t['categoryEffect'] == 'expenseDebit' || t['categoryEffect'] == 'loanRepay').fold(0.0, (s, i) => s + ((i['amount'] as num?)?.toDouble() ?? 0.0));
      final double inv = rows.where((t) => t['categoryEffect'] == 'assetIncrease').fold(0.0, (s, i) => s + ((i['amount'] as num?)?.toDouble() ?? 0.0));
      final double net = inc - (exp + inv);

      String? xlsPath;
      String? csvPath;

      if (format == 'excel' || format == 'both') {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final dirs = await _getCandidateBackupDirectories();
        final targetDir = dirs.firstWhere((d) => d.path.contains('/storage/emulated/0'), orElse: () => dirs.first);

        String escapeXml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

        final StringBuffer xlsXml = StringBuffer();
        xlsXml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
        xlsXml.writeln('<?mso-application progid="Excel.Sheet"?>');
        xlsXml.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
        xlsXml.writeln('<Worksheet ss:Name="Report"><Table>');
        xlsXml.writeln('<Row><Cell><Data ss:Type="String">${escapeXml("$appTitle - $reportTitle")}</Data></Cell></Row>');
        xlsXml.writeln('<Row><Cell><Data ss:Type="String">${_t("કુલ આવક", "Total Income")}</Data></Cell><Cell><Data ss:Type="Number">$inc</Data></Cell></Row>');
        xlsXml.writeln('<Row><Cell><Data ss:Type="String">${_t("કુલ ખર્ચ", "Total Expense")}</Data></Cell><Cell><Data ss:Type="Number">$exp</Data></Cell></Row>');
        xlsXml.writeln('<Row><Cell><Data ss:Type="String">${_t("કુલ રોકાણ", "Total Investment")}</Data></Cell><Cell><Data ss:Type="Number">$inv</Data></Cell></Row>');
        xlsXml.writeln('<Row><Cell><Data ss:Type="String">${_t("નેટ બચત", "Net Savings")}</Data></Cell><Cell><Data ss:Type="Number">$net</Data></Cell></Row>');

        final StringBuffer csvBuf = StringBuffer('\uFEFF');
        csvBuf.writeln('"$appTitle - $reportTitle"');

        if (extraSummaryLines != null && extraSummaryLines.isNotEmpty) {
          xlsXml.writeln('<Row></Row>');
          for (final line in extraSummaryLines) {
            final k = line['label'] ?? '';
            final v = line['value'] ?? '';
            xlsXml.writeln('<Row><Cell><Data ss:Type="String">${escapeXml(k)}</Data></Cell><Cell><Data ss:Type="String">${escapeXml(v)}</Data></Cell></Row>');
            csvBuf.writeln('"${k.replaceAll('"', '""')}","${v.replaceAll('"', '""')}"');
          }
        }

        xlsXml.writeln('<Row></Row>');
        xlsXml.writeln('<Row><Cell><Data ss:Type="String">${_t("તારીખ", "Date")}</Data></Cell><Cell><Data ss:Type="String">${_t("વિગત / શીર્ષક", "Title / Details")}</Data></Cell><Cell><Data ss:Type="String">${_t("કેટેગરી", "Category")}</Data></Cell><Cell><Data ss:Type="String">${_t("પ્રકાર", "Type")}</Data></Cell><Cell><Data ss:Type="String">${_t("ખાતું / નોંધ", "Account / Notes")}</Data></Cell><Cell><Data ss:Type="String">${_t("રકમ (₹)", "Amount (₹)")}</Data></Cell></Row>');
        csvBuf.writeln('${_t("તારીખ,વિગત / શીર્ષક,કેટેગરી,પ્રકાર,ખાતું / નોંધ,રકમ (₹)", "Date,Title / Details,Category,Type,Account / Notes,Amount (₹)")}');

        for (final tx in rows) {
          final parsedDt = DateTime.tryParse((tx['date'] ?? '').toString());
          final dt = parsedDt != null ? DateFormat('dd/MM/yyyy').format(parsedDt) : (tx['date'] ?? '').toString();
          final title = (tx['title'] ?? '').toString();
          final cat = (tx['categoryName'] ?? '').toString();
          final eff = tx['categoryEffect'] == 'incomeCredit'
              ? _t('આવક', 'Income')
              : (tx['categoryEffect'] == 'assetIncrease' ? _t('રોકાણ', 'Investment') : _t('ખર્ચ / પ્લાન', 'Expense / Plan'));
          final acc = (tx['accountName'] ?? '').toString();
          final amt = ((tx['amount'] as num?)?.toDouble() ?? 0.0);

          xlsXml.writeln(
            '<Row>'
            '<Cell><Data ss:Type="String">${escapeXml(dt)}</Data></Cell>'
            '<Cell><Data ss:Type="String">${escapeXml(title)}</Data></Cell>'
            '<Cell><Data ss:Type="String">${escapeXml(cat)}</Data></Cell>'
            '<Cell><Data ss:Type="String">${escapeXml(eff)}</Data></Cell>'
            '<Cell><Data ss:Type="String">${escapeXml(acc)}</Data></Cell>'
            '<Cell><Data ss:Type="Number">$amt</Data></Cell>'
            '</Row>',
          );
          csvBuf.writeln('"$dt","${title.replaceAll('"', '""')}","${cat.replaceAll('"', '""')}","${eff.replaceAll('"', '""')}","${acc.replaceAll('"', '""')}",$amt');
        }

        xlsXml.writeln('</Table></Worksheet></Workbook>');
        final safeSlug = reportTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_');
        final xlsFile = File('${targetDir.path}/Report_${safeSlug}_$timestamp.xls');
        final csvFile = File('${targetDir.path}/Report_${safeSlug}_$timestamp.csv');
        await xlsFile.writeAsString(xlsXml.toString(), flush: true);
        await csvFile.writeAsString(csvBuf.toString(), flush: true);
        xlsPath = xlsFile.path;
        csvPath = csvFile.path;
      }

      if (format == 'pdf' || format == 'both') {
        await ExportService.exportToPDF(rows, inc, exp, inv, net, reportTitle);
      }

      if (mounted && xlsPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t("✅ રિપોર્ટ સેવ થઈ ગયો", "✅ Report exported")}: $xlsPath'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t("એક્સપોર્ટ ભૂલ", "Export error")}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<DataMap> _buildSipPortfolioRows(double expectedReturnPct, int years) {
    final List<DataMap> sipRows = [];
    final int months = years * 12;

    // ૧. MF SIPs
    for (final raw in mfInvestmentsBox.values) {
      final m = Map<dynamic, dynamic>.from(raw);
      if (m['investmentMode'] == 'SIP') {
        final double amt = (m['investedAmount'] as num?)?.toDouble() ?? 0.0;
        final String freq = (m['sipFrequency'] ?? 'માસિક (Monthly)').toString();
        final int interval = (m['sipIntervalDays'] as num?)?.toInt() ?? _getIntervalDaysForFrequency(freq);
        final double monthlyEq = amt * (30.0 / math.max(1, interval));
        final double futureVal = _calculateFutureValue(currentSaved: 0, monthlySip: monthlyEq, annualReturnPct: expectedReturnPct, months: months);
        sipRows.add({
          'date': m['date'] ?? DateTime.now().toIso8601String(),
          'title': 'MF SIP: ${m['schemeName']} ($freq | ₹${amt.toStringAsFixed(0)}/installment)',
          'categoryName': 'Mutual Fund SIP',
          'categoryEffect': 'assetIncrease',
          'accountName': '$years ${_t("વર્ષે અંદાજિત મૂડી", "yr Projected")} (@${expectedReturnPct.toStringAsFixed(1)}%): ₹${futureVal.toStringAsFixed(0)}',
          'amount': futureVal,
        });
      }
    }

    // ૨. Stock SIPs
    for (final raw in stockInvestmentsBox.values) {
      final s = Map<dynamic, dynamic>.from(raw);
      if (s['investmentMode'] == 'SIP') {
        final double amt = (s['totalInvested'] as num?)?.toDouble() ?? 0.0;
        final String freq = (s['sipFrequency'] ?? 'માસિક (Monthly)').toString();
        final int interval = (s['sipIntervalDays'] as num?)?.toInt() ?? _getIntervalDaysForFrequency(freq);
        final double monthlyEq = amt * (30.0 / math.max(1, interval));
        final double futureVal = _calculateFutureValue(currentSaved: 0, monthlySip: monthlyEq, annualReturnPct: expectedReturnPct, months: months);
        sipRows.add({
          'date': s['date'] ?? DateTime.now().toIso8601String(),
          'title': 'Stock/ETF SIP: ${s['symbol']} ($freq | ₹${amt.toStringAsFixed(0)})',
          'categoryName': 'Stock / ETF SIP',
          'categoryEffect': 'assetIncrease',
          'accountName': '$years ${_t("વર્ષે અંદાજિત મૂડી", "yr Projected")}: ₹${futureVal.toStringAsFixed(0)}',
          'amount': futureVal,
        });
      }
    }

    // ૩. AutoPay SIPs (જે MF/Stock માં ન હોય)
    for (final raw in autoPayBox.values) {
      final a = Map<dynamic, dynamic>.from(raw);
      if (a['type'] == 'SIP' && a['isActive'] == true) {
        final String target = (a['toTarget'] ?? '').toString();
        final bool alreadyListed = sipRows.any((r) => r['title'].toString().contains(target));
        if (!alreadyListed) {
          final double amt = (a['amount'] as num?)?.toDouble() ?? 0.0;
          final String freq = (a['sipFrequency'] ?? 'માસિક (Monthly)').toString();
          final int interval = (a['sipIntervalDays'] as num?)?.toInt() ?? _getIntervalDaysForFrequency(freq);
          final double monthlyEq = amt * (30.0 / math.max(1, interval));
          final double futureVal = _calculateFutureValue(currentSaved: 0, monthlySip: monthlyEq, annualReturnPct: expectedReturnPct, months: months);
          sipRows.add({
            'date': DateTime.now().toIso8601String(),
            'title': 'Scheduled SIP: $target ($freq | ₹${amt.toStringAsFixed(0)})',
            'categoryName': 'AutoPay SIP',
            'categoryEffect': 'assetIncrease',
            'accountName': '$years ${_t("વર્ષે અંદાજિત મૂડી", "yr Projected")}: ₹${futureVal.toStringAsFixed(0)}',
            'amount': futureVal,
          });
        }
      }
    }
    return sipRows;
  }

  List<DataMap> _buildFinancialPlanningRows({bool futureProjection = false}) {
    final List<DataMap> planRows = [];
    for (final raw in goalsBox.values) {
      final g = Map<dynamic, dynamic>.from(raw);
      final double target = (g['targetAmount'] as num?)?.toDouble() ?? 0.0;
      final double saved = (g['savedAmount'] as num?)?.toDouble() ?? 0.0;
      final double monthly = (g['monthlyContribution'] as num?)?.toDouble() ?? 0.0;
      final double rate = (g['expectedReturn'] as num?)?.toDouble() ?? 12.0;
      final DateTime tDate = DateTime.tryParse((g['targetDate'] ?? '').toString()) ?? DateTime.now().add(const Duration(days: 365));
      final int monthsLeft = math.max(1, ((tDate.difference(DateTime.now()).inDays) / 30.44).round());
      final double reqSip = _calculateRequiredMonthlySip(math.max(0.0, target - saved), rate, monthsLeft);
      final double fv = _calculateFutureValue(currentSaved: saved, monthlySip: monthly > 0 ? monthly : reqSip, annualReturnPct: rate, months: monthsLeft);

      planRows.add({
        'date': tDate.toIso8601String(),
        'title': '${g['name']} (${g['goalType']})',
        'categoryName': futureProjection ? _t('ભવિષ્યની મૂડી અંદાજ', 'Future Wealth Projection') : _t('ફાઇનાન્સિયલ પ્લાનિંગ નોંધ', 'Financial Planning Note'),
        'categoryEffect': 'assetIncrease',
        'accountName': futureProjection
            ? '${_t("હાલ", "Saved")}: ₹${saved.toStringAsFixed(0)} | ${_t("માસિક", "Monthly")}: ₹${(monthly > 0 ? monthly : reqSip).toStringAsFixed(0)} @${rate.toStringAsFixed(1)}% | ${_t("પ્લાન", "Plan")}: ${g['investmentPlan'] ?? ""}'
            : '${_t("લક્ષ્ય", "Target")}: ₹${target.toStringAsFixed(0)} | ${_t("બાકી", "Gap")}: ₹${math.max(0, target - saved).toStringAsFixed(0)} | ${g['investmentPlan'] ?? ""}',
        'amount': futureProjection ? fv : target,
      });
    }
    return planRows;
  }

  void _openFullExportPage() {
    String selectedFormat = 'both'; // pdf, excel, both
    String scope = 'filtered'; // filtered, allFY, allTime
    double sipReturnRate = 12.0;
    int sipHorizonYears = 10;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setPageState) {
            List<DataMap> getScopedTx() {
              if (scope == 'allFY') return entireFYTransactions;
              if (scope == 'allTime') {
                final list = transactionsBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
                list.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));
                return list;
              }
              return filteredTransactions;
            }

            final scopedTx = getScopedTx();
            final expOnly = scopedTx.where((t) => t['categoryEffect'] == 'expenseDebit' || t['categoryEffect'] == 'loanRepay').toList();
            final incOnly = scopedTx.where((t) => t['categoryEffect'] == 'incomeCredit').toList();
            final invOnly = scopedTx.where((t) => t['categoryEffect'] == 'assetIncrease').toList();
            final sipRows = _buildSipPortfolioRows(sipReturnRate, sipHorizonYears);
            final planNotes = _buildFinancialPlanningRows(futureProjection: false);
            final planFuture = _buildFinancialPlanningRows(futureProjection: true);

            final double totalSipCorpus = sipRows.fold(0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));
            final double totalPlanFuture = planFuture.fold(0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));

            return Scaffold(
              appBar: AppBar(
                title: Text(_t('સંપૂર્ણ હિસાબ એક્સપોર્ટ અને વિશ્લેષણ', 'Full Account Export & Analysis')),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // વિભાગ ૧: અગાઉના ત્રણેય ઝડપી એક્સપોર્ટ વિકલ્પો
                    Text(_t('૧. ઝડપી સંપૂર્ણ હિસાબ એક્સપોર્ટ', '1. Quick Full Account Export'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
                    const SizedBox(height: 6),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                            title: Text(_t('સંપૂર્ણ હિસાબ એક્સપોર્ટ (PDF રિપોર્ટ)', 'Full Account Export (PDF Report)')),
                            trailing: const Icon(Icons.download),
                            onTap: () => _exportCustomReport(reportTitle: 'Full_Account_PDF', rows: scopedTx, format: 'pdf'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.table_chart, color: Colors.green),
                            title: Text(_t('સંપૂર્ણ હિસાબ એક્સપોર્ટ (Excel અને CSV ફાઇલ)', 'Full Account Export (Excel & CSV)')),
                            trailing: const Icon(Icons.download),
                            onTap: () => _exportReportToExcelFile(),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.done_all, color: Colors.teal),
                            title: Text(_t('PDF + Excel બંને રિપોર્ટ એકસાથે બનાવો', 'Export Both PDF + Excel Together')),
                            trailing: const Icon(Icons.download),
                            onTap: () => _exportCustomReport(reportTitle: 'Full_Account_Combined', rows: scopedTx, format: 'both'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // વિભાગ ૨: પોતાની શરતો પ્રમાણે એક્સપોર્ટ ફિલ્ટર્સ
                    Text(_t('૨. પોતાની શરતો પ્રમાણે વિશ્લેષણ અને રિપોર્ટ એક્સપોર્ટ', '2. Custom Condition Analysis & Export'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 8),
                    Card(
                      color: adaptiveTintBg(Colors.indigo),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: scope,
                                    isExpanded: true,
                                    decoration: InputDecoration(labelText: _t('ડેટા સમયગાળો', 'Data Scope'), isDense: true),
                                    items: [
                                      DropdownMenuItem(value: 'filtered', child: Text(_t('હાલનું ફિલ્ટર (${selectedFilter.name})', 'Current Filter'))),
                                      DropdownMenuItem(value: 'allFY', child: Text(_t('આખું FY ($selectedFinancialYearStart-${selectedFinancialYearStart + 1})', 'Full FY'))),
                                      DropdownMenuItem(value: 'allTime', child: Text(_t('બધા જ વ્યવહારો (All Time)', 'All Transactions'))),
                                    ],
                                    onChanged: (v) => setPageState(() => scope = v!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedFormat,
                                    isExpanded: true,
                                    decoration: InputDecoration(labelText: _t('ફાઇલ ફોર્મેટ', 'Export Format'), isDense: true),
                                    items: [
                                      DropdownMenuItem(value: 'both', child: Text(_t('PDF + Excel બંને', 'Both PDF + Excel'))),
                                      const DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                                      const DropdownMenuItem(value: 'excel', child: Text('Excel (.xls / .csv)')),
                                    ],
                                    onChanged: (v) => setPageState(() => selectedFormat = v!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('${_t("SIP અંદાજિત વળતર", "SIP Return")}: ${sipReturnRate.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: sipReturnRate,
                                    min: 6,
                                    max: 20,
                                    divisions: 28,
                                    onChanged: (v) => setPageState(() => sipReturnRate = v),
                                  ),
                                ),
                                DropdownButton<int>(
                                  value: sipHorizonYears,
                                  items: [5, 10, 15, 20, 25, 30].map((y) => DropdownMenuItem(value: y, child: Text('$y ${_t("વર્ષ", "Yr")}'))).toList(),
                                  onChanged: (v) => setPageState(() => sipHorizonYears = v!),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ૭ અલગ અલગ વિશ્લેષણ રિપોર્ટ્સ
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.money_off, color: Colors.redAccent),
                            title: Text(_t('ફક્ત ખર્ચના વ્યવહારો (${expOnly.length})', 'Expenses Only (${expOnly.length})')),
                            trailing: const Icon(Icons.file_download, color: Colors.redAccent),
                            onTap: () => _exportCustomReport(reportTitle: 'Expenses_Only_Report', rows: expOnly, format: selectedFormat),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.attach_money, color: Colors.green),
                            title: Text(_t('ફક્ત આવકના વ્યવહારો (${incOnly.length})', 'Income Only (${incOnly.length})')),
                            trailing: const Icon(Icons.file_download, color: Colors.green),
                            onTap: () => _exportCustomReport(reportTitle: 'Income_Only_Report', rows: incOnly, format: selectedFormat),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.trending_up, color: Colors.blue),
                            title: Text(_t('ફક્ત રોકાણના વ્યવહારો (${invOnly.length})', 'Investments Only (${invOnly.length})')),
                            trailing: const Icon(Icons.file_download, color: Colors.blue),
                            onTap: () => _exportCustomReport(reportTitle: 'Investments_Only_Report', rows: invOnly, format: selectedFormat),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.event_note, color: Colors.purple),
                            title: Text(_t('આવનારા ફાઇનાન્સિયલ પ્લાનિંગની નોંધ (${planNotes.length})', 'Upcoming Financial Planning Notes (${planNotes.length})')),
                            trailing: const Icon(Icons.file_download, color: Colors.purple),
                            onTap: () => _exportCustomReport(reportTitle: 'Financial_Planning_Notes', rows: planNotes, format: selectedFormat),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.savings, color: Colors.deepOrange),
                            title: Text(_t('ફાઇનાન્સિયલ પ્લાનિંગથી ભવિષ્યની મૂડી રિપોર્ટ', 'Future Wealth from Financial Planning')),
                            subtitle: Text('${_t("અંદાજિત કુલ મૂડી", "Projected Total")}: ₹${totalPlanFuture.toStringAsFixed(0)}'),
                            trailing: const Icon(Icons.file_download, color: Colors.deepOrange),
                            onTap: () => _exportCustomReport(
                              reportTitle: 'Financial_Planning_Future_Corpus',
                              rows: planFuture,
                              format: selectedFormat,
                              extraSummaryLines: [
                                {'label': _t('પ્લાનિંગ દ્વારા કુલ ભવિષ્યની મૂડી', 'Total Projected Wealth from Goals'), 'value': '₹${totalPlanFuture.toStringAsFixed(0)}'},
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.autorenew, color: Colors.teal),
                            title: Text(_t('કુલ SIP યાદી (${sipRows.length}) અને $sipHorizonYears વર્ષે ભવિષ્યની મૂડી', 'All SIPs (${sipRows.length}) & $sipHorizonYears-Yr Future Corpus')),
                            subtitle: Text('${_t("અંદાજિત SIP મૂડી", "Projected SIP Corpus")} (@${sipReturnRate.toStringAsFixed(1)}%): ₹${totalSipCorpus.toStringAsFixed(0)}'),
                            trailing: const Icon(Icons.file_download, color: Colors.teal),
                            onTap: () => _exportCustomReport(
                              reportTitle: 'All_SIP_Future_Corpus_${sipHorizonYears}Yr',
                              rows: sipRows,
                              format: selectedFormat,
                              extraSummaryLines: [
                                {'label': _t('કુલ સક્રિય SIP સંખ્યા', 'Total Active SIPs'), 'value': '${sipRows.length}'},
                                {'label': _t('$sipHorizonYears વર્ષે કુલ અંદાજિત મૂડી (@${sipReturnRate.toStringAsFixed(1)}%)', '$sipHorizonYears-Yr Projected Corpus'), 'value': '₹${totalSipCorpus.toStringAsFixed(0)}'},
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.library_books, color: Colors.indigo),
                            title: Text(_t('સંયુક્ત માસ્ટર રિપોર્ટ (બધું જ એકસાથે)', 'Combined Master Report (Everything Together)'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(_t('આવક + ખર્ચ + રોકાણ + SIP ભવિષ્યની મૂડી + ફાઇનાન્સિયલ પ્લાનિંગ', 'Income + Expense + Investment + SIP Corpus + Financial Planning')),
                            trailing: const Icon(Icons.file_download, color: Colors.indigo),
                            onTap: () {
                              final combined = <DataMap>[...scopedTx, ...sipRows, ...planFuture];
                              _exportCustomReport(
                                reportTitle: 'Combined_Master_Financial_Report',
                                rows: combined,
                                format: selectedFormat,
                                extraSummaryLines: [
                                  {'label': _t('કુલ સક્રિય SIP', 'Active SIPs'), 'value': '${sipRows.length} (₹${totalSipCorpus.toStringAsFixed(0)} in ${sipHorizonYears}Y)'},
                                  {'label': _t('ફાઇનાન્સિયલ ગોલ્સ ભવિષ્યની મૂડી', 'Goals Projected Wealth'), 'value': '₹${totalPlanFuture.toStringAsFixed(0)}'},
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =========================================================
  // (સુધારો ૬) સંપૂર્ણ એપ વોઇસ કમાન્ડ અને ચોક્કસ વ્યક્તિ માટે સ્પીકર પ્રોફાઇલ
  // =========================================================
  Future<void> _speakFeedback(String text) async {
    if (settingsBox.get('voiceTtsEnabled', defaultValue: true) != true) return;
    try {
      await _nativeChannel.invokeMethod('speakText', {
        'text': text,
        'locale': isEn ? 'en-IN' : 'gu-IN',
      });
    } catch (_) {}
  }

  void _openVoiceProfileSettingsDialog() {
    final ownerCtrl = TextEditingController(text: (settingsBox.get('voiceOwnerName', defaultValue: '') ?? '').toString());
    final wakeCtrl = TextEditingController(text: (settingsBox.get('voiceWakePhrase', defaultValue: 'હેલો ફાઇનાન્સ') ?? 'હેલો ફાઇનાન્સ').toString());
    bool strictOwnerOnly = settingsBox.get('voiceStrictOwnerOnly', defaultValue: false) == true;
    bool ttsEnabled = settingsBox.get('voiceTtsEnabled', defaultValue: true) == true;
    bool isEnrolled = settingsBox.get('voicePrintEnrolled', defaultValue: false) == true;
    String enrollStatus = isEnrolled
        ? _t('✅ વ્યક્તિગત અવાજની ઓળખ (Voice Profile) નોંધાયેલ છે.', '✅ Authorized speaker voice profile is enrolled.')
        : _t('હજુ સુધી અવાજ નોંધાયેલ નથી.', 'No voice sample enrolled yet.');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.record_voice_over, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(child: Text(_t('વોઇસ અને સ્પીકર પ્રોફાઇલ સેટિંગ્સ', 'Voice & Speaker Profile'), style: const TextStyle(fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ownerCtrl,
                  decoration: InputDecoration(
                    labelText: _t('અધિકૃત વ્યક્તિનું નામ (Authorized Speaker Name)', 'Authorized Speaker Name'),
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),
                TextField(
                  controller: wakeCtrl,
                  decoration: InputDecoration(
                    labelText: _t('સિક્રેટ વોઇસ વેક-વર્ડ / પાસફ્રેઝ', 'Secret Wake-Word / Voice Passphrase'),
                    hintText: _t('દા.ત. હેલો ફાઇનાન્સ / My Finance', 'e.g. Hello Finance'),
                    prefixIcon: const Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('માત્ર નોંધાયેલ વ્યક્તિના અવાજ પર જ કમાન્ડ ચલાવો', 'Authorized Speaker Only Mode'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  subtitle: Text(_t('અન્ય વ્યક્તિ બોલે તો કમાન્ડ અટકાવી દેશે', 'Blocks voice commands from unrecognized speakers'), style: const TextStyle(fontSize: 11)),
                  value: strictOwnerOnly,
                  onChanged: (v) => setDlgState(() => strictOwnerOnly = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('વોઇસ જવાબ (Text-to-Speech) ચાલુ રાખો', 'Enable Spoken Voice Feedback (TTS)'), style: const TextStyle(fontSize: 12.5)),
                  value: ttsEnabled,
                  onChanged: (v) => setDlgState(() => ttsEnabled = v),
                ),
                const Divider(),
                Text(enrollStatus, style: TextStyle(fontSize: 11.5, color: isEnrolled ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.mic, color: Colors.deepPurple),
                    label: Text(_t('🎙️ તમારો અવાજ રેકોર્ડ / કેલિબ્રેટ કરો (Voice Enroll)', '🎙️ Enroll / Calibrate My Voice')),
                    onPressed: () async {
                      final ownerName = ownerCtrl.text.trim().isEmpty ? 'Owner' : ownerCtrl.text.trim();
                      try {
                        await _nativeChannel.invokeMethod('enrollSpeakerVoice', {
                          'ownerName': ownerName,
                          'wakePhrase': wakeCtrl.text.trim(),
                        });
                      } catch (_) {}
                      await settingsBox.put('voicePrintEnrolled', true);
                      await settingsBox.put('voiceOwnerName', ownerName);
                      setDlgState(() {
                        isEnrolled = true;
                        enrollStatus = _t('✅ $ownerName નો અવાજ પ્રોફાઇલ સફળતાપૂર્વક સેવ થઈ ગયો!', '✅ Voice profile enrolled for $ownerName!');
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('રદ', 'Cancel'))),
            ElevatedButton(
              onPressed: () {
                settingsBox.put('voiceOwnerName', ownerCtrl.text.trim());
                settingsBox.put('voiceWakePhrase', wakeCtrl.text.trim());
                settingsBox.put('voiceStrictOwnerOnly', strictOwnerOnly);
                settingsBox.put('voiceTtsEnabled', ttsEnabled);
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_t('✅ વોઇસ પ્રોફાઇલ સેવ થઈ ગઈ!', '✅ Voice profile saved!')), backgroundColor: Colors.deepPurple),
                );
              },
              child: Text(_t('સેવ કરો', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _executeVoiceCommand(String rawCommand, {bool speakerVerified = true}) async {
    final cmd = rawCommand.trim();
    if (cmd.isEmpty) return _t('કોઈ કમાન્ડ મળ્યો નથી.', 'No command received.');

    final bool strictMode = settingsBox.get('voiceStrictOwnerOnly', defaultValue: false) == true;
    final String wakePhrase = (settingsBox.get('voiceWakePhrase', defaultValue: '') ?? '').toString().trim().toLowerCase();
    final String ownerName = (settingsBox.get('voiceOwnerName', defaultValue: 'Owner') ?? 'Owner').toString();

    final lower = cmd.toLowerCase();
    if (strictMode && !speakerVerified) {
      if (wakePhrase.isEmpty || !lower.contains(wakePhrase)) {
        final msg = _t(
          '🔒 અવાજ ઓળખાયો નથી! માત્ર $ownerName (અથવા વેક-વર્ડ "$wakePhrase") જ કમાન્ડ આપી શકે છે.',
          '🔒 Speaker not verified! Only $ownerName (or passphrase "$wakePhrase") is authorized.',
        );
        await _speakFeedback(msg);
        return msg;
      }
    }

    // ૧. રિંગટોન બંધ કરો
    if (lower.contains('રિંગટોન બંધ') || lower.contains('stop ringtone') || lower.contains('mute')) {
      await _stopRingtone();
      final msg = _t('🔇 રિંગટોન બંધ કરી દીધી છે.', '🔇 Ringtone stopped.');
      await _speakFeedback(msg);
      return msg;
    }

    // ૨. ભાષા બદલો
    if (lower.contains('english') || lower.contains('અંગ્રેજી')) {
      appLanguage.value = 'en';
      settingsBox.put('appLanguage', 'en');
      setState(() {});
      await _speakFeedback('Switched app language to English.');
      return '✅ Switched app language to English.';
    }
    if (lower.contains('gujarati') || lower.contains('ગુજરાતી')) {
      appLanguage.value = 'gu';
      settingsBox.put('appLanguage', 'gu');
      setState(() {});
      await _speakFeedback('એપ્લિકેશનની ભાષા ગુજરાતીમાં બદલી દીધી છે.');
      return '✅ એપ્લિકેશનની ભાષા ગુજરાતીમાં બદલી દીધી છે.';
    }

    // ૩. ડાર્ક / લાઇટ મોડ
    if (lower.contains('dark mode') || lower.contains('ડાર્ક મોડ')) {
      appThemeMode.value = ThemeMode.dark;
      settingsBox.put('isDarkMode', true);
      setState(() {});
      final msg = _t('🌙 ડાર્ક મોડ ચાલુ કર્યો.', '🌙 Dark mode enabled.');
      await _speakFeedback(msg);
      return msg;
    }
    if (lower.contains('light mode') || lower.contains('લાઇટ મોડ')) {
      appThemeMode.value = ThemeMode.light;
      settingsBox.put('isDarkMode', false);
      setState(() {});
      final msg = _t('☀️ લાઇટ મોડ ચાલુ કર્યો.', '☀️ Light mode enabled.');
      await _speakFeedback(msg);
      return msg;
    }

    // ૪. એપ લોક
    if (lower.contains('lock app') || lower.contains('લોક કરો')) {
      setState(() => _isAppLocked = true);
      return _t('🔒 એપ લૉક કરી દીધી.', '🔒 App locked.');
    }

    // ૫. ક્વેરી (કુલ આવક / ખર્ચ / રોકાણ / બચત)
    if (lower.contains('કેટલો') || lower.contains('કેટલી') || lower.contains('total') || lower.contains('balance') || lower.contains('summary')) {
      final inc = _calculateTotal('incomeCredit');
      final exp = _calculateTotal('expenseDebit') + _calculateTotal('loanRepay');
      final inv = _calculateTotal('assetIncrease');
      final net = inc - (exp + inv);
      String msg;
      if (lower.contains('ખર્ચ') || lower.contains('expense')) {
        msg = _t('તમારો કુલ ખર્ચ ₹${exp.toStringAsFixed(0)} છે.', 'Your total expense is ₹${exp.toStringAsFixed(0)}.');
      } else if (lower.contains('આવક') || lower.contains('income')) {
        msg = _t('તમારી કુલ આવક ₹${inc.toStringAsFixed(0)} છે.', 'Your total income is ₹${inc.toStringAsFixed(0)}.');
      } else if (lower.contains('રોકાણ') || lower.contains('investment')) {
        msg = _t('તમારું કુલ રોકાણ ₹${inv.toStringAsFixed(0)} છે.', 'Your total investment is ₹${inv.toStringAsFixed(0)}.');
      } else {
        msg = _t(
          'આવક ₹${inc.toStringAsFixed(0)}, ખર્ચ ₹${exp.toStringAsFixed(0)}, રોકાણ ₹${inv.toStringAsFixed(0)}, અને નેટ બચત ₹${net.toStringAsFixed(0)} છે.',
          'Income ₹${inc.toStringAsFixed(0)}, Expense ₹${exp.toStringAsFixed(0)}, Investment ₹${inv.toStringAsFixed(0)}, Net Savings ₹${net.toStringAsFixed(0)}.',
        );
      }
      await _speakFeedback(msg);
      return msg;
    }

    // ૬. વ્યવહાર ઉમેરો (સંખ્યા + ખર્ચ / આવક / રોકાણ)
    final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cmd);
    if (numMatch != null && (lower.contains('ખર્ચ') || lower.contains('expense') || lower.contains('આવક') || lower.contains('income') || lower.contains('રોકાણ') || lower.contains('invest') || lower.contains('sip') || lower.contains('ઉમેરો') || lower.contains('add'))) {
      final double amt = double.tryParse(numMatch.group(1)!) ?? 0.0;
      if (amt > 0) {
        String effect = 'expenseDebit';
        String catId = '1';
        String catName = _t('ઘરખર્ચ (Groceries & Bills)', 'Household & Bills');
        int catColor = Colors.redAccent.toARGB32();
        if (lower.contains('આવક') || lower.contains('income') || lower.contains('પગાર') || lower.contains('salary')) {
          effect = 'incomeCredit';
          catId = '2';
          catName = _t('પગાર / ધંધાકીય આવક', 'Salary / Business Income');
          catColor = Colors.green.toARGB32();
        } else if (lower.contains('રોકાણ') || lower.contains('invest') || lower.contains('sip') || lower.contains('મ્યુચ્યુઅલ')) {
          effect = 'assetIncrease';
          catId = '3';
          catName = _t('શેરબજાર / મ્યુચ્યુઅલ ફંડ', 'Stocks / Mutual Fund');
          catColor = Colors.blue.toARGB32();
        }
        final acc = accounts.isNotEmpty ? accounts.first : {'id': '1', 'name': _t('બેંક ખાતું', 'Bank Account')};
        final txId = "voice_tx_${DateTime.now().millisecondsSinceEpoch}";
        transactionsBox.put(txId, {
          'id': txId,
          'title': cmd,
          'amount': amt,
          'date': DateTime.now().toIso8601String(),
          'hasTime': true,
          'categoryId': catId,
          'categoryName': catName,
          'categoryEffect': effect,
          'categoryColor': catColor,
          'accountId': acc['id'].toString(),
          'accountName': acc['name'],
        });
        setState(() {});
        final msg = _t('✅ વોઇસ કમાન્ડથી ₹${amt.toStringAsFixed(0)} ($catName) નોંધાઈ ગયા!', '✅ Added ₹${amt.toStringAsFixed(0)} ($catName) via voice command!');
        await _speakFeedback(msg);
        return msg;
      }
    }

    // ૭. નેવિગેશન કમાન્ડ્સ
    if (lower.contains('વિશ્લેષણ') || lower.contains('analysis')) {
      setState(() => _selectedTabIndex = 1);
      return _t('📊 નાણાકીય વિશ્લેષણ ટેબ ખોલ્યું.', '📊 Opened Financial Analysis tab.');
    }
    if (lower.contains('બજેટ') || lower.contains('budget') || lower.contains('લક્ષ્યાંક') || lower.contains('goal')) {
      setState(() => _selectedTabIndex = 2);
      return _t('🎯 બજેટ અને લક્ષ્યાંક ટેબ ખોલ્યું.', '🎯 Opened Budget & Goals tab.');
    }
    if (lower.contains('ઇન્વેસ્ટમેન્ટ') || lower.contains('investment') || lower.contains('પોર્ટફોલિયો')) {
      setState(() => _selectedTabIndex = 3);
      return _t('📈 ઇન્વેસ્ટમેન્ટ ટેબ ખોલ્યું.', '📈 Opened Investment tab.');
    }
    if (lower.contains('દૈનિક') || lower.contains('home') || lower.contains('entry')) {
      setState(() => _selectedTabIndex = 0);
      return _t('🏠 દૈનિક એન્ટ્રી ટેબ ખોલ્યું.', '🏠 Opened Daily Entries tab.');
    }
    if (lower.contains('એક્સપોર્ટ') || lower.contains('export') || lower.contains('રિપોર્ટ')) {
      _openFullExportPage();
      return _t('📄 એક્સપોર્ટ પેજ ખોલ્યું.', '📄 Opened Export page.');
    }
    if (lower.contains('રિમાઇન્ડર') || lower.contains('reminder') || lower.contains('autopay')) {
      _openAutoPayManager();
      return _t('🔔 ઓટો-પે / રિમાઇન્ડર મેનેજર ખોલ્યું.', '🔔 Opened Auto-Pay / Reminder Manager.');
    }
    if (lower.contains('સેટિંગ્સ') || lower.contains('settings')) {
      _openSettingsDialog();
      return _t('⚙️ સેટિંગ્સ ખોલ્યું.', '⚙️ Opened Settings.');
    }

    final fallback = _t(
      'કમાન્ડ સમજાયો નહીં. ઉદાહરણ: "500 કરિયાણું ખર્ચ ઉમેરો", "કુલ ખર્ચ કેટલો છે", "બજેટ ખોલો", "એક્સપોર્ટ ખોલો".',
      'Command not recognized. Try: "Add 500 expense groceries", "Total expense", "Open budget", "Open export".',
    );
    await _speakFeedback(fallback);
    return fallback;
  }

  void _openVoiceCommandSheet() {
    final cmdCtrl = TextEditingController();
    final String ownerName = (settingsBox.get('voiceOwnerName', defaultValue: '') ?? '').toString();
    final bool strictMode = settingsBox.get('voiceStrictOwnerOnly', defaultValue: false) == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 18, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _isListeningVoice ? Colors.red : Colors.deepPurple,
                    child: const Icon(Icons.mic, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('🎙️ વોઇસ કમાન્ડ આસિસ્ટન્ટ', '🎙️ Voice Command Assistant'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          strictMode
                              ? _t('🔒 અધિકૃત સ્પીકર: ${ownerName.isEmpty ? "સેટ નથી" : ownerName}', '🔒 Authorized Speaker: ${ownerName.isEmpty ? "Not Set" : ownerName}')
                              : _t('બધા વોઇસ કમાન્ડ સક્રિય છે', 'Voice control active'),
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _t('સ્પીકર પ્રોફાઇલ સેટિંગ્સ', 'Speaker Profile Settings'),
                    icon: const Icon(Icons.manage_accounts, color: Colors.deepPurple),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openVoiceProfileSettingsDialog();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListeningVoice ? Colors.red : Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                  icon: Icon(_isListeningVoice ? Icons.hearing : Icons.mic),
                  label: Text(_isListeningVoice ? _t('સાંભળી રહ્યું છે...', 'Listening...') : _t('બોલવા માટે ટૅપ કરો (Speak Command)', 'Tap to Speak Command')),
                  onPressed: () async {
                    setSheetState(() {
                      _isListeningVoice = true;
                      _voiceStatusText = _t('🎙️ બોલો...', '🎙️ Listening...');
                    });
                    try {
                      final dynamic result = await _nativeChannel.invokeMethod('startVoiceRecognition', {
                        'locale': isEn ? 'en-IN' : 'gu-IN',
                        'strictOwnerOnly': strictMode,
                        'ownerName': ownerName,
                      });
                      String spoken = '';
                      bool verified = true;
                      if (result is Map) {
                        spoken = (result['text'] ?? '').toString();
                        verified = result['speakerVerified'] != false;
                      } else if (result is String) {
                        spoken = result;
                      }
                      if (spoken.isNotEmpty) {
                        cmdCtrl.text = spoken;
                        final reply = await _executeVoiceCommand(spoken, speakerVerified: verified);
                        setSheetState(() {
                          _lastVoiceTranscript = spoken;
                          _voiceStatusText = reply;
                        });
                      } else {
                        setSheetState(() => _voiceStatusText = _t('અવાજ સંભળાયો નહીં, ફરી પ્રયાસ કરો.', 'No speech detected, try again.'));
                      }
                    } catch (_) {
                      setSheetState(() => _voiceStatusText = _t('નેટિવ માઇક ઉપલબ્ધ ન હોય તો નીચે કીબોર્ડ માઇક વડે બોલો/લખો.', 'Use keyboard mic or type your command below.'));
                    } finally {
                      setSheetState(() => _isListeningVoice = false);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: cmdCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: _t('દા.ત. 500 કરિયાણું ખર્ચ ઉમેરો / બજેટ ખોલો', 'e.g. Add 500 expense groceries / Open budget'),
                      ),
                      onSubmitted: (v) async {
                        final reply = await _executeVoiceCommand(v, speakerVerified: !strictMode);
                        setSheetState(() => _voiceStatusText = reply);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () async {
                      final reply = await _executeVoiceCommand(cmdCtrl.text, speakerVerified: !strictMode);
                      setSheetState(() => _voiceStatusText = reply);
                    },
                    child: Text(_t('ચલાવો', 'Run')),
                  ),
                ],
              ),
              if (_voiceStatusText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_voiceStatusText, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final sample in [
                    _t('કુલ ખર્ચ કેટલો છે', 'Total expense'),
                    _t('બજેટ ખોલો', 'Open budget'),
                    _t('ઇન્વેસ્ટમેન્ટ ખોલો', 'Open investment'),
                    _t('એક્સપોર્ટ ખોલો', 'Open export'),
                    _t('રિંગટોન બંધ કરો', 'Stop ringtone'),
                  ])
                    ActionChip(
                      label: Text(sample, style: const TextStyle(fontSize: 11)),
                      onPressed: () async {
                        cmdCtrl.text = sample;
                        final reply = await _executeVoiceCommand(sample, speakerVerified: !strictMode);
                        setSheetState(() => _voiceStatusText = reply);
                      },
                    ),
                ],
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

  // =========================================================
  // વિસ્તૃત EMI / ક્રેડિટ કાર્ડ / SIP / વીમા મેનેજર (તારીખ, સમય, રીંગટોન અને મોબાઇલ ફ્લેશ મેસેજ સાથે)
  // =========================================================
  void _openAutoPayManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final list = autoPayBox.values.map((e) => Map<dynamic, dynamic>.from(e)).toList();
          return AlertDialog(
            title: const Text('ઓટો-પે / SIP / રીમાઇન્ડર મેનેજર'),
            content: SizedBox(
              width: double.maxFinite,
              height: 410,
              child: list.isEmpty
                  ? const Center(child: Text('કોઈ EMI, SIP, ક્રેડિટ કાર્ડ કે વીમા રીમાઇન્ડર સેટ કરેલ નથી.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final a = list[i];
                        final isAuto = (a['executionMode'] ?? 'auto') == 'auto';
                        final isCc = a['type'] == 'CreditCard';
                        final int h = (a['reminderHour'] as num?)?.toInt() ?? 9;
                        final int m = (a['reminderMinute'] as num?)?.toInt() ?? 0;
                        final String tStr = TimeOfDay(hour: h, minute: m).format(context);
                        final String rTone = (a['ringtoneName'] ?? 'ડિફોલ્ટ અલાર્મ').toString();
                        final bool flashOn = a['enableFlashMessage'] ?? true;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              isCc ? Icons.credit_card : Icons.notifications_active,
                              color: isAuto ? Colors.teal : Colors.orange,
                            ),
                            title: Text("${a['type']}: ${a['toTarget'] ?? ''} (₹${(a['amount'] as num).toStringAsFixed(0)})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(
                              "તારીખ: ${a['day']} • સમય: $tStr • [${isAuto ? 'ઓટો-પે' : 'રીમાઇન્ડર'}]\n"
                              "🎵 ટોન: $rTone • ${flashOn ? '⚡ ફ્લેશ મેસેજ ON' : 'ફ્લેશ OFF'}",
                              style: const TextStyle(fontSize: 11),
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.flash_on, size: 18, color: Colors.amber),
                                  tooltip: 'ફ્લેશ મેસેજ ટેસ્ટ કરો',
                                  onPressed: () => _showFlashReminderPopup(a),
                                ),
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

    String type = existingItem != null ? existingItem['type'] : 'SIP';
    String mode = existingItem != null ? (existingItem['executionMode'] ?? 'auto') : 'auto';
    bool autoGenFromDaily = existingItem != null ? (existingItem['autoGenerateFromDaily'] == true) : isAutoCcBillEnabled;

    int remHour = existingItem != null ? ((existingItem['reminderHour'] as num?)?.toInt() ?? 9) : 9;
    int remMin = existingItem != null ? ((existingItem['reminderMinute'] as num?)?.toInt() ?? 0) : 0;
    TimeOfDay selectedReminderTime = TimeOfDay(hour: remHour, minute: remMin);

    final List<String> ringtoneOptions = [
      'ડિફોલ્ટ અલાર્મ ટોન (Default Alarm)',
      'નોટિફિકેશન બીપ (Notification Chime)',
      'ક્લાસિક બેલ રિંગટોન (Classic Bell)',
      'ઇમરજન્સી અલર્ટ (Urgent Beep)',
      'સોફ્ટ મેલોડી (Soft Tone)',
    ];
    String selectedRingtone = existingItem != null && existingItem['ringtoneName'] != null
        ? existingItem['ringtoneName'].toString()
        : ringtoneOptions.first;
    if (!ringtoneOptions.contains(selectedRingtone)) {
      ringtoneOptions.add(selectedRingtone);
    }
    String customRingtonePath = existingItem != null ? (existingItem['customRingtonePath'] ?? '').toString() : '';
    List<Map<String, dynamic>> sipFreqList = _getSipFrequencyOptions();
    String sipFrequency = existingItem != null && existingItem['sipFrequency'] != null
        ? existingItem['sipFrequency'].toString()
        : sipFreqList.first['name'].toString();
    if (!sipFreqList.any((f) => f['name'] == sipFrequency)) {
      sipFreqList.add({'name': sipFrequency, 'days': _getIntervalDaysForFrequency(sipFrequency)});
    }
    bool enableFlashMessage = existingItem != null ? (existingItem['enableFlashMessage'] ?? true) : true;
    DateTime? specificReminderDate = existingItem != null && existingItem['specificReminderDate'] != null
        ? DateTime.tryParse(existingItem['specificReminderDate'].toString())
        : null;

    String fromAccId = existingItem != null
        ? existingItem['fromAccountId']
        : (accounts.isNotEmpty ? accounts.first['id'].toString() : '');
    String ccAccId = existingItem != null && existingItem['ccAccountId'] != null
        ? existingItem['ccAccountId']
        : (accounts.firstWhere((a) => _isCreditCardAccount(a), orElse: () => accounts.first)['id'].toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingItem == null ? 'નવું ઓટો-પે / SIP રીમાઇન્ડર' : 'રીમાઇન્ડર સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'પ્રકાર પસંદ કરો'),
                  items: const [
                    DropdownMenuItem(value: 'SIP', child: Text('મ્યુચ્યુઅલ ફંડ / શેર SIP')),
                    DropdownMenuItem(value: 'CreditCard', child: Text('ક્રેડિટ કાર્ડ બિલ (Credit Card)')),
                    DropdownMenuItem(value: 'EMI', child: Text('લોન EMI હપ્તો')),
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
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'નામ / વિગત (દા.ત. HDFC SIP, SBI CC, PLI)')),
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
                    value: autoGenFromDaily,
                    onChanged: (val) => setDlgState(() => autoGenFromDaily = val),
                  ),
                ],
                TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'રકમ / પ્રીમિયમ (₹)')),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dayCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'દર મહિનાની તારીખ (1-31)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text('સમય: ${selectedReminderTime.format(context)}', style: const TextStyle(fontSize: 11.5)),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: selectedReminderTime);
                          if (t != null) setDlgState(() => selectedReminderTime = t);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(
                    specificReminderDate != null
                        ? 'ચોક્કસ તારીખ: ${DateFormat('dd/MM/yyyy').format(specificReminderDate!)}'
                        : 'ચોક્કસ તારીખ પસંદ કરો (વૈકલ્પિક)',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _clampDate1800To2100(specificReminderDate ?? DateTime.now()),
                      firstDate: DateTime(1800, 1, 1),
                      lastDate: DateTime(2100, 12, 31),
                    );
                    if (d != null) {
                      setDlgState(() {
                        specificReminderDate = d;
                        dayCtrl.text = d.day.toString();
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: sipFrequency,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: _t('ફ્રીક્વન્સી (માસિક/અઠવાડિક/15 દિવસ/દૈનિક)', 'Frequency')),
                        items: sipFreqList.map((f) => DropdownMenuItem(value: f['name'].toString(), child: Text(f['name'].toString(), style: const TextStyle(fontSize: 11.5)))).toList(),
                        onChanged: (v) => setDlgState(() => sipFrequency = v!),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.teal),
                      tooltip: _t('નવી ફ્રીક્વન્સી ઉમેરો', 'Add Custom Frequency'),
                      onPressed: () async {
                        final added = await _openAddCustomSipFrequencyDialog();
                        if (added != null) {
                          setDlgState(() {
                            sipFreqList = _getSipFrequencyOptions();
                            sipFrequency = added;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedRingtone,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: _t('રીમાઇન્ડર રિંગટોન પસંદ કરો', 'Select Reminder Ringtone')),
                        items: ringtoneOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 11.5)))).toList(),
                        onChanged: (v) {
                          _stopRingtone();
                          setDlgState(() => selectedRingtone = v!);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.teal),
                      tooltip: _t('રિંગટોન સાંભળો', 'Play Ringtone'),
                      onPressed: () => _playSelectedRingtone(selectedRingtone, customPath: customRingtonePath),
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
                      tooltip: _t('રિંગટોન બંધ કરો', 'Stop Ringtone'),
                      onPressed: () => _stopRingtone(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.audio_file, size: 16, color: Colors.indigo),
                        label: Text(
                          customRingtonePath.isNotEmpty
                              ? '🎵 ${customRingtonePath.split('/').last}'
                              : _t('ઇન્ટરનલ મેમરીમાંથી ઓડિયો ફાઇલ પસંદ કરો', 'Pick Audio File from Internal Storage'),
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () async {
                          await _stopRingtone();
                          final picked = await _pickAudioFileFromInternalMemory();
                          if (picked != null) {
                            setDlgState(() {
                              customRingtonePath = picked['path']!;
                              final label = 'કસ્ટમ: ${picked['name']}';
                              if (!ringtoneOptions.contains(label)) {
                                ringtoneOptions.add(label);
                              }
                              selectedRingtone = label;
                            });
                          }
                        },
                      ),
                    ),
                    if (customRingtonePath.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                        tooltip: _t('કસ્ટમ ઓડિયો દૂર કરો', 'Clear Custom Audio'),
                        onPressed: () {
                          _stopRingtone();
                          setDlgState(() {
                            customRingtonePath = '';
                            selectedRingtone = ringtoneOptions.first;
                          });
                        },
                      ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('મોબાઇલમાં ફ્લેશ મેસેજ (Flash Alert Popup) તરીકે બતાવો', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: const Text('નિર્ધારિત તારીખ અને સમયે સ્ક્રીન પર રિંગટોન સાથે ફ્લેશ મેસેજ આવશે', style: TextStyle(fontSize: 10.5)),
                  value: enableFlashMessage,
                  onChanged: (v) => setDlgState(() => enableFlashMessage = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: fromAccId,
                  decoration: const InputDecoration(labelText: 'ચુકવણી થનાર બેંક ખાતું'),
                  items: accounts.map((a) => DropdownMenuItem(value: a['id'].toString(), child: Text(a['name']))).toList(),
                  onChanged: (v) {
                    if (v != null) fromAccId = v;
                  },
                ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  dense: true,
                  title: const Text('ઓટો-પે (તારીખે આપોઆપ ખાતામાંથી કપાત)', style: TextStyle(fontSize: 12)),
                  value: 'auto',
                  groupValue: mode,
                  onChanged: (val) => setDlgState(() => mode = val!),
                ),
                RadioListTile<String>(
                  dense: true,
                  title: const Text('મેન્યુઅલ (ડેશબોર્ડ અને ફ્લેશ મેસેજ રીમાઇન્ડર)', style: TextStyle(fontSize: 12)),
                  value: 'manual',
                  groupValue: mode,
                  onChanged: (val) => setDlgState(() => mode = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () { _stopRingtone(); Navigator.pop(ctx); }, child: Text(_t('રદ', 'Cancel'))),
            ElevatedButton(
              onPressed: () {
                final id = existingItem != null ? existingItem['id'] : "auto_${DateTime.now().millisecondsSinceEpoch}";
                final savedMap = {
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
                  'reminderHour': selectedReminderTime.hour,
                  'reminderMinute': selectedReminderTime.minute,
                  'ringtoneName': selectedRingtone,
                  'customRingtonePath': customRingtonePath,
                  'sipFrequency': sipFrequency,
                  'sipIntervalDays': _getIntervalDaysForFrequency(sipFrequency),
                  'enableFlashMessage': enableFlashMessage,
                  'specificReminderDate': specificReminderDate?.toIso8601String(),
                  'isActive': true,
                  'lastProcessed': existingItem != null ? (existingItem['lastProcessed'] ?? '') : '',
                };
                autoPayBox.put(id, savedMap);
                // Native Android Alarm schedule call (if configured in MainActivity)
                try {
                  _nativeChannel.invokeMethod('scheduleFlashReminder', savedMap);
                } catch (_) {}
                _processAutoPayAndSIP();
                _stopRingtone();
                if (onSaved != null) onSaved();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(_t('સેવ કરો', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // કેટેગરી મેનેજર (સુધારી શકાય + પ્રકાર બદલી શકાય: ખર્ચ, આવક, રોકાણ)
  // =========================================================
  String _categoryEffectLabel(String effect) {
    switch (effect) {
      case 'incomeCredit':
        return 'આવક (Income)';
      case 'assetIncrease':
        return 'રોકાણ (Investment)';
      case 'loanRepay':
        return 'લોન / બિલ ખર્ચ';
      default:
        return 'ખર્ચ (Expense)';
    }
  }

  void _openAddOrEditCategoryDialog({Map<dynamic, dynamic>? existingCat, required VoidCallback onSaved}) {
    final nameCtrl = TextEditingController(text: existingCat != null ? existingCat['name'] : '');
    String effect = existingCat != null ? (existingCat['effect'] ?? 'expenseDebit') : 'expenseDebit';
    if (effect == 'loanRepay') effect = 'expenseDebit';
    int selectedColorVal = existingCat != null
        ? ((existingCat['color'] as num?)?.toInt() ?? Colors.teal.toARGB32())
        : Colors.teal.toARGB32();

    final List<Color> catColors = [
      Colors.redAccent,
      Colors.green,
      Colors.blue,
      Colors.amber.shade800,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.brown,
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingCat == null ? 'નવી કેટેગરી ઉમેરો' : 'કેટેગરી સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'કેટેગરીનું નામ'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: effect,
                  decoration: const InputDecoration(labelText: 'કેટેગરીનો પ્રકાર (ખર્ચ / આવક / રોકાણ)'),
                  items: const [
                    DropdownMenuItem(value: 'expenseDebit', child: Text('ખર્ચ (Expense)')),
                    DropdownMenuItem(value: 'incomeCredit', child: Text('આવક (Income)')),
                    DropdownMenuItem(value: 'assetIncrease', child: Text('રોકાણ (Investment)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => effect = v);
                  },
                ),
                const SizedBox(height: 12),
                const Text('રંગ પસંદ કરો:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: catColors.map((c) {
                    final isSel = c.toARGB32() == selectedColorVal;
                    return InkWell(
                      onTap: () => setDlgState(() => selectedColorVal = c.toARGB32()),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: c,
                        child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final id = existingCat != null ? existingCat['id'].toString() : "cat_${DateTime.now().millisecondsSinceEpoch}";

                categoriesBox.put(id, {
                  'id': id,
                  'name': name,
                  'effect': effect,
                  'color': selectedColorVal,
                });

                // જો કેટેગરી સુધારી હોય તો તે કેટેગરીના જૂના વ્યવહારોમાં પણ નામ અને પ્રકાર અપડેટ કરો
                if (existingCat != null) {
                  for (final rawTx in transactionsBox.values.toList()) {
                    final tx = Map<dynamic, dynamic>.from(rawTx);
                    if (tx['categoryId'].toString() == id) {
                      tx['categoryName'] = name;
                      tx['categoryEffect'] = effect;
                      tx['categoryColor'] = selectedColorVal;
                      transactionsBox.put(tx['id'], tx);
                    }
                  }
                }

                onSaved();
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

  void _openCategoryManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('કેટેગરી મેનેજર (ખર્ચ / આવક / રોકાણ)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final Color c = Color((cat['color'] as num?)?.toInt() ?? Colors.teal.toARGB32());
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 12, backgroundColor: c),
                    title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('પ્રકાર: ${_categoryEffectLabel(cat['effect'].toString())}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                          onPressed: () {
                            _openAddOrEditCategoryDialog(
                              existingCat: cat,
                              onSaved: () => setDlgState(() {}),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            if (categories.length <= 1) return;
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
              icon: const Icon(Icons.add, size: 16),
              label: const Text('નવી કેટેગરી ઉમેરો'),
              onPressed: () {
                _openAddOrEditCategoryDialog(onSaved: () => setDlgState(() {}));
              },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // બેંક અને ક્રેડિટ કાર્ડ ખાતા મેનેજર:
  // - બેંક એકાઉન્ટ: બેંકનું નામ, બ્રાન્ચનું નામ, પ્રકાર (Saving, Salary કે કસ્ટમ), વ્યાજ દર (%), પ્રારંભિક કિંમત
  // - ક્રેડિટ કાર્ડ: આપનાર બેંક/NBFC નું નામ, કાર્ડનો પ્રકાર, મહત્તમ લિમિટ, વોર્નિંગ લિમિટ, પ્રારંભિક બાકી રકમ
  // =========================================================
  void _openAddOrEditAccountDialog({Map<dynamic, dynamic>? existingAcc, required VoidCallback onSaved}) {
    final bool isCcInit = existingAcc != null ? _isCreditCardAccount(existingAcc) : false;
    String accountCategory = existingAcc != null
        ? (existingAcc['accountCategory'] ?? (isCcInit ? 'CreditCard' : 'Bank')).toString()
        : 'Bank';

    final displayNameCtrl = TextEditingController(text: existingAcc != null ? (existingAcc['name'] ?? '') : '');
    final bankNameCtrl = TextEditingController(text: existingAcc != null ? (existingAcc['bankName'] ?? '') : '');
    final branchNameCtrl = TextEditingController(text: existingAcc != null ? (existingAcc['branchName'] ?? '') : '');
    final customSubTypeCtrl = TextEditingController(text: existingAcc != null ? (existingAcc['accountSubType'] ?? '') : '');
    final interestRateCtrl = TextEditingController(text: existingAcc != null ? ((existingAcc['interestRate'] ?? 3.5).toString()) : '3.5');
    final openingBalCtrl = TextEditingController(text: existingAcc != null ? ((existingAcc['openingBalance'] ?? 0.0).toString()) : '0');

    // Credit Card specific controllers
    final issuerNameCtrl = TextEditingController(text: existingAcc != null ? (existingAcc['issuerName'] ?? '') : '');
    final cardTypeCtrl = TextEditingController(text: existingAcc != null ? (existingAcc['cardType'] ?? 'Visa / RuPay Platinum') : 'Visa / RuPay Platinum');
    final maxLimitCtrl = TextEditingController(text: existingAcc != null ? ((existingAcc['maxLimit'] ?? 100000.0).toString()) : '100000');
    final warnLimitCtrl = TextEditingController(text: existingAcc != null ? ((existingAcc['warningLimit'] ?? 75000.0).toString()) : '75000');

    final List<String> bankTypePresets = [
      'સેવિંગ એકાઉન્ટ (Savings Account)',
      'સેલેરી એકાઉન્ટ (Salary Account)',
      'કરંટ એકાઉન્ટ (Current Account)',
      'ડીમેટ / ટ્રેડિંગ એકાઉન્ટ (Demat A/C)',
      'રોકડ ખાતું (Cash Wallet)',
      'અન્ય (કસ્ટમ પ્રકાર લખો)',
    ];
    String selectedBankPreset = bankTypePresets.first;
    if (existingAcc != null) {
      final savedT = (existingAcc['accountSubType'] ?? existingAcc['type'] ?? '').toString();
      if (bankTypePresets.contains(savedT)) {
        selectedBankPreset = savedT;
      } else if (savedT.isNotEmpty) {
        selectedBankPreset = 'અન્ય (કસ્ટમ પ્રકાર લખો)';
        customSubTypeCtrl.text = savedT;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existingAcc == null ? 'નવું બેંક / ક્રેડિટ કાર્ડ ખાતું ઉમેરો' : 'ખાતાની વિગત સુધારો'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Bank', icon: Icon(Icons.account_balance, size: 16), label: Text('બેંક / રોકડ ખાતું', style: TextStyle(fontSize: 11.5))),
                    ButtonSegment(value: 'CreditCard', icon: Icon(Icons.credit_card, size: 16), label: Text('ક્રેડિટ કાર્ડ', style: TextStyle(fontSize: 11.5))),
                  ],
                  selected: {accountCategory == 'CreditCard' ? 'CreditCard' : 'Bank'},
                  onSelectionChanged: (s) => setDlgState(() => accountCategory = s.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: displayNameCtrl,
                  decoration: InputDecoration(
                    labelText: accountCategory == 'CreditCard'
                        ? 'કાર્ડનું પ્રદર્શિત નામ (દા.ત. HDFC Millennia CC)'
                        : 'ખાતાનું પ્રદર્શિત નામ (દા.ત. SBI સેવિંગ ખાતું)',
                  ),
                ),
                if (accountCategory != 'CreditCard') ...[
                  TextField(
                    controller: bankNameCtrl,
                    decoration: const InputDecoration(labelText: 'બેંકનું નામ (દા.ત. State Bank of India, HDFC)'),
                  ),
                  TextField(
                    controller: branchNameCtrl,
                    decoration: const InputDecoration(labelText: 'બ્રાન્ચનું નામ (દા.ત. જામનગર મેઈન બ્રાન્ચ)'),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBankPreset,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ખાતાનો પ્રકાર પસંદ કરો'),
                    items: bankTypePresets.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedBankPreset = v);
                    },
                  ),
                  if (selectedBankPreset == 'અન્ય (કસ્ટમ પ્રકાર લખો)')
                    TextField(
                      controller: customSubTypeCtrl,
                      decoration: const InputDecoration(labelText: 'તમારો કસ્ટમ ખાતા પ્રકાર લખો (દા.ત. NRE, Joint, Overdraft)'),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: interestRateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'વાર્ષિક વ્યાજ દર (%)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: openingBalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'પ્રારંભિક સિલક (₹)'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  TextField(
                    controller: issuerNameCtrl,
                    decoration: const InputDecoration(labelText: 'કાર્ડ આપનાર બેંક અથવા NBFC નું નામ (દા.ત. SBI Card, Bajaj Finserv)'),
                  ),
                  TextField(
                    controller: cardTypeCtrl,
                    decoration: const InputDecoration(labelText: 'કાર્ડનો પ્રકાર (દા.ત. Visa Platinum, RuPay, MasterCard)'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: maxLimitCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'મહત્તમ લિમિટ (₹)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: warnLimitCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'વોર્નિંગ લિમિટ (₹)'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: openingBalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'પ્રારંભિક વપરાયેલ / બાકી રકમ (₹)'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ')),
            ElevatedButton(
              onPressed: () {
                final String name = displayNameCtrl.text.trim();
                if (name.isEmpty) return;

                final String id = existingAcc != null ? existingAcc['id'].toString() : "acc_${DateTime.now().millisecondsSinceEpoch}";
                final double openBal = double.tryParse(openingBalCtrl.text) ?? 0.0;

                if (accountCategory == 'CreditCard') {
                  final String issuer = issuerNameCtrl.text.trim();
                  final String cType = cardTypeCtrl.text.trim();
                  final double maxL = double.tryParse(maxLimitCtrl.text) ?? 100000.0;
                  final double warnL = double.tryParse(warnLimitCtrl.text) ?? (maxL * 0.8);

                  accountsBox.put(id, {
                    'id': id,
                    'name': name,
                    'type': 'ક્રેડિટ કાર્ડ ($cType)',
                    'accountCategory': 'CreditCard',
                    'issuerName': issuer,
                    'cardType': cType,
                    'maxLimit': maxL,
                    'warningLimit': warnL,
                    'openingBalance': openBal,
                  });
                } else {
                  final String finalSubType = selectedBankPreset == 'અન્ય (કસ્ટમ પ્રકાર લખો)'
                      ? (customSubTypeCtrl.text.trim().isEmpty ? 'અન્ય બેંક ખાતું' : customSubTypeCtrl.text.trim())
                      : selectedBankPreset;
                  final double intRate = double.tryParse(interestRateCtrl.text) ?? 3.5;

                  accountsBox.put(id, {
                    'id': id,
                    'name': name,
                    'type': finalSubType,
                    'accountCategory': finalSubType.contains('રોકડ') ? 'Cash' : 'Bank',
                    'bankName': bankNameCtrl.text.trim(),
                    'branchName': branchNameCtrl.text.trim(),
                    'accountSubType': finalSubType,
                    'interestRate': intRate,
                    'openingBalance': openBal,
                  });
                }

                // જૂના વ્યવહારોમાં ખાતાનું નામ અપડેટ કરો
                if (existingAcc != null) {
                  for (final rawTx in transactionsBox.values.toList()) {
                    final tx = Map<dynamic, dynamic>.from(rawTx);
                    if (tx['accountId'].toString() == id) {
                      tx['accountName'] = name;
                      transactionsBox.put(tx['id'], tx);
                    }
                  }
                }

                onSaved();
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

  void _openAccountManager() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('બેંક અને ક્રેડિટ કાર્ડ ખાતા મેનેજર'),
          content: SizedBox(
            width: double.maxFinite,
            height: 410,
            child: ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final a = accounts[i];
                final String accId = a['id'].toString();
                final bool isCc = _isCreditCardAccount(a);
                final double currentBal = getAccountCurrentBalance(accId);
                final double ccUsed = isCc ? getCreditCardUsedAmount(accId) : 0.0;
                final double maxLim = (a['maxLimit'] as num?)?.toDouble() ?? 0.0;
                final double warnLim = (a['warningLimit'] as num?)?.toDouble() ?? 0.0;
                final bool isOverWarn = isCc && warnLim > 0 && ccUsed >= warnLim;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      isCc ? Icons.credit_card : Icons.account_balance,
                      color: isOverWarn ? Colors.red : (isCc ? Colors.deepOrange : Colors.teal),
                    ),
                    title: Text(a['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                      isCc
                          ? 'આપનાર: ${a['issuerName'] ?? '-'} • પ્રકાર: ${a['cardType'] ?? '-'}\n'
                            'વપરાશ: ₹${ccUsed.toStringAsFixed(0)} / મહત્તમ લિમિટ: ₹${maxLim.toStringAsFixed(0)} (વોર્નિંગ: ₹${warnLim.toStringAsFixed(0)})'
                            '${isOverWarn ? '\n⚠️ વોર્નિંગ લિમિટ કરતાં ખર્ચ વધારે છે!' : ''}'
                          : '${a['bankName'] != null && a['bankName'].toString().isNotEmpty ? '${a['bankName']} (${a['branchName'] ?? ''}) • ' : ''}${a['type']}\n'
                            'પ્રારંભિક: ₹${((a['openingBalance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)} | હાલની સિલક: ₹${currentBal.toStringAsFixed(0)} | વ્યાજ: ${((a['interestRate'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: isOverWarn ? Colors.redAccent : null),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                          tooltip: 'સુધારો',
                          onPressed: () {
                            _openAddOrEditAccountDialog(
                              existingAcc: a,
                              onSaved: () => setDlgState(() {}),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            if (accounts.length <= 1) return;
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
              icon: const Icon(Icons.add, size: 16),
              label: const Text('નવું ખાતું / કાર્ડ ઉમેરો'),
              onPressed: () {
                _openAddOrEditAccountDialog(onSaved: () => setDlgState(() {}));
              },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('પૂર્ણ')),
          ],
        ),
      ),
    );
  }

  void _openCategoryBudgetDialog() {
    final refIncCtrl = TextEditingController(text: _getBudgetReferenceIncome().toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final double refInc = double.tryParse(refIncCtrl.text) ?? _getBudgetReferenceIncome();
          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text('$budgetPeriod ${_t("બજેટ લક્ષ્યાંક ગોઠવો (₹ અને %)", "Budget Targets (₹ & %)")}', style: const TextStyle(fontSize: 15.5))),
                IconButton(
                  tooltip: _t('કેટેગરી ઉમેરો / સુધારો', 'Add / Edit Categories'),
                  icon: const Icon(Icons.edit_note, color: Colors.teal),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openCategoryManager();
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 410,
              child: Column(
                children: [
                  TextField(
                    controller: refIncCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: _t('આધાર આવક (₹) - % ગણતરી માટે', 'Base Income (₹) - for % calculation'),
                      prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v) ?? 0.0;
                      if (parsed > 0) {
                        budgetBox.put('refIncome_$budgetPeriod', parsed);
                        setDlgState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, i) {
                        final cat = categories[i];
                        final budgetKey = 'budget_${budgetPeriod}_${cat['id']}';
                        final pctKey = 'budgetPct_${budgetPeriod}_${cat['id']}';
                        final modeKey = 'budgetMode_${budgetPeriod}_${cat['id']}';

                        String mode = (budgetBox.get(modeKey, defaultValue: 'rs') ?? 'rs').toString();
                        double rsVal = (budgetBox.get(budgetKey, defaultValue: 0.0) as num).toDouble();
                        double pctVal = (budgetBox.get(pctKey, defaultValue: 0.0) as num).toDouble();
                        if (mode == 'pct' && pctVal > 0) {
                          rsVal = (refInc * pctVal) / 100.0;
                        } else if (rsVal > 0 && refInc > 0) {
                          pctVal = (rsVal / refInc) * 100.0;
                        }

                        final ctrl = TextEditingController(
                          text: mode == 'pct'
                              ? (pctVal > 0 ? pctVal.toStringAsFixed(1) : '')
                              : (rsVal > 0 ? rsVal.toStringAsFixed(0) : ''),
                        );

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                    ),
                                    ChoiceChip(
                                      label: const Text('₹', style: TextStyle(fontSize: 11)),
                                      selected: mode == 'rs',
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) {
                                        budgetBox.put(modeKey, 'rs');
                                        setDlgState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    ChoiceChip(
                                      label: const Text('%', style: TextStyle(fontSize: 11)),
                                      selected: mode == 'pct',
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) {
                                        budgetBox.put(modeKey, 'pct');
                                        setDlgState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 82,
                                      child: TextField(
                                        controller: ctrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          hintText: mode == 'pct' ? '0 %' : '₹ 0',
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                        ),
                                        onChanged: (val) {
                                          final numVal = double.tryParse(val) ?? 0.0;
                                          if (mode == 'pct') {
                                            budgetBox.put(pctKey, numVal);
                                            budgetBox.put(budgetKey, (refInc * numVal) / 100.0);
                                          } else {
                                            budgetBox.put(budgetKey, numVal);
                                            budgetBox.put(pctKey, refInc > 0 ? (numVal / refInc) * 100.0 : 0.0);
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${_t("સમકક્ષ", "Equivalent")}: ₹${rsVal.toStringAsFixed(0)}  •  ${pctVal.toStringAsFixed(1)}%',
                                  style: TextStyle(fontSize: 10.5, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.category, size: 16),
                label: Text(_t('કેટેગરી સુધારો', 'Edit Categories')),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openCategoryManager();
                },
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: Text(_t('સેવ કરો', 'Save')),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- ટેબ ૧: દૈનિક એન્ટ્રી અને રીમાઇન્ડર ---
  Widget _buildTransactionsTab() {
    final pendingReminders = pendingManualReminders;

    // ક્રેડિટ કાર્ડમાં જો કોઈ કાર્ડ વોર્નિંગ લિમિટ કરતાં વધી ગયું હોય તેની યાદી
    final List<DataMap> overLimitCards = accounts.where((a) {
      if (!_isCreditCardAccount(a)) return false;
      final double warnL = (a['warningLimit'] as num?)?.toDouble() ?? 0.0;
      final double maxL = (a['maxLimit'] as num?)?.toDouble() ?? 0.0;
      final double used = getCreditCardUsedAmount(a['id'].toString());
      return (warnL > 0 && used >= warnL) || (maxL > 0 && used >= maxL);
    }).toList();

    return Column(
      children: [
        if (overLimitCards.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.red.shade900.withOpacity(0.45) : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: overLimitCards.map((cc) {
                final used = getCreditCardUsedAmount(cc['id'].toString());
                final warnL = (cc['warningLimit'] as num?)?.toDouble() ?? 0.0;
                final maxL = (cc['maxLimit'] as num?)?.toDouble() ?? 0.0;
                return Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '⚠️ ક્રેડિટ કાર્ડ વોર્નિંગ (${cc['name']}): ખર્ચ ₹${used.toStringAsFixed(0)} થયો છે (વોર્નિંગ લિમિટ: ₹${warnL.toStringAsFixed(0)} | મહત્તમ: ₹${maxL.toStringAsFixed(0)})',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.red.shade900),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        if (pendingReminders.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.amber.shade900.withOpacity(0.35) : Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active, color: isDark ? Colors.amberAccent : Colors.amber.shade900, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "બાકી હપ્તા / બિલ રીમાઇન્ડર (${pendingReminders.length})",
                      style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.amberAccent : Colors.amber.shade900),
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
                          "${rem['type']}: ${rem['toTarget']} - ₹${(rem['amount'] as num).toStringAsFixed(0)} (${rem['day']} તારીખ)",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor),
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
                ),
        ),
      ],
    );
  }

  Widget _buildMiniSummaryCard(String title, double amount, Color color) {
    return Expanded(
      child: Card(
        color: color.withOpacity(isDark ? 0.22 : 0.12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color.withOpacity(0.4))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: isDark ? Colors.white : color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : color))),
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

    if (_isAppLocked) {
      return Scaffold(
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
                    Text('નાણાકીય વૉલ્ટ સુરક્ષિત રીતે લૉક છે', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    const SizedBox(height: 4),
                    Text(widget.userEmail, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
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
    // 1800 થી 2100 સુધીના તમામ નાણાકીય વર્ષો (FY)
    final List<int> fyYears = List.generate(301, (index) => 1800 + index);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openChangeScreenTitleDialog,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(appTitle, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 13, color: Colors.grey),
                ],
              ),
              Text(widget.userEmail, style: TextStyle(fontSize: 10, color: secondaryTextColor)),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic, color: Colors.deepPurple),
            tooltip: _t('વોઇસ કમાન્ડ', 'Voice Command'),
            onPressed: _openVoiceCommandSheet,
          ),
          IconButton(
            icon: const Icon(Icons.backup, color: Colors.teal),
            tooltip: _t('બેકઅપ અને રિસ્ટોર', 'Backup & Restore'),
            onPressed: _openBackupAndRestoreDialog,
          ),
          IconButton(
            icon: const CircleAvatar(
              radius: 14,
              backgroundColor: Colors.teal,
              child: Icon(Icons.currency_rupee, color: Colors.white, size: 17),
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
              label: Text(_t('હિસાબ નોંધો', 'Add Entry')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.receipt_long), label: _t('દૈનિક એન્ટ્રી', 'Daily')),
          NavigationDestination(icon: const Icon(Icons.analytics), label: _t('નાણાકીય વિશ્લેષણ', 'Analysis')),
          NavigationDestination(icon: const Icon(Icons.track_changes), label: _t('બજેટ લક્ષ્યાંક', 'Budget')),
          NavigationDestination(icon: const Icon(Icons.trending_up), label: _t('ઇન્વેસ્ટમેન્ટ', 'Invest')),
        ],
      ),
      body: ValueListenableBuilder<String?>(
        valueListenable: appBackgroundImage,
        builder: (context, bgPath, _) {
          final bool hasValidBg = bgPath != null && bgPath.isNotEmpty && File(bgPath).existsSync();
          return Stack(
            children: [
              if (hasValidBg)
                Positioned.fill(
                  child: Image.file(
                    File(bgPath),
                    fit: BoxFit.cover,
                  ),
                ),
              if (hasValidBg)
                Positioned.fill(
                  child: Container(
                    color: isDark ? Colors.black.withOpacity(0.68) : Colors.white.withOpacity(0.72),
                  ),
                ),
              Column(
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
                            value: selectedFinancialYearStart.clamp(1800, 2100),
                            underline: const SizedBox(),
                            items: fyYears
                                .map((y) => DropdownMenuItem(
                                      value: y,
                                      child: Text('$y-${(y + 1).toString().substring(2)}'),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => selectedFinancialYearStart = val);
                            },
                          ),
                          const Spacer(),
                          DropdownButton<TimeFilter>(
                            value: selectedFilter,
                            underline: const SizedBox(),
                            items: [
                              DropdownMenuItem(value: TimeFilter.daily, child: Text(_t('દૈનિક', 'Daily'))),
                              DropdownMenuItem(value: TimeFilter.monthly, child: Text(_t('માસિક', 'Monthly'))),
                              DropdownMenuItem(value: TimeFilter.quarterly, child: Text(_t('ત્રિમાસિક', 'Quarterly'))),
                              DropdownMenuItem(value: TimeFilter.halfYearly, child: Text(_t('છ માસિક', 'Half-Yearly'))),
                              DropdownMenuItem(value: TimeFilter.yearly, child: Text(_t('વાર્ષિક', 'Yearly'))),
                              DropdownMenuItem(value: TimeFilter.allFY, child: Text(_t('આખું FY', 'Full FY'))),
                              DropdownMenuItem(value: TimeFilter.custom, child: Text(_t('ચોક્કસ તારીખ', 'Specific Date'))),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => selectedFilter = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // (સુધારો ૧) પ્રથમ ટેબ / ચોક્કસ તારીખ પસંદગી અને સોર્ટિંગ બાર
                  if (selectedFilter == TimeFilter.custom)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      color: adaptiveTintBg(Colors.teal),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.date_range, size: 15),
                              label: Text('${_t("થી", "From")}: ${DateFormat("dd/MM/yyyy").format(customStartDate)}', style: const TextStyle(fontSize: 11.5)),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _clampDate1800To2100(customStartDate),
                                  firstDate: DateTime(1800, 1, 1),
                                  lastDate: DateTime(2100, 12, 31),
                                );
                                if (d != null) {
                                  setState(() {
                                    customStartDate = d;
                                    if (customEndDate.isBefore(customStartDate)) {
                                      customEndDate = customStartDate;
                                    }
                                  });
                                }
                              },
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.event, size: 15),
                              label: Text('${_t("સુધી", "To")}: ${DateFormat("dd/MM/yyyy").format(customEndDate)}', style: const TextStyle(fontSize: 11.5)),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _clampDate1800To2100(customEndDate),
                                  firstDate: DateTime(1800, 1, 1),
                                  lastDate: DateTime(2100, 12, 31),
                                );
                                if (d != null) {
                                  setState(() {
                                    customEndDate = d;
                                    if (customStartDate.isAfter(customEndDate)) {
                                      customStartDate = customEndDate;
                                    }
                                  });
                                }
                              },
                            ),
                            ActionChip(
                              label: Text(_t('એક જ તારીખ', 'Single Day'), style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _clampDate1800To2100(customStartDate),
                                  firstDate: DateTime(1800, 1, 1),
                                  lastDate: DateTime(2100, 12, 31),
                                );
                                if (d != null) {
                                  setState(() {
                                    customStartDate = d;
                                    customEndDate = d;
                                  });
                                }
                              },
                            ),
                            DropdownButton<String>(
                              value: _txSortMode,
                              isDense: true,
                              underline: const SizedBox(),
                              items: [
                                DropdownMenuItem(value: 'date_desc', child: Text(_t('નવી → જૂની', 'Newest First'), style: const TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: 'date_asc', child: Text(_t('જૂની → નવી', 'Oldest First'), style: const TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: 'amount_desc', child: Text(_t('વધુ રકમ', 'High Amount'), style: const TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: 'amount_asc', child: Text(_t('ઓછી રકમ', 'Low Amount'), style: const TextStyle(fontSize: 11.5))),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _txSortMode = v);
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
                        _buildMiniSummaryCard(_t('આવક', 'Income'), totalIncome, Colors.green),
                        _buildMiniSummaryCard(_t('ખર્ચ', 'Expense'), totalExpense, Colors.redAccent),
                        _buildMiniSummaryCard(_t('રોકાણ', 'Invest'), assetGain, Colors.blue),
                        _buildMiniSummaryCard(_t('નેટ બચત', 'Net Save'), netSavings, Colors.teal),
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
            ],
          );
        },
      ),
    );
  }
}
