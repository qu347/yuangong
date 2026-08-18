import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthSessionStatus { loading, authenticated, unauthenticated }

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  final store = AuthSessionStore();
  ref.onDispose(store.dispose);
  return store;
});

class AuthSessionStore extends ChangeNotifier {
  AuthSessionStatus _status = AuthSessionStatus.loading;

  AuthSessionStatus get status => _status;

  void markLoading() => _setStatus(AuthSessionStatus.loading);
  void markAuthenticated() => _setStatus(AuthSessionStatus.authenticated);
  void markUnauthenticated() => _setStatus(AuthSessionStatus.unauthenticated);

  void _setStatus(AuthSessionStatus nextStatus) {
    if (_status == nextStatus) {
      return;
    }
    _status = nextStatus;
    notifyListeners();
  }
}
