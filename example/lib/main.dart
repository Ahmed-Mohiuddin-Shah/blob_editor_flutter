import 'dart:ui';

import 'package:blob_editor/blob_editor.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const BlobEditorDemo());
}

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

  /// Insets for interactive content. Decoration stay behind via Stack.
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

  double contentHeight({double topExtra = 0, double bottomExtra = 0}) =>
      (size.height - safe.top - topExtra - safe.bottom - bottomExtra)
          .clamp(0.0, size.height);
}

class BlobEditorDemo extends StatefulWidget {
  const BlobEditorDemo({super.key});

  @override
  State<BlobEditorDemo> createState() => _BlobEditorDemoState();
}

class _BlobEditorDemoState extends State<BlobEditorDemo> {
  BlobThemeMode _themeMode = BlobThemeMode.system;

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
        onThemeMode: (m) => setState(() => _themeMode = m),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.themeMode, required this.onThemeMode});

  final BlobThemeMode themeMode;
  final ValueChanged<BlobThemeMode> onThemeMode;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  String _log = '';

  @override
  Widget build(BuildContext context) {
    final screen = DemoScreen.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pad = screen.pad(topExtra: kToolbarHeight, horizontal: 16);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        title: const Text('blob editor'),
        backgroundColor: dark
            ? const Color(0x991A1A1A)
            : const Color(0x99FFFFFF),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed — draws behind status bar / nav / app bar.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.8),
                radius: 1.2,
                colors: dark
                    ? const [
                        Color(0x59F10EA0),
                        Color(0x000A0A0A),
                      ]
                    : const [
                        Color(0x33F10EA0),
                        Color(0x00F5F5F5),
                      ],
              ),
              color: dark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
            ),
          ),
          Padding(
            padding: pad,
            child: screen.isLandscape
                ? _landscapeBody(dark)
                : _portraitBody(dark),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    return BlobEditor(
      blocky: false,
      themeMode: widget.themeMode,
      primary: const Color(0xFFF10EA0),
      secondary: const Color(0xFFE95214),
      onCancel: () => setState(() => _log = 'cancelled'),
      onExport: (payload) {
        setState(() {
          _log =
              'bg=${payload.background}\n'
              'chat=${payload.chat.length}B\n'
              'thumbnail=${payload.thumbnail.length}B\n'
              'full=${payload.full.length}B\n'
              'objects=${payload.document.objects.length}';
        });
      },
    );
  }

  Widget _chrome(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick an image → edit → Export returns '
          'document + chat/thumbnail/full PNGs',
          style: TextStyle(
            color: dark ? Colors.white70 : Colors.black54,
          ),
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

  Widget _portraitBody(bool dark) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _chrome(dark),
        const SizedBox(height: 16),
        _editor(),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_log, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ],
    );
  }

  Widget _landscapeBody(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact chrome so the editor can own the remaining height.
        SizedBox(
          height: 36,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final m in BlobThemeMode.values)
                  ChoiceChip(
                    label: Text(m.name),
                    selected: widget.themeMode == m,
                    onSelected: (_) => widget.onThemeMode(m),
                    visualDensity: VisualDensity.compact,
                  ),
                if (_log.isNotEmpty)
                  Text(
                    _log.split('\n').first,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
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
}
