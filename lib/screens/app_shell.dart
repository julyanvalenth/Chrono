import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../logic/time_utils.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chrono_mark.dart';
import '../widgets/common.dart';
import '../widgets/icons.dart';
import 'auth.dart';
import 'chat.dart';
import 'deadlines.dart';
import 'home.dart';
import 'onboarding.dart';
import 'today.dart';

/// Root of the app: onboarding stages, then the four tabs with the tab bar,
/// toast and block sheet layered on top.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final Widget body = state.booting
        ? const _Loading()
        : state.bootFailed
        ? const _CantConnect()
        : switch (state.stage) {
            Stage.welcome => const WelcomeScreen(),
            Stage.auth => const AuthScreen(),
            Stage.source => const ScheduleSourceScreen(),
            Stage.prefs => const PreferencesScreen(),
            Stage.building => const BuildingScreen(),
            Stage.app => const _Tabs(),
          };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: C.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack(context, state);
        },
        child: Scaffold(
          backgroundColor: C.bg,
          resizeToAvoidBottomInset: true,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: easeOut,
            child: KeyedSubtree(
              key: state.booting
                  ? const ValueKey('booting')
                  : state.bootFailed
                  ? const ValueKey('offline')
                  : ValueKey(state.stage),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack(BuildContext context, AppState state) {
    if (state.sheetId != null) return state.openSheet(null);
    switch (state.stage) {
      case Stage.auth:
      case Stage.source:
        return state.goStage(Stage.welcome);
      case Stage.prefs:
        return state.goStage(Stage.source);
      case Stage.app when state.tab != AppTab.home:
        return state.goTab(AppTab.home);
      default:
        SystemNavigator.pop();
    }
  }
}

/// Shown while the app signs in and loads the schedule. Same logo, size and
/// background as the native splash (assets/branding), so the hand-off is seamless;
/// a small spinner fades in only if loading takes a moment.
class _Loading extends StatefulWidget {
  const _Loading();
  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends State<_Loading> {
  var _slow = false;
  late final Timer _timer = Timer(const Duration(milliseconds: 900), () {
    if (mounted) setState(() => _slow = true);
  });

  @override
  void initState() {
    super.initState();
    _timer; // start it
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading Chrono',
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            const ChronoMark(size: 112, hole: 28),
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 96,
              child: AnimatedOpacity(
                opacity: _slow ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: C.lime,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logged in, but the server couldn't be reached at launch.
class _CantConnect extends StatelessWidget {
  const _CantConnect();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(32, pad.top + 24, 32, pad.bottom + 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          const ChronoMark(size: 56, rest: C.surface3, hole: 14),
          const SizedBox(height: 22),
          Text(
            'Can’t reach Chrono',
            style: poppins(27, weight: w600, letterSpacing: -0.54),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your internet connection. Your schedule is safe in your account.',
            style: poppins(14.5, color: C.ink2, lineHeight: 21.75),
          ),
          const Spacer(),
          Btn(label: 'Try again', onTap: state.connect),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: state.logOut,
              child: Text(
                'Log out',
                style: poppins(13.5, weight: w500, color: C.ink2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tabBarHeight = 60 + bottomInset;

    final Widget screen = switch (state.tab) {
      AppTab.home => const HomeScreen(),
      AppTab.today => const TodayScreen(),
      AppTab.chat => const ChatScreen(),
      AppTab.deadlines => const DeadlinesScreen(),
    };

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: KeyedSubtree(key: ValueKey(state.tab), child: screen),
            ),
            _TabBar(height: tabBarHeight),
          ],
        ),
        if (state.toast != null && state.tab != AppTab.chat)
          Positioned(
            left: 14,
            right: 14,
            bottom: tabBarHeight + 12,
            child: _ToastView(toast: state.toast!),
          ),
        if (state.sheetBlock != null)
          _SheetLayer(key: ValueKey(state.sheetId), block: state.sheetBlock!),
      ],
    );
  }
}

/* ---------------- Tab bar ---------------- */

class _TabBar extends StatelessWidget {
  const _TabBar({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    Widget item(AppTab tab, String label, Widget Function(Color) icon) {
      final active = state.tab == tab;
      final color = active ? C.ink : C.ink3;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => state.goTab(tab),
            child: Column(
              children: [
                const SizedBox(height: 4),
                icon(color),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: poppins(11, weight: w600, color: color),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
      decoration: BoxDecoration(
        color: C.bg,
        border: Border(top: BorderSide(color: C.line(0.08))),
      ),
      alignment: Alignment.topCenter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item(AppTab.home, 'Home', (c) => TabIcon(TabGlyph.home, color: c)),
          item(AppTab.today, 'Today', (c) => TabIcon(TabGlyph.today, color: c)),
          item(AppTab.chat, 'Chrono', (c) => ChronoMark(size: 24, rest: c)),
          item(
            AppTab.deadlines,
            'Deadlines',
            (c) => TabIcon(TabGlyph.deadlines, color: c),
          ),
        ],
      ),
    );
  }
}

/* ---------------- Toast ---------------- */

class _ToastView extends StatefulWidget {
  const _ToastView({required this.toast});
  final ToastData toast;
  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_ToastView old) {
    super.didUpdateWidget(old);
    if (old.toast.id != widget.toast.id) _arm();
  }

  void _arm() {
    _timer?.cancel();
    final id = widget.toast.id;
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) AppScope.read(context).dismissToast(id);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final t = widget.toast;
    return TweenAnimationBuilder<double>(
      key: ValueKey(t.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: child,
        ),
      ),
      child: Semantics(
        liveRegion: true,
        child: Container(
          height: 54,
          padding: EdgeInsets.only(
            left: 17,
            right: t.focusIds.isEmpty ? 17 : 7,
          ),
          decoration: BoxDecoration(
            color: C.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line(0.1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: poppins(14, weight: w500),
                ),
              ),
              if (t.canUndo)
                TextButton(
                  onPressed: state.undo,
                  style: TextButton.styleFrom(
                    foregroundColor: C.limeSoft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    'Undo',
                    style: poppins(13.5, weight: w600, color: C.limeSoft),
                  ),
                ),
              if (t.focusIds.isNotEmpty)
                Pressable(
                  onTap: () {
                    final id = t.focusIds.first;
                    final b = state.blocks.where((x) => x.id == id).firstOrNull;
                    state.viewInTimeline(id, b?.day ?? state.selectedDay);
                  },
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.surface3,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('View', style: poppins(13.5, weight: w600)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- Block sheet ---------------- */

class _SheetLayer extends StatefulWidget {
  const _SheetLayer({super.key, required this.block});
  final Block block;
  @override
  State<_SheetLayer> createState() => _SheetLayerState();
}

class _SheetLayerState extends State<_SheetLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final b = widget.block;
    final anim = CurvedAnimation(parent: _c, curve: easeOut);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: anim,
              child: Semantics(
                label: 'Close',
                button: true,
                child: GestureDetector(
                  onTap: () => state.openSheet(null),
                  child: const ColoredBox(color: Color(0x9E000000)),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(anim),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, 31, 20, bottom + 24),
                decoration: const BoxDecoration(
                  color: C.sheet,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: -21,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: C.line(0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KindTag(
                          b.kind.label.toUpperCase(),
                          bg: kindStyle(b.kind).bg,
                          fg: kindStyle(b.kind).ink,
                          large: true,
                          radius: 7,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          b.title,
                          style: poppins(
                            24,
                            weight: w600,
                            lineHeight: 26.4,
                            letterSpacing: -0.48,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${days[b.day].long} · ${range(b.start, b.end)} · ${duration(b.length)}${b.detail != null ? ' · ${b.detail}' : ''}',
                          style: poppins(13, weight: w500, color: C.ink2),
                        ),
                        const SizedBox(height: 17),
                        if (b.kind == Kind.lecture) ...[
                          Text(
                            'Classes are fixed. Chrono plans everything else around them.',
                            style: poppins(13.5, color: C.ink2, lineHeight: 20),
                          ),
                          const SizedBox(height: 17),
                          Btn(
                            label: 'Close',
                            onTap: () => state.openSheet(null),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: Btn(
                                  label: b.done ? 'Mark not done' : 'Mark done',
                                  height: 54,
                                  radius: 14,
                                  fontSize: 14.5,
                                  onTap: () => state.markDone(b.id),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Btn(
                                  label: 'Push 30 min',
                                  style: BtnStyle.ghost,
                                  height: 54,
                                  radius: 14,
                                  fontSize: 14.5,
                                  onTap: () => state.push(b.id, 30),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Btn(
                                  label: 'Move with AI',
                                  style: BtnStyle.ghost,
                                  leading: const Spark(color: C.lime, size: 14),
                                  height: 54,
                                  radius: 14,
                                  fontSize: 14.5,
                                  onTap: () {
                                    state.goTab(AppTab.chat);
                                    state.send(
                                      'Move ${b.title} to my next free slot',
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Btn(
                                  label: 'Remove',
                                  style: BtnStyle.ghost,
                                  color: C.danger,
                                  height: 54,
                                  radius: 14,
                                  fontSize: 14.5,
                                  onTap: () => state.remove(b.id),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
