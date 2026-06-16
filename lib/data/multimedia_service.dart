import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

class MultimediaService {
  final SupabaseClient _supabaseClient;

  MultimediaService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  /// Uploads a photo (.jpg/.png) or audio file (.m4a/.mp3) to Supabase Storage
  /// and returns its public URL for Gemini to access.
  Future<String> uploadMediaToSupabase(File file, String bucketName) async {
    final String userId = _supabaseClient.auth.currentUser?.id ?? 'anonymous';
    
    // Generate a unique filename using timestamp
    // Example file.path: /data/user/0/app/cache/image_picker.jpg
    final String extension = file.path.split('.').last;
    final String fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
    final String filePath = '$userId/$fileName';

    try {
      // Upload file to the specified Supabase bucket
      await _supabaseClient.storage.from(bucketName).upload(
            filePath,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // Return the securely generated public URL
      return _supabaseClient.storage.from(bucketName).getPublicUrl(filePath);
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      final isBucketNotFound = errorString.contains('bucket not found') ||
          (e is StorageException && (e.statusCode == '404' || e.message.toLowerCase().contains('bucket not found')));

      if (isBucketNotFound) {
        try {
          // Attempt to create the bucket dynamically
          await _supabaseClient.storage.createBucket(
            bucketName,
            const BucketOptions(public: true),
          );

          // Retry upload
          await _supabaseClient.storage.from(bucketName).upload(
                filePath,
                file,
                fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
              );

          return _supabaseClient.storage.from(bucketName).getPublicUrl(filePath);
        } catch (createErr) {
          throw Exception('Failed to upload media because bucket "$bucketName" does not exist and could not be created: $createErr');
        }
      }
      throw Exception('Failed to upload media to Supabase: $e');
    }
  }
}
