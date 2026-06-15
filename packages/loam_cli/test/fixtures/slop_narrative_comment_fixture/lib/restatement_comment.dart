// ignore_for_file: unnecessary_getters_setters, unused_element – fixture declarations are loaded by ProjectLoader only.

class _Counter {
  // constructor
  _Counter();

  int _value = 0;

  // getter
  int get _count => _value < 0 ? 0 : _value;

  // setter
  set _count(int v) {
    _value = v;
  }
}
