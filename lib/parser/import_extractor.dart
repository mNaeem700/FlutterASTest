import 'package:analyzer/dart/ast/ast.dart';
import 'models/import_model.dart';

class ImportExtractor {
  const ImportExtractor();

  List<ImportModel> extract(
    CompilationUnit unit,
  ) {
    final imports = <ImportModel>[];

    for (final directive in unit.directives) {
      if (directive is! ImportDirective) {
        continue;
      }

      imports.add(
        ImportModel(
          uri: directive.uri.stringValue ?? '',
          // FIX: Removed .lexeme because .name is already a String
          prefix: directive.prefix?.name,
          isDeferred: directive.deferredKeyword != null,
          shownNames: _extractShownNames(directive),
          hiddenNames: _extractHiddenNames(directive),
          offset: directive.offset,
          endOffset: directive.end,
        ),
      );
    }

    return imports;
  }

  List<String> _extractShownNames(
    ImportDirective directive,
  ) {
    final names = <String>[];

    for (final combinator in directive.combinators) {
      if (combinator is ShowCombinator) {
        names.addAll(
          combinator.shownNames.map(
            // FIX: Removed .lexeme
            (e) => e.name,
          ),
        );
      }
    }

    return List.unmodifiable(names);
  }

  List<String> _extractHiddenNames(
    ImportDirective directive,
  ) {
    final names = <String>[];

    for (final combinator in directive.combinators) {
      if (combinator is HideCombinator) {
        names.addAll(
          combinator.hiddenNames.map(
            // FIX: Removed .lexeme
            (e) => e.name,
          ),
        );
      }
    }

    return List.unmodifiable(names);
  }
}
