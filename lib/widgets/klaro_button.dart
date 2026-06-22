import 'package:flutter/material.dart';
import '../theme/klaro.dart';

/// Primary action button — the only place (besides the logo) that carries the
/// brand gradient, per the Klaro design rules.
class KlaroButton extends StatelessWidget {
  const KlaroButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    return AnimatedContainer(
      duration: Klaro.durFast,
      curve: Klaro.ease,
      decoration: BoxDecoration(
        gradient: enabled ? Klaro.gradient : null,
        color: enabled ? null : Klaro.raised,
        borderRadius: BorderRadius.circular(Klaro.radiusPill),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Klaro.violet.withValues(alpha: 0.45),
                  blurRadius: 22,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(Klaro.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else if (icon != null)
                  Icon(icon,
                      size: 18, color: enabled ? Colors.white : Klaro.textFaint),
                if (loading || icon != null) const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: Klaro.sans,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: enabled ? Colors.white : Klaro.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
