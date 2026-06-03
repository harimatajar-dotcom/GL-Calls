import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/recording_model.dart';

class PresignedUrlResponse {
  final bool success;
  final String uploadUrl;
  final String fileUrl;
  final String filePath;
  final int expiresIn;
  final String method; // POST or PUT
  final Map<String, dynamic> formFields; // AWS signature fields for multipart POST

  PresignedUrlResponse({
    required this.success,
    required this.uploadUrl,
    required this.fileUrl,
    required this.filePath,
    required this.expiresIn,
    this.method = 'POST',
    this.formFields = const {},
  });

  factory PresignedUrlResponse.fromJson(Map<String, dynamic> json) {
    // v3 API response: {upload_url, file_path, form_fields, expires_at, method}
    final uploadUrl = (json['upload_url'] ?? '').toString();
    final method = (json['method'] ?? 'POST').toString().toUpperCase();
    String fileUrl = (json['file_url'] ?? '').toString();

    // Derive file URL from upload URL
    if (fileUrl.isEmpty && uploadUrl.isNotEmpty) {
      final qIndex = uploadUrl.indexOf('?');
      fileUrl = qIndex > 0 ? uploadUrl.substring(0, qIndex) : uploadUrl;
    }

    final formFields = <String, dynamic>{};
    if (json['form_fields'] is Map) {
      (json['form_fields'] as Map).forEach((k, v) {
        formFields[k.toString()] = v;
      });
    }

    return PresignedUrlResponse(
      success: json['success'] as bool? ?? true,
      uploadUrl: uploadUrl,
      fileUrl: fileUrl,
      filePath: (json['file_path'] ?? '').toString(),
      expiresIn: json['expires_in'] is int ? json['expires_in'] as int : 300,
      method: method,
      formFields: formFields,
    );
  }
}

abstract class RecordingUploadDataSource {
  Future<PresignedUrlResponse> getPresignedUrl({
    required int vendorId,
    required String fileName,
    required String mimeType,
    int fileSize,
  });

