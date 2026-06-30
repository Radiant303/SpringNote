# spring_note

A new Flutter project.

## Development Notes

### Flutter Rust Bridge

Rust APIs exposed to Flutter are declared under `rust/src/`, with generated
Dart and Rust bridge files written to `lib/src/rust/` and
`rust/src/frb_generated.rs`.

After changing exposed Rust types or functions, regenerate the bridge from the
`spring_note/` directory:

```sh
flutter_rust_bridge_codegen generate
```

This project currently pins `flutter_rust_bridge` to `2.12.0` in
`pubspec.yaml`; keep the generated files synchronized with that version.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
