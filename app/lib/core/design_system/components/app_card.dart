import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Card contenitore di base: bordo hairline, fondo overlay sottile, angoli
/// arrotondati. Il vocabolario visivo di cui si compongono le altre card
/// (KPI, riepiloghi, righe di dettaglio).
///
/// Se [onTap] è fornito, la card risponde con il ripple Material (deciso
/// su #7: nessuna divergenza Cupertino).
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Default: [AppRadii.lgRadius].
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadii.lgRadius;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.overlayCard,
        borderRadius: radius,
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      ),
    );
  }
}
