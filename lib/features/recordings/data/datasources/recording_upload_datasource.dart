import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/recording_model.dart';

class PresignedUrlResponse {
  final bool success;
  final String uploadUrl;
  final String fileUrl;
  final String filePath;
  final int expiresIn;

  PresignedUrlResponse({
    required this.success,
    required this.uploadUrl,
    required this.fileUrl,
    required this.filePath,
    required this.expiresIn,
  });

  factory PresignedUrlResponse.fromJson(Map<String, dynamic> json) {
    return PresignedUrlResponse(
      success: json['success'] as bool? ?? true,
      uploadUrl: json['upload_url'] as String,
      fileUrl: json['file_url'] as String,
      filePath: json['file_path'] as String,
      expiresIn: json['expires_in'] as int? ?? 300,
    );
  }
}

abstract class RecordingUploadDataSource {
  Future<PresignedUrlResponse> getPresignedUrl({
    required int vendorId,
    required String fileName,
    required String mimeType,
  });

  Future<bool> uploadToS3({
    required String uploadUrl,
    required String filePath,
    required String mimeType,
  });
}

class RecordingUploadDataSourceImpl implements RecordingUploadDataSource {
  final ApiClient apiClient;

  RecordingUploadDataSourceImpl({required this.apiClient});

  String _getMimeType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'amr':
        return 'audio/amr';
      case '3gp':
        return 'audio/3gpp';
      case 'flac':
        return 'audio/flac';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'webm':
        return 'audio/webm';
      default:
        return 'audio/mpeg';
    }
  }

  @override
  Future<PresignedUrlResponse> getPresignedUrl({
    required int vendorId,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      // Sanitize fileName: replace spaces with underscores and remove + character
      final sanitizedFileName = fileName
          .replaceAll('+', '')
          .replaceAll(' ', '_');

      final response = await apiClient.dio.post(
        '/gl-dialer/voice/presigned-url',
        data: {
          'vendor_id': vendorId,
          'file_name': sanitizedFileName,
          'mime_type': mimeType,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return PresignedUrlResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to get presigned URL: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('Network error getting presigned URL: ${e.message}');
    }
  }

  @override
  Future<bool> uploadToS3({
    required String uploadUrl,
    required String filePath,
    required String mimeType,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;

      // Use a separate Dio instance for S3 upload (no auth headers)
      final s3Dio = Dio();

      final response = await s3Dio.put(
        uploadUrl,
        data: Stream.fromIterable([fileBytes]),
        options: Options(
          headers: {
            'Content-Type': mimeType,
            'Content-Length': fileSize,
          },
          contentType: mimeType,
        ),
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      throw Exception('Failed to upload to S3: ${e.message}');
    } catch (e) {
      throw Exception('Error uploading to S3: $e');
    }
  }

  Future<RecordingModel?> uploadRecording({
    required RecordingModel recording,
    required int vendorId,
  }) async {
    try {
      final mimeType = _getMimeType(recording.fileName);

      // Step 1: Get presigned URL
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('📤 UPLOADING: ${recording.fileName}');
      _logGreen('   Phone: ${recording.phoneNumber ?? 'Unknown'}');

      final presignedResponse = await getPresignedUrl(
        vendorId: vendorId,
        fileName: recording.fileName,
        mimeType: mimeType,
      );

      // Step 2: Upload to S3
      final playPath = recording.playablePath;
      final uploadSuccess = await uploadToS3(
        uploadUrl: presignedResponse.uploadUrl,
        filePath: playPath,
        mimeType: mimeType,
      );

      if (uploadSuccess) {
        _logGreen('✅ SUCCESS: Uploaded to S3');
        _logGreen('   S3 Path: ${presignedResponse.filePath}');
        _logGreen('   File URL: ${presignedResponse.fileUrl}');
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        // Return updated model
        return recording.copyWith(
          isUploaded: true,
          uploadUrl: presignedResponse.fileUrl,
          s3Path: presignedResponse.filePath,
          uploadedAt: DateTime.now(),
        );
      } else {
        _logRed('❌ FAILED: Upload to S3 failed');
        return null;
      }
    } catch (e) {
      _logRed('❌ ERROR: $e');
      return null;
    }
  }

  void _logGreen(String message) {
    // ANSI green color code
    print('\x1B[32m$message\x1B[0m');
  }

  void _logRed(String message) {
    // ANSI red color code
    print('\x1B[31m$message\x1B[0m');
  }
}
