import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chrome.dart';
import 'document.dart';
import 'ops.dart';
import 'render.dart';
import 'validate.dart';

enum _PrintSection { stickers, layout, transform, page }

const _sectionLabels = {
  _PrintSection.stickers: 'Stickers',
  _PrintSection.layout: 'Layout',
  _PrintSection.transform: 'Transform',
  _PrintSection.page: 'Page',
};

/// Drop-in print sheet editor. Portrait: header → ~70% stage → section nav → panel.
class PrintLayout extends StatefulWidget {
  const PrintLayout({
    super.key,
    required this.assets,
    required this.resolveAsset,
    required this.onExport,
    this.document,
    this.primary = const Color(0xFFF10EA0),
    this.secondary = const Color(0xFFE95214),
    this.onPrimary = Colors.white,
    this.onSecondary = Colors.white,
    this.blocky = false,
    this.themeMode = BlobThemeMode.system,
    this.onCancel,
  });

  final List<PrintAssetMeta> assets;
  final Future<ui.Image?> Function(String assetId) resolveAsset;
  final Map<String, dynamic>? document;
  final Color primary;
  final Color secondary;
  final Color onPrimary;
  final Color onSecondary;
  final bool blocky;
  final BlobThemeMode themeMode;
  final void Function(PrintExportPayload payload) onExport;
  final VoidCallback? onCancel;

  @override
  State<PrintLayout> createState() => _PrintLayoutState();
}

class _PrintLayoutState extends State<PrintLayout> {
  late PrintDocument _doc;
  String? _selectedId;
  _PrintSection? _section = _PrintSection.stickers;
  final Map<String, ui.Image> _images = {};
  int _gridRows = 3;
  int _gridCols = 3;
  String _preset = 'a4';
  bool _busy = false;

  BorderRadius get _radius =>
      widget.blocky ? BorderRadius.zero : BorderRadius.circular(24);

  @override
  void initState() {
    super.initState();
    if (widget.document != null) {
      try {
        _doc = validatePrintDocument(widget.document);
      } catch (_) {
        _doc = createEmptyPrintDocument(pageA4());
      }
    } else {
      _doc = createEmptyPrintDocument(pageA4());
    }
    _loadAssets();
  }

