import 'package:flutter/material.dart';

import '../services/auth_service.dart';

enum _Modo { entrar, registro, recuperar }

/// Pantalla de acceso con usuario de Supabase Auth: iniciar sesión, crear
/// cuenta (solo correos @grefa.org) y recuperar la contraseña. Permite
/// trabajar sin conexión (solo local) si el operario aún no tiene cobertura o
/// cuenta.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  _Modo _modo = _Modo.entrar;
  bool _busy = false;
  bool _ocultar = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  void _cambiarModo(_Modo m) => setState(() {
        _modo = m;
        _error = null;
        _info = null;
        _password.clear();
        _password2.clear();
      });

  Future<void> _enviar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      switch (_modo) {
        case _Modo.entrar:
          await widget.auth.signIn(_email.text, _password.text);
        // El gate cambia solo a la pantalla principal al notificar el servicio.
        case _Modo.registro:
          final r = await widget.auth.signUp(
            email: _email.text,
            password: _password.text,
            fullName: _nombre.text,
          );
          if (r == SignUpResult.confirmEmail && mounted) {
            setState(() {
              _modo = _Modo.entrar;
              _password.clear();
              _password2.clear();
              _info = 'Cuenta creada. Te hemos enviado un correo: abre el enlace '
                  'para confirmarla y después inicia sesión aquí con la misma '
                  'contraseña.';
            });
          }
        case _Modo.recuperar:
          await widget.auth.resetPassword(_email.text);
          if (mounted) {
            setState(() {
              _modo = _Modo.entrar;
              _info = 'Si el correo tiene cuenta, te hemos enviado un enlace para '
                  'elegir una contraseña nueva. Revisa también el spam. Cuando la '
                  'cambies, inicia sesión aquí con la nueva.';
            });
          }
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _titulo => switch (_modo) {
        _Modo.entrar => 'Inicia sesión para sincronizar los datos con la oficina.',
        _Modo.registro =>
          'Crea tu cuenta con tu correo @grefa.org.',
        _Modo.recuperar =>
          'Te enviaremos un enlace para elegir una contraseña nueva.',
      };

  String get _botonTexto => switch (_modo) {
        _Modo.entrar => 'Entrar',
        _Modo.registro => 'Crear cuenta',
        _Modo.recuperar => 'Enviar enlace',
      };

  Widget _campoClave({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    bool ultimo = false,
  }) =>
      TextFormField(
        key: key,
        controller: controller,
        enabled: !_busy,
        obscureText: _ocultar,
        autofillHints: [
          _modo == _Modo.entrar ? AutofillHints.password : AutofillHints.newPassword,
        ],
        textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: ultimo ? (_) => _enviar() : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
            icon: Icon(_ocultar ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _ocultar = !_ocultar),
          ),
        ),
        validator: validator,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registro = _modo == _Modo.registro;
    final recuperar = _modo == _Modo.recuperar;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.egg_alt,
                          size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('GREFA · Campaña Aguilucho',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(_titulo,
                          key: const ValueKey('login-titulo'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 24),
                      if (registro) ...[
                        TextFormField(
                          key: const ValueKey('login-nombre'),
                          controller: _nombre,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Escribe tu nombre'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        key: const ValueKey('login-email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        textInputAction:
                            recuperar ? TextInputAction.done : TextInputAction.next,
                        onFieldSubmitted: recuperar ? (_) => _enviar() : null,
                        decoration: InputDecoration(
                          labelText: 'Correo electrónico',
                          hintText: registro ? 'nombre@grefa.org' : null,
                          prefixIcon: const Icon(Icons.mail_outline),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (!t.contains('@')) return 'Escribe un correo válido';
                          if (registro && !AuthService.correoPermitido(t)) {
                            return 'Solo correos ${AuthService.dominioPermitido}';
                          }
                          return null;
                        },
                      ),
                      if (!recuperar) ...[
                        const SizedBox(height: 12),
                        _campoClave(
                          key: const ValueKey('login-password'),
                          controller: _password,
                          label: registro ? 'Contraseña (mínimo 8)' : 'Contraseña',
                          ultimo: !registro,
                          validator: (v) {
                            if ((v ?? '').isEmpty) return 'Escribe la contraseña';
                            if (registro &&
                                v!.length < AuthService.minLongitudClave) {
                              return 'Mínimo ${AuthService.minLongitudClave} caracteres';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (registro) ...[
                        const SizedBox(height: 12),
                        _campoClave(
                          key: const ValueKey('login-password2'),
                          controller: _password2,
                          label: 'Repite la contraseña',
                          ultimo: true,
                          validator: (v) => v != _password.text
                              ? 'Las contraseñas no coinciden'
                              : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            key: const ValueKey('login-error'),
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: 12),
                        Text(_info!,
                            key: const ValueKey('login-info'),
                            style: TextStyle(color: theme.colorScheme.primary)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('login-entrar'),
                        onPressed: _busy ? null : _enviar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5))
                              : Text(_botonTexto),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_modo == _Modo.entrar) ...[
                        TextButton(
                          key: const ValueKey('login-olvide'),
                          onPressed:
                              _busy ? null : () => _cambiarModo(_Modo.recuperar),
                          child: const Text('He olvidado mi contraseña'),
                        ),
                        TextButton(
                          key: const ValueKey('login-crear'),
                          onPressed:
                              _busy ? null : () => _cambiarModo(_Modo.registro),
                          child: const Text('Crear cuenta (@grefa.org)'),
                        ),
                        TextButton(
                          key: const ValueKey('login-sin-conexion'),
                          onPressed: _busy ? null : widget.auth.workOffline,
                          child: const Text('Trabajar sin conexión (solo local)'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sin sesión los datos se guardan en este dispositivo y '
                          'se subirán cuando inicies sesión.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else
                        TextButton(
                          key: const ValueKey('login-volver'),
                          onPressed:
                              _busy ? null : () => _cambiarModo(_Modo.entrar),
                          child: const Text('Volver a iniciar sesión'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo para cambiar la contraseña con la sesión iniciada.
Future<void> mostrarCambiarClave(BuildContext context, AuthService auth) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _CambiarClaveDialog(auth: auth),
  );
  if (ok == true) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Contraseña cambiada correctamente.')));
  }
}

class _CambiarClaveDialog extends StatefulWidget {
  const _CambiarClaveDialog({required this.auth});
  final AuthService auth;

  @override
  State<_CambiarClaveDialog> createState() => _CambiarClaveDialogState();
}

class _CambiarClaveDialogState extends State<_CambiarClaveDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _repite = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nueva.dispose();
    _repite.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.changePassword(_nueva.text);
      if (mounted) Navigator.pop(context, true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_reset),
      title: const Text('Cambiar contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('clave-nueva'),
              controller: _nueva,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                  labelText: 'Contraseña nueva (mínimo 8)'),
              validator: (v) => (v ?? '').length < AuthService.minLongitudClave
                  ? 'Mínimo ${AuthService.minLongitudClave} caracteres'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('clave-repite'),
              controller: _repite,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Repite la contraseña'),
              validator: (v) =>
                  v != _nueva.text ? 'Las contraseñas no coinciden' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: const ValueKey('clave-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
            key: const ValueKey('clave-guardar'),
            onPressed: _busy ? null : _guardar,
            child: const Text('Cambiar')),
      ],
    );
  }
}
