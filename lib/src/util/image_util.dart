import "dart:async";
import "dart:convert" show utf8;
import "dart:developer" show log;
import "dart:io" show Directory, File, FileSystemException;
import "dart:typed_data" show Uint8List;

import "package:crypto/crypto.dart" show sha256;
import "package:path_provider/path_provider.dart" show getTemporaryDirectory;

class ImageUtil {
  // todo: maxCacheCount or maxCacheSize 도입
  static final Map<String, String> _hashPathMap = {};
  static final Map<String, Future<String>> _inflightSaveByKey = {};

  static Future<Directory>? _imageTempDirInitFuture;
  static Directory? _imageTempDir;

  static Future<String> saveImage(
    Uint8List bytes, [
    String? cacheKey,
  ]) async {
    if (bytes.isEmpty) {
      throw StateError("ImageUtil.saveImage: image bytes is empty");
    }

    final key = cacheKey ?? _generateImageHashFromBytes(bytes);
    final cachedPath = _hashPathMap[key];

    if (cachedPath != null && await _isValidImageFilePath(cachedPath)) {
      log("이미 저장된 이미지입니다. 저장된 path를 반환합니다. $cachedPath",
          name: "ImageSaveUtil");
      return cachedPath;
    }

    if (cachedPath != null) {
      _hashPathMap.remove(key);
    }

    final inflight = _inflightSaveByKey[key];
    if (inflight != null) {
      return await inflight;
    }

    final future = _saveImageInternal(key, bytes);
    _inflightSaveByKey[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inflightSaveByKey[key], future)) {
        _inflightSaveByKey.remove(key);
      }
    }
  }

  static Future<String> _saveImageInternal(String key, Uint8List bytes) async {
    final path = await _makeFile(key, bytes);
    _hashPathMap[key] = path;
    return path;
  }

  /* ----- Hashing ----- */

  static String _generateImageHashFromBytes(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /* ----- File ----- */

  static Future<String> _makeFile(String key, Uint8List bytes) async {
    final tempDirPath = await _getDir().then((d) => d.path);
    final hashedKey = sha256.convert(utf8.encode(key)).toString();
    final finalPath = "$tempDirPath/$hashedKey.png";
    final tempPath =
        "$tempDirPath/$hashedKey.tmp_${DateTime.now().microsecondsSinceEpoch}.png";

    File? tempFile;
    try {
      tempFile = await File(tempPath).writeAsBytes(bytes, flush: true);
      final writtenLength = await tempFile.length();
      if (writtenLength <= 0) {
        throw StateError(
            "ImageUtil._makeFile: written temp file size is zero. path=$tempPath");
      }

      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }

      final movedFile = await tempFile.rename(finalPath);
      final finalLength = await movedFile.length();
      if (finalLength <= 0) {
        throw StateError(
            "ImageUtil._makeFile: final file size is zero. path=$finalPath");
      }

      return movedFile.path;
    } on FileSystemException catch (e) {
      log("저장중 오류가 발생했습니다. 메시지: ${e.message}", name: "ImageSaveUtil");
      rethrow;
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  static Future<bool> _isValidImageFilePath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      return await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<Directory> _getDir() async {
    final cached = _imageTempDir;
    if (cached != null) return cached;

    final inflight = _imageTempDirInitFuture;
    if (inflight != null) {
      final dir = await inflight;
      _imageTempDir = dir;
      return dir;
    }

    final initFuture = _initTempDir();
    _imageTempDirInitFuture = initFuture;
    try {
      final dir = await initFuture;
      _imageTempDir = dir;
      return dir;
    } finally {
      _imageTempDirInitFuture = null;
    }
  }

  static Future<Directory> _initTempDir() async {
    final tempDir = await getTemporaryDirectory();
    final targetFolderDir = Directory("${tempDir.path}/$_newTempFolderPath");
    await _cleanUpLegacyTempDir(targetFolderDir);
    await _cleanUpPreviousTempDir(targetFolderDir);
    final imageTempDirParent = await targetFolderDir.create();
    final imageTempDir = await imageTempDirParent.createTemp(_newPathPrefix);
    return imageTempDir;
  }

  static Future<void> _cleanUpPreviousTempDir(Directory imgTempDir) async {
    if (!(await imgTempDir.exists())) return; // guard.

    final previousCacheFolderStream = imgTempDir.list();
    final previousCacheFolders = await previousCacheFolderStream.toList();

    for (final folder in previousCacheFolders) {
      if (folder case Directory(:final path)) {
        unawaited(_deleteDirectorySafely(folder, path: path)); // not wait.
      }
    }
  }

  static Future<void> _cleanUpLegacyTempDir(Directory newCacheFolderDir) async {
    // new version folder detected. return fast.
    if (await newCacheFolderDir.exists()) return;

    final tempDir = await getTemporaryDirectory();
    final subDirSteam = tempDir.list();

    await for (final dir in subDirSteam) {
      if (dir case Directory(:final path)) {
        final name = path.split("/").last;
        if (name.startsWith(_oldV1PathPrefix)) {
          unawaited(_deleteDirectorySafely(dir, path: path)); // not wait.
        }
      }
    }
  }

  static Future<void> _deleteDirectorySafely(
    Directory dir, {
    required String path,
  }) async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      log(
        "임시 폴더 삭제 중 오류가 발생했습니다. 경로: $path, 메시지: ${e.message}",
        name: "ImageSaveUtil",
      );
    } catch (e) {
      log("임시 폴더 삭제 중 오류가 발생했습니다. 경로: $path, 오류: $e",
          name: "ImageSaveUtil");
    }
  }

  /// using <= 1.4.2
  static const _oldV1PathPrefix = "img_";

  /// currently using (1.4.3~)
  static const _newTempFolderPath = "fnm1_img";
  static const _newPathPrefix = "fnm1_img_";
}
