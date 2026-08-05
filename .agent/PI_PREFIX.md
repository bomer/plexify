# Pi — standing instructions for Plexify

Prepend this whole file to every task. The task itself goes at the end, under **TASK**.

---

## What you are working on

Plexify is a Flutter music player for a personal Plex server. It runs on Windows desktop and
Android from one codebase. It is written in Dart.

You handle **small, contained UI and presentation changes**: labels, spacing, icons, tooltips,
empty states, sort options, showing a value that is already available. Anything larger is
handed back — see *When to stop*.

Repository root: `C:\dev\plexify`

---

## Hard rules

1. **Change as little as possible.** Fix the thing asked for. Do not tidy, rename, reformat or
   "improve" anything else, even if it looks wrong. Unrelated changes will be rejected.
2. **Never edit a file ending in `.g.dart`.** These are generated. Editing them silently
   breaks the build.
3. **Never edit `pubspec.yaml`.** Do not add packages. If a task seems to need a new package,
   stop and hand back.
4. **Never run `dart run build_runner build`.**
5. **Do not commit.** Leave changes in the working tree unless told otherwise.
6. **Do not delete files.**
7. If a rule here conflicts with the task, follow the rule and say so.

## Where you may work

**Allowed:**

```
lib/features/**      screens and widgets
lib/shell/**          navigation scaffold, sidebar, layout
```

**Ask first — do not edit without being told explicitly:**

```
lib/core/providers.dart     the provider graph
lib/core/plex/**            Plex API client
```

**Never:**

```
lib/core/db/**        database schema — needs codegen
lib/core/sync/**       sync engine — subtle and heavily tested
lib/core/audio/**      playback and reporting
windows/**             C++ runner
android/**             Gradle and manifests
**/*.g.dart            generated
```

---

## Commands

Use the full path to Flutter. Do not rely on `flutter` being on PATH — it is not.

Check the code compiles and is clean. **This must pass before you finish:**

```bash
C:/Users/James/flutter-sdk/flutter/bin/flutter.bat analyze
```

Run the tests. **This must pass before you finish:**

```bash
C:/Users/James/flutter-sdk/flutter/bin/flutter.bat test
```

Format what you changed. Note this one is `dart`, not `flutter` — there is no
`flutter format` command:

```bash
C:/Users/James/flutter-sdk/flutter/bin/dart.bat format lib
```

If you are in a shell whose working directory looks like `\\wsl.localhost\...`, run
`cd C:/dev/plexify` first. Flutter cannot run from that path.

Do not run `flutter run` or `flutter build`. They are slow and need a device.

---

## How the code is written

**State comes from Riverpod, declared by hand.** There is no code generation for providers.
A widget reads state like this:

```dart
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    ...
  }
}
```

Use `ConsumerWidget` and `ref.watch(...)` to read. Use `ref.read(...)` inside callbacks like
`onPressed`. Providers live in `lib/core/providers.dart` — read them, do not add to them
without being asked.

**Comments say why, not what.** Do not write `// increment the counter`. Write a comment only
when the code would look arbitrary or wrong without it, and explain the reason.

```dart
// Remaining rather than total — more useful mid-track.
'-${_format(total - position)}'
```

**Use the theme, never hard-coded colours.**

```dart
final theme = Theme.of(context);
style: theme.textTheme.bodySmall?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
)
```

Never write `Colors.grey`, `Color(0xFF...)` or a literal font size. The app supports light and
dark; hard-coded colours break one of them.

**Match the file you are editing.** Its spacing, naming and comment density are the target.

---

## Gotchas that bite UI work here

- **Phone vs desktop is decided by width, not platform.** Use `isCompactLayout(context)` from
  `lib/shell/layout.dart`. Never use `Platform.isAndroid` for layout — a narrow desktop window
  has the same problem a phone does.
- **Artwork always goes through the `Artwork` widget** (`lib/features/library/artwork.dart`).
  It handles the missing-image and failed-load cases. Do not write `Image.network` yourself.
- **Pull-to-refresh does nothing on desktop.** A mouse wheel produces no drag. If you add a
  refresh gesture, there must also be a button.
- **Lists can be very long** — tens of thousands of tracks. Use `ListView.builder`, never
  `ListView(children: [...])` for library data.
- **Text from the library needs `maxLines` and `overflow: TextOverflow.ellipsis`.** Album and
  track titles are arbitrarily long and will overflow.

---

## When to stop and hand back

Stop, change nothing, and explain what you found if any of these are true:

- The task needs a new package, a database column, or a change to the sync or audio code.
- The task needs a new provider, or a change to how data is fetched from Plex.
- `flutter analyze` reports an error you cannot fix in the files you are allowed to touch.
- A test fails and the fix is not obviously in your change.
- The task is ambiguous and two readings would produce different code.
- You have tried the same fix twice and it has not worked.

Handing back is a correct outcome, not a failure. Guessing is worse than stopping. Say plainly
which of the above applies and what you would need.

---

## Before you say you are done

Confirm each of these. Do not claim done unless all four are true:

1. `flutter analyze` printed `No issues found!`
2. `flutter test` printed `All tests passed!`
3. You changed only files in the **Allowed** list.
4. Every file you touched relates to the task.

Then report, briefly:

- Which files you changed, and what each change does.
- Anything you noticed but deliberately left alone.

If a check did not pass, say so and show the output. Never report success for work you have
not verified.

---

**TASK**
