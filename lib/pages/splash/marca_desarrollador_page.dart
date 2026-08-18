import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import 'splash_page.dart';

/// Primera pantalla que ve cualquiera al abrir la app: un instante de marca
/// del estudio que la desarrolló, antes de pasar al splash real de
/// Panadería Ronceros. Se muestra una sola vez por arranque en frío, nunca
/// al volver de segundo plano (esta página no vuelve a montarse porque
/// `SplashPage` reemplaza la ruta en vez de apilarse encima).
class MarcaDesarrolladorPage extends StatefulWidget {
  const MarcaDesarrolladorPage({super.key});

  @override
  State<MarcaDesarrolladorPage> createState() =>
      _MarcaDesarrolladorPageState();
}

class _MarcaDesarrolladorPageState extends State<MarcaDesarrolladorPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(FadeRoute(builder: (_) => const SplashPage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.secondary, AppColors.primary],
                    ),
                  ),
                )
                .animate()
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 450.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 250.ms),
            const SizedBox(height: 18),
            Text(
                  'RONCEROS LABS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.94),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 5,
                  ),
                )
                .animate(delay: 200.ms)
                .fadeIn(duration: 450.ms)
                .moveY(begin: 6, end: 0, curve: Curves.easeOut),
          ],
        ).animate().fadeOut(delay: 950.ms, duration: 350.ms),
      ),
    );
  }
}
