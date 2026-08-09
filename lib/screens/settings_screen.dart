import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/klaro_links.dart';
import '../providers/expense_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/device_capabilities.dart';
import '../services/health_check.dart';
import '../theme/klaro.dart';
import '../widgets/klaro_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  bool _testing = false;
  ApiTestResult? _result; // null = untested
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ApiService.instance.baseUrl);
    _keyCtrl = TextEditingController(text: ApiService.instance.apiKey);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await ApiService.instance
        .testConnection(url: _urlCtrl.text, apiKey: _keyCtrl.text);
    if (mounted) {
      setState(() {
        _testing = false;
        _result = result;
      });
    }
  }

  Future<void> _save() async {
    await ApiService.instance.setBaseUrl(_urlCtrl.text);
    await ApiService.instance.setApiKey(_keyCtrl.text);
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AccountCard(),
          const SizedBox(height: 20),
          const _HealthSection(),
          const SizedBox(height: 20),
          const Text(
            'Backend server',
            style: TextStyle(
              fontFamily: Klaro.display,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Klaro.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Where the app sends your expenses. Use the cloud address '
            '(https://klaro-api.vercel.app) to sync from anywhere, '
            'your laptop’s address (http://192.168.1.5:8000) on home Wi-Fi, '
            'or http://localhost:8000 when connected by USB cable.',
            style: TextStyle(fontSize: 12.5, color: Klaro.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {
              _result = null;
              _saved = false;
            }),
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'https://klaro-api.onrender.com',
              prefixIcon: Icon(Icons.dns_outlined, color: Klaro.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: true,
            onChanged: (_) => setState(() {
              _result = null;
              _saved = false;
            }),
            decoration: const InputDecoration(
              labelText: 'API key',
              hintText: 'Leave empty for a local server without one',
              prefixIcon: Icon(Icons.key_outlined, color: Klaro.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          if (_result != null) _TestResultBanner(result: _result!),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'Testing…' : 'Test connection'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KlaroButton(
                  onPressed: _save,
                  label: _saved ? 'Saved' : 'Save',
                  icon: _saved ? Icons.check : Icons.save_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Klaro.blue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
              border: Border.all(color: Klaro.blue.withValues(alpha: 0.25)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Klaro.blueLt),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cloud setup: the API key is the API_KEY env var on the '
                    'Vercel project (Settings → Environment Variables). For '
                    'home Wi-Fi instead, run "ipconfig" on the laptop, use '
                    'the IPv4 address + ":8000", and leave the key empty.',
                    style: TextStyle(
                        fontSize: 12, color: Klaro.blueLt, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _HelpSupportSection(),
          // Only meaningful when signed in — account deletion needs a session.
          if (AuthService.instance.isSignedIn) ...[
            const SizedBox(height: 24),
            const _DangerZoneSection(),
          ],
        ],
      ),
    );
  }
}

/// Irreversible account actions. Houses in-app account deletion — a Play Store
/// requirement for any app with user accounts: the user must be able to request
/// deletion of their account and data from within the app itself.
class _DangerZoneSection extends StatefulWidget {
  const _DangerZoneSection();

  @override
  State<_DangerZoneSection> createState() => _DangerZoneSectionState();
}

class _DangerZoneSectionState extends State<_DangerZoneSection> {
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final ok = await ApiService.instance.deleteAccount();
    if (!mounted) return;

    if (!ok) {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Couldn’t delete your account — check your connection and try again.'),
        ),
      );
      return;
    }

    // Backend wiped: clear the device copy, end the session, return to the gate.
    await context.read<ExpenseProvider>().clearLocalData();
    await AuthService.instance.signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your account and data have been deleted.')),
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Danger zone',
          style: TextStyle(
            fontFamily: Klaro.display,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Klaro.danger,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Permanently delete your account and everything in it — expenses, '
          'budgets and learned categories. This cannot be undone.',
          style: TextStyle(fontSize: 12.5, color: Klaro.textMuted),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Klaro.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Klaro.radiusMd),
            border: Border.all(color: Klaro.danger.withValues(alpha: 0.30)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Klaro.radiusMd),
            onTap: _deleting ? null : _confirmAndDelete,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  if (_deleting)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Klaro.danger),
                    )
                  else
                    const Icon(Icons.delete_forever_outlined,
                        size: 20, color: Klaro.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _deleting ? 'Deleting your account…' : 'Delete account',
                      style: const TextStyle(
                          color: Klaro.danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-factor confirm for an irreversible delete: the user must type DELETE so
/// it can never happen on a stray tap.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();
  static const _phrase = 'DELETE';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _ctrl.text.trim().toUpperCase() == _phrase;
    return AlertDialog(
      backgroundColor: Klaro.raised,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Klaro.radiusLg)),
      title: const Text('Delete account?',
          style: TextStyle(
              fontFamily: Klaro.display, fontSize: 17, color: Klaro.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently erases your account and all your data for '
            '${AuthService.instance.email ?? 'this account'}. It cannot be undone.',
            style: const TextStyle(color: Klaro.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Text('Type DELETE to confirm',
              style: TextStyle(color: Klaro.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'DELETE',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Klaro.textMuted)),
        ),
        TextButton(
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          child: Text('Delete forever',
              style: TextStyle(
                  color: canDelete ? Klaro.danger : Klaro.textFaint)),
        ),
      ],
    );
  }
}

/// "Is Klaro actually working?" — asks the phone what Klaro is allowed to do
/// and says so plainly. Exists because every capability the app depends on can
/// be switched off silently (a denied permission, an OEM battery policy, a
/// stricter Android release), leaving an app that looks fine and does nothing.
class _HealthSection extends StatefulWidget {
  const _HealthSection();

