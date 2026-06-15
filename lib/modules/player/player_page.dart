import 'package:flutter/material.dart';
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
    _c = Get.put(PlayerController(), tag: widget.args.episodeUrl);
    _c.load(widget.args.episodeUrl, widget.args.package);
  }

  @override
  void dispose() {
    Get.delete<PlayerController>(tag: widget.args.episodeUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.args.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          Obx(() {
            final data = _c.watchData.value;
            if (data == null || !data.hasMultipleQualities) {
              return const SizedBox.shrink();
            }
            return _QualityButton(c: _c, streams: data.streams);
          }),
        ],
      ),
      body: Obx(() {
        if (_c.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (_c.error.value != null) {
          return _ErrorView(
            message: _c.error.value!,
            reason: _c.watchData.value?.reason,
            onBack: () => Navigator.of(context).pop(),
          );
        }

        return Video(
          controller: _c.videoController,
          controls: MaterialVideoControls,
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------

class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.c, required this.streams});

  final PlayerController c;
  final List<WatchStream> streams;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = c.selectedStream.value;
      return PopupMenuButton<WatchStream>(
        tooltip: 'Calidad',
        initialValue: current,
        onSelected: c.switchStream,
        itemBuilder: (_) => streams
            .map(
              (s) => PopupMenuItem(
                value: s,
                child: Text(s.displayLabel),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Chip(
            label: Text(
              current?.displayLabel ?? 'Auto',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: Colors.white12,
            side: BorderSide.none,
          ),
        ),
      );
    });
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
    'premium_required' => '🔒 Contenido de pago',
    'region_blocked'   => '🌍 No disponible en tu región',
    'js_eval_required' => '⚠️ Este sitio requiere evaluación JS',
    _                  => r,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.white54, size: 64),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: Colors.white70)),
        if (reason != null) ...[
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _reasonLabel(reason!),
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 24),
        TextButton.icon(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          label: const Text('Volver', style: TextStyle(color: Colors.white)),
          onPressed: onBack,
        ),
      ],
    );
  }
}
