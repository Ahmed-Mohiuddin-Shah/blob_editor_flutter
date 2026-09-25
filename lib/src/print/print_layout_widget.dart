import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chrome.dart';
import 'document.dart';
import 'ops.dart';
import 'render.dart';
import 'validate.dart';

/// Drop-in print sheet editor. Host supplies sticker assets + resolve images.
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
  final Map<String, ui.Image> _images = {};
  int _gridRows = 3;
  int _gridCols = 3;
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

  void _applyPreset(PrintPage page) {
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    final platform = MediaQuery.platformBrightnessOf(context);
    final colors = BlobChromeColors.resolve(widget.themeMode, platform);
    final selected = _selected;

    return BlobGlass(
      colors: colors,
      borderRadius: _radius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.onCancel != null)
                _btn(colors, 'Cancel', widget.onCancel!),
              _btn(colors, 'A4', () => _applyPreset(pageA4())),
              _btn(colors, 'A5', () => _applyPreset(pageA5())),
              _btn(colors, 'Square', () => _applyPreset(pageCustom(210, 210))),
              Text('Grid $_gridRows×$_gridCols',
                  style: TextStyle(color: colors.muted, fontSize: 12)),
              IconButton(
                tooltip: 'Fewer rows',
                onPressed: () => setState(() => _gridRows = (_gridRows - 1).clamp(1, 8)),
                icon: const Icon(Icons.remove, size: 18),
              ),
              IconButton(
                tooltip: 'More rows',
                onPressed: () => setState(() => _gridRows = (_gridRows + 1).clamp(1, 8)),
                icon: const Icon(Icons.add, size: 18),
              ),
              IconButton(
                tooltip: 'Fewer cols',
                onPressed: () => setState(() => _gridCols = (_gridCols - 1).clamp(1, 8)),
                icon: const Icon(Icons.chevron_left, size: 18),
              ),
              IconButton(
                tooltip: 'More cols',
                onPressed: () => setState(() => _gridCols = (_gridCols + 1).clamp(1, 8)),
                icon: const Icon(Icons.chevron_right, size: 18),
              ),
              _btn(colors, 'Auto grid', () {
                setState(() {
                  _doc = layoutGrid(
                    widget.assets.map((a) => a.id).toList(),
                    _doc.page,
                    LayoutGridOptions(rows: _gridRows, columns: _gridCols),
                  );
                  _selectedId = null;
                });
              }),
              FilterChip(
                label: const Text('Cut marks'),
                selected: _doc.page.cutMarks,
                onSelected: (v) => setState(() {
                  _doc = setPrintPage(_doc, _doc.page.copyWith(cutMarks: v));
                }),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: widget.primary),
                onPressed: _busy ? null : _export,
                child: Text('Export', style: TextStyle(color: widget.onPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 88,
                  child: ListView(
                    children: [
                      Text('Stickers',
                          style: TextStyle(color: colors.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      for (final a in widget.assets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => setState(() {
                              _doc = addPrintItem(_doc, assetId: a.id);
                            }),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: colors.btnBorder),
                                  borderRadius: BorderRadius.circular(8),
                                  color: colors.btn,
                                ),
                                child: _images[a.id] != null
                                    ? RawImage(
                                        image: _images[a.id],
                                        fit: BoxFit.contain,
                                      )
                                    : Center(
                                        child: Text(
                                          a.label ?? a.id,
                                          style: TextStyle(
                                              fontSize: 10, color: colors.muted),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _stage(colors)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: selected == null
                      ? Text(
                          'Tap a sticker to move, resize, or rotate.',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Size mm',
                                style: TextStyle(
                                    color: colors.muted, fontSize: 11)),
                            Slider(
                              value: selected.widthMm.clamp(8, 200),
                              min: 8,
                              max: 200,
                              activeColor: widget.primary,
                              onChanged: (v) => setState(() {
                                _doc = resizePrintItem(_doc, selected.id, v);
                              }),
                            ),
                            Text('Rotate',
                                style: TextStyle(
                                    color: colors.muted, fontSize: 11)),
                            Slider(
                              value: selected.rotationDeg.clamp(-180, 180),
                              min: -180,
                              max: 180,
                              activeColor: widget.secondary,
                              onChanged: (v) => setState(() {
                                _doc = rotatePrintItem(_doc, selected.id, v);
                              }),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _doc = removePrintItem(_doc, selected.id);
                                _selectedId = null;
                              }),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(BlobChromeColors colors, String label, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.foreground,
        side: BorderSide(color: colors.btnBorder),
      ),
      onPressed: onTap,
      child: Text(label),
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
                        onTap: () => setState(() => _selectedId = it.id),
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
                                    ? Border.all(
                                        color: widget.primary, width: 2)
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
