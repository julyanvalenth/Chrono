import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../logic/time_utils.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chrono_mark.dart';
import '../widgets/common.dart';

EdgeInsets _screenPadding(BuildContext context, {double top = 14}) {
  final pad = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(24, pad.top + top, 24, pad.bottom + 24);
}

/* ---------------- Welcome ---------------- */

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: _screenPadding(context, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const ChronoMark(size: 24, hole: 6),
            const SizedBox(width: 8),
            Text('Chrono', style: poppins(17, weight: w700, letterSpacing: -0.34)),
          ]),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => box.maxHeight < 200
                  ? const SizedBox.shrink()
                  : const Center(child: ChronoMark(size: 108, hole: 26, rest: C.surface2)),
            ),
          ),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Plan less.\n'),
              TextSpan(text: 'Live more.', style: poppins(37, weight: w600, color: C.lime, style: FontStyle.italic, lineHeight: 37, letterSpacing: -0.74)),
            ]),
            style: poppins(37, weight: w600, lineHeight: 37, letterSpacing: -0.74),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 342),
            child: Text(
              'Tell Chrono what’s on your plate. It builds your day around classes and deadlines, then rearranges it when life happens.',
              style: poppins(15, color: C.ink2, lineHeight: 22.5),
            ),
          ),
          const SizedBox(height: 27),
          Btn(
            label: 'Get started',
            onTap: () => state.online ? state.goStage(Stage.source) : state.showAuth(AuthMode.signUp),
          ),
          if (!state.online) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => state.showAuth(AuthMode.logIn),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Already have an account? ', style: poppins(13.5, color: C.ink2)),
                    TextSpan(text: 'Log in', style: poppins(13.5, weight: w600, color: C.lime)),
                  ]),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/* ---------------- Step header ---------------- */

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.onBack});
  final int step;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(children: [
        Transform.translate(
          offset: const Offset(-8, 0),
          child: IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: C.ink, size: 22),
          ),
        ),
        const Spacer(),
        Text('STEP $step / 2', style: poppins(11, weight: w500, color: C.ink2, letterSpacing: 0.66)),
      ]),
    );
  }
}

/* ---------------- Step 1: class schedule ---------------- */

enum _SourceMode { choose, type, reading, found }

class ScheduleSourceScreen extends StatefulWidget {
  const ScheduleSourceScreen({super.key});
  @override
  State<ScheduleSourceScreen> createState() => _ScheduleSourceScreenState();
}

class _ScheduleSourceScreenState extends State<ScheduleSourceScreen> {
  var _mode = _SourceMode.choose;
  final _typed = TextEditingController();
  String? _error;

