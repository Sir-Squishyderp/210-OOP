// main.dart
// Full file implementing sections (textboxes and grids) appended to the bottom,
// single global showRichText toggle, dropdown to add textbox or grid,
// persistence of files & sections via SharedPreferences.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final _themeNotifier = ValueNotifier(ThemeMode.light);

  // Removed the const MyApp({super.key}); constructor from _MyAppState.
  // State classes do not have constructors of their associated widget.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
      home: NotesHome(),
      debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

// ---------- Models ----------

class NoteFile {
  String name;
  List<Section> sections;

  NoteFile(this.name, this.sections);

  // Convenience factory for legacy single-text-file compatibility (if needed)
  factory NoteFile.fromSingleText(String name, String text) {
    return NoteFile(name, [Section.textbox(text)]);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory NoteFile.fromJson(Map<String, dynamic> m) {
    final secs = <Section>[];
    final rawList = (m['sections'] as List<dynamic>?) ?? [];
    for (final s in rawList) {
      secs.add(Section.fromJson(Map<String, dynamic>.from(s)));
    }
    return NoteFile(m['name'] as String, secs.isEmpty ? [Section.textbox('')] : secs);
  }

  // Combined text (concatenate sections with delimiters) used for parsing links, etc.
  String combinedText() {
    final buf = StringBuffer();
    for (var i = 0; i < sections.length; i++) {
      final sec = sections[i];
      if (sec.type == SectionType.textbox) {
        buf.writeln(sec.text ?? '');
      } else if (sec.type == SectionType.grid) {
        // join cells with newline separators so links inside cells are found
        for (var c in sec.cells) {
          buf.writeln(c);
        }
      }
      // add a divider to avoid accidental merges
      if (i != sections.length - 1) buf.writeln(''); // blank line between sections
    }
    return buf.toString();
  }
}

enum SectionType { textbox, grid }

class Section {
  SectionType type;
  // for textbox
  String? text;

  // for grid
  int? rows;
  int? cols;
  List<String> cells; // length rows*cols (row-major)

  Section.textbox(this.text)
      : type = SectionType.textbox,
        rows = null,
        cols = null,
        cells = [];

  Section.grid(this.rows, this.cols)
      : type = SectionType.grid,
        text = null,
        cells = List.generate((rows ?? 0) * (cols ?? 0), (_) => '');

  Map<String, dynamic> toJson() {
    return {
      'type': type == SectionType.textbox ? 'textbox' : 'grid',
      'text': text,
      'rows': rows,
      'cols': cols,
      'cells': cells,
    };
  }

  factory Section.fromJson(Map<String, dynamic> m) {
    final t = m['type'] as String? ?? 'textbox';
    if (t == 'grid') {
      final rows = (m['rows'] as int?) ?? 0;
      final cols = (m['cols'] as int?) ?? 0;
      final rawCells = (m['cells'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final s = Section.grid(rows, cols);
      if (rawCells.length == rows * cols) {
        s.cells = rawCells;
      } else {
        // normalize length
        s.cells = List<String>.from(rawCells);
        while (s.cells.length < rows * cols) s.cells.add('');
        if (s.cells.length > rows * cols) s.cells = s.cells.sublist(0, rows * cols);
      }
      return s;
    } else {
      return Section.textbox((m['text'] as String?) ?? '');
    }
  }
}

// ---------- NotesHome Widget ----------

class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  static const String _prefsKeyFiles = 'notes_files_v1';
  static const String _prefsKeyIndex = 'notes_current_index_v1';

  List<NoteFile> files = [NoteFile.fromSingleText("Default", "")];
  int currentIndex = 0;
  bool showRichText = false; // single global toggle for entire file

  SharedPreferences? _prefs;

  // Controllers per section:
  // For textboxes -> controllersText[i] corresponds to file.sections[i] if textbox
  // For grids -> controllersGrid[i] is null for textbox sections, or a flattened list of controllers for grid cells
  List<TextEditingController?> controllersText = [];
  List<List<TextEditingController>?> controllersGrid = [];

  // Right-side lists
  List<String> linkedToRefs = []; // order-of-appearance in current note
  List<String> linkedByRefs = []; // alphabetical list of files that link to current file

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
  }

