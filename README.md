# Dialogue

Local-first chat simulator with a shared **Rust** core (`SQLite3`), **Tauri** desktop app (Windows, React + TypeScript + Tailwind CSS + SmoothUI-inspired animations), and **Flutter** mobile app (Android).

## Structure

- `core/` (`dialogue_core`): Shared Rust core (SQLite3 persistence, characters, 1-on-1 & group chats, messages with edit/delete/reply, LAN mDNS discovery, QR pairing, bidirectional LWW sync, `.zip` backup export/import, and C-ABI FFI for Flutter).
- `desktop/`: Tauri v2 + React + Tailwind CSS desktop app.
- `mobile/`: Flutter Android app consuming `dialogue_core` via `dart:ffi`.

## Running Tests (Rust Core)

```powershell
cargo test --package dialogue_core
```

## Running Desktop (Tauri)

```powershell
cd desktop
pnpm install
pnpm tauri dev
```

## Building & Running Mobile (Flutter + Android)

1. Build `libdialogue_core.so` for Android ABIs using `cargo-ndk` (into `mobile/android/app/src/main/jniLibs/`):

```powershell
cargo install cargo-ndk
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o mobile/android/app/src/main/jniLibs build --release -p dialogue_core
```

2. Run Flutter:

```powershell
cd mobile
flutter pub get
flutter run
```
