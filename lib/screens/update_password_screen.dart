import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (mounted) {
        setState(() {
          _message = 'Mot de passe modifié. Vous êtes connecté.';
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
          _message = 'Impossible de modifier le mot de passe. Réessayez.';
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
      appBar: AppBar(title: const Text('Nouveau mot de passe')),
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
                    const Icon(Icons.lock_reset, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Choisissez un nouveau mot de passe',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Nouveau mot de passe',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) => (value ?? '').length < 6
                          ? 'Le mot de passe doit contenir au moins 6 caractères.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _updatePassword(),
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le mot de passe',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? 'Les mots de passe ne correspondent pas.'
                          : null,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _messageIsError ? colors.error : colors.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isLoading ? null : _updatePassword,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer le nouveau mot de passe'),
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
