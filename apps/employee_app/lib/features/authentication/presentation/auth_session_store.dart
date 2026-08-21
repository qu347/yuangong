import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/current_user.dart';

enum AuthSessionStatus { loading, authenticated, unauthenticated }

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  final store = AuthSessionStore();
  ref.onDispose(store.dispose);
  return store;
});

class AuthSessionStore extends ChangeNotifier {
  AuthSessionStatus _status = AuthSessionStatus.loading;
  UserCapabilities _capabilities = const UserCapabilities.none();
  String? _employeeId;

  AuthSessionStatus get status => _status;
  UserCapabilities get capabilities => _capabilities;
  String? get employeeId => _employeeId;

  void markLoading() {
    _employeeId = null;
    _setStatus(AuthSessionStatus.loading, forceNotify: true);
  }

  void markAuthenticated([CurrentUser? user]) {
    _capabilities = user?.capabilities ?? const UserCapabilities.none();
    _employeeId = user?.employeeId;
    _setStatus(AuthSessionStatus.authenticated, forceNotify: true);
  }

  void markUnauthenticated() {
    _capabilities = const UserCapabilities.none();
    _employeeId = null;
    _setStatus(AuthSessionStatus.unauthenticated, forceNotify: true);
  }

  void _setStatus(AuthSessionStatus nextStatus, {bool forceNotify = false}) {
    if (_status == nextStatus && !forceNotify) {
      return;
    }
    _status = nextStatus;
    notifyListeners();
  }
}
