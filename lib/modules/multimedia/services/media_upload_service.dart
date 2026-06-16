import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/supabase_client.dart';

class MediaUploadService {
  final SupabaseClient _supabaseClient;

  MediaUploadService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  /// Uploads media to Supabase Storage and returns the absolute public URL.
  Future<String> uploadChatMedia(Uint8List fileBytes, String fileExtension, String bucketName) async {
    final userId = _supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Authentication required to upload media.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '$userId/$timestamp.$fileExtension';

    try {
      await _supabaseClient.storage.from(bucketName).uploadBinary(
        filePath,
        fileBytes,
        fileOptions: FileOptions(contentType: _getContentType(fileExtension)),
      );

      final publicUrl = _supabaseClient.storage.from(bucketName).getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      final isBucketNotFound = errorString.contains('bucket not found') ||
          (e is StorageException && (e.statusCode == '404' || e.message.toLowerCase().contains('bucket not found')));

      if (isBucketNotFound) {
        try {
          debugPrint('Bucket $bucketName not found. Attempting to create it...');
          await _supabaseClient.storage.createBucket(
            bucketName,
            const BucketOptions(public: true),
          );

          // Retry upload after successful bucket creation
          await _supabaseClient.storage.from(bucketName).uploadBinary(
            filePath,
            fileBytes,
            fileOptions: FileOptions(contentType: _getContentType(fileExtension)),
          );

          final publicUrl = _supabaseClient.storage.from(bucketName).getPublicUrl(filePath);
          return publicUrl;
        } catch (createErr) {
          debugPrint('Failed to create bucket: $createErr');
          throw Exception('Failed to upload media because bucket "$bucketName" does not exist and could not be created: $createErr');
        }
      }

      debugPrint('Media upload error: $e');
      throw Exception('Failed to upload media: $e');
    }
  }

  String _getContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/m4a';
      default:
        return 'application/octet-stream';
    }
  }
}
