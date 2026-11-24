import 'package:flutter/material.dart';

import '../data/models.dart';
import '../logic/time_utils.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class DeadlinesScreen extends StatefulWidget {
  const DeadlinesScreen({super.key});
  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final open = state.deadlines.where((d) => !d.done).toList();
    final urgent = open.where((d) => d.isUrgent).length;
    final list = state.deadlines.where((d) => d.done == _done).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 4,
        16,
        24,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deadlines',
                style: poppins(
                  30,
                  weight: w600,
                  lineHeight: 40,
                  letterSpacing: -0.6,
                ),
              ),
              Text(
                '${open.length} OPEN · $urgent DUE WITHIN A DAY',
                style: metaStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: C.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              for (final done in [false, true])
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _done = done),
                    selected: _done == done,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _done == done ? C.surface3 : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        done ? 'Done' : 'Upcoming',
                        style: poppins(13.5, weight: w600),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final d in list) ...[
          _DeadlineCard(
            d: d,
            planned: d.plannedFor(state.blocks),
            onToggle: () => state.toggleDeadline(d.id),
            onPlan: () {
              state.goTab(AppTab.chat);
              state.send('Plan time for ${d.title}');
            },
          ),
          const SizedBox(height: 10),
        ],
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: panelBox(
              radius: 18,
              color: Colors.transparent,
              border: 0.16,
            ),
            child: Text(
              _done
                  ? 'Finished deadlines show up here.'
                  : 'No open deadlines. Add one by telling Chrono, e.g. “Essay due Friday, 3h”.',
              textAlign: TextAlign.center,
              style: poppins(13.5, color: C.ink2, lineHeight: 20),
            ),
          ),
      ],
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({
    required this.d,
    required this.planned,
    required this.onToggle,
    required this.onPlan,
  });
  final Deadline d;
  final int planned;
  final VoidCallback onToggle;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final short = planned < d.estimate;
    final tagStyle = d.isUrgent
        ? kindStyle(Kind.task)
        : kindStyle(Kind.breakTime);
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
      decoration: panelBox(radius: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            checked: d.done,
            label: '${d.done ? 'Reopen' : 'Complete'} ${d.title}',
            child: Pressable(
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d.done ? C.green : Colors.transparent,
                  border: Border.all(color: d.done ? C.green : C.line(0.3)),
                ),
                child: d.done
                    ? Text(
                        '✓',
                        style: poppins(
                          12,
                          weight: w700,
                          color: C.bg,
                          lineHeight: 14,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            style: poppins(
                              15,
                              weight: w600,
                              lineHeight: 19.5,
                              color: d.done ? C.ink2 : C.ink,
                              decoration: d.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${d.course} · ~${duration(d.estimate)}',
                            style: poppins(12, color: C.ink2, lineHeight: 16.8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    KindTag(
                      d.dueLabel,
                      bg: tagStyle.bg,
                      fg: tagStyle.ink,
                      large: true,
                    ),
                  ],
                ),
                if (!d.done && planned > 0) ...[
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: ProgressBar(
                          value: planned / d.estimate,
                          color: short ? C.lime : C.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${duration(planned)} / ${duration(d.estimate)} planned',
                        style: poppins(10.5, weight: w500, color: C.ink2),
                      ),
                    ],
                  ),
                ],
                if (!d.done && short) ...[
                  const SizedBox(height: 13),
                  Btn(
                    label: 'Plan with Chrono',
                    leading: const Spark(size: 13),
                    height: 36,
                    radius: 18,
                    fontSize: 13,
                    expand: false,
                    padding: 14,
                    onTap: onPlan,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