  @override
  void dispose() {
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (final c in controllersText) {
      c?.dispose();
    }
    for (final list in controllersGrid) {
      if (list != null) {
        for (final c in list) {
          c.dispose();
        }
      }
    }
    controllersText = [];
    controllersGrid = [];
  }

  Future<void> _loadFromPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final filesJson = _prefs!.getString(_prefsKeyFiles);
    final idx = _prefs!.getInt(_prefsKeyIndex);

    if (filesJson != null) {
      try {
        final decoded = jsonDecode(filesJson) as List<dynamic>;
        files = decoded.map((e) => NoteFile.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (e) {
        files = [NoteFile.fromSingleText("Default", "")];
      }
    } else {
      files = [NoteFile.fromSingleText("Default", "")];
    }

    if (idx != null && idx >= 0 && idx < files.length) {
      currentIndex = idx;
    } else {
      currentIndex = 0;
    }

    _buildControllersForCurrentFile();
    _rebuildAllLinkMaps();
    setState(() {});
  }

  Future<void> _saveAllToPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    final encoded = jsonEncode(files.map((f) => f.toJson()).toList());
    await _prefs!.setString(_prefsKeyFiles, encoded);
    await _prefs!.setInt(_prefsKeyIndex, currentIndex);
  }

  // Build controllers arrays from files[currentIndex].sections
  void _buildControllersForCurrentFile() {
    // dispose existing
    _disposeAllControllers();

    final file = files[currentIndex];
    controllersText = List<TextEditingController?>.filled(file.sections.length, null);
    controllersGrid = List<List<TextEditingController>?>.filled(file.sections.length, null);

    for (var i = 0; i < file.sections.length; i++) {
      final s = file.sections[i];
      if (s.type == SectionType.textbox) {
        final ctrl = TextEditingController(text: s.text ?? '');
        ctrl.addListener(() {
          // update model live
          s.text = ctrl.text;
          _onSectionTextChanged();
        });
        controllersText[i] = ctrl;
      } else {
        final total = (s.rows ?? 0) * (s.cols ?? 0);
        final list = List<TextEditingController>.generate(total, (j) {
          final t = (j < s.cells.length) ? s.cells[j] : '';
          final c = TextEditingController(text: t);
          c.addListener(() {
            s.cells[j] = c.text;
            _onSectionTextChanged();
          });
          return c;
        });
        controllersGrid[i] = list;
      }
    }
  }

  // Save controllers content into model (used before switching files and when persisting)
  void _flushControllersToModel() {
    final file = files[currentIndex];
    for (var i = 0; i < file.sections.length; i++) {
      final s = file.sections[i];
      if (s.type == SectionType.textbox) {
        final ctrl = controllersText.length > i ? controllersText[i] : null;
        s.text = ctrl?.text ?? s.text ?? '';
      } else {
        final list = (controllersGrid.length > i) ? controllersGrid[i] : null;
        if (list != null) {
          for (var j = 0; j < list.length && j < s.cells.length; j++) {
            s.cells[j] = list[j].text;
          }
        }
      }
    }
  }

  void _onSectionTextChanged() {
    // called when any controller changes; update linked maps live
    _saveCurrentToFile(silent: true);
    _rebuildAllLinkMapsAcrossApp();
  }

  // ------------------ Parser & Helpers ------------------

  // ---- Font family handling: accept filenames e.g. "Comic Sans MS.ttf" inside .font(...)
  String? _resolveFontFamily(String raw) {
    if (raw == null) return null;
    final name = raw.trim().replaceAll('"', '').replaceAll("'", "");
    // If they passed a filename like Comic Sans MS.ttf -> remove extension
    final cleaned = name.replaceAll(RegExp(r'\.(ttf|otf|TTF|OTF)$'), '').trim();
    if (cleaned.isEmpty) return null;
    return cleaned; // let Flutter use family name declared in pubspec.yaml
  }

