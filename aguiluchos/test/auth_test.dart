import 'dart:async';
import 'dart:io';

import 'package:aguiluchos/app/aguiluchos_app.dart';
import 'package:aguiluchos/models/nido_grefa_model.dart';
import 'package:aguiluchos/screens/login_screen.dart';
import 'package:aguiluchos/services/auth_service.dart';
import 'package:aguiluchos/services/database_service.dart';
import 'package:aguiluchos/services/image_storage_service.dart';
import 'package:aguiluchos/services/last_write_wins.dart';
import 'package:aguiluchos/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'helpers/fakes.dart';

class FakeAuthBackend implements AuthBackend {
  final _ctrl = StreamController<String?>.broadcast();
  String? _email;
  Object? failWith;
  int signOuts = 0;

  @override
  String? get currentEmail => _email;

  @override
  Stream<String?> get emailChanges => _ctrl.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (failWith != null) throw failWith!;
    _email = email;
    _ctrl.add(email);
  }

  /// `true`: el alta deja la sesión iniciada; `false`: exige confirmar el correo.
  bool signUpConSesion = false;
  String? ultimoAlta;
  String? ultimoRedirectAlta;
  String? ultimoReset;
  String? ultimoRedirectReset;
  String? claveNueva;

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String redirectTo,
  }) async {
    if (failWith != null) throw failWith!;
    ultimoAlta = '$email|$fullName';
    ultimoRedirectAlta = redirectTo;
    if (signUpConSesion) {
      _email = email;
      _ctrl.add(email);
    }
    return signUpConSesion;
  }

  @override
  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  }) async {
    if (failWith != null) throw failWith!;
    ultimoReset = email;
    ultimoRedirectReset = redirectTo;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    if (failWith != null) throw failWith!;
    claveNueva = newPassword;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _email = null;
    _ctrl.add(null);
  }

  Future<void> close() => _ctrl.close();
}

