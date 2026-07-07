import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spring_note/core/models/wallpaper_settings.dart';
import 'package:spring_note/core/services/wallpaper_service.dart';

void main() {
  group('WallpaperService.resolveAbsolutePath', () {
    test('returns null when imagePath is null', () {
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        clearImagePath: true,
      );
      expect(
        WallpaperService.resolveAbsolutePath(
          settings: settings,
          dataDirectory: '/tmp/data',
        ),
        isNull,
      );
    });

    test('returns null when imagePath is empty', () {
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        imagePath: '',
      );
      expect(
        WallpaperService.resolveAbsolutePath(
          settings: settings,
          dataDirectory: '/tmp/data',
        ),
        isNull,
      );
    });

    test('joins relative path under dataDirectory', () {
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        imagePath: p.join('wallpapers', 'wallpaper_1.png'),
      );
      expect(
        WallpaperService.resolveAbsolutePath(
          settings: settings,
          dataDirectory: '/tmp/data',
        ),
        p.join('/tmp/data', 'wallpapers', 'wallpaper_1.png'),
      );
    });

    test('returns absolute path as-is', () {
      const abs = r'C:\Users\me\appdata\wallpapers\wallpaper_1.png';
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        imagePath: abs,
      );
      expect(
        WallpaperService.resolveAbsolutePath(
          settings: settings,
          dataDirectory: '/tmp/data',
        ),
        abs,
      );
    });
  });

  group('WallpaperService.validateOnLoad', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wallpaper_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns settings unchanged when mode is not image', () async {
      const settings = WallpaperSettings.defaults;
      final result = await WallpaperService.validateOnLoad(
        settings: settings,
        dataDirectory: tempDir.path,
      );
      expect(result, settings);
    });

    test('falls back to defaults when imagePath is null', () async {
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        clearImagePath: true,
      );
      final result = await WallpaperService.validateOnLoad(
        settings: settings,
        dataDirectory: tempDir.path,
      );
      expect(result, WallpaperSettings.defaults);
    });

    test('falls back to defaults when file is missing', () async {
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        imagePath: 'wallpapers/missing.png',
      );
      final result = await WallpaperService.validateOnLoad(
        settings: settings,
        dataDirectory: tempDir.path,
      );
      expect(result, WallpaperSettings.defaults);
    });

    test('returns settings unchanged when file exists', () async {
      final subDir = Directory(p.join(tempDir.path, 'wallpapers'))
        ..createSync(recursive: true);
      final image = File(p.join(subDir.path, 'wallpaper_1.png'))
        ..writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);

      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        imagePath: p.relative(image.path, from: tempDir.path),
      );
      final result = await WallpaperService.validateOnLoad(
        settings: settings,
        dataDirectory: tempDir.path,
      );
      expect(result, settings);
    });
  });

  group('WallpaperService.adoptImage', () {
    late Directory tempDir;
    late Directory wallpaperDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wallpaper_adopt_');
      wallpaperDir = Directory(p.join(tempDir.path, 'wallpapers'))
        ..createSync(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> makeSourceImage(String name) async {
      final srcDir = await Directory.systemTemp.createTemp('wallpaper_src_');
      addTearDown(() async {
        if (await srcDir.exists()) {
          await srcDir.delete(recursive: true);
        }
      });
      final src = File(p.join(srcDir.path, name))
        ..writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
      return src;
    }

    test('throws when source file does not exist', () async {
      final settings = WallpaperSettings.defaults;
      expect(
        () => WallpaperService.adoptImage(
          sourceFile: File(p.join(tempDir.path, 'nope.png')),
          current: settings,
          dataDirectory: tempDir.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws on unsupported extension', () async {
      final src = await makeSourceImage('bad.txt');
      expect(
        () => WallpaperService.adoptImage(
          sourceFile: src,
          current: WallpaperSettings.defaults,
          dataDirectory: tempDir.path,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('copies file, returns image mode, prunes old wallpapers', () async {
      // Seed two old wallpaper_* files plus an unrelated file.
      final oldA = File(p.join(wallpaperDir.path, 'wallpaper_oldA.jpg'))
        ..writeAsBytesSync(const [0x01]);
      final oldB = File(p.join(wallpaperDir.path, 'wallpaper_oldB.jpg'))
        ..writeAsBytesSync(const [0x02]);
      final preserved = File(p.join(wallpaperDir.path, 'user_data.bin'))
        ..writeAsBytesSync(const [0x03]);

      final src = await makeSourceImage('fresh.png');
      final settings = WallpaperSettings.defaults.copyWith(
        mode: WallpaperMode.image,
        imagePath: 'wallpapers/wallpaper_oldA.jpg',
      );

      final result = await WallpaperService.adoptImage(
        sourceFile: src,
        current: settings,
        dataDirectory: tempDir.path,
      );

      // Result is image mode with relative imagePath under dataDirectory.
      expect(result.mode, WallpaperMode.image);
      expect(result.imagePath, isNotNull);
      expect(p.isAbsolute(result.imagePath!), isFalse);
      expect(p.dirname(result.imagePath!), 'wallpapers');

      // The new file exists on disk.
      final newFile = File(p.join(tempDir.path, result.imagePath!));
      expect(await newFile.exists(), isTrue);

      // Old wallpaper files were pruned, but the unrelated file was kept.
      expect(await oldA.exists(), isFalse);
      expect(await oldB.exists(), isFalse);
      expect(await preserved.exists(), isTrue);
    });

    test('alsoKeepPath prevents that file from being pruned', () async {
      // Use a path that mimics "the other widget's current wallpaper".
      final keepMe = File(p.join(wallpaperDir.path, 'wallpaper_keep.jpg'))
        ..writeAsBytesSync(const [0x42]);
      final oldOther = File(p.join(wallpaperDir.path, 'wallpaper_old.jpg'))
        ..writeAsBytesSync(const [0x07]);

      final src = await makeSourceImage('new.png');
      final result = await WallpaperService.adoptImage(
        sourceFile: src,
        current: WallpaperSettings.defaults,
        dataDirectory: tempDir.path,
        alsoKeepPath: keepMe.path,
      );

      expect(await keepMe.exists(), isTrue);
      expect(await oldOther.exists(), isFalse);

      // Sanity: new file is also there.
      expect(
        await File(p.join(tempDir.path, result.imagePath!)).exists(),
        isTrue,
      );
    });
  });

  group('WallpaperService.clearImageFiles', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wallpaper_clear_');
      await Directory(
        p.join(tempDir.path, 'wallpapers'),
      ).create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('removes only wallpaper_ prefixed files', () async {
      final wp1 = File(p.join(tempDir.path, 'wallpapers', 'wallpaper_1.jpg'))
        ..writeAsBytesSync(const [0x01]);
      final wp2 = File(p.join(tempDir.path, 'wallpapers', 'wallpaper_2.png'))
        ..writeAsBytesSync(const [0x02]);
      final keep = File(p.join(tempDir.path, 'wallpapers', 'cover.jpg'))
        ..writeAsBytesSync(const [0x03]);
      final readme = File(p.join(tempDir.path, 'wallpapers', 'README'))
        ..writeAsBytesSync(const [0x04]);

      await WallpaperService.clearImageFiles(tempDir.path);

      expect(await wp1.exists(), isFalse);
      expect(await wp2.exists(), isFalse);
      expect(await keep.exists(), isTrue);
      expect(await readme.exists(), isTrue);
    });

    test('is a no-op when wallpapers directory does not exist', () async {
      // tempDir exists but has no wallpapers/ subdir.
      await Directory(p.join(tempDir.path, 'wallpapers')).delete();
      await WallpaperService.clearImageFiles(tempDir.path);
      // No exception means success.
      expect(
        await Directory(p.join(tempDir.path, 'wallpapers')).exists(),
        isFalse,
      );
    });
  });
}
