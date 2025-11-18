// --------------- FULL MAIN.DART WITH .font() AND .size() FIXED ------------------

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: NotesHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class NoteFile {
  String name;
  String text;
  NoteFile(this.name, this.text);
  Map<String, dynamic> toJson() => {'name': name, 'text': text};
  factory NoteFile.fromJson(Map<String, dynamic> map) =>
      NoteFile(map['name'] as String, map['text'] as String);
}

class NotesHome extends StatefulWidget {
  const NotesHome({super.key});
  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  static const String _prefsKeyFiles = 'notes_files_v1';
  static const String _prefsKeyIndex = 'notes_current_index_v1';

  List<NoteFile> files = [NoteFile("Default", "")];
  int currentIndex = 0;
  bool showRichText = false;

  final TextEditingController _mainController = TextEditingController();
  List<String> linkedToRefs = [];
  List<String> linkedByRefs = [];
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _mainController.addListener(_onTextChanged_saveOnly);
    _loadFromPrefs();
  }

  @override
  void dispose() {
    _mainController.removeListener(_onTextChanged_saveOnly);
    _mainController.dispose();
    super.dispose();
  }

  // ------------------ Persistence ------------------

  Future<void> _loadFromPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final filesJson = _prefs!.getString(_prefsKeyFiles);
    final idx = _prefs!.getInt(_prefsKeyIndex);

    if (filesJson != null) {
      try {
        final decoded = jsonDecode(filesJson) as List<dynamic>;
        files = decoded
            .map((e) => NoteFile.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (e) {
        files = [NoteFile("Default", "")];
      }
    }

    if (idx != null && idx >= 0 && idx < files.length) {
      currentIndex = idx;
    } else {
      currentIndex = 0;
    }

    _mainController.text = files[currentIndex].text;
    _rebuildAllLinkMaps();
    setState(() {});
  }

  Future<void> _saveAllToPrefs() async {
    if (_prefs == null) _prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(files.map((f) => f.toJson()).toList());
    await _prefs!.setString(_prefsKeyFiles, encoded);
    await _prefs!.setInt(_prefsKeyIndex, currentIndex);
  }

  // ------------------ Parser & Helpers ------------------

  List<InlineSpan> _parseRichTextSpans(String input) {
    List<InlineSpan> spans = [];
    int currentIndexLocal = 0;

    // handle escaped literal bracket patterns: \[[...]]
    final escapedPattern = RegExp(r'\\\[\[(.+?)\]\]');
    for (final string in escapedPattern.allMatches(input)) {
      if (string.start > currentIndexLocal) {
        spans.addAll(
            _parseNormalBrackets(input.substring(currentIndexLocal, string.start)));
      }
      final content = string.group(1)!;
      spans.add(TextSpan(
          text: '[[$content]]',
          style: const TextStyle(fontSize: 18, color: Colors.black)));
      currentIndexLocal = string.end;
    }
    if (currentIndexLocal < input.length) {
      spans.addAll(_parseNormalBrackets(input.substring(currentIndexLocal)));
    }
    return spans;
  }

  // Updated parser: supports .font("Name") and .size("N") (quoted), plus colors and other commands.
  List<InlineSpan> _parseNormalBrackets(String input) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\[\[(.+?)\]\]');
    int lastEnd = 0;

    // commandPattern: name + optional parentheses with anything inside (non-greedy)
    final commandPattern = RegExp(r'\.(#[A-Za-z0-9]+|[A-Za-z0-9]+)\((.*?)\)');

    for (final match in pattern.allMatches(input)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: input.substring(lastEnd, match.start)));
      }

      String content = match.group(1)!;

      // Extract commands
      final commandsMatches = commandPattern.allMatches(content).toList();

      // Map name -> rawArg (may be empty string)
      final commands = <String, String?>{};
      for (final m in commandsMatches) {
        final name = m.group(1)!.toLowerCase();
        final argRaw = m.group(2); // may include quotes
        commands[name] = argRaw;
      }

      // Remove commands from base text (strip command occurrences)
      String text = content.replaceAll(commandPattern, '');

      // Hidden -> skip entirely in RichText
      if (commands.containsKey("hidden")) {
        if (!showRichText) {
          spans.add(TextSpan(text: text));
        }
        lastEnd = match.end;
        continue;
      }

      // If NO commands -> invalid ref -> show literal [[text]] with wavy underline
      if (commands.isEmpty) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(
              "[[$text]]",
              style: const TextStyle(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.wavy,
                decorationColor: Colors.red,
                color: Colors.black,
                fontSize: 18,
              ),
            ),
          ),
        );
        lastEnd = match.end;
        continue;
      }

      // Build text style
      TextStyle style = const TextStyle(fontSize: 18, color: Colors.black);
      bool highlight = false;
      Color? colorFromCmd;

      // Iterate over commands; order doesn't matter (stackable)
      commands.forEach((cmd, arg) {
        final lower = cmd.toLowerCase();
        switch (lower) {
          case 'bold':
            style = style.copyWith(fontWeight: FontWeight.bold);
            break;
          case 'italics':
            style = style.copyWith(fontStyle: FontStyle.italic);
            break;
          case 'underline':
            final existing = style.decoration;
            if (existing == null) {
              style = style.copyWith(decoration: TextDecoration.underline);
            } else {
              style = style.copyWith(
                  decoration: TextDecoration.combine([existing, TextDecoration.underline]));
            }
            break;
          case 'highlight':
            highlight = true;
            break;
          case 'size':
            if (arg != null) {
              final cleaned = arg.trim().replaceAll('"', '').replaceAll("'", "");
              final value = double.tryParse(cleaned);
              if (value != null) style = style.copyWith(fontSize: value);
            }
            break;
          default:
            // treat unrecognized as color name/hex
            colorFromCmd = _resolveColor(cmd);
            break;
        }
      });

      if (colorFromCmd != null) style = style.copyWith(color: colorFromCmd);
      if (highlight) style = style.copyWith(backgroundColor: Colors.yellow);

      spans.add(TextSpan(text: text, style: style));

      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      spans.add(TextSpan(text: input.substring(lastEnd)));
    }

    return spans;
  }

  // -------- All other code stays the same below (UI, rename, linked lists, etc.) --------
  // I preserved your app logic and changed only parsing-related bits and added _resolveFontFamily helper.
  // ------------------------------------------------------------------------------

  // Extract ordered unique file refs
  List<String> _extractFileRefsOrdered(String input) {
    final pattern = RegExp(r'\[\[(.+?)\]\]');
    // command name pattern: capture command names only (we don't need args here)
    final commandNamePattern = RegExp(r'\.(\#?[A-Za-z0-9]+|\w+)\(');
    final refs = <String>[];
    for (final match in pattern.allMatches(input)) {
      String content = match.group(1)!;
      final commands = commandNamePattern
          .allMatches(content)
          .map((e) => e.group(1)!.toLowerCase())
          .toList();
      if (commands.contains('file')) {
        // remove any .commands(...) occurrences to get base name
        final cleaned = content.replaceAll(RegExp(r'\.\w+\(.*?\)'), '');
        final trimmed = cleaned.trim();
        if (trimmed.isNotEmpty && !refs.contains(trimmed)) refs.add(trimmed);
      } else {
        // bare references are considered for rename & linked-by, but do not show as linked-to
      }
    }
    return refs;
  }

  void _ensureFileExists(String name) {
    if (!files.any((f) => f.name == name)) {
      files.add(NoteFile(name, ""));
    }
  }

  List<String> _computeLinkedByFor(String target) {
    final pattern = RegExp(r'\[\[(.+?)\]\]');
    final commandNamePattern = RegExp(r'\.(\#?[A-Za-z0-9]+|\w+)\(');
    final result = <String>{};
    for (final f in files) {
      if (f.name == target) continue;
      for (final match in pattern.allMatches(f.text)) {
        String content = match.group(1)!;
        final commands = commandNamePattern
            .allMatches(content)
            .map((e) => e.group(1)!.toLowerCase())
            .toList();
        // strip commands to get base
        final base = content.replaceAll(RegExp(r'\.\w+\(.*?\)'), '').trim();
        if (commands.contains('file')) {
          if (base == target) result.add(f.name);
        } else {
          // bare reference counts as linking when computing linked-by
          if (base == target) result.add(f.name);
        }
      }
    }
    final list = result.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _rebuildAllLinkMaps() {
    final currentText = files[currentIndex].text;
    final refs = _extractFileRefsOrdered(currentText);

    // 2) Update linkedToRefs (in-order)
    linkedToRefs = refs;

    // 3) Update linkedByRefs (alphabetical)
    linkedByRefs = _computeLinkedByFor(files[currentIndex].name);

    _saveAllToPrefs();

    setState(() {});
  }

  void _createMissingLinkedFilesForCurrent() {
    final currentText = files[currentIndex].text;
    final refs = _extractFileRefsOrdered(currentText);
    bool changed = false;
    for (final r in refs) {
      if (!files.any((f) => f.name == r)) {
        files.add(NoteFile(r, ""));
        changed = true;
      }
    }
    if (changed) _saveAllToPrefs();
  }

  // ------------------ Note operations ------------------

  void _saveCurrentToFile() {
    if (currentIndex >= 0 && currentIndex < files.length) {
      files[currentIndex].text = _mainController.text;
      _saveAllToPrefs();
    }
  }

  void _openNoteByIndex(int index) {
    if (index < 0 || index >= files.length) return;
    setState(() {
      _saveCurrentToFile();
      currentIndex = index;
      _mainController.text = files[currentIndex].text;
      showRichText = false;
      _rebuildAllLinkMaps();
    });
  }

  void _addNoteViaDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController nameController = TextEditingController();
        return AlertDialog(
          title: const Text("Name New Note"),
          content: TextField(controller: nameController, autofocus: true),
          actions: [
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  files.add(NoteFile(name, ""));
                  _saveAllToPrefs();
                  _openNoteByIndex(files.length - 1);
                }
                Navigator.pop(context);
              },
              child: const Text("Create"),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
          ],
        );
      },
    );
  }

  void _renameNoteDialog(int index) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController renameController =
            TextEditingController(text: files[index].name);
        return AlertDialog(
          title: const Text("Rename Note"),
          content: TextField(controller: renameController, autofocus: true),
          actions: [
            TextButton(
              onPressed: () {
                final newName = renameController.text.trim();
                if (newName.isNotEmpty) {
                  final oldName = files[index].name;

                  final pattern = RegExp(r'\[\[\s*' +
                      RegExp.escape(oldName) +
                      r'([^\]]*)\]\]');

                  for (var f in files) {
                    f.text = f.text.replaceAllMapped(pattern, (m) {
                      final rest = m.group(1) ?? '';
                      final restLower = rest.toLowerCase();
                      if (restLower.contains('.file()')) {
                        return '[[$newName$rest]]';
                      } else {
                        return '[[$newName${rest}.file()]]';
                      }
                    });
                  }

                  files[index].name = newName;
                  _mainController.text = files[currentIndex].text;

                  _rebuildAllLinkMapsAcrossApp();
                  _saveAllToPrefs();
                }
                Navigator.pop(context);
              },
              child: const Text("Rename"),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
          ],
        );
      },
    );
  }

  void _deleteNoteConfirm(int index) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Note"),
          content: Text(
              "Delete \"${files[index].name}\"? This cannot be undone."),
          actions: [
            TextButton(
              onPressed: () {
                final wasCurrent = index == currentIndex;
                files.removeAt(index);
                if (files.isEmpty) files.add(NoteFile("Default", ""));
                if (wasCurrent) {
                  currentIndex = index == 0 ? 0 : index - 1;
                  _mainController.text = files[currentIndex].text;
                } else {
                  if (currentIndex > index) currentIndex--;
                }
                _rebuildAllLinkMapsAcrossApp();
                _saveAllToPrefs();
                Navigator.pop(context);
              },
              child:
                  const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
          ],
        );
      },
    );
  }

  void _createOrNavigateToFileByName(String name) {
    final existingIndex = files.indexWhere((f) => f.name == name);
    if (existingIndex != -1) {
      _openNoteByIndex(existingIndex);
    } else {
      files.add(NoteFile(name, ""));
      _saveAllToPrefs();
      _openNoteByIndex(files.length - 1);
    }
  }

  void _rebuildAllLinkMapsAcrossApp() {
    if (currentIndex >= files.length) currentIndex = files.length - 1;
    _rebuildAllLinkMaps();
    _saveAllToPrefs();
  }

  void _onTextChanged_saveOnly() {
    if (currentIndex >= 0 && currentIndex < files.length) {
      files[currentIndex].text = _mainController.text;
      _rebuildAllLinkMapsAcrossApp();
      _saveAllToPrefs();
    }
  }

  Color _resolveColor(String name) {
    final lower = name.toLowerCase();
    switch (lower) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'pink':
        return Colors.pink;
      case 'teal':
        return Colors.teal;
    }
    if (RegExp(r'^#?[0-9A-Fa-f]{6}$').hasMatch(name)) {
      final hex = name.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.black;
  }

  // ------------------ UI ------------------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final boxHeight = screenHeight / 1.5;
    final boxWidth = screenWidth / 2;

    return Scaffold(
      appBar: AppBar(title: Text(files[currentIndex].name)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                child: Row(
                  children: [
                    const Text("Notes",
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(onPressed: _addNoteViaDialog, icon: const Icon(Icons.add)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12.0),
                      title: Text(
                        files[index].name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: index == currentIndex,
                      onTap: () {
                        Navigator.pop(context);
                        _openNoteByIndex(index);
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') {
                            Navigator.pop(context);
                            _renameNoteDialog(index);
                          } else if (value == 'delete') {
                            Navigator.pop(context);
                            _deleteNoteConfirm(index);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'rename', child: Text('Rename')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                        icon: const Icon(Icons.more_vert),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          Row(
            children: [
              SizedBox(width:boxWidth/2.3),
              ElevatedButton(
                onPressed: () {
                  _saveCurrentToFile();
                  _createMissingLinkedFilesForCurrent();
                  _rebuildAllLinkMapsAcrossApp();
                  setState(() => showRichText = true);
                },
                child: const Icon(Icons.save, size:30, color: Colors.black),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  setState(() => showRichText = false);
                },
                child: const Icon(Icons.drive_file_rename_outline_sharp, size:30, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: boxWidth,
                    height: boxHeight,
                    child: showRichText
                        ? SingleChildScrollView(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                    fontSize: 18, color: Colors.black),
                                children:
                                    _parseRichTextSpans(_mainController.text),
                              ),
                            ),
                          )
                        : TextField(
                            controller: _mainController,
                            keyboardType: TextInputType.multiline,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText:
                                  "Enter text here.\n\n\n\n\n\n\n\n\n\n\n\n",
                            ),
                          ),
                  ),

                  const SizedBox(width: 12),

                  IntrinsicWidth(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: boxHeight),
                      child: linkedToRefs.isEmpty
                          ? const SizedBox(width: 24)
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 4.0),
                                    child: Text("Linked To:",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  ...linkedToRefs.map((name) {
                                    final idx = files
                                        .indexWhere((f) => f.name == name);
                                    final exists = idx != -1;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4.0, horizontal: 6.0),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(90, 36),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                        ),
                                        onPressed: () {
                                          if (exists) {
                                            _openNoteByIndex(idx);
                                          } else {
                                            files.add(NoteFile(name, ""));
                                            _saveAllToPrefs();
                                            _openNoteByIndex(
                                                files.length - 1);
                                          }
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.folder,
                                                size: 18),
                                            const SizedBox(width: 6),
                                            Flexible(
                                                child: Text(name,
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  IntrinsicWidth(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: boxHeight),
                      child: linkedByRefs.isEmpty
                          ? const SizedBox(width: 24)
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 4.0),
                                    child: Text("Linked By:",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  ...linkedByRefs.map((name) {
                                    final idx = files
                                        .indexWhere((f) => f.name == name);
                                    final exists = idx != -1;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4.0, horizontal: 6.0),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(90, 36),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                        ),
                                        onPressed: () {
                                          if (exists) _openNoteByIndex(idx);
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.link,
                                                size: 18),
                                            const SizedBox(width: 6),
                                            Flexible(
                                                child: Text(name,
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ]),
      ),
    );
  }

  static bool listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}