  @override
  void didUpdateWidget(covariant PrintLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assets != widget.assets) _loadAssets();
  }

  Future<void> _loadAssets() async {
    for (final a in widget.assets) {
      if (_images.containsKey(a.id)) continue;
      final img = await widget.resolveAsset(a.id);
      if (img != null && mounted) {
        setState(() => _images[a.id] = img);
      }
    }
  }

  PrintItem? get _selected =>
      _selectedId == null ? null : findPrintItem(_doc, _selectedId!);

  void _applyPreset(String kind) {
    final page = kind == 'a4'
        ? pageA4()
        : kind == 'a5'
            ? pageA5()
            : pageCustom(210, 210);
    setState(() {
      _preset = kind;
      _doc = setPrintPage(
        _doc,
        page.copyWith(
          cutMarks: _doc.page.cutMarks,
          background: _doc.page.background,
        ),
      );
    });
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final png = await renderPrintPng(_doc, (id) => _images[id], dpi: 96);
      widget.onExport(PrintExportPayload(document: _doc, previewPng: png));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSection(_PrintSection id) {
    setState(() => _section = _section == id ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final platform = MediaQuery.platformBrightnessOf(context);
    final colors = BlobChromeColors.resolve(widget.themeMode, platform);

    return BlobGlass(
      colors: colors,
      borderRadius: _radius,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(colors),
          const SizedBox(height: 8),
          Expanded(flex: 7, child: _stage(colors)),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionNav(colors),
                if (_section != null) ...[
                  const SizedBox(height: 6),
                  Expanded(child: _panel(colors)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BlobChromeColors colors) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: widget.onCancel != null
                ? IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: widget.onCancel,
                    icon: Icon(Icons.arrow_back, color: colors.foreground),
                    tooltip: 'Back',
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final e in const [
                  ('a4', 'A4'),
                  ('a5', 'A5'),
                  ('square', 'Sq'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _presetChip(colors, e.$1, e.$2),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.primary,
              foregroundColor: widget.onPrimary,
              minimumSize: const Size(72, 44),
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _export,
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(BlobChromeColors colors, String id, String label) {
    final active = _preset == id;
    return Material(
      color: active ? widget.primary : colors.btn,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _applyPreset(id),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? widget.onPrimary : colors.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionNav(BlobChromeColors colors) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final id in _PrintSection.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_sectionLabels[id]!),
                selected: _section == id,
                onSelected: (_) => _toggleSection(id),
                selectedColor: widget.primary,
                labelStyle: TextStyle(
                  color: _section == id ? widget.onPrimary : colors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel(BlobChromeColors colors) {
    return BlobGlass(
      colors: colors,
      borderRadius: BorderRadius.circular(widget.blocky ? 0 : 16),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                _sectionLabels[_section]!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: colors.foreground,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _section = null),
                child: const Text('Close'),
              ),
            ],
          ),
          Expanded(child: _panelBody(colors)),
        ],
      ),
    );
  }

  Widget _panelBody(BlobChromeColors colors) {
    switch (_section!) {
      case _PrintSection.stickers:
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final a in widget.assets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() {
                    _doc = addPrintItem(_doc, assetId: a.id);
                  }),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.btnBorder),
                        borderRadius: BorderRadius.circular(10),
                        color: colors.btn,
                      ),
                      child: _images[a.id] != null
                          ? RawImage(image: _images[a.id], fit: BoxFit.contain)
                          : Center(
                              child: Text(
                                a.label ?? a.id,
                                style: TextStyle(fontSize: 9, color: colors.muted),
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
      case _PrintSection.layout:
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _stepper(colors, 'Rows', _gridRows, (v) => setState(() => _gridRows = v)),
            const SizedBox(width: 12),
            _stepper(colors, 'Cols', _gridCols, (v) => setState(() => _gridCols = v)),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: widget.primary),
              onPressed: () => setState(() {
                _doc = layoutGrid(
                  widget.assets.map((a) => a.id).toList(),
                  _doc.page,
                  LayoutGridOptions(rows: _gridRows, columns: _gridCols),
                );
                _selectedId = null;
              }),
              child: Text('Auto grid', style: TextStyle(color: widget.onPrimary)),
            ),
          ],
        );
      case _PrintSection.transform:
        final selected = _selected;
        if (selected == null) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Select a sticker on the page',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          );
        }
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Size', style: TextStyle(color: colors.muted, fontSize: 10)),
                  Slider(
                    value: selected.widthMm.clamp(8, 200),
                    min: 8,
                    max: 200,
                    activeColor: widget.primary,
                    onChanged: (v) => setState(() {
                      _doc = resizePrintItem(_doc, selected.id, v);
                    }),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Rotate', style: TextStyle(color: colors.muted, fontSize: 10)),
                  Slider(
                    value: selected.rotationDeg.clamp(-180, 180),
                    min: -180,
                    max: 180,
                    activeColor: widget.secondary,
                    onChanged: (v) => setState(() {
                      _doc = rotatePrintItem(_doc, selected.id, v);
                    }),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _doc = removePrintItem(_doc, selected.id);
                _selectedId = null;
              }),
              child: const Text('Remove'),
            ),
          ],
        );
      case _PrintSection.page:
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            FilterChip(
              label: const Text('Cut marks'),
              selected: _doc.page.cutMarks,
              onSelected: (v) => setState(() {
                _doc = setPrintPage(_doc, _doc.page.copyWith(cutMarks: v));
              }),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                final next = _doc.page.background == 'transparent'
                    ? '#FFFFFF'
                    : 'transparent';
                _doc = setPrintPage(_doc, _doc.page.copyWith(background: next));
              }),
              child: Text(
                _doc.page.background == 'transparent' ? 'White BG' : 'Clear BG',
              ),
            ),
          ],
        );
    }
  }

  Widget _stepper(
    BlobChromeColors colors,
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: colors.muted, fontSize: 11)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged((value - 1).clamp(1, 8)),
          icon: const Icon(Icons.remove, size: 18),
        ),
        Text('$value', style: TextStyle(color: colors.foreground)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged((value + 1).clamp(1, 8)),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }

  Widget _stage(BlobChromeColors colors) {
    final page = _doc.page;
    Color? bg;
    if (page.background != 'transparent') {
      final hex = page.background.replaceFirst('#', '');
      if (hex.length == 6) bg = Color(int.parse('FF$hex', radix: 16));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final aspect = page.widthMm / page.heightMm;
        var w = maxW;
        var h = w / aspect;
        if (h > maxH) {
          h = maxH;
          w = h * aspect;
        }
        final mmPerPx = page.widthMm / w;

        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bg ?? Colors.white,
                border: Border.all(color: colors.glassBorder),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final it in _doc.items)
                    Positioned(
                      left: (it.xMm / page.widthMm) * w,
                      top: (it.yMm / page.heightMm) * h,
                      width: (it.widthMm / page.widthMm) * w,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedId = it.id;
                          _section ??= _PrintSection.transform;
                        }),
                        onPanUpdate: (d) {
                          final cur = findPrintItem(_doc, it.id);
                          if (cur == null) return;
                          setState(() {
                            _selectedId = it.id;
                            _doc = movePrintItem(
                              _doc,
                              it.id,
                              cur.xMm + d.delta.dx * mmPerPx,
                              cur.yMm + d.delta.dy * mmPerPx,
                            );
                          });
                        },
                        child: Transform.rotate(
                          angle: it.rotationDeg * 3.141592653589793 / 180,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: _selectedId == it.id
                                    ? Border.all(color: widget.primary, width: 2)
                                    : null,
                              ),
                              child: _images[it.assetId] != null
                                  ? RawImage(
                                      image: _images[it.assetId],
                                      fit: BoxFit.contain,
                                    )
                                  : const ColoredBox(color: Colors.black12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (page.cutMarks)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _MarginPainter(page)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MarginPainter extends CustomPainter {
  _MarginPainter(this.page);
  final PrintPage page;

  @override
  void paint(Canvas canvas, Size size) {
    final m = page.marginMm;
    final paint = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromLTRB(
      (m.left / page.widthMm) * size.width,
      (m.top / page.heightMm) * size.height,
      size.width - (m.right / page.widthMm) * size.width,
      size.height - (m.bottom / page.heightMm) * size.height,
    );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _MarginPainter old) => old.page != page;
}
