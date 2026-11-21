import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/app_shell.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(ChronoApp(state: AppState()));
}

class ChronoApp extends StatelessWidget {
  const ChronoApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Chrono',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: C.bg,
          colorScheme: const ColorScheme.dark(primary: C.lime, surface: C.bg, onSurface: C.ink),
          textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
          splashFactory: NoSplash.splashFactory,
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: C.lime,
            selectionColor: C.lime.withValues(alpha: 0.3),
            selectionHandleColor: C.lime,
          ),
        ),
        home: const AppShell(),
      ),
    );
  }
}