void main() {
  group('AuthService', () {
    late FakeAuthBackend backend;
    late AuthService auth;

    setUp(() {
      backend = FakeAuthBackend();
      auth = AuthService(backend: backend, requiresLogin: true);
    });

    tearDown(() async {
      auth.dispose();
      await backend.close();
    });

    test('sin sesión exige login y no puede sincronizar', () {
      expect(auth.isSignedIn, isFalse);
      expect(auth.needsLoginScreen, isTrue);
      expect(auth.canSync, isFalse);
    });

    test('iniciar sesión permite sincronizar y oculta el login', () async {
      await auth.signIn('  ana@grefa.org ', 'secreto');
      expect(auth.isSignedIn, isTrue);
      expect(auth.email, 'ana@grefa.org');
      expect(auth.canSync, isTrue);
      expect(auth.needsLoginScreen, isFalse);
    });

    test('credenciales erróneas dan un mensaje en español', () async {
      backend.failWith = const AuthException('Invalid login credentials');
      await expectLater(
        auth.signIn('a@b.c', 'mala'),
        throwsA(isA<AuthFailure>().having(
            (e) => e.message, 'message', 'Correo o contraseña incorrectos.')),
      );
      expect(auth.isSignedIn, isFalse);
    });

    test('error de red se explica como falta de conexión', () async {
      backend.failWith = const SocketException('sin red');
      await expectLater(
        auth.signIn('a@b.c', 'x'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.message, 'message', contains('Sin conexión'))),
      );
    });

    test('trabajar sin conexión salta el login pero no sincroniza', () {
      auth.workOffline();
      expect(auth.needsLoginScreen, isFalse);
      expect(auth.canSync, isFalse);
      auth.requestLogin();
      expect(auth.needsLoginScreen, isTrue);
    });

    test('cerrar sesión vuelve a pedir el acceso', () async {
      await auth.signIn('a@b.c', 'x');
      await auth.signOut();
      expect(backend.signOuts, 1);
      expect(auth.isSignedIn, isFalse);
      expect(auth.needsLoginScreen, isTrue);
    });

    test('solo se admiten correos @grefa.org', () {
      expect(AuthService.correoPermitido('ana@grefa.org'), isTrue);
      expect(AuthService.correoPermitido('  Ana.Lopez@GREFA.ORG '), isTrue);
      expect(AuthService.correoPermitido('ana@gmail.com'), isFalse);
      expect(AuthService.correoPermitido('ana@gref.org'), isFalse);
      expect(AuthService.correoPermitido('ana@grefa.org.evil.com'), isFalse);
      expect(AuthService.correoPermitido('x@evil.com@grefa.org'), isFalse);
      expect(AuthService.correoPermitido('@grefa.org'), isFalse);
    });

    test('crear cuenta: valida dominio y clave, y pide confirmar el correo',
        () async {
      await expectLater(
        auth.signUp(email: 'ana@gmail.com', password: 'abcdefgh', fullName: 'Ana'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.message, 'message', contains('@grefa.org'))),
      );
      await expectLater(
        auth.signUp(email: 'ana@grefa.org', password: 'corta', fullName: 'Ana'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.message, 'message', contains('8 caracteres'))),
      );
      expect(backend.ultimoAlta, isNull);

      final r = await auth.signUp(
          email: ' Ana@Grefa.org ', password: 'abcdefgh', fullName: ' Ana L. ');
      expect(r, SignUpResult.confirmEmail);
      expect(backend.ultimoAlta, 'ana@grefa.org|Ana L.');
      expect(backend.ultimoRedirectAlta, AuthService.urlConfirmacion);
      expect(auth.isSignedIn, isFalse);
    });

    test('crear cuenta sin confirmación deja la sesión iniciada', () async {
      backend.signUpConSesion = true;
      final r = await auth.signUp(
          email: 'ana@grefa.org', password: 'abcdefgh', fullName: 'Ana');
      expect(r, SignUpResult.signedIn);
      expect(auth.isSignedIn, isTrue);
    });

    test('recuperar contraseña envía el enlace a grefa-proyectos', () async {
      await auth.resetPassword(' Ana@grefa.org ');
      expect(backend.ultimoReset, 'ana@grefa.org');
      expect(backend.ultimoRedirectReset, AuthService.urlRecuperacion);
      expect(AuthService.urlRecuperacion, contains('/actualizar-contrasena'));
      await expectLater(auth.resetPassword('sin-arroba'),
          throwsA(isA<AuthFailure>()));
    });

    test('cambiar contraseña exige sesión y mínimo de caracteres', () async {
      await expectLater(auth.changePassword('abcdefgh'),
          throwsA(isA<AuthFailure>()));
      await auth.signIn('ana@grefa.org', 'x');
      await expectLater(auth.changePassword('corta'),
          throwsA(isA<AuthFailure>()));
      await auth.changePassword('nueva-clave-1');
      expect(backend.claveNueva, 'nueva-clave-1');
    });

    test('solo aquilagestion@grefa.org es administrador y puede borrar', () async {
      await auth.signIn('ana@grefa.org', 'x');
      expect(auth.isAdmin, isFalse);
      expect(auth.canDelete, isFalse);
      await auth.signOut();
      await auth.signIn('AquilaGestion@grefa.org', 'x');
      expect(auth.isAdmin, isTrue);
      expect(auth.canDelete, isTrue);
      // Sin login obligatorio (solo local) no hay restricción.
      expect(AuthService().canDelete, isTrue);
    });

    test('sin requiresLogin (piloto) nunca bloquea', () {
      final piloto = AuthService(backend: backend, requiresLogin: false);
      expect(piloto.needsLoginScreen, isFalse);
      expect(piloto.canSync, isTrue);
      piloto.dispose();
    });
  });

  group('SyncService con login', () {
    late FakeClock clock;
    late DatabaseService db;
    late FakeGateway gw;
    late FakeAuthBackend backend;
    late AuthService auth;
    late SyncService sync;
    late StreamController<bool> conn;

    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (sync.state.status != SyncStatus.syncing) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (sync.state.status != SyncStatus.syncing) return;
        }
      }
    }

    setUp(() async {
      clock = FakeClock();
      db = await openTestDb(clock);
      gw = FakeGateway();
      backend = FakeAuthBackend();
      auth = AuthService(backend: backend, requiresLogin: true);
      conn = StreamController<bool>.broadcast();
    });

    tearDown(() async {
      sync.dispose();
      auth.dispose();
      await backend.close();
      await conn.close();
      await db.close();
    });

    Future<void> arrancar({
      Duration periodic = const Duration(hours: 1),
    }) async {
      sync = SyncService(
        db: db,
        gateway: gw,
        auth: auth,
        connectivityStream: conn.stream,
        initialConnectivity: () async => true,
        clock: clock.call,
        periodicInterval: periodic,
      );
      await sync.start();
      await settle();
    }

    test('sin sesión no habla con el servidor y lo indica', () async {
      await arrancar();
      await db.guardar(nidoDeEjemplo());
      final r = await sync.syncNow();
      expect(r.skippedReason, contains('Inicia sesión'));
      expect(gw.upsertCalls, 0);
      expect(sync.state.needsLogin, isTrue);
      expect(sync.state.pendingCount, 1);
    });

    test('al iniciar sesión sube lo pendiente automáticamente', () async {
      await arrancar();
      await db.guardar(nidoDeEjemplo(etiqueta: 'P-1'));
      expect(gw.upsertCalls, 0);

      await auth.signIn('ana@grefa.org', 'x');
      await settle();
      for (var i = 0; i < 20 && gw.upsertCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await settle();

      expect(gw.upsertCalls, 1);
      expect(sync.state.needsLogin, isFalse);
      expect(sync.state.pendingCount, 0);
    });

    test('el sondeo periódico baja cambios de la web sin pendientes', () async {
      await auth.signIn('ana@grefa.org', 'x');
      await arrancar(periodic: const Duration(milliseconds: 60));
      expect(await db.consultar(), isEmpty);

      // Alguien edita en el panel web.
      gw.remoteWrite(nidoDeEjemplo(
          etiqueta: 'WEB-1', updatedAt: DateTime.utc(2026, 5, 1, 12)));

      for (var i = 0; i < 40 && (await db.consultar()).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final locales = await db.consultar();
      expect(locales.map((n) => n.etiqueta), ['WEB-1']);
      expect(sync.state.pendingCount, 0);
    });
  });

  group('Carga inicial vs. Supabase', () {
    test('la carga inicial sin editar cede ante la versión remota sin conflicto', () {
      final local = nidoDeEjemplo(
          id: 'x', updatedAt: NidoGrefaModel.marcaCargaInicial)
        ..isSynced = false;
      final remote = nidoDeEjemplo(id: 'x', updatedAt: DateTime.utc(2026, 11, 2));
      expect(local.esCargaInicialSinEditar, isTrue);
      expect(LastWriteWins.resolve(local: local, remote: remote),
          LwwDecision.takeRemote);
    });

    test('un nido editado por el operario sigue generando conflicto', () {
      final local = nidoDeEjemplo(id: 'x', updatedAt: DateTime.utc(2026, 11, 1))
        ..isSynced = false;
      final remote = nidoDeEjemplo(id: 'x', updatedAt: DateTime.utc(2026, 11, 2));
      expect(local.esCargaInicialSinEditar, isFalse);
      expect(LastWriteWins.resolve(local: local, remote: remote),
          LwwDecision.takeRemoteWithConflict);
    });
  });

  group('Pantalla de acceso', () {
    late DatabaseService db;
    late SyncService sync;
    late Directory tmp;
    late FakeAuthBackend backend;
    late AuthService auth;

    setUpAll(() async {
      await initializeDateFormatting('es_ES');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
    });

    Future<void> arrancar(WidgetTester tester) async {
      await tester.runAsync(() async {
        db = await openTestDb(FakeClock());
        tmp = await Directory.systemTemp.createTemp('auth_widget_test');
      });
      backend = FakeAuthBackend();
      auth = AuthService(backend: backend, requiresLogin: true);
      sync = SyncService(db: db, auth: auth);
      // Pantalla alta: el formulario de alta no cabe en 600 px de alto.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AguiluchosApp(
        db: db,
        sync: sync,
        auth: auth,
        images: ImageStorageService(baseDirectory: tmp),
      ));
      await tester.pump();
    }

    Future<void> cerrar(WidgetTester tester) async {
      // Desmonta el árbol antes de cerrar la BD (HomeScreen escucha cambios).
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 15));
      sync.dispose();
      auth.dispose();
      await backend.close();
      await tester.runAsync(() async {
        await db.close();
        await tmp.delete(recursive: true);
      });
    }

    testWidgets('muestra el login, rechaza datos vacíos y errores de servidor',
        (tester) async {
      await arrancar(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('login-entrar')));
      await tester.pump();
      expect(find.text('Escribe un correo válido'), findsOneWidget);
      expect(find.text('Escribe la contraseña'), findsOneWidget);

      backend.failWith = const AuthException('Invalid login credentials');
      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'ana@grefa.org');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'mala');
      await tester.tap(find.byKey(const ValueKey('login-entrar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('crear cuenta y recuperar contraseña desde la pantalla de acceso',
        (tester) async {
      await arrancar(tester);

      // Recuperar contraseña.
      await tester.tap(find.byKey(const ValueKey('login-olvide')));
      await tester.pump();
      expect(find.byKey(const ValueKey('login-password')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'ana@grefa.org');
      await tester.tap(find.byKey(const ValueKey('login-entrar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(backend.ultimoReset, 'ana@grefa.org');
      expect(find.byKey(const ValueKey('login-info')), findsOneWidget);

      // Crear cuenta: rechaza otros dominios y contraseñas distintas.
      await tester.tap(find.byKey(const ValueKey('login-crear')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('login-nombre')), 'Ana López');
      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'ana@gmail.com');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'abcdefgh');
      await tester.enterText(
          find.byKey(const ValueKey('login-password2')), 'otra-cosa');
      await tester.tap(find.byKey(const ValueKey('login-entrar')));
      await tester.pump();
      expect(find.text('Solo correos @grefa.org'), findsOneWidget);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(backend.ultimoAlta, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'ana@grefa.org');
      await tester.enterText(
          find.byKey(const ValueKey('login-password2')), 'abcdefgh');
      await tester.tap(find.byKey(const ValueKey('login-entrar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(backend.ultimoAlta, 'ana@grefa.org|Ana López');
      // Vuelve al acceso con el aviso de confirmar el correo.
      expect(find.textContaining('Cuenta creada'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('trabajar sin conexión entra en la app principal',
        (tester) async {
      await arrancar(tester);
      await tester.tap(find.byKey(const ValueKey('login-sin-conexion')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('GREFA - Campaña Aguilucho'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('con sesión correcta se entra directamente a la app',
        (tester) async {
      await arrancar(tester);
      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'ana@grefa.org');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'bien');
      await tester.tap(find.byKey(const ValueKey('login-entrar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('GREFA - Campaña Aguilucho'), findsOneWidget);
      await cerrar(tester);
    });
  });
}
