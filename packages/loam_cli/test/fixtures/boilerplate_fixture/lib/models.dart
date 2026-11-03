// ignore_for_file: public_member_api_docs
// Two value classes whose boilerplate is intentionally identical, plus two
// real (non-boilerplate) duplicates that must still be reported.

class Point {
  Point({required this.x, required this.y, required this.label, this.tag});

  factory Point.fromJson(Map<String, dynamic> json) {
    final x = json['x'] as int;
    final y = json['y'] as int;
    final label = json['label'] as String;
    final tag = json['tag'] as String?;
    return Point(x: x, y: y, label: label, tag: tag);
  }

  final int x;
  final int y;
  final String label;
  final String? tag;

  Point copyWith({int? x, int? y, String? label, String? tag}) {
    return Point(
      x: x ?? this.x,
      y: y ?? this.y,
      label: label ?? this.label,
      tag: tag ?? this.tag,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    result['x'] = x;
    result['y'] = y;
    result['label'] = label;
    result['tag'] = tag;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Point &&
        other.x == x &&
        other.y == y &&
        other.label == label &&
        other.tag == tag;
  }

  @override
  int get hashCode {
    var result = 17;
    result = 31 * result + x.hashCode;
    result = 31 * result + y.hashCode;
    result = 31 * result + label.hashCode;
    result = 31 * result + tag.hashCode;
    return result;
  }

  @override
  String toString() {
    final buffer = StringBuffer('Point(');
    buffer.write('x: $x, ');
    buffer.write('y: $y, ');
    buffer.write('label: $label, ');
    buffer.write('tag: $tag)');
    return buffer.toString();
  }

  // Real duplicate (also present in Size.describe): must still be reported.
  String describe(List<int> values) {
    final sorted = [...values]..sort();
    var total = 0;
    for (final v in sorted) {
      if (v.isEven) {
        total += v * 2;
      } else {
        total -= v;
      }
    }
    return 'sum=$total first=${sorted.first} last=${sorted.last}';
  }

  // Named copyWith but a positional parameter: not boilerplate by form.
  Point copyWithPositional(int nx, int ny, String nlabel, String? ntag) {
    final result = Point(x: nx, y: ny, label: nlabel, tag: ntag);
    final adjusted = Point(x: result.x + 1, y: result.y + 1, label: nlabel);
    return adjusted.x > 100 ? result : adjusted;
  }
}

class Size {
  Size({required this.w, required this.h, required this.name, this.unit});

  factory Size.fromJson(Map<String, dynamic> json) {
    final w = json['w'] as int;
    final h = json['h'] as int;
    final name = json['name'] as String;
    final unit = json['unit'] as String?;
    return Size(w: w, h: h, name: name, unit: unit);
  }

  final int w;
  final int h;
  final String name;
  final String? unit;

  Size copyWith({int? w, int? h, String? name, String? unit}) {
    return Size(
      w: w ?? this.w,
      h: h ?? this.h,
      name: name ?? this.name,
      unit: unit ?? this.unit,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    result['w'] = w;
    result['h'] = h;
    result['name'] = name;
    result['unit'] = unit;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Size &&
        other.w == w &&
        other.h == h &&
        other.name == name &&
        other.unit == unit;
  }

  @override
  int get hashCode {
    var result = 17;
    result = 31 * result + w.hashCode;
    result = 31 * result + h.hashCode;
    result = 31 * result + name.hashCode;
    result = 31 * result + unit.hashCode;
    return result;
  }

  @override
  String toString() {
    final buffer = StringBuffer('Size(');
    buffer.write('w: $w, ');
    buffer.write('h: $h, ');
    buffer.write('name: $name, ');
    buffer.write('unit: $unit)');
    return buffer.toString();
  }

  String describe(List<int> values) {
    final sorted = [...values]..sort();
    var total = 0;
    for (final v in sorted) {
      if (v.isEven) {
        total += v * 2;
      } else {
        total -= v;
      }
    }
    return 'sum=$total first=${sorted.first} last=${sorted.last}';
  }

  Size copyWithPositional(int nw, int nh, String nname, String? nunit) {
    final result = Size(w: nw, h: nh, name: nname, unit: nunit);
    final adjusted = Size(w: result.w + 1, h: result.h + 1, name: nname);
    return adjusted.w > 100 ? result : adjusted;
  }
}
