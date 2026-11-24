import 'package:flutter/material.dart';

import '../data/models.dart';
import '../logic/suggestions.dart';
import '../logic/time_utils.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/composer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final todays = dayBlocks(state.blocks, today);
    final current = todays.where((b) => b.start <= now && now < b.end).firstOrNull;
    final upcoming = todays.where((b) => b.start >= now).take(3).toList();
    final classesLeft = todays.where((b) => b.kind == Kind.lecture && b.end > now).length;
    final focus = todays.where((b) => b.kind == Kind.focus || b.kind == Kind.task).fold(0, (s, b) => s + b.length);
    final dueSoon = state.deadlines.where((d) => !d.done && d.urgent).take(2).toList();
    final prompts = suggestPrompts(
      blocks: state.blocks,
      deadlines: state.deadlines,
      focusWindow: state.prefs.focus.name,
      bedtime: state.prefs.bedtime,
      day: today,
      now: now,
    );

    void ask(String text) {
      state.goTab(AppTab.chat);
      state.send(text);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 4, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${days[today].long.toUpperCase()} · ${days[today].date} OCT', style: metaStyle),
                const SizedBox(height: 2),
                Text(
                  'Good morning,\n${state.firstName}',
                  style: poppins(29, weight: w600, lineHeight: 30.45, letterSpacing: -0.58),
                ),
              ]),
            ),
            const Avatar(),
          ]),
        ),
        if (current != null) ...[
          const SizedBox(height: 10),
          Pressable(
            onTap: () => state.goTab(AppTab.today),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: C.lime, borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('HAPPENING NOW', style: poppins(10.5, weight: w600, color: C.limeInk, letterSpacing: 0.84)),
                  const Spacer(),
                  Text(range(current.start, current.end), style: poppins(11, weight: w500, color: C.limeInk)),
                ]),
                const SizedBox(height: 6),
                Text(current.title, style: poppins(24, weight: w600, color: C.limeInk, lineHeight: 25.2, letterSpacing: -0.48)),
                const SizedBox(height: 10),
                ProgressBar(
                  value: (now - current.start) / current.length,
                  color: C.limeInk,
                  track: C.limeInk.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Text('${current.end - now} min left', style: poppins(12.5, weight: w500, color: C.limeInk)),
                  const Spacer(),
                  Text(current.detail ?? '', style: poppins(12.5, weight: w500, color: C.limeInk)),
                ]),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat('$classesLeft', classesLeft == 1 ? 'class left' : 'classes left')),
          const SizedBox(width: 8),
          Expanded(child: _Stat(duration(focus), 'focus planned')),
          const SizedBox(width: 8),
          Expanded(child: _Stat(duration(freeMinutes(state.blocks, today)), 'free today')),
        ]),
        const SizedBox(height: 14),
        _Panel(
          title: 'Up next',
          link: 'Full day →',
          onLink: () => state.goTab(AppTab.today),
          children: [
            for (final b in upcoming) _NextRow(block: b, onTap: () => state.showBlock(b.id)),
            if (upcoming.isEmpty) const _Empty('Nothing else planned today.'),
          ],
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'Due soon',
          link: 'All →',
          onLink: () => state.goTab(AppTab.deadlines),
          children: [
            for (final d in dueSoon) _DueRow(d),
            if (dueSoon.isEmpty) const _Empty('Nothing due in the next day.'),
          ],
        ),
        const SizedBox(height: 14),
        Composer(home: true, onSubmit: ask),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in prompts) Chip2(p, onTap: () => ask(p)),
        ]),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 12),
      decoration: panelBox(radius: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: poppins(21, weight: w600, lineHeight: 29, letterSpacing: -0.42)),
        const SizedBox(height: 2),
        Text(label, style: poppins(10.5, weight: w500, color: C.ink2, lineHeight: 13.65)),
      ]),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.link, required this.onLink, required this.children});
  final String title;
  final String link;
  final VoidCallback onLink;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: panelBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 10, 6, 0),
          child: Row(children: [
            Text(title, style: poppins(15, weight: w600)),
            const Spacer(),
            TextButton(
              onPressed: onLink,
              style: TextButton.styleFrom(
                foregroundColor: C.lime,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(link, style: poppins(12.5, weight: w600, color: C.lime)),
            ),
          ]),
        ),
        ...children,
      ]),
    );
  }
}

class _NextRow extends StatelessWidget {
  const _NextRow({required this.block, required this.onTap});
  final Block block;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: block.title,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            SizedBox(width: 58, child: Text(clock(block.start), style: poppins(11.5, weight: w500, color: C.ink2))),
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(color: kindStyle(block.kind).bar, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(block.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: poppins(14, weight: w600)),
                Text(duration(block.length), style: poppins(11.5, color: C.ink2)),
              ]),
            ),
            KindTag.kind(block.kind),
          ]),
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow(this.d);
  final Deadline d;
  @override
  Widget build(BuildContext context) {
    final task = kindStyle(Kind.task);
    return Padding(
      padding: const EdgeInsets.fromLTRB(17, 6, 17, 8),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(d.title, style: poppins(14, weight: w600))),
          KindTag(d.due, bg: task.bg, fg: task.ink, large: true, radius: 6),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ProgressBar(value: d.planned / d.estimate, color: d.planned >= d.estimate ? C.green : C.lime),
          ),
          const SizedBox(width: 10),
          Text('${duration(d.planned)} / ${duration(d.estimate)}', style: poppins(10.5, weight: w500, color: C.ink2)),
        ]),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(17, 8, 17, 12), child: Text(text, style: poppins(13, color: C.ink3)));
}
