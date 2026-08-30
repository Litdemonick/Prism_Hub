import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/degradacion_en_caliente.dart';
import 'package:prismhub/utils/encabezado_de_sesion.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_mas.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// La pantalla de **PrismHub+**: qué aparato detectó y qué está haciendo con eso.
///
/// ── Por qué esto se muestra y no se esconde ─────────────────────────────────
///
/// La app se comporta distinto según el aparato: pide menos calidad de vídeo en
/// un televisor modesto, le pone turno a las peticiones, acorta las animaciones.
/// Todo eso, invisible, es una caja negra: alguien con un televisor de 0,9 GB ve
/// 720p donde su amigo ve 1080p y no tiene forma de saber por qué.
///
/// Acá se ve las tres cosas juntas: **qué aparato es**, **qué se ajustó por
/// eso**, y el interruptor para apagarlo. Con el interruptor apagado se dice
/// bien claro que no se está optimizando nada, que es justo lo que hay que
/// mirar primero si la app va lenta.
///
/// ── Un diseño para los tres modos ───────────────────────────────────────────
///
/// La misma pantalla en televisor, teléfono y PC. Las filas van en
/// [FocusableCard], así que el mando le da foco visible a lo que se puede
/// tocar; el dedo y el ratón funcionan sobre lo mismo. Lo único que cambia son
/// los tamaños: desde el sillón un texto de 13 no se lee.
class PrismHubMasPage extends StatefulWidget {
  const PrismHubMasPage({super.key});

  @override
  State<PrismHubMasPage> createState() => _PrismHubMasPageState();
}

class _PrismHubMasPageState extends State<PrismHubMasPage> {
  /// Cuántos MB soltó la última limpieza, o null si todavía no se limpió.
  double? _soltados;
  bool _limpiando = false;

  bool get _tv => PlatformTv.esTelevisionSync;

  double get _tituloSz => _tv ? 22 : 16;
  double get _textoSz => _tv ? 17 : 14;
  double get _chicoSz => _tv ? 15 : 12;

  Future<void> _alternar() async {
    await PrismHubStorage.setSetting(
      SettingKey.prismhubMas,
      !PrismHubMas.encendido,
    );
    // Al apagarlo se olvida lo aprendido: si alguien pide que la app no se
    // adapte, arrastrar un nivel rebajado de antes sería seguir adaptándola.
    if (!PrismHubMas.encendido) await DegradacionEnCaliente.olvidar();
    PrismHubMas.anotarEnElRegistro();
    if (mounted) setState(() {});
  }

  Future<void> _limpiar() async {
    setState(() => _limpiando = true);
    final bytes = await PrismHubMas.limpiar();
    if (!mounted) return;
    setState(() {
      _limpiando = false;
      _soltados = bytes / (1024 * 1024);
    });
  }

