/// A tiny, dependency-free arithmetic evaluator supporting + - * / and
/// decimal points, with standard operator precedence. Good enough to
/// make the decoy calculator behave like a real one.
class CalculatorEngine {
  double evaluate(String expression) {
    final tokens = _tokenize(expression);
    if (tokens.isEmpty) return 0;
    final parser = _Parser(tokens);
    return parser.parseExpression();
  }

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      if ('0123456789.'.contains(ch)) {
        buffer.write(ch);
      } else if ('+-*/'.contains(ch)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(ch);
      }
      // any other character (e.g. a trailing '=') is ignored by the engine
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}

class _Parser {
  _Parser(this.tokens);
  final List<String> tokens;
  int _pos = 0;

  String? get _peek => _pos < tokens.length ? tokens[_pos] : null;

  double parseExpression() {
    var value = parseTerm();
    while (_peek == '+' || _peek == '-') {
      final op = tokens[_pos++];
      final rhs = parseTerm();
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  }

  double parseTerm() {
    var value = parseFactor();
    while (_peek == '*' || _peek == '/') {
      final op = tokens[_pos++];
      final rhs = parseFactor();
      value = op == '*' ? value * rhs : value / rhs;
    }
    return value;
  }

  double parseFactor() {
    final token = _peek;
    if (token == null) return 0;
    _pos++;
    return double.tryParse(token) ?? 0;
  }
}

