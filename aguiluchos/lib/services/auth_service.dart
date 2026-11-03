import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de autenticación con un mensaje ya listo para mostrar al operario.
class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Resultado de crear una cuenta.
enum SignUpResult {
  /// Supabase no exige confirmar el correo: ya hay sesión iniciada.
  signedIn,

  /// Se envió un correo de confirmación: hay que abrir el enlace y luego entrar.
  confirmEmail,
}

/// Abstracción del proveedor de identidad (Supabase Auth): permite probar
/// [AuthService] y la pantalla de acceso sin red.
abstract class AuthBackend {
  /// Correo de la sesión guardada en el dispositivo (o `null` si no hay).
  String? get currentEmail;

  /// Emite el correo al iniciar sesión y `null` al cerrarla o caducar.
  Stream<String?> get emailChanges;

  Future<void> signIn({required String email, required String password});

  /// Crea la cuenta. Devuelve `true` si ya queda con sesión iniciada.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String redirectTo,
  });

  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  });

  Future<void> updatePassword(String newPassword);

  /// Cierra la sesión solo en este dispositivo (no necesita red).
  Future<void> signOut();
}

class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._auth);

  final GoTrueClient _auth;

  static String? _emailDe(Session? s) =>
      s == null ? null : (s.user.email ?? 'usuario');

  @override
  String? get currentEmail => _emailDe(_auth.currentSession);

  @override
  Stream<String?> get emailChanges =>
      _auth.onAuthStateChange.map((s) => _emailDe(s.session));

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String redirectTo,
  }) async {
    final r = await _auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
      emailRedirectTo: redirectTo,
    );
    return r.session != null;
  }

  @override
  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  }) =>
      _auth.resetPasswordForEmail(email, redirectTo: redirectTo);

  @override
  Future<void> updatePassword(String newPassword) async {
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<void> signOut() => _auth.signOut(scope: SignOutScope.local);
}

/// Estado de acceso de la app.
///
/// * Con Supabase configurado y `requiresLogin`, la sincronización solo
///   funciona con una sesión de Supabase Auth (las políticas RLS exigen el rol
///   `authenticated` y un correo `@grefa.org`).
/// * Cualquiera con correo `@grefa.org` puede crear su cuenta; el único
///   administrador es [adminEmail] (es el único que puede borrar nidos).
/// * El operario siempre puede **trabajar sin conexión** (solo local): los
///   datos se guardan y se subirán cuando inicie sesión.
/// * La sesión se conserva en el dispositivo: tras el primer acceso no hace
///   falta red para abrir la app.
class AuthService extends ChangeNotifier {
  AuthService({AuthBackend? backend, this.requiresLogin = false})
      : _backend = backend {
    _email = backend?.currentEmail;
    _sub = backend?.emailChanges.listen((email) {
      if (email == _email) return;
      _email = email;
      if (email != null) _workOffline = false;
      notifyListeners();
    });
  }

  /// Dominio de correo con acceso a los datos.
  static const dominioPermitido = '@grefa.org';

  /// Único administrador de la campaña.
  static const adminEmail = 'aquilagestion@grefa.org';

  /// Los enlaces de confirmación y recuperación abren la web de GREFA
  /// (grefa-proyectos), que ya sabe fijar la contraseña nueva. Misma cuenta:
  /// ambos sistemas comparten el proyecto de Supabase.
  static const urlConfirmacion =
      'https://grefa-proyectos.vercel.app/auth/callback?next=/';
  static const urlRecuperacion =
      'https://grefa-proyectos.vercel.app/auth/callback?next=/actualizar-contrasena';

  static const minLongitudClave = 8;

  final AuthBackend? _backend;

  /// `false` si no hay Supabase o el piloto se compiló sin login.
  final bool requiresLogin;

  StreamSubscription<String?>? _sub;
  String? _email;
  bool _workOffline = false;

  bool get isSignedIn => _email != null;
  String? get email => _email;

  bool get isAdmin => _email?.toLowerCase() == adminEmail;

  /// Borrar nidos: solo el administrador (o la app sin cuentas, solo local).
  bool get canDelete => !requiresLogin || isAdmin;

  /// `true` si la app puede hablar con Supabase en nombre del usuario.
  bool get canSync => !requiresLogin || isSignedIn;

