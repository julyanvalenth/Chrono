import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'onboarding.dart' show WorkPrefsFields;

/// Profile sheet, opened by tapping the avatar (top right of Home / Today):
/// name, email, work preferences and log out.
Future<void> showProfileSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.sheet,
      barrierColor: const Color(0x9E000000),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _ProfileSheet(),
    );

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: C.line(0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              const Avatar(size: 56, interactive: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(state.userName, style: poppins(19, weight: w600), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    state.userEmail.isEmpty ? 'Offline' : state.userEmail,
                    style: poppins(13, color: C.ink2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              IconButton(
                tooltip: 'Edit name',
                onPressed: state.online ? () => _editName(context, state) : null,
                icon: const Icon(Icons.edit_outlined, color: C.ink2, size: 20),
              ),
            ]),
            const SizedBox(height: 26),
            Text('WORK PREFERENCES', style: poppins(11, weight: w500, color: C.ink2, letterSpacing: 0.66)),
            const SizedBox(height: 4),
            Text('Chrono plans focus time and breaks around these.', style: poppins(13, color: C.ink3)),
            const SizedBox(height: 16),
            const WorkPrefsFields(),
            const SizedBox(height: 28),
            Btn(
              label: 'Log out',
              style: BtnStyle.ghost,
              color: C.danger,
              leading: const Icon(Icons.logout_rounded, color: C.danger, size: 19),
              onTap: () => _confirmLogOut(context, state),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, AppState state) async {
    final name = await showDialog<String>(context: context, builder: (_) => _NameDialog(state.userName));
    if (name != null) state.setName(name);
  }

  Future<void> _confirmLogOut(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Log out?', style: poppins(17, weight: w600)),
        content: Text(
          'Your schedule stays saved to your account. Log in again to pick it up.',
          style: poppins(14, color: C.ink2, lineHeight: 20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: poppins(14, weight: w500, color: C.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Log out', style: poppins(14, weight: w600, color: C.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context); // close the sheet
    await state.logOut();
  }
}

/// Owns its controller so it lives until the dialog has finished closing.
class _NameDialog extends StatefulWidget {
  const _NameDialog(this.initial);
  final String initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Your name', style: poppins(17, weight: w600)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 40,
        style: poppins(15),
        cursorColor: C.lime,
        decoration: chronoField('What should Chrono call you?'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: poppins(14, weight: w500, color: C.ink2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text('Save', style: poppins(14, weight: w600, color: C.lime)),
        ),
      ],
    );
  }
}