  @override
  State<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<_HealthSection> {
  HealthReport? _report;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final provider = context.read<ExpenseProvider>();
    final report = await HealthReport.run(DeviceCapabilities(
      pendingChanges: provider.pendingSyncCount,
      syncFailed: provider.syncFailed,
    ));
    if (mounted) {
      setState(() {
        _report = report;
        _running = false;
      });
    }
  }

  static (Color, IconData) _tone(HealthStatus s) => switch (s) {
        HealthStatus.ok => (Klaro.positive, Icons.check_circle_outline),
        HealthStatus.warning => (Klaro.alert, Icons.error_outline),
        HealthStatus.problem => (Klaro.danger, Icons.cancel_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final (headColor, _) = _tone(report?.overall ?? HealthStatus.ok);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Is Klaro working?',
              style: TextStyle(
                fontFamily: Klaro.display,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Klaro.text,
              ),
            ),
            const Spacer(),
            if (_running)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(
                onPressed: _run,
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Re-check',
                    style: TextStyle(color: Klaro.violetLt, fontSize: 12.5)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          report == null
              ? 'Checking this phone…'
              : report.overall == HealthStatus.ok
                  ? 'Everything Klaro needs is working on this phone.'
                  : '${report.problemCount > 0 ? "Something needs your attention" : "Worth a look"} — details below.',
          style: TextStyle(fontSize: 12.5, color: headColor),
        ),
        const SizedBox(height: 12),
        if (report != null)
          Container(
            decoration: BoxDecoration(
              color: Klaro.surface,
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
              border: Border.all(color: Klaro.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < report.checks.length; i++)
                  _HealthRow(
                    check: report.checks[i],
                    last: i == report.checks.length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.check, required this.last});
  final HealthCheck check;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _HealthSectionState._tone(check.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Klaro.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.title,
                    style: const TextStyle(
                        color: Klaro.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(check.detail,
                    style: const TextStyle(
                        color: Klaro.textMuted, fontSize: 11.5, height: 1.4)),
                if (check.fix != null) ...[
                  const SizedBox(height: 5),
                  Text('→ ${check.fix}',
                      style: TextStyle(
                          color: color, fontSize: 11.5, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contact support + the hosted legal/help documents (Phase 7.4). Required for
/// the Play listing and DPDP-Act compliance.
class _HelpSupportSection extends StatelessWidget {
  const _HelpSupportSection();

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme == 'mailto' ? 'mail app' : 'link'}')),
      );
    }
  }

  Future<void> _contactSupport(BuildContext context) async {
    final body = Uri.encodeComponent(
      '\n\n—\nKlaro app • v1.11.0\nDevice/OS: (please describe your issue above)',
    );
    final subject = Uri.encodeComponent('Klaro support');
    await _open(
      context,
      Uri.parse('mailto:${KlaroLinks.supportEmail}?subject=$subject&body=$body'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Help & support',
          style: TextStyle(
            fontFamily: Klaro.display,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Klaro.text,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Klaro.surface,
            borderRadius: BorderRadius.circular(Klaro.radiusMd),
            border: Border.all(color: Klaro.line),
          ),
          child: Column(
            children: [
              _LinkRow(
                icon: Icons.mail_outline,
                label: 'Contact support',
                onTap: () => _contactSupport(context),
              ),
              _LinkRow(
                icon: Icons.help_outline,
                label: 'Help & FAQ',
                onTap: () => _open(context, Uri.parse(KlaroLinks.help)),
              ),
              _LinkRow(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy policy',
                onTap: () => _open(context, Uri.parse(KlaroLinks.privacy)),
              ),
              _LinkRow(
                icon: Icons.description_outlined,
                label: 'Terms of service',
                onTap: () => _open(context, Uri.parse(KlaroLinks.terms)),
              ),
              _LinkRow(
                icon: Icons.delete_outline,
                label: 'Delete your data',
                onTap: () => _open(context, Uri.parse(KlaroLinks.dataDeletion)),
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Klaro.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Klaro.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Klaro.text, fontSize: 13.5)),
            ),
            const Icon(Icons.open_in_new, size: 15, color: Klaro.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Signed-in account row with a sign-out action. Hidden when no session (the
/// auth gate would be showing the login screen anyway).
class _AccountCard extends StatelessWidget {
  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Klaro.raised,
        title: const Text('Sign out?', style: TextStyle(color: Klaro.text)),
        content: const Text(
          'Your data stays safe in your account — sign back in any time.',
          style: TextStyle(color: Klaro.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Klaro.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out', style: TextStyle(color: Klaro.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AuthService.instance.signOut();
      // AuthGate reacts to the auth change; pop back to it.
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.email;
    if (email == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusMd),
        border: Border.all(color: Klaro.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: Klaro.gradient,
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Signed in as',
                    style: TextStyle(color: Klaro.textMuted, fontSize: 11.5)),
                const SizedBox(height: 2),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Klaro.text, fontSize: 13.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout, size: 16, color: Klaro.danger),
            label: const Text('Sign out', style: TextStyle(color: Klaro.danger, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// Three-state connection test result: connected, key rejected, unreachable.
class _TestResultBanner extends StatelessWidget {
  const _TestResultBanner({required this.result});
  final ApiTestResult result;

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = switch (result) {
      ApiTestResult.ok => (
          Klaro.positive,
          Icons.check_circle,
          'Connected — backend reachable and the API key works.',
        ),
      ApiTestResult.unauthorized => (
          Klaro.alert,
          Icons.key_off_outlined,
          'Backend reachable, but it rejected the API key. Check the key.',
        ),
      ApiTestResult.unreachable => (
          Klaro.danger,
          Icons.error_outline,
          'Could not reach the backend. Check the address, network, '
              'and that the server is running.',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Klaro.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
