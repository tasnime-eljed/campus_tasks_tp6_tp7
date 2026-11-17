import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/queue_state.dart';
import '../providers/connectivity_provider.dart';
import '../providers/queue_provider.dart';
import '../widgets/loading_widget.dart';
import '../widgets/offline_banner.dart';
import '../widgets/queue_empty_widget.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.displayName, required this.isAdmin});

  final String displayName;
  final bool isAdmin;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  late final TextEditingController _nameController;
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _pendingUsers = [];
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final queue = context.read<QueueProvider>();
      queue.fetchInitialQueue();
      queue.startRealtime();
      if (widget.isAdmin) _loadPendingUsers();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<QueueProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    try {
      await context.read<QueueProvider>().addClient(name);
      _nameController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de vous ajouter à la file : $error')),
        );
      }
    }
  }

  Future<void> _loadPendingUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final rows = await Supabase.instance.client
          .from('user_profiles')
          .select('id, display_name, email, created_at')
          .eq('status', 'pending')
          .neq('email', '')
          .order('created_at');
      if (mounted) setState(() => _pendingUsers = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de charger les demandes : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _approveUser(Map<String, dynamic> user) async {
    try {
      await Supabase.instance.client
          .from('user_profiles')
          .update({'status': 'approved'})
          .eq('id', user['id']);
      if (mounted) {
        setState(() => _pendingUsers.removeWhere((row) => row['id'] == user['id']));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['display_name'] ?? user['email']} approuvé')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approbation impossible : $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueProvider>();
    final connectivity = context.watch<ConnectivityProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'File d’attente · Admin' : 'Waiting Room'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Actualiser les demandes',
              icon: const Icon(Icons.refresh),
              onPressed: _loadPendingUsers,
            ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(status: connectivity.status),
          if (widget.isAdmin) _buildPendingApprovals(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: widget.isAdmin ? 'Nom du client' : 'Votre nom',
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _add, child: const Text('Ajouter')),
                  ],
                ),
                if (widget.isAdmin) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: queue.clients.isEmpty
                          ? null
                          : () async {
                              try {
                                await queue.callNextClient();
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Action impossible : $error')),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Appeler le prochain client'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody(queue)),
        ],
      ),
    );
  }

  Widget _buildPendingApprovals() {
    if (_loadingUsers) return const LinearProgressIndicator();
    if (_pendingUsers.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        title: Text('Comptes à approuver (${_pendingUsers.length})'),
        children: [
          for (final user in _pendingUsers)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(user['display_name'] as String? ?? 'Sans nom'),
              subtitle: Text(user['email'] as String? ?? ''),
              trailing: IconButton(
                tooltip: 'Approuver',
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: () => _approveUser(user),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(QueueProvider queue) {
    switch (queue.state) {
      case QueueState.initial:
      case QueueState.loading:
        return const LoadingWidget(message: 'Chargement de la file…');
      case QueueState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(queue.errorMessage ?? 'Erreur'),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: queue.fetchInitialQueue, child: const Text('Réessayer')),
            ],
          ),
        );
      case QueueState.empty:
        return const QueueEmptyWidget();
      default:
        final clients = queue.clients;
        return RefreshIndicator(
          onRefresh: queue.fetchInitialQueue,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: clients.length + (queue.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= clients.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final client = clients[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(client.name),
                  subtitle: widget.isAdmin
                      ? (client.hasLocation
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(client.locationText),
                                ],
                              )
                            : const Text('Localisation indisponible'))
                      : Icon(
                          client.hasLocation
                              ? Icons.location_on_outlined
                              : Icons.location_off_outlined,
                          size: 18,
                          color: client.hasLocation ? Colors.red : Colors.grey,
                        ),
                  trailing: widget.isAdmin
                      ? IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await queue.deleteClient(client.id);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Suppression impossible : $error')),
                                );
                              }
                            }
                          },
                        )
                      : null,
                ),
              );
            },
          ),
        );
    }
  }
}