  @override
  Widget build(BuildContext context) {
    final encendido = PrismHubMas.encendido;
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'PrismHub+',
          style: TextStyle(
            color: HomeTheme.textPrimary,
            fontSize: _tituloSz,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ColoredBox(
        color: HomeTheme.bg,
        child: SafeArea(
          top: false,
          child: Center(
            // Acotado y centrado: en un PC a pantalla completa o en una tablet
            // apaisada, una lista de punta a punta deja la etiqueta pegada a un
            // borde y el valor al otro, con medio metro de nada en medio.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: EdgeInsets.all(_tv ? 28 : 16),
                children: [
                  _queEs(),
                  const SizedBox(height: 18),
                  _elInterruptor(encendido),
                  const SizedBox(height: 22),
                  _rotulo('settings.mas-tu-aparato'.i18n),
                  const SizedBox(height: 10),
                  _laFicha(),
                  const SizedBox(height: 22),
                  _rotulo('settings.mas-que-ajusta'.i18n),
                  const SizedBox(height: 10),
                  _loQueAjusta(encendido),
                  const SizedBox(height: 22),
                  _rotulo('settings.mas-limpieza'.i18n),
                  const SizedBox(height: 10),
                  _laLimpieza(),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _queEs() => Container(
        padding: EdgeInsets.all(_tv ? 20 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Color.alphaBlend(
            HomeTheme.accentPink.withValues(alpha: 0.07),
            HomeTheme.bg,
          ),
          border: Border.all(
            color: HomeTheme.accentPink.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          'settings.mas-que-es'.i18n,
          style: TextStyle(
            fontSize: _textoSz,
            height: 1.5,
            color: HomeTheme.textPrimary,
          ),
        ),
      );

  Widget _elInterruptor(bool encendido) => FocusableCard(
        borderRadius: 14,
        conCrecido: false,
        onTap: () => unawaited(_alternar()),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _tv ? 20 : 14,
            vertical: _tv ? 20 : 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Color.alphaBlend(
              Colors.white.withValues(alpha: 0.05),
              HomeTheme.bg,
            ),
          ),
          child: Row(
            children: [
              Icon(
                encendido ? Icons.bolt : Icons.bolt_outlined,
                color: encendido ? HomeTheme.accentPink : HomeTheme.textMuted,
                size: _tv ? 30 : 24,
              ),
              SizedBox(width: _tv ? 18 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'settings.mas-optimizar'.i18n,
                      style: TextStyle(
                        fontSize: _textoSz + 1,
                        fontWeight: FontWeight.w600,
                        color: HomeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      encendido
                          ? (PrismHubMas.estaAjustando
                              ? 'settings.mas-ajustando'.i18n
                              : 'settings.mas-sin-recortes'.i18n)
                          : 'settings.mas-apagado-aviso'.i18n,
                      style: TextStyle(
                        fontSize: _chicoSz,
                        height: 1.4,
                        color: encendido
                            ? HomeTheme.textMuted
                            : HomeTheme.accentRed,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: _tv ? 14 : 10),
              // Una pastilla con la palabra y no un interruptor dibujado: desde
              // el sillón, la perilla de un switch chico no se lee.
              _Pastilla(activa: encendido, grande: _tv),
            ],
          ),
        ),
      );

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          texto.toUpperCase(),
          style: TextStyle(
            fontSize: _chicoSz,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: HomeTheme.textMuted,
          ),
        ),
      );

  /// Lo que la app sabe del aparato. Es exactamente lo mismo que va en la
  /// cabecera del registro, para que no puedan decir cosas distintas.
  Widget _laFicha() => _Tarjeta(
        tv: _tv,
        hijos: [
          for (final p in EncabezadoDeSesion.fichaEnPares())
            _Fila(
              etiqueta: p.etiqueta,
              valor: p.valor,
              tamano: _textoSz,
              tamanoChico: _chicoSz,
            ),
        ],
      );

  Widget _loQueAjusta(bool encendido) {
    final sinRecorte = 'settings.mas-sin-recorte'.i18n;
    final peticiones = PrismHubMas.peticionesALaVez;
    final deMas = PrismHubMas.pixelesQueSeConstruyenDeMas;
    return _Tarjeta(
      tv: _tv,
      hijos: [
        _Fila(
          etiqueta: 'settings.mas-calidad'.i18n,
          valor: 'hasta ${PrismHubMas.techoDeCalidad}p',
          tamano: _textoSz,
          tamanoChico: _chicoSz,
        ),
        _Fila(
          etiqueta: 'settings.mas-peticiones'.i18n,
          valor: peticiones == 0 ? sinRecorte : '$peticiones a la vez',
          tamano: _textoSz,
          tamanoChico: _chicoSz,
        ),
        _Fila(
          etiqueta: 'settings.mas-animaciones'.i18n,
          valor: _duracionDeEjemplo(sinRecorte),
          tamano: _textoSz,
          tamanoChico: _chicoSz,
        ),
        _Fila(
          etiqueta: 'settings.mas-listas'.i18n,
          valor: deMas == null ? sinRecorte : '${deMas.round()} px',
          tamano: _textoSz,
          tamanoChico: _chicoSz,
        ),
        if (!encendido)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'settings.mas-apagado-detalle'.i18n,
              style: TextStyle(
                fontSize: _chicoSz,
                height: 1.4,
                color: HomeTheme.accentRed,
              ),
            ),
          ),
      ],
    );
  }

  /// Cuánto dura una animación normal en este aparato.
  ///
  /// Se muestra con un ejemplo concreto de 300 ms —la duración habitual de una
  /// transición— porque «se acortan un 50 %» no le dice nada a nadie.
  String _duracionDeEjemplo(String sinRecorte) {
    const normal = Duration(milliseconds: 300);
    final ahora = PrismHubMas.animacion(normal);
    if (ahora == normal) return sinRecorte;
    return '${ahora.inMilliseconds} ms en vez de ${normal.inMilliseconds}';
  }

  Widget _laLimpieza() => _Tarjeta(
        tv: _tv,
        hijos: [
          Text(
            'settings.mas-limpieza-detalle'.i18n,
            style: TextStyle(
              fontSize: _chicoSz,
              height: 1.5,
              color: HomeTheme.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          FocusableCard(
            borderRadius: 10,
            conCrecido: false,
            // FocusableCard pide un onTap sí o sí, así que mientras limpia se
            // le pasa uno que no hace nada en vez de null: el foco del mando
            // tiene que seguir cayendo en el botón aunque esté trabajando.
            onTap: () {
              if (!_limpiando) unawaited(_limpiar());
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: _tv ? 16 : 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: HomeTheme.accentPink.withValues(alpha: 0.18),
                border: Border.all(
                  color: HomeTheme.accentPink.withValues(alpha: 0.5),
                ),
              ),
              child: Center(
                child: Text(
                  _limpiando
                      ? 'settings.mas-limpiando'.i18n
                      : 'settings.mas-limpiar'.i18n,
                  style: TextStyle(
                    fontSize: _textoSz,
                    fontWeight: FontWeight.w600,
                    color: HomeTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          if (_soltados != null) ...[
            const SizedBox(height: 12),
            Text(
              FlutterI18n.translate(
                context,
                'settings.mas-limpiado',
                translationParams: {'mb': _soltados!.toStringAsFixed(1)},
              ),
              style: TextStyle(
                fontSize: _chicoSz,
                color: const Color(0xFF6FCFA5),
              ),
            ),
          ],
        ],
      );
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.hijos, required this.tv});

  final List<Widget> hijos;
  final bool tv;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(tv ? 20 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Color.alphaBlend(
            Colors.white.withValues(alpha: 0.05),
            HomeTheme.bg,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: hijos,
        ),
      );
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.etiqueta,
    required this.valor,
    required this.tamano,
    required this.tamanoChico,
  });

  final String etiqueta;
  final String valor;
  final double tamano;
  final double tamanoChico;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: tamano * 6.5,
              child: Text(
                etiqueta,
                style: TextStyle(
                  fontSize: tamanoChico,
                  fontWeight: FontWeight.w600,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                valor,
                style: TextStyle(
                  fontSize: tamano,
                  height: 1.35,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.activa, required this.grande});

  final bool activa;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final color = activa ? HomeTheme.accentPink : HomeTheme.textMuted;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: grande ? 18 : 12,
        vertical: grande ? 9 : 6,
      ),
      decoration: BoxDecoration(
        color: activa
            ? color.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: activa ? color : HomeTheme.border),
      ),
      child: Text(
        activa ? 'common.on'.i18n : 'common.off'.i18n,
        style: TextStyle(
          fontSize: grande ? 15 : 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
