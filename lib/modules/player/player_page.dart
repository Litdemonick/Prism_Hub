import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/models/watch_data.dart';
import 'player_controller.dart';
import 'watch_args.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.args});
  final WatchArgs args;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerController _c;

  @override
  void initState() {
    super.initState();
    // Modo inmersivo: ocultar barra de estado y navegación
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _c = Get.put(PlayerController(), tag: widget.args.episodeUrl);
    _c.load(widget.args.episodeUrl, widget.args.package);
  }

  @override
  void dispose() {
    Get.delete<PlayerController>(tag: widget.args.episodeUrl);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (_c.isLoading.value) {
          return _LoadingView(title: widget.args.title);
        }
        if (_c.error.value != null) {
          return _ErrorView(
            message: _c.error.value!,
            reason: _c.watchData.value?.reason,
            onBack: () => Navigator.of(context).pop(),
          );
        }
        return _PlayerView(
          c: _c,
          title: widget.args.title,
          onBack: () => Navigator.of(context).pop(),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista principal de reproducción
// ---------------------------------------------------------------------------

class _PlayerView extends StatelessWidget {
  const _PlayerView({
    required this.c,
    required this.title,
    required this.onBack,
  });

  final PlayerController c;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final data = c.watchData.value!;

    return MaterialVideoControlsTheme(
      normal: _buildTheme(context, data),
      fullscreen: _buildTheme(context, data),
      child: Video(
        controller: c.videoController,
        controls: MaterialVideoControls,
      ),
    );
  }

  MaterialVideoControlsThemeData _buildTheme(
    BuildContext context,
    WatchData data,
  ) {
    return MaterialVideoControlsThemeData(
      topButtonBar: [
        // Botón volver
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: onBack,
        ),
        const SizedBox(width: 4),
        // Título
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Subtítulos
        if (data.subtitles.isNotEmpty)
          _SubtitleButton(c: c, rootContext: context),
        // Velocidad
        _SpeedButton(c: c),
        // Calidad
        if (data.hasMultipleQualities)
          _QualityButton(c: c, streams: data.streams),
      ],
      // bottomButtonBar usa el default de media_kit_video
      // (play/pause, progress, volume, fullscreen)
    );
  }
}

// ---------------------------------------------------------------------------
// Botón de subtítulos
// ---------------------------------------------------------------------------

class _SubtitleButton extends StatelessWidget {
  const _SubtitleButton({required this.c, required this.rootContext});
  final PlayerController c;
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => IconButton(
        tooltip: 'Subtítulos',
        icon: Icon(
          Icons.subtitles_rounded,
          color: c.selectedSubtitleIdx.value >= 0
              ? const Color(0xFFFBBF24)
              : Colors.white,
        ),
        onPressed: () => _showSheet(rootContext),
      ),
    );
  }

  void _showSheet(BuildContext ctx) {
    final subs = c.watchData.value?.subtitles ?? [];
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Obx(
        () => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Subtítulos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _SubTile(
                label: 'Desactivado',
                icon: Icons.subtitles_off_rounded,
                selected: c.selectedSubtitleIdx.value < 0,
                onTap: () {
                  c.setSubtitle(-1);
                  Navigator.of(ctx).pop();
                },
              ),
              ...subs.asMap().entries.map(
                (e) => _SubTile(
                  label: e.value.label,
                  sublabel: e.value.lang,
                  icon: Icons.subtitles_rounded,
                  selected: c.selectedSubtitleIdx.value == e.key,
                  onTap: () {
                    c.setSubtitle(e.key);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.sublabel,
  });
  final String label;
  final String? sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFFBBF24) : Colors.white60;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFFFBBF24) : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: sublabel != null
          ? Text(sublabel!, style: const TextStyle(color: Colors.white38))
          : null,
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xFFFBBF24))
          : null,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Botón de velocidad
// ---------------------------------------------------------------------------

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.c});
  final PlayerController c;

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopupMenuButton<double>(
        tooltip: 'Velocidad',
        initialValue: c.speed.value,
        onSelected: c.setSpeed,
        color: const Color(0xFF1A1A1A),
        itemBuilder: (_) => _speeds
            .map(
              (s) => PopupMenuItem<double>(
                value: s,
                child: Text(
                  s == 1.0 ? 'Normal' : '${s}x',
                  style: TextStyle(
                    color: c.speed.value == s
                        ? const Color(0xFFFBBF24)
                        : Colors.white,
                    fontWeight: c.speed.value == s
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            c.speed.value == 1.0 ? '1x' : '${c.speed.value}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Botón de calidad
// ---------------------------------------------------------------------------

class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.c, required this.streams});
  final PlayerController c;
  final List<WatchStream> streams;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopupMenuButton<WatchStream>(
        tooltip: 'Calidad',
        initialValue: c.selectedStream.value,
        onSelected: c.switchStream,
        color: const Color(0xFF1A1A1A),
        itemBuilder: (_) => streams
            .map(
              (s) => PopupMenuItem<WatchStream>(
                value: s,
                child: Text(
                  s.displayLabel,
                  style: TextStyle(
                    color: c.selectedStream.value == s
                        ? const Color(0xFFFBBF24)
                        : Colors.white,
                    fontWeight: c.selectedStream.value == s
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hd_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 4),
              Text(
                c.selectedStream.value?.displayLabel ?? 'Auto',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estados auxiliares
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onBack,
    this.reason,
  });

  final String message;
  final String? reason;
  final VoidCallback onBack;

  static String _reasonLabel(String r) => switch (r) {
    'premium_required' => '🔒  Contenido de pago',
    'region_blocked'   => '🌍  No disponible en tu región',
    'js_eval_required' => '⚠️  Este sitio requiere JS avanzado',
    _                  => r,
  };

  @override
  Widget build(BuildContext context) {
    final showReason = reason != null;
    final displayMsg = message == '__reason__'
        ? 'No se pudo obtener el stream'
        : message;

    return Column(
      children: [
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: onBack,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white38,
                    size: 72,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    displayMsg,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  if (showReason) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _reasonLabel(reason!),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white70,
                    ),
                    label: const Text(
                      'Volver',
                      style: TextStyle(color: Colors.white70),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: onBack,
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
