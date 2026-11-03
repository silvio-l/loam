import '../core/base.dart';
import '../services/repo.dart';

class Home {
  Home(this.base) : repo = Repo(base);
  final Base base;
  final Repo repo;
}
