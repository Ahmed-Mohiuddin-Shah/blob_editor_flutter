import 'dart:ui' as ui;

import 'package:blob_editor/blob_editor.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const BlobEditorDemo());
}

enum _DemoMode { pick, composition, print }

/// Screen size + system safe insets. Background paints full-bleed; pad content.
class DemoScreen {
  DemoScreen(this.size, this.safe);

  factory DemoScreen.of(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    return DemoScreen(
      mq?.size ?? Size.zero,
      mq?.padding ?? EdgeInsets.zero,
    );
  }

  final Size size;
  final EdgeInsets safe;

  bool get isLandscape => size.width > size.height;

  EdgeInsets pad({
    double horizontal = 16,
    double topExtra = 0,
    double bottomExtra = 0,
  }) =>
      EdgeInsets.fromLTRB(
        safe.left + horizontal,
        safe.top + topExtra,
        safe.right + horizontal,
        safe.bottom + bottomExtra,
      );
}

class BlobEditorDemo extends StatefulWidget {
  const BlobEditorDemo({super.key});

  @override
  State<BlobEditorDemo> createState() => _BlobEditorDemoState();
}

class _BlobEditorDemoState extends State<BlobEditorDemo> {
  BlobThemeMode _themeMode = BlobThemeMode.system;
  _DemoMode _mode = _DemoMode.pick;

  @override
  Widget build(BuildContext context) {
    final dark = _themeMode == BlobThemeMode.dark ||
        (_themeMode == BlobThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    return MaterialApp(
      title: 'blob_editor example',
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF10EA0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF10EA0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _Home(
        themeMode: _themeMode,
        mode: _mode,
        onThemeMode: (m) => setState(() => _themeMode = m),
        onMode: (m) => setState(() => _mode = m),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({
    required this.themeMode,
    required this.mode,
    required this.onThemeMode,
    required this.onMode,
  });

  final BlobThemeMode themeMode;
  final _DemoMode mode;
  final ValueChanged<BlobThemeMode> onThemeMode;
  final ValueChanged<_DemoMode> onMode;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  String _log = '';
  Map<String, ui.Image>? _demoImages;

  static const _demoColors = <String, Color>{
    'pink': Color(0xFFF10EA0),
    'orange': Color(0xFFE95214),
    'teal': Color(0xFF0AABB5),
    'violet': Color(0xFF7C3AED),
    'lime': Color(0xFF84CC16),
    'sky': Color(0xFF38BDF8),
  };

  @override
  void initState() {
    super.initState();
    _bakeDemoStickers();
  }

  Future<void> _bakeDemoStickers() async {
    final out = <String, ui.Image>{};
    for (final e in _demoColors.entries) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = e.value;
      canvas.drawCircle(const Offset(64, 64), 60, paint);
      paint
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      canvas.drawCircle(const Offset(64, 64), 60, paint);
      final picture = recorder.endRecording();
      out[e.key] = await picture.toImage(128, 128);
    }
    if (mounted) setState(() => _demoImages = out);
  }

  @override
  Widget build(BuildContext context) {
    final screen = DemoScreen.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pad = screen.pad(topExtra: kToolbarHeight, horizontal: 16);
    final title = switch (widget.mode) {
      _DemoMode.pick => 'blob editor',
      _DemoMode.composition => 'composition',
      _DemoMode.print => 'print layout',
    };

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        title: Text(title),
        leading: widget.mode != _DemoMode.pick
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _log = '');
                  widget.onMode(_DemoMode.pick);
                },
              )
            : null,
        backgroundColor: dark
            ? const Color(0x991A1A1A)
            : const Color(0x99FFFFFF),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.8),
                radius: 1.2,
                colors: dark
                    ? const [Color(0x59F10EA0), Color(0x000A0A0A)]
                    : const [Color(0x33F10EA0), Color(0x00F5F5F5)],
              ),
              color: dark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
            ),
          ),
          Padding(
            padding: pad,
            child: switch (widget.mode) {
              _DemoMode.pick => _picker(dark),
              _DemoMode.composition => screen.isLandscape
                  ? _compositionLandscape(dark)
                  : _compositionPortrait(dark),
              _DemoMode.print => _printBody(dark),
            },
          ),
        ],
      ),
    );
  }

  Widget _picker(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose an editor',
          style: TextStyle(color: dark ? Colors.white70 : Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final m in BlobThemeMode.values)
              ChoiceChip(
                label: Text(m.name),
                selected: widget.themeMode == m,
                onSelected: (_) => widget.onThemeMode(m),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => widget.onMode(_DemoMode.composition),
          child: const Text('Composition — 1024² sticker editor'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => widget.onMode(_DemoMode.print),
          child: const Text('Print layout — A4 / pack stickers'),
        ),
      ],
    );
  }

  Widget _editor() {
    return BlobEditor(
      blocky: false,
      themeMode: widget.themeMode,
      primary: const Color(0xFFF10EA0),
      secondary: const Color(0xFFE95214),
      onCancel: () => widget.onMode(_DemoMode.pick),
      onExport: (payload) {
        setState(() {
          _log =
              'bg=${payload.background}\n'
              'chat=${payload.chat.length}B\n'
              'thumbnail=${payload.thumbnail.length}B\n'
              'full=${payload.full.length}B\n'
              'mask=${payload.mask?.length ?? 0}B\n'
              'objects=${payload.document.objects.length}';
        });
      },
    );
  }

  Widget _compositionChrome(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick an image → edit → Export returns document + PNGs',
          style: TextStyle(color: dark ? Colors.white70 : Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final m in BlobThemeMode.values)
              ChoiceChip(
                label: Text(m.name),
                selected: widget.themeMode == m,
                onSelected: (_) => widget.onThemeMode(m),
              ),
          ],
        ),
      ],
    );
  }

  Widget _compositionPortrait(bool dark) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _compositionChrome(dark),
        const SizedBox(height: 16),
        _editor(),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_log, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ],
    );
  }

  Widget _compositionLandscape(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                for (final m in BlobThemeMode.values)
                  ChoiceChip(
                    label: Text(m.name),
                    selected: widget.themeMode == m,
                    onSelected: (_) => widget.onThemeMode(m),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _editor()),
      ],
    );
  }

  Widget _printBody(bool dark) {
    final images = _demoImages;
    if (images == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add stickers · Auto grid · Export document + preview PNG',
          style: TextStyle(color: dark ? Colors.white70 : Colors.black54),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PrintLayout(
            themeMode: widget.themeMode,
            assets: [
              for (final e in _demoColors.entries)
                PrintAssetMeta(id: e.key, label: e.key),
            ],
            resolveAsset: (id) async => images[id],
            onCancel: () => widget.onMode(_DemoMode.pick),
            onExport: (payload) {
              setState(() {
                _log =
                    'preview=${payload.previewPng.length}B\n'
                    'items=${payload.document.items.length}\n'
                    'page=${payload.document.page.widthMm}×${payload.document.page.heightMm}mm';
              });
            },
          ),
        ),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ],
    );
  }
}
