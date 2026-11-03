/// Splits source-rule expressions without breaking quoted or nested content.
class RuleTokenizer {
  const RuleTokenizer();

  List<String> splitTopLevel(String input, String separator) {
    if (separator.isEmpty) {
      throw ArgumentError.value(separator, 'separator', 'must not be empty');
    }
    final parts = <String>[];
    var start = 0;
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    int? quote;
    var escaped = false;

    for (var index = 0; index < input.length; index++) {
      final code = input.codeUnitAt(index);
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == quote) {
          quote = null;
        }
        continue;
      }
      if (code == 0x22 || code == 0x27) {
        quote = code;
        continue;
      }
      if (code == 0x28) {
        parentheses++;
      } else if (code == 0x29) {
        if (parentheses > 0) parentheses--;
      } else if (code == 0x5b) {
        brackets++;
      } else if (code == 0x5d) {
        if (brackets > 0) brackets--;
      } else if (code == 0x7b) {
        braces++;
      } else if (code == 0x7d && braces > 0) {
        braces--;
      }
      if (parentheses == 0 &&
          brackets == 0 &&
          braces == 0 &&
          input.startsWith(separator, index)) {
        parts.add(input.substring(start, index));
        index += separator.length - 1;
        start = index + 1;
      }
    }
    parts.add(input.substring(start));
    return List.unmodifiable(parts);
  }

  int indexOfTopLevel(String input, String marker) {
    if (marker.isEmpty) return -1;
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    int? quote;
    var escaped = false;
    for (var index = 0; index < input.length; index++) {
      final code = input.codeUnitAt(index);
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == quote) {
          quote = null;
        }
        continue;
      }
      if (code == 0x22 || code == 0x27) {
        quote = code;
        continue;
      }
      if (code == 0x28) {
        parentheses++;
      } else if (code == 0x29 && parentheses > 0) {
        parentheses--;
      } else if (code == 0x5b) {
        brackets++;
      } else if (code == 0x5d && brackets > 0) {
        brackets--;
      } else if (code == 0x7b) {
        braces++;
      } else if (code == 0x7d && braces > 0) {
        braces--;
      }
      if (parentheses == 0 &&
          brackets == 0 &&
          braces == 0 &&
          input.startsWith(marker, index)) {
        return index;
      }
    }
    return -1;
  }
}
