import 'package:supabase_flutter/supabase_flutter.dart';

class ServerGarmentSummary {
  const ServerGarmentSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.subtype,
    required this.photoState,
  });
  final String id;
  final String name;
  final String category;
  final String subtype;
  final String photoState;

  factory ServerGarmentSummary.fromJson(Map<String, dynamic> json) =>
      ServerGarmentSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        subtype: json['subtype'] as String,
        photoState: json['photo_state'] as String,
      );
}

/// Deliberately does not implement WardrobeRepository (which permits writes).
abstract interface class ServerWardrobeReader {
  Future<List<ServerGarmentSummary>> listOwn(String userId);
}

class SupabaseServerWardrobeReader implements ServerWardrobeReader {
  SupabaseServerWardrobeReader(this.client);
  final SupabaseClient client;

  @override
  Future<List<ServerGarmentSummary>> listOwn(String userId) async {
    if (client.auth.currentUser?.id != userId ||
        client.auth.currentSession == null) {
      throw StateError('Authentication required');
    }
    // RLS is the security boundary; this filter also scopes the normal request.
    final rows = await client
        .from('garments')
        .select('id,name,category,subtype,photo_state')
        .eq('user_id', userId)
        .order('server_created_at', ascending: false)
        .limit(100);
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Session changed');
    }
    return rows.map(ServerGarmentSummary.fromJson).toList(growable: false);
  }
}