  /// Send the typed text to the AI.
  Future<void> _readText() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = _SourceMode.reading;
      _error = null;
    });
    final err = await AppScope.read(context).readSchedule(text: _typed.text);
    if (!mounted) return;
    setState(() {
      _error = err;
      _mode = err == null ? _SourceMode.found : _SourceMode.type;
    });
  }

  /// Pick a timetable photo/screenshot and send it to the AI.
  Future<void> _scan() async {
    final source = kIsWeb ? ImageSource.gallery : await _pickSource();
    if (source == null || !mounted) return;
    XFile? file;
    try {
      // Downscale so the upload stays small; timetable text is still easy to read at this size.
      file = await ImagePicker().pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 85);
    } catch (e) {
      setState(() => _error = 'Couldn’t open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
      return;
    }
    if (file == null || !mounted) return;
    final state = AppScope.read(context);
    setState(() {
      _mode = _SourceMode.reading;
      _error = null;
    });
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final mime = file.mimeType ??
        (name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
    final err = await state.readSchedule(image: bytes, mimeType: mime);
    if (!mounted) return;
    setState(() {
      _error = err;
      _mode = err == null ? _SourceMode.found : _SourceMode.choose;
    });
  }

  Future<ImageSource?> _pickSource() => showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: C.sheet,
        barrierColor: const Color(0x9E000000),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Add your timetable', style: poppins(15, weight: w600)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: C.ink),
                title: Text('Choose a screenshot', style: poppins(14, weight: w500)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: C.ink),
                title: Text('Take a photo', style: poppins(14, weight: w500)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ]),
          ),
        ),
      );

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final selected = state.courses.where((c) => c.selected).length;
    final canContinue = _mode == _SourceMode.found && selected > 0;

    return Padding(
      padding: _screenPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(
            step: 1,
            onBack: () => _mode == _SourceMode.choose
                ? state.goStage(Stage.welcome)
                : setState(() => _mode = _SourceMode.choose),
          ),
          const SizedBox(height: 17),
          Text('Add your class schedule', style: poppins(27, weight: w600, lineHeight: 28.35, letterSpacing: -0.54)),
          const SizedBox(height: 4),
          Text(
            'Classes are fixed. Chrono plans everything else around them.',
            style: poppins(14.5, color: C.ink2, lineHeight: 21.75),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: KeyedSubtree(key: ValueKey(_mode), child: _content(state)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Btn(label: 'Continue', onTap: canContinue ? () => state.goStage(Stage.prefs) : null),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: poppins(13, color: C.danger, lineHeight: 18.2)),
          ),
        );

  Widget _content(AppState state) {
    switch (_mode) {
      case _SourceMode.choose:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _OptionCard(
            featured: true,
            title: 'Scan a timetable screenshot',
            desc: 'Photo of your KRS or campus portal. AI reads courses, days and rooms.',
            onTap: _scan,
          ),
          const SizedBox(height: 10),
          _OptionCard(
            title: 'Type it to Chrono',
            desc: '“Stats Tue & Thu 10am, HCI Friday 9…”',
            onTap: () => setState(() {
              _mode = _SourceMode.type;
              _error = null;
            }),
          ),
          _errorText(),
        ]);
      case _SourceMode.type:
        return Container(
          padding: const EdgeInsets.all(19),
          decoration: panelBox(radius: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Your classes, in your own words', style: poppins(13, weight: w500, color: C.ink2)),
            const SizedBox(height: 12),
            TextField(
              controller: _typed,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              style: poppins(14.5, lineHeight: 21),
              cursorColor: C.lime,
              decoration: InputDecoration(
                hintText: 'Stats Tue & Thu 10am, HCI Friday 9, Data Structures Mon & Thu 8am…',
                hintStyle: poppins(14.5, color: C.ink3, lineHeight: 21),
                filled: true,
                fillColor: C.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.line(0.12))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.line(0.12))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.line(0.24))),
              ),
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: _typed.text.trim().isEmpty ? 0.4 : 1,
              child: Btn(
                label: 'Read my classes',
                style: BtnStyle.soft,
                height: 46,
                radius: 14,
                fontSize: 14,
                onTap: _typed.text.trim().isEmpty ? null : _readText,
              ),
            ),
            _errorText(),
          ]),
        );
      case _SourceMode.reading:
        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(19),
            decoration: panelBox(radius: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reading your timetable…', style: poppins(13, weight: w500, color: C.ink2)),
              const SizedBox(height: 14),
              const _Skeleton(widthFactor: 1),
              const SizedBox(height: 12),
              const _Skeleton(widthFactor: 0.7),
              const SizedBox(height: 12),
              const _Skeleton(widthFactor: 0.85),
            ]),
          ),
        );
      case _SourceMode.found:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '✓ FOUND ${state.courses.length} ${state.courses.length == 1 ? 'COURSE' : 'COURSES'}: UNTICK ANY TO SKIP',
            style: poppins(11, weight: w500, color: C.green, letterSpacing: 0.44),
          ),
          const SizedBox(height: 9),
          for (final c in state.courses) ...[
            _CourseRow(course: c, onTap: () => state.toggleCourse(c.id)),
            const SizedBox(height: 8),
          ],
        ]);
    }
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.title, required this.desc, required this.onTap, this.featured = false});
  final String title;
  final String desc;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 20),
        decoration: BoxDecoration(
          color: featured ? C.surface2 : C.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: featured ? C.lime.withValues(alpha: 0.35) : C.line(0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: poppins(16, weight: w600)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(desc, style: poppins(13, color: C.ink2, lineHeight: 18.2)),
          ),
        ]),
      ),
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton({required this.widthFactor});
  final double widthFactor;
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widget.widthFactor,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final x = -1.0 + _c.value * 3;
          return Container(
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: LinearGradient(
                begin: Alignment(x - 1, 0),
                end: Alignment(x + 1, 0),
                colors: const [C.surface2, C.surface3, C.surface2],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.onTap});
  final Course course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = course.selected;
    final dayList = course.days.map((d) => days[d].short[0] + days[d].short.substring(1).toLowerCase()).join(' · ');
    return Semantics(
      checked: on,
      child: Pressable(
        onTap: onTap,
        label: course.name,
        child: Container(
          constraints: const BoxConstraints(minHeight: 67),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: panelBox(radius: 14),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? C.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: on ? C.ink : C.line(0.3), width: on ? 1 : 1.5),
              ),
              child: on ? Text('✓', style: poppins(13, weight: w700, color: C.bg, lineHeight: 15)) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: on ? 1 : 0.45,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(course.name, style: poppins(14.5, weight: w600)),
                  const SizedBox(height: 2),
                  Text('$dayList ${range(course.start, course.end)} ${course.room}', style: poppins(11.5, color: C.ink2)),
                ]),
              ),
            ),
            Opacity(
              opacity: on ? 1 : 0.45,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: kindStyle(Kind.lecture).bar, shape: BoxShape.circle),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/* ---------------- Step 2: preferences ---------------- */

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: _screenPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(step: 2, onBack: () => state.goStage(Stage.source)),
          const SizedBox(height: 19),
          Text('How do you like to work?', style: poppins(27, weight: w600, lineHeight: 28.35, letterSpacing: -0.54)),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: const WorkPrefsFields(),
            ),
          ),
          const SizedBox(height: 16),
          Btn(
            label: 'Build my schedule',
            trailing: const Spark(size: 16),
            onTap: () => state.goStage(Stage.building),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Focus window, bedtime and break pickers for onboarding and the profile.
class WorkPrefsFields extends StatelessWidget {
  const WorkPrefsFields({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final prefs = state.prefs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PickLegend('I focus best in the…'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in const [
            (FocusWindow.morning, 'Morning', '08–12'),
            (FocusWindow.afternoon, 'Afternoon', '13–17'),
            (FocusWindow.evening, 'Evening', '17–19'),
            (FocusWindow.night, 'Night', '19–23'),
          ])
            SizedBox(
              width: 152,
              child: PickChip(
                on: prefs.focus == o.$1,
                tall: true,
                label: o.$2,
                hint: o.$3,
                onTap: () => state.setPrefs(focus: o.$1),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        PickLegend('Bedtime'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in const ['21:00', '21:30', '22:00', '22:30', '23:00', '23:30', '00:00', '00:30'])
            PickChip(on: prefs.bedtime == t, label: t, onTap: () => state.setPrefs(bedtime: t)),
        ]),
        const SizedBox(height: 20),
        PickLegend('Break between blocks'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const [5, 10, 15, 20, 30, 45])
            PickChip(on: prefs.breakMin == m, label: '$m min', onTap: () => state.setPrefs(breakMin: m)),
        ]),
    ]);
  }
}