  Future<bool> uploadToS3({
    required PresignedUrlResponse presigned,
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
    int fileSize = 0,
  }) async {
    try {
      // Sanitize fileName: replace spaces with underscores and remove + character
      final sanitizedFileName = fileName
          .replaceAll('+', '')
          .replaceAll(' ', '_');

      // Get businessId (user.id from login) from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String businessId = prefs.getString('business_id') ?? '';

      // Fallback: try to extract user.id from cached user JSON
      if (businessId.isEmpty) {
        final cachedUserJson = prefs.getString('CACHED_USER') ?? '';
        debugPrint('\x1B[33m[Upload] business_id missing, checking cached user...\x1B[0m');
        debugPrint('\x1B[33m[Upload] Cached user: $cachedUserJson\x1B[0m');
        if (cachedUserJson.isNotEmpty) {
          try {
            final userMap = jsonDecode(cachedUserJson) as Map<String, dynamic>;
            final userId = userMap['user_id'] ?? userMap['id'] ?? userMap['business_id'];
            if (userId != null && userId.toString().isNotEmpty) {
              businessId = userId.toString();
              await prefs.setString('business_id', businessId);
              debugPrint('\x1B[33m[Upload] Recovered business_id: $businessId\x1B[0m');
            }
          } catch (e) {
            debugPrint('\x1B[31m[Upload] Failed to parse cached user: $e\x1B[0m');
          }
        }
      }

      if (businessId.isEmpty) {
        throw Exception('No business_id found - please logout and login again');
      }

      final requestBody = {
        'resource_type': 'voice_recordings',
        'file_name': sanitizedFileName,
        'mime_type': mimeType,
        'file_size': fileSize,
      };

      final endpoint = ApiConstants.presignedUrlForBusiness(businessId);

      // Print API call in green
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 PRESIGNED URL REQUEST\x1B[0m');
      debugPrint('\x1B[32m[API] URL: ${ApiConstants.baseUrl}$endpoint\x1B[0m');
      debugPrint('\x1B[32m[API] Method: POST\x1B[0m');
      debugPrint('\x1B[32m[API] Business ID: $businessId\x1B[0m');
      debugPrint('\x1B[32m[API] Auth: Bearer ${apiClient.authToken?.substring(0, 20) ?? "NONE"}...\x1B[0m');
      debugPrint('\x1B[32m[API] Body: $requestBody\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      final response = await apiClient.dio.post(
        endpoint,
        data: requestBody,
      );

      debugPrint('\x1B[32m[API] ✅ Response: ${response.statusCode} - ${response.data}\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return PresignedUrlResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to get presigned URL: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] ❌ PRESIGNED URL ERROR\x1B[0m');
      debugPrint('\x1B[32m[API] URL: ${e.requestOptions.uri}\x1B[0m');
      debugPrint('\x1B[32m[API] Status: ${e.response?.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Response: ${e.response?.data}\x1B[0m');
      debugPrint('\x1B[32m[API] Message: ${e.message}\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      throw Exception('Network error getting presigned URL: ${e.message}');
    }
  }

  @override
  Future<bool> uploadToS3({
    required PresignedUrlResponse presigned,
    required String filePath,
    required String mimeType,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final fileSize = await file.length();
      _logBlue('📦 File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
      _logBlue('📦 Method: ${presigned.method}');
      _logBlue('📦 Upload URL: ${presigned.uploadUrl}');

      // Use a separate Dio instance for S3 upload (no interceptors = no auth header)
      final s3Dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 300),
        receiveTimeout: const Duration(seconds: 60),
      ));

      int lastProgress = 0;
      Response response;

      if (presigned.method == 'POST' && presigned.formFields.isNotEmpty) {
        // Build multipart form-data: form_fields FIRST, file LAST
        final formMap = <String, dynamic>{};

        // 1. Add all AWS form fields first (order matters!)
        presigned.formFields.forEach((key, value) {
          formMap[key] = value.toString();
        });

        _logBlue('📦 Form fields: ${formMap.keys.toList()}');

        // 2. Add the file LAST with field name 'file'
        formMap['file'] = await MultipartFile.fromFile(
          filePath,
          filename: file.path.split('/').last,
          contentType: DioMediaType.parse(mimeType),
        );

        final formData = FormData.fromMap(formMap);

        response = await s3Dio.post(
          presigned.uploadUrl,
          data: formData,
          options: Options(
            // Don't set Content-Type - Dio sets it with multipart boundary
            headers: {},
          ),
          onSendProgress: (sent, total) {
            final progress = ((sent / total) * 100).toInt();
            if (progress >= lastProgress + 20 || progress == 100) {
              _logBlue('📤 Upload progress: $progress% ($sent / $total bytes)');
              lastProgress = progress;
            }
          },
        );
      } else {
        // Fallback: PUT raw bytes (legacy presigned URL endpoint)
        final fileBytes = await file.readAsBytes();
        response = await s3Dio.put(
          presigned.uploadUrl,
          data: fileBytes,
          options: Options(
            headers: {
              'Content-Type': mimeType,
              'Content-Length': fileSize.toString(),
            },
            contentType: mimeType,
            requestEncoder: (request, options) => fileBytes,
          ),
          onSendProgress: (sent, total) {
            final progress = ((sent / total) * 100).toInt();
            if (progress >= lastProgress + 20 || progress == 100) {
              _logBlue('📤 Upload progress: $progress% ($sent / $total bytes)');
              lastProgress = progress;
            }
          },
        );
      }

      _logBlue('📤 S3 Response: ${response.statusCode}');
      return response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.sendTimeout) {
        _logRed('❌ Upload timed out - slow network');
      } else if (e.type == DioExceptionType.connectionTimeout) {
        _logRed('❌ Connection timed out');
      }
      throw Exception('Failed to upload to S3: ${e.message}');
    } catch (e) {
      throw Exception('Error uploading to S3: $e');
    }
  }

  void _logBlue(String message) {
    print('\x1B[34m$message\x1B[0m');
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

      // Get actual file size from disk if recording.fileSize is 0
      int actualFileSize = recording.fileSize;
      if (actualFileSize == 0) {
        try {
          final f = File(recording.playablePath);
          if (await f.exists()) {
            actualFileSize = await f.length();
          }
        } catch (_) {}
      }

      final presignedResponse = await getPresignedUrl(
        vendorId: vendorId,
        fileName: recording.fileName,
        mimeType: mimeType,
        fileSize: actualFileSize,
      );

      // Step 2: Upload to S3 (POST multipart with form_fields)
      final playPath = recording.playablePath;
      final uploadSuccess = await uploadToS3(
        presigned: presignedResponse,
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
