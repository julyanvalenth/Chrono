import 'package:flutter/material.dart';

import '../data/models.dart';
import '../logic/chrono_engine.dart';
import '../logic/suggestions.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chrono_mark.dart';
import '../widgets/common.dart';
import '../widgets/composer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  int _seen = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final count = state.messages.length + (state.thinking ? 1 : 0);
    if (count != _seen) {
      final first = _seen == -1;
      _seen = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        if (first) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: easeOut);
        }
      });
    }

    final items = <Widget>[
      for (final m in state.messages) _MessageView(m),
      if (state.thinking) const _Typing(),
    ];
    final prompts = suggestPrompts(
      blocks: state.blocks,
      deadlines: state.deadlines,
      focusWindow: state.prefs.focus.name,
      bedtime: state.prefs.bedtime,
      day: today,
      now: now,
    );

    return Column(children: [
      Container(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 3, 20, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.line(0.08)))),
        child: Row(children: [
          const ChronoMark(size: 40, hole: 9),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chrono', style: poppins(16, weight: w600, lineHeight: 20)),
            Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('your scheduler · online', style: poppins(11.5, weight: w500, color: C.ink2)),
            ]),
          ]),
        ]),
      ),
      Expanded(
        // Reversed list keeps messages pinned to the bottom like the design.
        child: ListView.separated(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => items[items.length - 1 - i],
        ),
      ),
      SizedBox(
        height: 54,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          itemCount: prompts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Chip2(prompts[i], onTap: state.thinking ? null : () => state.send(prompts[i])),
        ),
      ),
      Composer(onSubmit: state.send, busy: state.thinking),
    ]);
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView(this.m);
  final ChatMessage m;

  @override
  Widget build(BuildContext context) {
    return switch (m) {
      TextMessage(:final fromUser, :final text) => Align(
          alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: fromUser ? 300 : 344),
            padding: fromUser ? const EdgeInsets.symmetric(horizontal: 14, vertical: 11) : const EdgeInsets.fromLTRB(15, 11, 15, 12),
            decoration: BoxDecoration(
              color: fromUser ? C.ink : C.surface,
              borderRadius: BorderRadius.circular(18),
              border: fromUser ? null : Border.all(color: C.line(0.08)),
            ),
            child: Text(text, style: poppins(14.5, color: fromUser ? C.bg : C.ink, lineHeight: 21.03)),
          ),
        ),
      ProposalMessage() => _Proposal(m as ProposalMessage),
    };
  }
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Chrono is typing',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: panelBox(radius: 18),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Opacity(
                  opacity: 0.3 + 0.7 * (1 - ((_c.value - i * 0.15) % 1 - 0.5).abs() * 2).clamp(0, 1),
                  child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.ink3, shape: BoxShape.circle)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Proposal extends StatelessWidget {
  const _Proposal(this.p);
  final ProposalMessage p;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final n = p.changes.length;
    final status = switch (p.status) {
      ProposalStatus.pending => Text('$n CHANGE${n > 1 ? 'S' : ''}', style: poppins(10.5, weight: w600, color: C.ink3)),
      ProposalStatus.applied => Text('✓ APPLIED', style: poppins(10.5, weight: w600, color: C.green)),
      ProposalStatus.dismissed => Text('SKIPPED', style: poppins(10.5, weight: w600, color: C.ink3)),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Opacity(
        opacity: p.status == ProposalStatus.dismissed ? 0.55 : 1,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 346),
          clipBehavior: Clip.antiAlias,
          decoration: panelBox(radius: 18, border: 0.1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 37,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.line(0.07)))),
              child: Row(children: [
                Text('PROPOSED CHANGES', style: poppins(10.5, weight: w600, color: C.ink2, letterSpacing: 0.63)),
                const Spacer(),
                status,
              ]),
            ),
            for (final c in p.changes) _ChangeRow(c),
            if (p.status == ProposalStatus.pending)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                child: Row(children: [
                  Expanded(
                    flex: 122,
                    child: Btn(
                      label: 'Not now',
                      style: BtnStyle.soft,
                      height: 44,
                      radius: 12,
                      fontSize: 14,
                      onTap: () => state.decide(p.id, ProposalStatus.dismissed),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 195,
                    child: Btn(
                      label: 'Apply changes',
                      height: 44,
                      radius: 12,
                      fontSize: 14,
                      onTap: () => state.decide(p.id, ProposalStatus.applied),
                    ),
                  ),
                ]),
              ),
            if (p.status == ProposalStatus.applied)
              Pressable(
                onTap: () => state.viewInTimeline(p.changes.first.targetId, p.changes.first.targetDay),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(children: [
                      Text('View in timeline', style: poppins(13.5, weight: w600, color: C.lime)),
                      const Spacer(),
                      const Icon(Icons.arrow_forward, color: C.lime, size: 16),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.c);
  final Change c;

  @override
  Widget build(BuildContext context) {
    final old = poppins(11, color: C.ink3, decoration: TextDecoration.lineThrough);
    final fresh = poppins(11, weight: w500);
    final (Color dot, String title, Widget whenText, Widget tag) = switch (c) {
      AddChange(:final block) => (
          C.lime,
          block.title,
          Text(slotLabel(slotOf(block)), style: fresh),
          const KindTag('NEW', bg: C.lime, fg: C.limeInk),
        ),
      MoveChange(:final title, :final kind, :final from, :final to) => (
          kindStyle(kind).bar,
          title,
          Text.rich(
            TextSpan(children: [
              TextSpan(text: slotLabel(from), style: old),
              TextSpan(text: '  →  ', style: poppins(11, color: C.ink3)),
              TextSpan(text: slotLabel(to), style: fresh),
            ]),
            semanticsLabel: '${slotLabel(from)}, moved to ${slotLabel(to)}',
          ),
          KindTag('MOVED', bg: kindStyle(Kind.personal).bg, fg: kindStyle(Kind.task).ink),
        ),
      RemoveChange(:final title, :final kind, :final from) => (
          kindStyle(kind).bar,
          title,
          Text(slotLabel(from), style: old),
          const KindTag('REMOVED', bg: C.surface2, fg: C.danger),
        ),
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.line(0.05)))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: poppins(13.5, weight: w600)),
            const SizedBox(height: 2),
            whenText,
          ]),
        ),
        const SizedBox(width: 8),
        tag,
      ]),
    );
  }
}
