import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/aguiluchos_app.dart';
import 'config/env.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/remote_nidos_gateway.dart';
import 'services/seed_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');

  DatabaseService.configureDesktopFactory();
  final db = DatabaseService();
  await db.init();
  await SeedService().cargarSiProcede(db);

  // Supabase solo se inicializa si hay credenciales reales. Sin ellas (o sin
  // red al arrancar) la app funciona igualmente en modo solo-local.
  RemoteNidosGateway? gateway;
  AuthService? auth;
  if (Env.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: Env.supabaseAnonKey,
      );
      gateway = SupabaseNidosGateway(Supabase.instance.client);
      // La sesión se guarda en el dispositivo: tras el primer acceso no hace
      // falta red para abrir la app.
      auth = AuthService(
        backend: SupabaseAuthBackend(Supabase.instance.client.auth),
        requiresLogin: Env.requireLogin,
      );
    } catch (e) {
      debugPrint('Supabase no disponible, modo solo local: $e');
    }
  } else {
    debugPrint('Supabase sin configurar (--dart-define): modo solo local.');
  }

  final sync = SyncService(db: db, gateway: gateway, auth: auth);
  runApp(AguiluchosApp(db: db, sync: sync, auth: auth));
  // Al volver a primer plano se baja lo que haya cambiado en la oficina.
  AppLifecycleListener(onResume: sync.onAppResumed);
  // No bloquea el arranque: escucha conectividad y sincroniza si procede.
  sync.start();
}
