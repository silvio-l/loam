// Entrypoint outside lib/ — must NOT be collected by FunctionComplexityCollector.
import 'package:complexity_collector_fixture/calculator.dart';

void main() {
  final calc = Calculator(0);
  print(calc.add(1, 2));
}
