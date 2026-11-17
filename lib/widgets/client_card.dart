import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/sync_status.dart';

class ClientCard extends StatelessWidget {
  final Client client;
  final bool isAdmin;

  const ClientCard({super.key, required this.client, this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(client.name),
        subtitle: isAdmin
            ? Text(
                client.hasLocation
                    ? 'Location: ${client.locationText}'
                    : 'Location not captured',
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              client.syncStatus == SyncStatus.synced
                  ? Icons.cloud_done
                  : Icons.cloud_off,
              color: client.syncStatus == SyncStatus.synced
                  ? Colors.green
                  : Colors.orange,
            ),
            const SizedBox(width: 8),
            Icon(
              client.hasLocation ? Icons.location_on : Icons.location_off,
              color: client.hasLocation ? Colors.green : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
