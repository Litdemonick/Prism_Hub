import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prismhub/data/services/import_service.dart';
import 'package:prismhub/models/import_result.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showImportDialog(BuildContext context) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ImportDialogContent(isMobile: true),
    );
  } else {
    await fluent.showDialog(
      context: context,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (context) => const _ImportDialogContent(isMobile: false),
    );
  }
}

class _ImportDialogContent extends StatefulWidget {
  const _ImportDialogContent({required this.isMobile});
  final bool isMobile;

  @override
  State<_ImportDialogContent> createState() => _ImportDialogContentState();
}

class _ImportDialogContentState extends State<_ImportDialogContent> {
  final _textController = TextEditingController();
  bool _isImporting = false;
  int _currentProgress = 0;
  int _totalProgress = 0;
  ImportResult? _result;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    // Leer el portapapeles tarda, y en ese rato el diálogo puede haberse
    // cerrado. Sin esto se seguía usando su `context` para abrir el aviso de
    // reemplazo, sobre una pantalla que ya no está.
    if (!mounted) return;
    if (data?.text != null && data!.text!.isNotEmpty) {
      if (_textController.text.isNotEmpty) {
        final confirm = await _confirmReplace(context);
        if (!confirm) return;
      }
      setState(() {
        _textController.text = data.text!;
      });
    }
  }

  Future<void> _loadFromFile() async {
    if (_textController.text.isNotEmpty) {
      final confirm = await _confirmReplace(context);
      if (!confirm) return;
    }

    try {
      setState(() {
        _isImporting = true;
        _currentProgress = 0;
        _totalProgress = 0;
        _result = null;
      });

      final res = await ImportService.importFromFile(
        onProgress: (c, t) {
          setState(() {
            _currentProgress = c;
            _totalProgress = t;
          });
        },
      );
      
      setState(() {
        _result = res;
      });
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('file-too-large')) {
        msg = 'import.file-too-large'.i18n;
      }
      _showError(msg);
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  Future<void> _startImport() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('Pega al menos un link para empezar.');
      return;
    }

    final urls = ImportService.extractUrls(text);
    if (urls.isEmpty) {
      _showError('No se encontró ningún link válido en el texto. Revisa lo que escribiste.');
      return;
    }

    setState(() {
      _isImporting = true;
      _currentProgress = 0;
      _totalProgress = 0;
      _result = null;
    });

    try {
      final res = await ImportService.importFromText(
        text: _textController.text,
        onProgress: (c, t) {
          setState(() {
            _currentProgress = c;
            _totalProgress = t;
          });
        },
      );
      setState(() {
        _result = res;
      });
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  Future<bool> _confirmReplace(BuildContext context) async {
    if (widget.isMobile) {
      final res = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: HomeTheme.cardSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('common.warning'.i18n, style: TextStyle(color: HomeTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: Text(
            'import.file-replace-confirm'.i18n,
            style: TextStyle(color: HomeTheme.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('common.cancel'.i18n, style: TextStyle(color: HomeTheme.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('common.confirm'.i18n, style: TextStyle(color: HomeTheme.accentPink, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return res ?? false;
    } else {
      final res = await fluent.showDialog<bool>(
        context: context,
        builder: (c) => fluent.ContentDialog(
          content: Text('import.file-replace-confirm'.i18n),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(c, false),
              child: Text('common.cancel'.i18n),
            ),
            fluent.FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('common.confirm'.i18n),
            ),
          ],
        ),
      );
      return res ?? false;
    }
  }

  void _showError(String error) {
    if (widget.isMobile) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: HomeTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      fluent.displayInfoBar(
        context,
        builder: (context, close) => fluent.InfoBar(
          title: Text('common.error'.i18n),
          content: Text(error),
          severity: fluent.InfoBarSeverity.error,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }

  Widget _buildAndroid(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset, top: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Container(
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 6,
                        decoration: BoxDecoration(
                          color: HomeTheme.border.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: HomeTheme.accentPink.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.download_rounded, color: HomeTheme.accentPink, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'import.title'.i18n,
                                style: TextStyle(
                                  color: HomeTheme.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'import.subtitle'.i18n,
                                style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 24),
                          color: HomeTheme.textMuted,
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const SizedBox(height: 32),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.fastOutSlowIn,
                      child: _result != null
                          ? _buildResultMobile()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ModernOutlineBtn(
                                        icon: Icons.content_paste_rounded,
                                        label: 'import.paste'.i18n,
                                        onTap: _isImporting ? null : _pasteFromClipboard,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _ModernOutlineBtn(
                                        icon: Icons.folder_open_rounded,
                                        label: 'import.load-file'.i18n,
                                        onTap: _isImporting ? null : _loadFromFile,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: HomeTheme.border.withValues(alpha: 0.3)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: TextField(
                                    controller: _textController,
                                    minLines: 3,
                                    maxLines: 6,
                                    style: TextStyle(color: HomeTheme.textPrimary, height: 1.5),
                                    decoration: InputDecoration(
                                      hintText: 'import.text-hint'.i18n,
                                      hintStyle: TextStyle(color: HomeTheme.textMuted.withValues(alpha: 0.6)),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(20),
                                    ),
                                  ),
                                ),
                              ),  const SizedBox(height: 24),
                                if (_isImporting)
                                  _buildProgressWidget()
                                else
                                  ElevatedButton(
                                    onPressed: _startImport,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: HomeTheme.accentPink,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      elevation: 8,
                                      shadowColor: HomeTheme.accentPink.withValues(alpha: 0.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.auto_awesome_rounded, size: 20),
                                        const SizedBox(width: 12),
                                        Text(
                                          'import.import-button'.i18n,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                const _LinkGrabberTipWidget(),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressWidget() {
    final percent = _totalProgress > 0 ? _currentProgress / _totalProgress : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HomeTheme.accentPink.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'import.progress'
                    .i18n
                    .replaceAll('{current}', '$_currentProgress')
                    .replaceAll('{total}', '$_totalProgress'),
                style: TextStyle(color: HomeTheme.accentPink, fontWeight: FontWeight.bold),
              ),
              Text(
                '${(percent * 100).toInt()}%',
                style: TextStyle(color: HomeTheme.textPrimary, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.black26,
              color: HomeTheme.accentPink,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: HomeTheme.accentPink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBadge(
                    icon: Icons.check_circle_rounded,
                    color: Colors.greenAccent,
                    value: '${_result!.totalImported}',
                    label: 'Completados',
                  ),
                  _StatBadge(
                    icon: Icons.error_rounded,
                    color: HomeTheme.accentRed,
                    value: '${_result!.totalErrors}',
                    label: 'Errores',
                  ),
                ],
              ),
              if (_result!.totalDuplicates > 0 || _result!.totalNsfw > 0 || _result!.totalSkipped > 0) ...[
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_result!.totalDuplicates > 0)
                      _MiniStat(icon: Icons.copy_rounded, val: '${_result!.totalDuplicates}', text: 'Duplicados', color: Colors.blueAccent),
                    if (_result!.totalNsfw > 0)
                      _MiniStat(icon: Icons.eighteen_up_rating_rounded, val: '${_result!.totalNsfw}', text: 'NSFW', color: Colors.orangeAccent),
                    if (_result!.totalSkipped > 0)
                      _MiniStat(icon: Icons.delete_sweep_rounded, val: '${_result!.totalSkipped}', text: 'Saltados', color: Colors.grey),
                  ],
                ),
              ],
            ],
          ),
        ),
        
        if (_result!.importedByExtension.isNotEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text('EXTENSIONES DETECTADAS', style: TextStyle(color: HomeTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 16),
          if (_result!.importedByExtension.length == 1)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [HomeTheme.accentPink.withValues(alpha: 0.2), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.extension_rounded, size: 40, color: HomeTheme.accentPink),
                    const SizedBox(height: 12),
                    Text(
                      _result!.importedByExtension.keys.first,
                      style: TextStyle(color: HomeTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_result!.importedByExtension.values.first} lecturas',
                      style: TextStyle(color: HomeTheme.accentPink, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _result!.importedByExtension.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final e = _result!.importedByExtension.entries.elementAt(index);
                  return ListTile(
                    leading: Icon(Icons.extension_rounded, color: HomeTheme.textMuted),
                    title: Text(e.key, style: TextStyle(color: HomeTheme.textPrimary, fontWeight: FontWeight.w600)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: HomeTheme.accentPink.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${e.value}', style: TextStyle(color: HomeTheme.accentPink, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
        ],

        if (_result!.errors.isNotEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text('LINKS FALLIDOS (${_result!.errors.length})', style: TextStyle(color: HomeTheme.accentRed, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomeTheme.accentRed.withValues(alpha: 0.3)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _result!.errors.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final err = _result!.errors[index];
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.broken_image_rounded, color: HomeTheme.accentRed, size: 18),
                  title: Text(err.url, style: const TextStyle(fontSize: 12, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(err.reason, style: TextStyle(fontSize: 11, color: HomeTheme.accentRed), maxLines: 2, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          )
        ],

        if (_result!.limitReached) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomeTheme.accentRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HomeTheme.accentRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: HomeTheme.accentRed),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'import.limit-reached'.i18n,
                    style: TextStyle(color: HomeTheme.accentRed, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: HomeTheme.cardSurface,
            foregroundColor: HomeTheme.textPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: HomeTheme.border),
            ),
          ),
          child: Text('common.close'.i18n, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return fluent.ContentDialog(
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('import.title'.i18n, style: const TextStyle(fontWeight: FontWeight.bold)),
          fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.cancel, size: 16),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('import.subtitle'.i18n, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_result != null)
            Expanded(child: _buildResultDesktop())
          else ...[
            Row(
              children: [
                Expanded(
                  child: fluent.Button(
                    onPressed: _isImporting ? null : _pasteFromClipboard,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(fluent.FluentIcons.paste, size: 16),
                          const SizedBox(width: 8),
                          Text('import.paste'.i18n),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: fluent.Button(
                    onPressed: _isImporting ? null : _loadFromFile,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(fluent.FluentIcons.document, size: 16),
                          const SizedBox(width: 8),
                          Text('import.load-file'.i18n),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: fluent.TextBox(
                controller: _textController,
                maxLines: null,
                placeholder: 'import.text-hint'.i18n,
              ),
            ),
            const SizedBox(height: 16),
            if (_isImporting)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const fluent.ProgressBar(),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'import.progress'.i18n
                          .replaceAll('{current}', '$_currentProgress')
                          .replaceAll('{total}', '$_totalProgress'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            if (!_isImporting) ...[
              const SizedBox(height: 8),
              const _LinkGrabberTipWidget(),
            ],
          ],
        ],
      ),
      actions: _result != null
          ? [
              fluent.FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text('common.close'.i18n),
              )
            ]
          : [
              fluent.Button(
                onPressed: _isImporting ? null : () => Navigator.pop(context),
                child: Text('common.cancel'.i18n),
              ),
              if (!_isImporting)
                fluent.FilledButton(
                  onPressed: _startImport,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('import.import-button'.i18n),
                  ),
                ),
            ],
    );
  }

  Widget _buildResultDesktop() {
    return ListView(
      shrinkWrap: true,
      children: [
        Center(
          child: Text(
            'import.done-title'.i18n,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: HomeTheme.accentPink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _DesktopStatBadge(
                    icon: fluent.FluentIcons.check_mark,
                    color: Colors.green,
                    value: '${_result!.totalImported}',
                    label: 'Completados',
                  ),
                  if (_result!.totalErrors > 0)
                    _DesktopStatBadge(
                      icon: fluent.FluentIcons.error,
                      color: Colors.red,
                      value: '${_result!.totalErrors}',
                      label: 'Errores',
                    ),
                  if (_result!.totalDuplicates > 0)
                    _DesktopStatBadge(
                      icon: fluent.FluentIcons.copy,
                      color: Colors.blue,
                      value: '${_result!.totalDuplicates}',
                      label: 'Duplicados',
                    ),
                  if (_result!.totalNsfw > 0)
                    _DesktopStatBadge(
                      icon: fluent.FluentIcons.warning,
                      color: Colors.orange,
                      value: '${_result!.totalNsfw}',
                      label: 'NSFW',
                    ),
                ],
              ),
            ],
          ),
        ),
        
        if (_result!.importedByExtension.isNotEmpty) ...[
          const SizedBox(height: 32),
          const fluent.Divider(),
          const SizedBox(height: 24),
          if (_result!.importedByExtension.length == 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Column(
                  children: [
                    Icon(fluent.FluentIcons.puzzle, size: 48, color: HomeTheme.accentPink),
                    const SizedBox(height: 12),
                    Text(
                      _result!.importedByExtension.keys.first,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_result!.importedByExtension.values.first} lecturas',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._result!.importedByExtension.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                  child: Row(
                    children: [
                      const Icon(fluent.FluentIcons.puzzle, size: 20),
                      const SizedBox(width: 16),
                      Text(e.key, style: const TextStyle(fontSize: 16)),
                      const Spacer(),
                      Text('${e.value}', style: TextStyle(color: HomeTheme.accentPink, fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                )),
        ],

        if (_result!.errors.isNotEmpty) ...[
          const SizedBox(height: 24),
          const fluent.Divider(),
          const SizedBox(height: 16),
          Center(
            child: Text('LINKS FALLIDOS (${_result!.errors.length})', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _result!.errors.length,
              itemBuilder: (context, index) {
                final err = _result!.errors[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(fluent.FluentIcons.error, color: Colors.red, size: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(err.url, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(err.reason, style: const TextStyle(fontSize: 12, color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        ],
        if (_result!.limitReached) ...[
          const SizedBox(height: 24),
          fluent.InfoBar(
            title: const Text('Límite alcanzado'),
            content: Text('import.limit-reached'.i18n),
            severity: fluent.InfoBarSeverity.warning,
          ),
        ],
      ],
    );
  }
}

class _ModernOutlineBtn extends StatelessWidget {
  const _ModernOutlineBtn({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: HomeTheme.border.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: HomeTheme.textMuted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: HomeTheme.textPrimary, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: HomeTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: HomeTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.val, required this.text, required this.color});
  final IconData icon;
  final String val;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text('$val $text', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _DesktopStatBadge extends StatelessWidget {
  const _DesktopStatBadge({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkGrabberTipWidget extends StatefulWidget {
  const _LinkGrabberTipWidget();
  @override
  State<_LinkGrabberTipWidget> createState() => _LinkGrabberTipWidgetState();
}

class _LinkGrabberTipWidgetState extends State<_LinkGrabberTipWidget> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = Tween<double>(begin: 0.7, end: 1.0).animate(
    CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _launchUrl() async {
    final uri = Uri.parse('https://chromewebstore.google.com/detail/link-grabber/caodelkhipncidmoebgbbeemedohcdma?hl=es');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: HomeTheme.accentPink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    FadeTransition(
                      opacity: _pulse,
                      child: Icon(Icons.lightbulb_circle_rounded, color: HomeTheme.accentPink, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿Cómo importar listas grandes?',
                            style: TextStyle(color: HomeTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          if (!_expanded)
                            Text(
                              'Tutorial rápido (PC/Android)',
                              style: TextStyle(color: HomeTheme.textMuted, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: HomeTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              child: !_expanded ? const SizedBox.shrink() : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(color: HomeTheme.textMuted, fontSize: 13, height: 1.5),
                        children: [
                          const TextSpan(text: 'Si no quieres ir link por link, puedes usar esta extensión en tu PC o Android (si tu navegador soporta extensiones, ej. Kiwi o Lemur Browser). Ve a la página donde tienes tus mangas (como "Siguiendo" o "Favoritos") y dale clic a la extensión para extraer todos los links. ¡Pégalos arriba y deja que la magia ocurra!\n\n'),
                          TextSpan(text: '⚠️ Importante sobre tu Progreso:\n', style: TextStyle(color: HomeTheme.accentPink, fontWeight: FontWeight.bold)),
                          const TextSpan(text: '• '),
                          const TextSpan(text: 'Link Grabber (Listas): ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const TextSpan(text: 'Si pegas links que apuntan a la portada del manga, la app los agregará a tu biblioteca pero no sabrá en qué capítulo ibas.\n'),
                          const TextSpan(text: '• '),
                          const TextSpan(text: 'Link Directo: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const TextSpan(text: 'Si pegas el link directo de un capítulo exacto (ej. el que estabas leyendo), la app sí guardará tu progreso en ese capítulo.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _launchUrl,
                      icon: const Icon(Icons.extension_rounded, size: 18),
                      label: const Text('Descargar Link Grabber (Web)', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HomeTheme.accentPink.withValues(alpha: 0.15),
                        foregroundColor: HomeTheme.accentPink,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
