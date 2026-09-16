/// Library-level doc comment for the fixture.
library atelier.fixture;

import 'dart:math' as math;
import 'dart:async' show Future, Stream;
import 'package:meta/meta.dart' hide protected;
export 'src/thing.dart';
part 'part_file.dart';

// A line comment.
/* A block comment. */

/// Doc comment for a typedef.
typedef Callback<T> = void Function(T value, {bool flag});

const int kMaxItems = 42;
const double kRatio = 3.14e2;
final String greeting = 'hello';
var hex = 0xFF_FF;
late final int lateValue;

enum Color { red, green, blue }

sealed class Shape {
  const Shape();
}

/// A point with two fields.
@immutable
class Point<T extends num> extends Shape implements Comparable<Point<T>> {
  final T x;
  final T y;
  static int count = 0;
  static const int zero = 0;
  List<String> tags = <String>[];
  Map<String, int> lookup = const {'a': 1};

  const Point(this.x, this.y) : super();

  Point.origin() : this(0 as T, 0 as T);

  factory Point.fromJson(Map<String, dynamic> json) {
    return Point(json['x'] as T, json['y'] as T);
  }

  double get magnitude => math.sqrt((x * x + y * y).toDouble());

  set label(String value) {
    tags.add(value);
  }

  @override
  int compareTo(Point<T> other) => magnitude.compareTo(other.magnitude);

  Point<T> operator +(Point<T> other) => Point(x + other.x as T, y + other.y as T);

  @override
  String toString() => 'Point($x, $y) with ${tags.length} tags\n\tA \$escaped';
}

mixin Loggable on Shape {
  void log(String msg) => print('[${runtimeType}] $msg');
}

extension IntExt on int {
  bool get isBig => this > kMaxItems;
}

abstract class Repo<T> {
  Future<T?> find(int id);
  Stream<T> watch();
}

Future<int> compute(int a, [int b = 2, double? c]) async {
  await Future.delayed(const Duration(milliseconds: 10));
  var total = a + b * (c ?? 1).toInt();
  total ~/= 2;
  total <<= 1;
  total ??= 0;
  total += 1;
  total--;
  ++total;
  return total;
}

Iterable<int> squares(int n) sync* {
  for (var i = 0; i < n; i++) {
    yield i * i;
  }
}

void control(List<int> items, {required String name, int retries = 3}) {
  outer:
  for (final item in items) {
    if (item.isEven && item != 0 || item < -1) {
      continue outer;
    } else if (item % 3 == 0) {
      break;
    } else {
      print(item.toString());
    }
  }
  var i = 0;
  while (i < retries) {
    i++;
  }
  do {
    i--;
  } while (i > 0);
  switch (name) {
    case 'a':
      print("double quoted $name");
      break;
    case 'b':
    default:
      print(r'raw string \n');
  }
  final desc = switch (i) {
    0 => 'zero',
    _ when i > 10 => 'big',
    _ => 'other',
  };
  try {
    throw StateError(desc);
  } on StateError catch (e, st) {
    print('$e $st');
    rethrow;
  } catch (e) {
    assert(e != null, 'never');
  } finally {
    print(i.isBig ? true : false);
  }
  final list = [1, 2.5, 0x1F, 1e10, .5];
  final set = {1, 2, 3};
  final sym = #symbolName;
  final p = Point<int>(1, 2)
    ..label = 'x'
    ..tags.add('y');
  final sb = StringBuffer()..write('a')..writeln('b');
  final fn = (int v) => v * 2;
  final maybe = p?.tags?.length;
  final s = '''multi
line ${fn(3)}''';
  const cond = kMaxItems is int && cond is! String;
  print(list.length + set.length + sym.hashCode + maybe! + s.length);
  Color c = Color.red;
  var y = c == Color.red ? null : c;
  var nn = y! as Color;
  print(nn);
}
