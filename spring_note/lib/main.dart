import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/desktop_window_controller.dart';
import 'core/services/indexed_note_service.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindowController.initializeAndShow();
  await RustLib.init();
  runApp(const SpringNoteApp(noteService: IndexedNoteService()));
}
