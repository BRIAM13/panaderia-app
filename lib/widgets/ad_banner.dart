import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner adaptable real de Google AdMob, mostrado solo en la vista Cliente.
/// google_mobile_ads no tiene implementación para web/escritorio, así que
/// ahí simplemente no se carga nada (sin errores).
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  // ID de bloque de anuncios de PRUEBA oficial de Google (banner adaptable).
  // Reemplazar por el ID real de producción antes de publicar la app.
  static const _adUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _fallo = false;

  bool get _plataformaSoportada =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (_plataformaSoportada) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargarAnuncio());
    }
  }

  Future<void> _cargarAnuncio() async {
    if (!mounted) return;

    final anchoDisponible = MediaQuery.sizeOf(context).width.truncate();
    final tamano =
        await AdSize.getAnchoredAdaptiveBannerAdSize(
          Orientation.portrait,
          anchoDisponible,
        ) ??
        AdSize.banner;

    if (!mounted) return;

    final anuncio = BannerAd(
      adUnitId: AdBanner._adUnitId,
      size: tamano,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _bannerAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() => _fallo = true);
        },
      ),
    );

    await anuncio.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anuncio = _bannerAd;
    if (!_plataformaSoportada || _fallo || anuncio == null) {
      return const SizedBox.shrink();
    }

    // SafeArea(bottom) evita que el banner quede debajo de la barra de
    // gestos/navegación del sistema; el padding extra deja un margen táctil
    // de por medio para que no se disparen toques accidentales de esa barra
    // ni del contenido justo encima.
    return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 6),
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
            child: SizedBox(
              width: anuncio.size.width.toDouble(),
              height: anuncio.size.height.toDouble(),
              child: AdWidget(ad: anuncio),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 350.ms)
        .moveY(begin: 20, end: 0, curve: Curves.easeOutCubic);
  }
}
