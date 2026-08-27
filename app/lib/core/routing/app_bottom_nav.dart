import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mycomicbrain/core/design_system/tokens.dart';

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.raised = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Il pulsante centrale (scan), sollevato sopra il filo della barra.
  final bool raised;
}

const _destinations = [
  _NavDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
  _NavDestination(
    icon: Icons.collections_bookmark_outlined,
    selectedIcon: Icons.collections_bookmark,
    label: 'Collezione',
  ),
  _NavDestination(
    icon: Icons.document_scanner_outlined,
    selectedIcon: Icons.document_scanner,
    label: '',
    raised: true,
  ),
  _NavDestination(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Cerca'),
  _NavDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Impostazioni'),
];

/// Barra di navigazione a 5 voci con pulsante scan centrale rialzato —
/// non realizzabile con [NavigationBar] standard, per questo custom.
/// Vetro smerigliato e filo superiore riprendono il prototipo
/// (`app-design/Catalogo Fumetti.dc.html`, righe 785-803).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    // Il pulsante scan si solleva sopra il bordo della barra (vedi
    // `_RaisedScanButton`): il blur va clippato al rettangolo della barra,
    // ma la Row che contiene il pulsante deve restare fuori da quel clip,
    // altrimenti la parte sollevata viene tagliata.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceBase.withValues(alpha: 0.86),
                  border: const Border(top: BorderSide(color: AppColors.borderSubtle)),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs + 1,
              AppSpacing.sm,
              AppSpacing.xxs + 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  _NavItem(
                    destination: _destinations[i],
                    selected: i == currentIndex,
                    onTap: () => onDestinationSelected(i),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (destination.raised) {
      return _RaisedScanButton(icon: destination.icon, onTap: onTap);
    }

    final color = selected ? AppColors.accent : AppColors.textMuted;
    return Expanded(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.smRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? destination.selectedIcon : destination.icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  style: AppTypography.bodySmall.copyWith(fontSize: 9.5, fontWeight: FontWeight.w500, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RaisedScanButton extends StatelessWidget {
  const _RaisedScanButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -14),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: AppRadii.lgRadius,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentAlpha(0.3),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.lgRadius,
            child: Icon(icon, color: AppColors.onAccent, size: 20),
          ),
        ),
      ),
    );
  }
}
