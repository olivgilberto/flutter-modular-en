import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tasks_module/adapters/driving/l10n/tasks_module_localizations.dart';
import 'package:tasks_module/domain/entities/task.dart';

/// The module's translations (chapter 37). A key missing from a translation
/// is not an error for gen-l10n: the screen shows the template's English
/// text to whoever chose Portuguese. This test turns the warning into a
/// failure.
void main() {
  const arbDir = 'lib/adapters/driving/l10n';
  const template = 'tasks_module_en.arb';

  Map<String, Object?> read(String name) =>
      jsonDecode(File('$arbDir/$name').readAsStringSync())
          as Map<String, Object?>;

  Set<String> messages(Map<String, Object?> arb) =>
      arb.keys.where((key) => !key.startsWith('@')).toSet();

  final translations = [
    for (final file in Directory(arbDir).listSync().whereType<File>())
      if (file.path.endsWith('.arb')) file.uri.pathSegments.last,
  ]..sort();

  test('there is the template and at least one translation', () {
    expect(translations, containsAll([template, 'tasks_module_pt.arb']));
  });

  test('every translation has exactly the template\'s keys', () {
    final expected = messages(read(template));
    for (final name in translations) {
      final arb = read(name);
      expect(messages(arb), expected, reason: name);
      expect(
        name,
        'tasks_module_${arb['@@locale']}.arb',
        reason: 'the @@locale of $name',
      );
    }
  });

  test('the status select gives each language\'s word', () {
    final en = lookupTasksModuleLocalizations(const Locale('en'));
    final pt = lookupTasksModuleLocalizations(const Locale('pt', 'BR'));
    expect(en.taskSummary('Pay the bill', 'done'), '"Pay the bill", done');
    expect(
      pt.taskSummary('Pay the power bill', 'done'),
      '"Pay the power bill", concluída',
    );
    // In Portuguese no word matches the enum value's name: a new TaskStatus
    // value with no word in the ARB would fall into `other`, which repeats
    // the name, and this test would point it out.
    for (final status in TaskStatus.values) {
      expect(
        pt.taskSummary('Pay the power bill', status.name),
        isNot(endsWith(', ${status.name}')),
        reason: '$status',
      );
    }
  });

  test('the conflicts notice plural in both languages', () {
    final en = lookupTasksModuleLocalizations(const Locale('en'));
    final pt = lookupTasksModuleLocalizations(const Locale('pt', 'BR'));
    expect(en.conflictsNotice(1), '1 change needs your decision');
    expect(en.conflictsNotice(2), '2 changes need your decision');
    expect(pt.conflictsNotice(1), '1 alteração precisa da sua decisão');
    expect(pt.conflictsNotice(2), '2 alterações precisam da sua decisão');
  });

  test('the =1 trap: in Portuguese, the "one" category covers 0 and '
      '1', () {
    // gen-l10n writes the ARB's =1 case as Intl.pluralLogic's `one`
    // parameter. For Brazilian Portuguese, the CLDR rules put 0 in the
    // "one" category, and without an =0 case zero gets the sentence for 1.
    expect(
      Intl.pluralLogic(0, locale: 'pt', one: 'sentence for 1', other: 'other'),
      'sentence for 1',
    );
    expect(
      Intl.pluralLogic(0, locale: 'en', one: 'sentence for 1', other: 'other'),
      'other',
    );
    // That is why every plural in the module has the =0 case.
    final pt = lookupTasksModuleLocalizations(const Locale('pt', 'BR'));
    expect(pt.conflictsNotice(0), 'Nenhuma alteração precisa da sua decisão');
  });
}
