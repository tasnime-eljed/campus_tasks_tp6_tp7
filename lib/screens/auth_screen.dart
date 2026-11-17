import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'display_name': _nameController.text.trim()},
        );
        if (mounted) {
          setState(() {
            _message = response.session == null
                ? 'Compte créé. Vérifiez votre e-mail puis attendez l’approbation de l’administrateur.'
                : 'Compte créé. Attendez l’approbation de l’administrateur.';
            _messageIsError = false;
          });
        }
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _messageIsError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Une erreur est survenue. Réessayez.';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = 'Saisissez d’abord une adresse e-mail valide.';
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
      if (mounted) {
        setState(() {
          _message = 'Un lien de réinitialisation a été envoyé par e-mail.';
          _messageIsError = false;
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _messageIsError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Impossible d’envoyer le lien. Réessayez.';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.meeting_room_outlined, size: 64, color: colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      _isSignUp ? 'Créer un compte' : 'Connexion',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Waiting Room', textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 32),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nom',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) => value?.trim().isEmpty ?? true
                            ? 'Saisissez votre nom.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Adresse e-mail',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.isEmpty || !email.contains('@')
                            ? 'Saisissez une adresse e-mail valide.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: [
                        _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
                      ],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      validator: (value) => (value ?? '').length < 6
                          ? 'Le mot de passe doit contenir au moins 6 caractères.'
                          : null,
                    ),
                    if (!_isSignUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          child: const Text('Mot de passe oublié ?'),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    if (_message != null) ...[
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _messageIsError ? colors.error : colors.primary),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isSignUp ? 'Créer mon compte' : 'Se connecter'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _isSignUp = !_isSignUp;
                                _message = null;
                              }),
                      child: Text(_isSignUp
                          ? 'J’ai déjà un compte — me connecter'
                          : 'Pas encore de compte ? Créer un compte'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
