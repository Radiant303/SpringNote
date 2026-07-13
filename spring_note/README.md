# SpringNote application

This directory contains the Flutter desktop application and its Rust backend.
SpringNote stores notes as local Markdown files, uses Rust for indexed search,
AI-provider requests and WebDAV synchronization, and connects the two layers
with Flutter Rust Bridge.

## Development

Use Flutter 3.x with Dart 3.12 or later. Rust is required when the native
backend or generated bridge bindings change.

```sh
flutter pub get
flutter run -d windows
flutter analyze
flutter test
```

Run commands from this `spring_note/` directory. Substitute another supported
desktop device for `windows` where appropriate.

### Project layout

- `lib/features/`: page-level Flutter features such as Home, Notes, Memory and Settings.
- `lib/core/`: shared models, services, theme, widgets and app shell.
- `rust/src/`: indexed Markdown search, AI clients, cloud sync and statistics.
- `lib/src/rust/`: generated Dart bridge bindings; do not edit by hand.

### Flutter Rust Bridge

Rust APIs exposed to Flutter are declared under `rust/src/api/`. Generated Dart
and Rust bridge files live in `lib/src/rust/` and `rust/src/frb_generated.rs`.

After changing an exposed Rust type or function, regenerate the bridge from
this directory:

```sh
flutter_rust_bridge_codegen generate
```

The project pins `flutter_rust_bridge` to `2.12.0` in `pubspec.yaml`; keep the
generated bindings synchronized with that version and include regenerated files
in the same change.