  // parse and produce InlineSpan list for a given string
  List<InlineSpan> _parseRichTextSpans(String input) {
    List<InlineSpan> spans = [];
    int currentIndexLocal = 0;

    // handle escaped literal bracket patterns: \[[...]]
    final escapedPattern = RegExp(r'\\\[\[(.+?)\]\]');
    for (final string in escapedPattern.allMatches(input)) {
      if (string.start > currentIndexLocal) {
        spans.addAll(_parseNormalBrackets(input.substring(currentIndexLocal, string.start)));
      }
      final content = string.group(1)!;
      spans.add(TextSpan(text: '[[$content]]', style: const TextStyle(fontSize: 18, color: Colors.black)));
      currentIndexLocal = string.end;
    }
    if (currentIndexLocal < input.length) {
      spans.addAll(_parseNormalBrackets(input.substring(currentIndexLocal)));
    }
    return spans;
  }

  // main bracket parser for one block of text
  List<InlineSpan> _parseNormalBrackets(String input) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\[\[(.+?)\]\]');
    int lastEnd = 0;

    // commandPattern: name + parentheses contents (non-greedy)
    final commandPattern = RegExp(r'\.(#[A-Za-z0-9]+|[A-Za-z0-9]+)\((.*?)\)');

    for (final match in pattern.allMatches(input)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: input.substring(lastEnd, match.start)));
      }

      String content = match.group(1)!;

      // Extract commands
      final commandsMatches = commandPattern.allMatches(content).toList();

      final commands = <String, String?>{};
      for (final m in commandsMatches) {
        final name = m.group(1)!.toLowerCase();
        final argRaw = m.group(2);
        commands[name] = argRaw;
      }

      String text = content.replaceAll(commandPattern, '');

      // hidden()
      if (commands.containsKey('hidden')) {
        if (!showRichText) {
          spans.add(TextSpan(text: text));
        }
        lastEnd = match.end;
        continue;
      }

      if (commands.isEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Text(
            '[[$text]]',
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.wavy,
              decorationColor: Colors.red,
              color: Colors.black,
              fontSize: 18,
            ),
          ),
        ));
        lastEnd = match.end;
        continue;
      }

      TextStyle style = const TextStyle(fontSize: 18, color: Colors.black);
      bool highlight = false;
      Color? colorFromCmd;

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
              style = style.copyWith(decoration: TextDecoration.combine([existing, TextDecoration.underline]));
            }
            break;
          case 'highlight':
            highlight = true;
            break;
          case 'font':
            if (arg != null) {
              final fam = _resolveFontFamily(arg);
              if (fam != null && fam.isNotEmpty) style = style.copyWith(fontFamily: fam);
            }
            break;
          case 'size':
            if (arg != null) {
              final cleaned = arg.trim().replaceAll('"', '').replaceAll("'", "");
              final value = double.tryParse(cleaned);
              if (value != null) style = style.copyWith(fontSize: value);
            }
            break;
          default:
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

  // Extract ordered unique file refs from combined text based on [[Name.file()]]
  List<String> _extractFileRefsOrderedFromString(String input) {
    final pattern = RegExp(r'\[\[(.+?)\]\]');
    final commandPattern = RegExp(r'\.(\#?[A-Za-z0-9]+|\w+)\(');
    final refs = <String>[];
    for (final match in pattern.allMatches(input)) {
      String content = match.group(1)!;
      final commands = commandPattern.allMatches(content).map((m) => m.group(1)!.toLowerCase()).toList();
      if (commands.contains('file')) {
        final cleaned = content.replaceAll(RegExp(r'\.\w+\(.*?\)'), '');
        final trimmed = cleaned.trim();
        if (trimmed.isNotEmpty && !refs.contains(trimmed)) refs.add(trimmed);
      }
    }
    return refs;
  }

  // Rebuild both linkedToRefs and linkedByRefs for current file; does NOT create files
  void _rebuildAllLinkMaps() {
    final combined = files[currentIndex].combinedText();
    linkedToRefs = _extractFileRefsOrderedFromString(combined);
    linkedByRefs = _computeLinkedByFor(files[currentIndex].name);
    _saveAllToPrefs();
    setState(() {});
  }

  // extract refs and create actual files (deferred creation), called when Show Rich Text is pressed
  void _createMissingLinkedFilesForCurrent() {
    final currentText = files[currentIndex].combinedText();
    final refs = _extractFileRefsOrderedFromString(currentText);
    bool changed = false;
    for (final r in refs) {
      if (!files.any((f) => f.name == r)) {
        files.add(NoteFile.fromSingleText(r, ''));
        changed = true;
      }
    }
    if (changed) _saveAllToPrefs();
  }

  // Compute which files reference 'target' (Linked By), alphabetical
  List<String> _computeLinkedByFor(String target) {
    final pattern = RegExp(r'\[\[(.+?)\]\]');
    final commandNamePattern = RegExp(r'\.(\#?[A-Za-z0-9]+|\w+)\(');
    final result = <String>{};
    for (final f in files) {
      if (f.name == target) continue;
      for (final match in pattern.allMatches(f.combinedText())) {
        String content = match.group(1)!;
        final commands = commandNamePattern.allMatches(content).map((e) => e.group(1)!.toLowerCase()).toList();
        final base = content.replaceAll(RegExp(r'\.\w+\(.*?\)'), '').trim();
        if (commands.contains('file')) {
          if (base == target) result.add(f.name);
        } else {
          if (base == target) result.add(f.name);
        }
      }
    }
    final list = result.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // ------------------ Note operations ------------------

  void _saveCurrentToFile({bool silent = false}) {
    // flush controllers
    _flushControllersToModel();
    // persist
    _saveAllToPrefs();
    if (!silent) {
      setState(() {});
    }
  }

  void _openNoteByIndex(int index) {
    if (index < 0 || index >= files.length) return;
    // flush current into model first
    _flushControllersToModel();
    _saveAllToPrefs();

    setState(() {
      currentIndex = index;
      _buildControllersForCurrentFile();
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
                  files.add(NoteFile.fromSingleText(name, ''));
                  _saveAllToPrefs();
                  _openNoteByIndex(files.length - 1);
                }
                Navigator.pop(context);
              },
              child: const Text("Create"),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ],
        );
      },
    );
  }

  // Rename: update file name AND replace references across all files (including bare references),
  // converting bare references into file-links and preserving other commands.
  void _renameNoteDialog(int index) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController renameController = TextEditingController(text: files[index].name);
        return AlertDialog(
          title: const Text("Rename Note"),
          content: TextField(controller: renameController, autofocus: true),
          actions: [
            TextButton(
              onPressed: () {
                final newName = renameController.text.trim();
                if (newName.isNotEmpty) {
                  final oldName = files[index].name;

                  final pattern = RegExp(r'\[\[\s*' + RegExp.escape(oldName) + r'([^\]]*)\]\]');

                  for (var f in files) {
                    // must update every section and every cell
                    for (var s in f.sections) {
                      if (s.type == SectionType.textbox) {
                        s.text = s.text!.replaceAllMapped(pattern, (m) {
                          final rest = m.group(1) ?? '';
                          final restLower = rest.toLowerCase();
                          if (restLower.contains('.file()')) {
                            return '[[$newName$rest]]';
                          } else {
                            return '[[$newName${rest}.file()]]';
                          }
                        });
                      } else {
                        for (var i = 0; i < s.cells.length; i++) {
                          s.cells[i] = s.cells[i].replaceAllMapped(pattern, (m) {
                            final rest = m.group(1) ?? '';
                            final restLower = rest.toLowerCase();
                            if (restLower.contains('.file()')) {
                              return '[[$newName$rest]]';
                            } else {
                              return '[[$newName${rest}.file()]]';
                            }
                          });
                        }
                      }
                    }
                  }

                  files[index].name = newName;
                  _buildControllersForCurrentFile();
                  _rebuildAllLinkMapsAcrossApp();
                  _saveAllToPrefs();
                }
                Navigator.pop(context);
              },
              child: const Text("Rename"),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
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
          content: Text("Delete \"${files[index].name}\"? This cannot be undone."),
          actions: [
            TextButton(
              onPressed: () {
                final wasCurrent = index == currentIndex;
                files.removeAt(index);
                if (files.isEmpty) files.add(NoteFile.fromSingleText("Default", ""));
                if (wasCurrent) {
                  currentIndex = index == 0 ? 0 : index - 1;
                  _buildControllersForCurrentFile();
                } else {
                  if (currentIndex > index) currentIndex--;
                }
                _rebuildAllLinkMapsAcrossApp();
                _saveAllToPrefs();
                Navigator.pop(context);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ],
        );
      },
    );
  }

  // When a linked-to button is pressed: create file if missing, then open it.
  void _createOrNavigateToFileByName(String name) {
    final existingIndex = files.indexWhere((f) => f.name == name);
    if (existingIndex != -1) {
      _openNoteByIndex(existingIndex);
    } else {
      files.add(NoteFile.fromSingleText(name, ""));
      _saveAllToPrefs();
      _openNoteByIndex(files.length - 1);
    }
  }

  void _rebuildAllLinkMapsAcrossApp() {
    if (currentIndex >= files.length) currentIndex = files.length - 1;
    _rebuildAllLinkMaps();
    _saveAllToPrefs();
  }

  // Called on controller changes — update model live
  void _onTextChangedSaveOnly() {
    _flushControllersToModel();
    _rebuildAllLinkMapsAcrossApp();
    _saveAllToPrefs();
  }

  // ---------- UI helpers for adding sections ----------

  // Append a new blank textbox section
  void _appendTextboxSection() {
    files[currentIndex].sections.add(Section.textbox(''));
    _buildControllersForCurrentFile();
    _saveAllToPrefs();
    setState(() {});
  }

  // Append a new grid section with rows x cols (asks user via dialog)
  void _appendGridSection(int rows, int cols) {
    files[currentIndex].sections.add(Section.grid(rows, cols));
    _buildControllersForCurrentFile();
    _saveAllToPrefs();
    setState(() {});
  }

  // Show dialog to ask rows and columns for grid
  void _showGridDialog() {
    final rCtrl = TextEditingController(text: '2');
    final cCtrl = TextEditingController(text: '2');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Grid size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: rCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rows')),
              TextField(controller: cCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Columns')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                final r = int.tryParse(rCtrl.text.trim()) ?? 0;
                final c = int.tryParse(cCtrl.text.trim()) ?? 0;
                if (r > 0 && c > 0) _appendGridSection(r, c);
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        );
      },
    );
  }

  // ------------------ Color resolver ------------------

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

  // ---------- Build UI ----------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final boxHeight = screenHeight / 1.5;
    final screenWidth = MediaQuery.of(context).size.width;
    final boxWidth = screenWidth / 2;

    final file = files[currentIndex];

    return Scaffold(
      appBar: AppBar(title: Text(file.name)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                child: Row(
                  children: [
                    const Text("Notes", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                    return Column( // Wrap ListTile in a Column to add the Divider and Theme Switch
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
                          title: Text(files[index].name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
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
                              const PopupMenuItem(value: 'rename', child: Text('Rename')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                            icon: const Icon(Icons.more_vert),
                          ),
                        ),
                        if (index == files.length -1) ...[ // Add divider and theme switch after the last list item
                          const Divider(),
                          ListTile(
                            title: const Text("Dark Mode"),
                            trailing: ValueListenableBuilder<ThemeMode>(
                              valueListenable: _MyAppState._themeNotifier,
                              builder: (context, mode, _) {
                                return Switch(
                                  value: mode == ThemeMode.dark,
                                  onChanged: (v) {
                                    _MyAppState._themeNotifier.value =
                                        v ? ThemeMode.dark : ThemeMode.light;
                                  },
                                );
                              },
                            ),
                          ),
                        ]
                      ],
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
          // Top buttons row: save (show rich), edit (text), dropdown to add sections
          Row(
            children: [
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  // Save controllers & create missing files referenced
                  _saveCurrentToFile(silent: true);
                  _createMissingLinkedFilesForCurrent();
                  _rebuildAllLinkMapsAcrossApp();
                  setState(() => showRichText = true);
                },
                child: const Icon(Icons.save, size: 24, color: Colors.black),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  setState(() => showRichText = false);
                },
                child: const Icon(Icons.edit, size: 24, color: Colors.black),
              ),
              const SizedBox(width: 8),
              // Dropdown to add textbox or grid
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'textbox') {
                    _appendTextboxSection();
                  } else if (value == 'grid') {
                    _showGridDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'textbox', child: Text('Add Textbox')),
                  const PopupMenuItem(value: 'grid', child: Text('Add Grid')),
                ],
                child: ElevatedButton(
                  onPressed: null,
                  child: const Icon(Icons.add_box, size: 24, color: Colors.black),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Main editable area: scrollable column of sections
          Expanded(
            child: Row(
              children: [
                // Main editor (scrollable)
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // For each section render either a TextField or Grid (cells)
                          for (var si = 0; si < file.sections.length; si++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: _buildSectionWidget(si),
                            ),

                          const SizedBox(height: 24),
                          // NOTE: Linked lists moved into the right-side sidebar so they are always accessible.
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Right-side fixed sidebar for Linked To / Linked By
                SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Links', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Linked To
                              const Text('Linked To:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              if (linkedToRefs.isEmpty) const Text('—'),
                              if (linkedToRefs.isNotEmpty)
                                ...linkedToRefs.map((name) {
                                  final idx = files.indexWhere((f) => f.name == name);
                                  final exists = idx != -1;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(minimumSize: const Size(90, 36)),
                                      onPressed: () {
                                        if (exists) {
                                          _openNoteByIndex(idx);
                                        } else {
                                          _createOrNavigateToFileByName(name);
                                        }
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.folder, size: 18),
                                          const SizedBox(width: 6),
                                          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),

                              const SizedBox(height: 12),

                              // Linked By
                              const Text('Linked By:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              if (linkedByRefs.isEmpty) const Text('—'),
                              if (linkedByRefs.isNotEmpty)
                                ...linkedByRefs.map((name) {
                                  final idx = files.indexWhere((f) => f.name == name);
                                  final exists = idx != -1;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(minimumSize: const Size(90, 36)),
                                      onPressed: () {
                                        if (exists) _openNoteByIndex(idx);
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.link, size: 18),
                                          const SizedBox(width: 6),
                                          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              const SizedBox(height: 24),
                              // Extra actions for sidebar
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]), // Closing bracket for Column
      ), // Closing bracket for Padding
    ); // Closing bracket for Scaffold
  }

  // Build the widget for a given section index
  Widget _buildSectionWidget(int si) {
    final file = files[currentIndex];
    final sec = file.sections[si];

    // If in RichText mode -> show parsed RichText representation
    if (showRichText) {
      if (sec.type == SectionType.textbox) {
        final text = sec.text ?? '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200)),
          child: RichText(
            text: TextSpan(style: const TextStyle(fontSize: 18, color: Colors.black), children: _parseRichTextSpans(text)),
          ),
        );
      } else {
        // grid view: show table of parsed rich cells
        final rows = sec.rows ?? 0;
        final cols = sec.cols ?? 0;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grid: ${rows}×${cols}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                children: List.generate(rows, (r) {
                  return TableRow(
                    children: List.generate(cols, (c) {
                      final idx = r * cols + c;
                      final cellText = (idx < sec.cells.length) ? sec.cells[idx] : '';
                      return Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: RichText(
                          text: TextSpan(style: const TextStyle(fontSize: 16, color: Colors.black), children: _parseRichTextSpans(cellText)),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
        );
      }
    } else {
      // Edit mode: textfields for textbox or grid cells
      if (sec.type == SectionType.textbox) {
        final ctrl = (controllersText.length > si) ? controllersText[si] : null;
        final c = ctrl ?? TextEditingController(text: sec.text ?? '');
        if (controllersText.length <= si || controllersText[si] == null) {
          // ensure controller is registered
          if (controllersText.length <= si) {
            controllersText.length = si + 1;
          }
          controllersText[si] = c;
        }
        return Container(
          width: double.infinity,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        );
      } else {
        final rows = sec.rows ?? 0;
        final cols = sec.cols ?? 0;
        final listCtrl = controllersGrid.length > si ? controllersGrid[si] : null;
        // ensure controllers exist
        if (listCtrl == null) {
          final total = rows * cols;
          final newList = List<TextEditingController>.generate(total, (idx) {
            final t = idx < sec.cells.length ? sec.cells[idx] : '';
            final tc = TextEditingController(text: t);
            tc.addListener(() {
              sec.cells[idx] = tc.text;
              _onSectionTextChanged();
            });
            return tc;
          });
          if (controllersGrid.length <= si) controllersGrid.length = si + 1;
          controllersGrid[si] = newList;
        }

        final controllers = controllersGrid[si]!;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grid: ${rows}×${cols}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                children: List.generate(rows, (r) {
                  return TableRow(
                    children: List.generate(cols, (c) {
                      final idx = r * cols + c;
                      final tc = controllers[idx];
                      return Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: TextField(
                          controller: tc,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(8)),
                          maxLines: null,
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
        );
      }
    }
  }
}
