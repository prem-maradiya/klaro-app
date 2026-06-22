/// Canonical Klaro support + legal links (Phase 7.4). Hosted as static pages on
/// the dashboard; linked from the in-app Settings "Help & support" section and
/// required by the Play listing / DPDP Act.
class KlaroLinks {
  static const String _base = 'https://klaro-dashboard.vercel.app';

  static const String privacy = '$_base/privacy.html';
  static const String terms = '$_base/terms.html';
  static const String dataDeletion = '$_base/data-deletion.html';
  static const String security = '$_base/security.html';
  static const String help = '$_base/help.html';

  /// Support inbox. A Gmail alias for now (a dedicated support@ domain comes with
  /// the brand domain, deferred until before public launch).
  static const String supportEmail = 'premmaradiya333@gmail.com';
}