class PickLegend extends StatelessWidget {
  const PickLegend(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text(text, style: poppins(13, weight: w600)),
      );
}

class PickChip extends StatelessWidget {
  const PickChip({super.key, required this.on, required this.label, required this.onTap, this.hint, this.tall = false});
  final bool on;
  final String label;
  final String? hint;
  final bool tall;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? C.bg : C.ink;
    return Pressable(
      onTap: onTap,
      selected: on,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minHeight: tall ? 72 : 46),
        padding: tall ? const EdgeInsets.fromLTRB(13, 13, 13, 13) : const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
        decoration: BoxDecoration(
          color: on ? C.ink : C.surface,
          borderRadius: BorderRadius.circular(tall ? 16 : 22),
          border: Border.all(color: C.line(0.1)),
        ),
        child: tall
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: poppins(14.5, weight: w600, color: fg)),
                  const SizedBox(height: 6),
                  Text(hint!, style: poppins(11, color: fg.withValues(alpha: 0.75))),
                ],
              )
            : Center(widthFactor: 1, child: Text(label, style: poppins(13.5, weight: w500, color: fg))),
      ),
    );
  }
}

/* ---------------- Building ---------------- */

class BuildingScreen extends StatefulWidget {
  const BuildingScreen({super.key});
  @override
  State<BuildingScreen> createState() => _BuildingScreenState();
}

class _BuildingScreenState extends State<BuildingScreen> {
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _timer = Timer(Duration(milliseconds: _step == 0 ? 500 : 750), () {
      if (!mounted) return;
      if (_step >= 4) {
        AppScope.read(context).finishOnboarding();
        return;
      }
      setState(() => _step++);
      _tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final courses = state.courses.where((c) => c.selected).length;
    final open = state.deadlines.where((d) => !d.done).length;
    final steps = [
      'Placing $courses course${courses == 1 ? '' : 's'} as fixed blocks',
      'Fitting $open deadlines into focus windows',
      'Adding ${state.prefs.breakMin}-min breaks, protecting ${state.prefs.bedtime} bedtime',
      'Leaving room for the unexpected',
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.bg, C.bgDeep]),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SpinningMark(),
            const SizedBox(height: 23),
            Text('Building your week…', style: poppins(29, weight: w600, lineHeight: 30.45, letterSpacing: -0.58)),
            const SizedBox(height: 24),
            for (final (i, s) in steps.indexed) ...[
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: i > _step ? 0.3 : 1,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 32,
                    child: Text(i < _step ? '✓' : '·', style: poppins(13, weight: w600, color: C.lime, lineHeight: 20)),
                  ),
                  Expanded(child: Text(s, style: poppins(14, weight: w500, lineHeight: 20))),
                ]),
              ),
              const SizedBox(height: 15),
            ],
          ],
        ),
      ),
    );
  }
}
