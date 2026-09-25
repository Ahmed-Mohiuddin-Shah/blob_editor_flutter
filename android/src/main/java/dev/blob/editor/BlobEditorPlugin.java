package dev.blob.editor;

import android.graphics.Bitmap;
import android.media.MediaMetadataRetriever;
import android.os.Handler;
import android.os.Looper;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.ByteArrayOutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** AGP9-safe video frame extract. Reuses retriever; work runs off the UI thread. */
public class BlobEditorPlugin implements FlutterPlugin, MethodCallHandler {
  private MethodChannel channel;
  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private final Handler main = new Handler(Looper.getMainLooper());
  private MediaMetadataRetriever retriever;
  private String openPath;

  @Override
  public void onAttachedToEngine(FlutterPlugin.FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), "blob_editor/video_poster");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if ("durationMs".equals(call.method)) {
      durationMs(call, result);
      return;
    }
    if ("release".equals(call.method)) {
      releaseRetriever();
      result.success(null);
      return;
    }
    if (!"posterPng".equals(call.method)) {
      result.notImplemented();
      return;
    }
    final String path = call.argument("path");
    if (path == null || path.isEmpty()) {
      result.error("bad_args", "path required", null);
      return;
    }
    Integer maxWidthArg = call.argument("maxWidth");
    final int maxWidth = maxWidthArg != null ? maxWidthArg : 480;
    Number timeMsArg = call.argument("timeMs");
    final long timeUs =
        timeMsArg != null ? Math.max(0, (long) (timeMsArg.doubleValue() * 1000.0)) : 0L;
    Boolean accurateArg = call.argument("accurate");
    final boolean accurate = accurateArg == null || accurateArg;

    executor.execute(
        () -> {
          try {
            ensureRetriever(path);
            // accurate → CLOSEST (nearest frame); play preview → CLOSEST_SYNC (keyframes, faster)
            final int option =
                accurate
                    ? MediaMetadataRetriever.OPTION_CLOSEST
                    : MediaMetadataRetriever.OPTION_CLOSEST_SYNC;
            Bitmap frame = retriever.getFrameAtTime(timeUs, option);
            if (frame == null && accurate) {
              frame =
                  retriever.getFrameAtTime(
                      timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
            }
            if (frame == null) {
              frame = retriever.getFrameAtTime();
            }
            if (frame == null) {
              main.post(() -> result.error("no_frame", "could not decode video frame", null));
              return;
            }
            Bitmap scaled = scaleDown(frame, maxWidth);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            final int quality = accurate ? 75 : 55;
            scaled.compress(Bitmap.CompressFormat.JPEG, quality, out);
            if (scaled != frame) {
              scaled.recycle();
            }
            frame.recycle();
            final byte[] bytes = out.toByteArray();
            main.post(() -> result.success(bytes));
          } catch (Exception e) {
            releaseRetriever();
            main.post(() -> result.error("poster_failed", e.getMessage(), null));
          }
        });
  }

  private synchronized void ensureRetriever(String path) {
    if (retriever != null && path.equals(openPath)) {
      return;
    }
    releaseRetriever();
    retriever = new MediaMetadataRetriever();
    retriever.setDataSource(path);
    openPath = path;
  }

  private synchronized void releaseRetriever() {
    if (retriever != null) {
      try {
        retriever.release();
      } catch (Exception ignored) {
      }
      retriever = null;
      openPath = null;
    }
  }

  private void durationMs(MethodCall call, Result result) {
    final String path = call.argument("path");
    if (path == null || path.isEmpty()) {
      result.error("bad_args", "path required", null);
      return;
    }
    executor.execute(
        () -> {
          try {
            ensureRetriever(path);
            String d = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
            long ms = d != null ? Long.parseLong(d) : 0L;
            Map<String, Object> map = new HashMap<>();
            map.put("durationMs", ms);
            main.post(() -> result.success(map));
          } catch (Exception e) {
            releaseRetriever();
            main.post(() -> result.error("duration_failed", e.getMessage(), null));
          }
        });
  }

  private static Bitmap scaleDown(Bitmap src, int maxWidth) {
    if (src.getWidth() <= maxWidth) {
      return src;
    }
    int h = Math.max(1, (int) (src.getHeight() * (maxWidth / (float) src.getWidth())));
    return Bitmap.createScaledBitmap(src, maxWidth, h, true);
  }

  @Override
  public void onDetachedFromEngine(FlutterPlugin.FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    releaseRetriever();
    executor.shutdownNow();
  }
}