  /// `true` mientras toca mostrar la pantalla de acceso.
  bool get needsLoginScreen => requiresLogin && !isSignedIn && !_workOffline;

  /// Correo del dominio de GREFA (`nombre@grefa.org`).
  static bool correoPermitido(String email) {
    final e = email.trim().toLowerCase();
    return e.endsWith(dominioPermitido) &&
        e.length > dominioPermitido.length &&
        !e.contains(' ') &&
        e.indexOf('@') == e.length - dominioPermitido.length;
  }

  Future<void> signIn(String email, String password) async {
    final backend = _requireBackend();
    await _wrap(() => backend.signIn(email: email.trim(), password: password));
    // El estado lo actualiza `emailChanges`; se refuerza por si el evento
    // llega después de volver de este método.
    _email = backend.currentEmail;
    _workOffline = false;
    notifyListeners();
  }

  /// Crea una cuenta (solo correos `@grefa.org`).
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final backend = _requireBackend();
    if (!correoPermitido(email)) {
      throw AuthFailure('Solo se admiten correos $dominioPermitido.');
    }
    _validarClave(password);
    late final bool conSesion;
    await _wrap(() async {
      conSesion = await backend.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        fullName: fullName.trim(),
        redirectTo: urlConfirmacion,
      );
    });
    if (conSesion) {
      _email = backend.currentEmail;
      _workOffline = false;
      notifyListeners();
      return SignUpResult.signedIn;
    }
    return SignUpResult.confirmEmail;
  }

  /// Envía el correo para elegir una contraseña nueva.
  Future<void> resetPassword(String email) async {
    final backend = _requireBackend();
    if (!email.trim().contains('@')) {
      throw AuthFailure('Escribe tu correo electrónico.');
    }
    await _wrap(() => backend.sendPasswordReset(
        email: email.trim().toLowerCase(), redirectTo: urlRecuperacion));
  }

  /// Cambia la contraseña del usuario con sesión iniciada.
  Future<void> changePassword(String newPassword) async {
    final backend = _requireBackend();
    if (!isSignedIn) throw AuthFailure('Inicia sesión para cambiar la contraseña.');
    _validarClave(newPassword);
    await _wrap(() => backend.updatePassword(newPassword));
  }

  Future<void> signOut() async {
    try {
      await _backend?.signOut();
    } finally {
      _email = null;
      _workOffline = false;
      notifyListeners();
    }
  }

  /// Entra en la app sin sesión (solo local, sin sincronizar).
  void workOffline() {
    _workOffline = true;
    notifyListeners();
  }

  /// Vuelve a mostrar la pantalla de acceso (desde el menú de la app).
  void requestLogin() {
    _workOffline = false;
    notifyListeners();
  }

  AuthBackend _requireBackend() {
    final b = _backend;
    if (b == null) throw AuthFailure('Supabase no está configurado.');
    return b;
  }

  static void _validarClave(String clave) {
    if (clave.length < minLongitudClave) {
      throw AuthFailure(
          'La contraseña debe tener al menos $minLongitudClave caracteres.');
    }
  }

  Future<void> _wrap(Future<void> Function() action) async {
    try {
      await action();
    } on AuthException catch (e) {
      throw AuthFailure(_mensaje(e));
    } on TimeoutException {
      throw AuthFailure(_sinConexion);
    } on AuthFailure {
      rethrow;
    } on Exception catch (e) {
      // SocketException / ClientException (sin red, DNS...).
      throw AuthFailure('$_sinConexion (${e.runtimeType})');
    }
  }

  static const _sinConexion =
      'Sin conexión: para esta acción se necesita internet.';

  static String _mensaje(AuthException e) {
    if (e is AuthRetryableFetchException) return _sinConexion;
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('not confirmed')) {
      return 'El correo todavía no está confirmado. Abre el enlace que te enviamos.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'Ese correo ya tiene cuenta. Inicia sesión o recupera la contraseña.';
    }
    if (m.contains('same password') || m.contains('different from the old')) {
      return 'La contraseña nueva debe ser distinta de la actual.';
    }
    if (m.contains('weak') || m.contains('at least')) {
      return 'La contraseña es demasiado débil: usa al menos '
          '$minLongitudClave caracteres.';
    }
    if (m.contains('rate limit') || e.statusCode == '429') {
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }
    return 'No se pudo completar la acción: ${e.message}';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
