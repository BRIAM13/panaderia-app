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

  // ID real del bloque de anuncios "Banner Cliente Inferior" en AdMob.
  static const _adUnitId = 'ca-app-pub-8167336469205854/6934217199';

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
        await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
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
    //
    // OJO: el alto total va en un SizedBox explícito, no en un Container
    // con alignment — un Container con alignment, al recibir restricciones
    // "acotadas pero grandes" (como las de bottomNavigationBar, que permite
    // hasta casi toda la pantalla), SE EXPANDE para llenar todo ese espacio
    // y luego centra el anuncio adentro — eso es justo lo que causaba que
    // el banner apareciera "flotando" en la mitad de la pantalla con un
    // hueco enorme debajo. Un SizedBox con alto fijo no tiene ese problema:
    // siempre mide exactamente lo que se le pide.
    final altoTotal = anuncio.size.height.toDouble() + 14;
    return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            width: double.infinity,
            height: altoTotal,
            child: Center(
              child: SizedBox(
                width: anuncio.size.width.toDouble(),
                height: anuncio.size.height.toDouble(),
                child: AdWidget(ad: anuncio),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 350.ms)
        .moveY(begin: 20, end: 0, curve: Curves.easeOutCubic);
  }
}
