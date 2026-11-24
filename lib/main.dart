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
  runApp(ChronoApp(state: AppState()..connect()));
}

/// Material 3 stretches scroll content at the edges on Android 12 and newer.
/// Chrono's cards and the tab bar deform badly when that happens, so drops the
/// stretch (and the glow) while keeping the platform scroll physics.
class _ChronoScrollBehavior extends MaterialScrollBehavior {
  const _ChronoScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
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
        scrollBehavior: const _ChronoScrollBehavior(),
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
