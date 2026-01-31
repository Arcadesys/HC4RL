import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

/// One person in the dataset: id (used for face_verification), display name.
class PersonEntry {
  PersonEntry({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  static PersonEntry fromJson(Map<String, dynamic> j) =>
      PersonEntry(id: j['id'] as String, name: j['name'] as String);
}

/// Local-only dataset: id -> name. Persisted as JSON.
class FaceDataset {
  static const String _filename = 'face_dataset.json';
  final List<PersonEntry> _entries = [];
  final Uuid _uuid = const Uuid();

  List<PersonEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(path.join(dir.path, _filename));
    if (!await file.exists()) return;
    final String raw = await file.readAsString();
    final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
    _entries.clear();
    for (final e in list) {
      _entries.add(PersonEntry.fromJson(e as Map<String, dynamic>));
    }
  }

  Future<void> save() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(path.join(dir.path, _filename));
    final list = _entries.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  String add(String name) {
    final id = _uuid.v4();
    _entries.add(PersonEntry(id: id, name: name));
    return id;
  }

  void remove(String id) {
    _entries.removeWhere((e) => e.id == id);
  }

  String? nameForId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e.name;
    }
    return null;
  }
}
