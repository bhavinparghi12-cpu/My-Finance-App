import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'constants.dart';
import 'auth_gate.dart';

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
