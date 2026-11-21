import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'chrono_mark.dart';
import 'common.dart';

/// "Tell Chrono what changed…" input. Home shows it as one pill with the mark;
/// Chat shows a separate send button.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.onSubmit, this.home = false, this.busy = false});
  final ValueChanged<String> onSubmit;
  final bool home;
  final bool busy;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _c = TextEditingController();

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty || widget.busy) return;
    widget.onSubmit(t);
    _c.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      onSubmitted: (_) => _submit(),
      textInputAction: TextInputAction.send,
      cursorColor: C.lime,
      style: poppins(widget.home ? 14.5 : 15),
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: 'Tell Chrono what changed…',
        hintStyle: poppins(widget.home ? 14.5 : 15, color: C.ink3),
      ),
    );

    final send = Semantics(
      button: true,
      label: 'Send',
      child: Opacity(
        opacity: widget.busy ? 0.35 : 1,
        child: Pressable(
          onTap: _submit,
          child: Container(
            width: widget.home ? 36 : 48,
            height: widget.home ? 36 : 48,
            decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle),
            child: Icon(Icons.arrow_upward_rounded, color: C.bg, size: widget.home ? 18 : 22),
          ),
        ),
      ),
    );

    if (widget.home) {
      return Container(
        height: 54,
        padding: const EdgeInsets.only(left: 11, right: 9),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: C.line(0.12)),
        ),
        child: Row(children: [
          const ChronoMark(size: 34),
          const SizedBox(width: 12),
          Expanded(child: field),
          send,
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 19),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: C.line(0.12)),
            ),
            child: field,
          ),
        ),
        const SizedBox(width: 8),
        send,
      ]),
    );
  }
}
