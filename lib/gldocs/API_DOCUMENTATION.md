# GL-Dialer API Documentation

## Table of Contents
1. [Overview](#overview)
2. [Base URL & Configuration](#base-url--configuration)
3. [Authentication](#authentication)
4. [API Endpoints](#api-endpoints)
5. [Application Workflow](#application-workflow)
6. [Permissions Required](#permissions-required)
7. [Data Models](#data-models)
8. [Error Handling](#error-handling)

---

## Overview

GL-Dialer (Tracker) is a Flutter mobile application designed for comprehensive call tracking, recording discovery, and synchronization. The app captures call logs, discovers call recordings from device storage, and syncs them to a backend server.

### Key Features
- Call log capture (incoming, outgoing, missed, rejected, blocked)
- Recording discovery from device storage
- Two-phase sync: Upload recordings to S3 → Sync call data with recording URLs
- Offline support with automatic sync when connected
- JWT authentication

---

## Base URL & Configuration

### Default API Base URL
```
https://app.getleadcrm.com
```

### Timeout Configuration
| Setting | Value |
|---------|-------|
| Connection Timeout | 30,000 ms (30 seconds) |
| Receive Timeout | 30,000 ms (30 seconds) |
| Max Retry Attempts | 3 |
| Default Sync Interval | 15 minutes |

### Headers
```json
{
  "Content-Type": "application/json",
  "Accept": "application/json",
  "Authorization": "Bearer <token>"
}
```

---

## Authentication

### Login
Authentication is performed using phone number and password.

**Endpoint:** `POST /gl-dialer/login`

**Request:**
```json
{
  "phone_number": "+919876543210",
  "password": "your_password"
}
```

**Response (200/202):**
```json
{
  "name": "User Name",
  "email": "user@example.com",
  "token": "jwt_token_here",
  "vendor_id": 12345
}
```

**Notes:**
- Phone number should include country code (e.g., +91 for India)
- Token is used for all subsequent authenticated requests
- `vendor_id` is used for recording uploads

---

### Logout
**Endpoint:** `POST /gl-dialer/logout`

**Headers:**
```
Authorization: Bearer <token>
```

**Response (200/202):**
```json
{
  "success": true
}
```

---

## API Endpoints

### 1. Voice Recording Presigned URL (API 1)

Get a presigned URL from AWS S3 to upload voice recordings.

**Endpoint:** `POST /gl-dialer/voice/presigned-url`

**Request:**
```json
{
  "vendor_id": 12345,
  "file_name": "recording_2024_01_15_10_30_00.mp3",
  "mime_type": "audio/mpeg"
}
```

**Supported MIME Types:**
| Extension | MIME Type |
|-----------|-----------|
| .mp3 | audio/mpeg |
| .wav | audio/wav |
| .m4a | audio/mp4 |
| .aac | audio/aac |
| .ogg | audio/ogg |
| .opus | audio/opus |
| .amr | audio/amr |
| .3gp | audio/3gpp |
| .flac | audio/flac |
| .wma | audio/x-ms-wma |
| .webm | audio/webm |

**Response (200/201):**
```json
{
  "success": true,
  "upload_url": "https://s3.amazonaws.com/bucket/path?presigned-params...",
  "file_url": "https://s3.amazonaws.com/bucket/path/filename.mp3",
  "file_path": "recordings/vendor_12345/recording_2024_01_15_10_30_00.mp3",
  "expires_in": 300
}
```

**Response Fields:**
| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether the request was successful |
| upload_url | string | Presigned S3 URL for uploading (PUT request) |
| file_url | string | Public URL of the file after upload |
| file_path | string | S3 path/key of the file |
| expires_in | integer | URL expiration time in seconds |

---

### 2. Upload to S3 Presigned URL (API 1.5)

Upload the file directly to S3 using the presigned URL.

**Endpoint:** `PUT <upload_url from presigned response>`

**Headers:**
```
Content-Type: audio/mpeg (or appropriate MIME type)
Content-Length: <file_size_in_bytes>
```

**Body:** Raw binary file data

**Response (200/204):** Empty response on success

---

### 3. Sync Calls (API 2)

Sync call logs with optional recording URLs to the server.

**Endpoint:** `POST /gl-dialer/calls/sync`

**Request:**
```json
{
  "data": [
    {
      "call_id": "abci12344",
      "phone_number": "919876543210",
      "call_start_at": "2024-01-15 10:30:00",
      "duration": 120,
      "event_type": "answered",
      "direction": "inbound",
      "recording_url": "recordings/vendor_12345/recording.mp3"
    },
    {
      "call_id": "abci12345",
      "phone_number": "919876543211",
      "call_start_at": "2024-01-15 11:00:00",
      "duration": 0,
      "event_type": "missed",
      "direction": "inbound"
    }
  ]
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| call_id | string | Yes | Unique identifier for the call (device-generated) |
| phone_number | string | Yes | Phone number with country code (e.g., 919876543210) |
| call_start_at | string | Yes | Call start timestamp (YYYY-MM-DD HH:MM:SS) |
| duration | integer | Yes | Call duration in seconds |
| event_type | string | Yes | Type of call event |
| direction | string | Yes | Call direction |
| recording_url | string | No | S3 path to recording (from presigned URL response) |

**Event Types:**
| Value | Description |
|-------|-------------|
| answered | Call was answered (duration > 0) |
| missed | Incoming call that was not answered |
| outgoing | Outgoing call that was not answered |
| incoming | Incoming call (generic) |

**Direction Values:**
| Value | Description |
|-------|-------------|
| inbound | Incoming call |
| outbound | Outgoing call |

**Response (200/202):**
```json
[]
```
*Empty array indicates all calls were synced successfully*

**OR**

```json
{
  "synced_numbers": ["919876543210", "919876543211"]
}
```

---

### 4. Sync Call with Audio (Alternative)

Sync a single call with audio file as multipart form data.

**Endpoint:** `POST /gl-dialer/calls/sync`

**Content-Type:** `multipart/form-data`

**Form Fields:**
| Field | Type | Description |
|-------|------|-------------|
| data | string (JSON) | JSON string containing array of call data |
| recording | file | Audio file binary |

**Example:**
```
data: [{"call_id":"abc123","phone_number":"919876543210",...}]
recording: <binary file>
```

---

## Application Workflow

### Complete Sync Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    APPLICATION SYNC FLOW                         │
└─────────────────────────────────────────────────────────────────┘

1. USER AUTHENTICATION
   ┌──────────┐     POST /gl-dialer/login     ┌──────────┐
   │  User    │ ────────────────────────────► │  Server  │
   │  Login   │ ◄──────────────────────────── │  Auth    │
   └──────────┘     { token, vendor_id }      └──────────┘

2. PHASE 1: UPLOAD RECORDINGS TO S3
   ┌──────────┐     POST /gl-dialer/voice/presigned-url
   │  App     │ ────────────────────────────► │  Server  │
   │  Request │     { vendor_id, file_name }  │          │
   │ Presigned│ ◄──────────────────────────── │          │
   │   URL    │     { upload_url, file_path } └──────────┘
   └──────────┘
        │
        ▼
   ┌──────────┐     PUT <upload_url>          ┌──────────┐
   │  Upload  │ ────────────────────────────► │   AWS    │
   │  to S3   │     <binary file data>        │   S3     │
   │          │ ◄──────────────────────────── │          │
   └──────────┘     200 OK                    └──────────┘
        │
        │ Save file_path locally
        ▼

3. PHASE 2: SYNC CALLS WITH RECORDING URLs
   ┌──────────┐     POST /gl-dialer/calls/sync
   │  Sync    │ ────────────────────────────► │  Server  │
   │  Calls   │     { data: [{ call_id,       │          │
   │          │       phone_number,           │          │
   │          │       recording_url, ... }] } │          │
   │          │ ◄──────────────────────────── │          │
   └──────────┘     { synced_numbers: [...] } └──────────┘
```

### Dashboard UI Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      DASHBOARD SCREEN                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  📼 RECORDED CALLS                                    [>]  │ │
│  │  X audio files stored locally                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  🔄 MANUAL SYNC                                            │ │
│  │  Upload recordings & sync calls                            │ │
│  │                                                             │ │
│  │  [Status Message]                                           │ │
│  │  ████████████████░░░░ 75%                                  │ │
│  │                                                             │ │
│  │  ┌─────────────┐  ┌─────────────┐                         │ │
│  │  │   UPLOAD    │  │ SYNC CALLS  │                         │ │
│  │  │  (Step 1)   │  │  (Step 2)   │                         │ │
│  │  └─────────────┘  └─────────────┘                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  📋 PENDING CALL SYNC                              [🔄]   │ │
│  │  X calls with recording URL                                │ │
│  │                                                             │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │              [ CALL SYNC ]                           │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                             │ │
│  │  📞 +91 9876543210                          [INCOMING]    │ │
│  │  🔗 recordings/vendor_123/file.mp3                        │ │
│  │  ────────────────────────────────────────                 │ │
│  │  📞 +91 9876543211                          [OUTGOING]    │ │
│  │  🔗 recordings/vendor_123/file2.mp3                       │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Sync Process Details

1. **Upload Button (Step 1):**
   - Scans device for local recordings
   - For each recording:
     - Request presigned URL from API
     - Upload file to S3
     - Save S3 file_path locally
   - Button turns GREEN when complete

2. **Sync Calls Button (Step 2):**
   - DISABLED (grey) until Upload completes
   - Enabled (green) after Upload
   - Syncs all unsynced calls with attached recording URLs
   - Marks calls as synced in local database

3. **Pending Call Sync Card:**
   - Shows calls that have recording URLs but aren't synced yet
   - Displays phone number and recording URL
   - "Call Sync" button syncs all pending calls

---

## Permissions Required

### Android Permissions

| Permission | Purpose | Required For |
|------------|---------|--------------|
| `READ_CALL_LOG` | Read device call history | Core functionality |
| `READ_CONTACTS` | Read contact names for caller ID | Display caller names |
| `INTERNET` | Network communication | API calls, S3 uploads |
| `ACCESS_NETWORK_STATE` | Check network connectivity | Sync scheduling |
| `ACCESS_WIFI_STATE` | Check WiFi status | WiFi-only sync option |
| `WAKE_LOCK` | Keep device awake during sync | Background sync |
| `FOREGROUND_SERVICE` | Run foreground service | Background sync |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevent doze mode | Reliable background sync |
| `RECEIVE_BOOT_COMPLETED` | Start service on boot | Auto-start after reboot |
| `READ_EXTERNAL_STORAGE` | Read files (Android ≤ 12) | Access recordings |
| `WRITE_EXTERNAL_STORAGE` | Write files (Android ≤ 10) | Save data |
| `MANAGE_EXTERNAL_STORAGE` | Full storage access (Android 11-12) | Access all recordings |
| `READ_MEDIA_AUDIO` | Read audio files (Android 13+) | Access recordings |
| `READ_MEDIA_IMAGES` | Read images (Android 13+) | Future use |
| `READ_MEDIA_VIDEO` | Read videos (Android 13+) | Future use |

### Permission Groups by Android Version

**Android 10 and below:**
- READ_EXTERNAL_STORAGE
- WRITE_EXTERNAL_STORAGE

**Android 11-12 (API 30-32):**
- MANAGE_EXTERNAL_STORAGE

**Android 13+ (API 33+):**
- READ_MEDIA_AUDIO
- READ_MEDIA_IMAGES
- READ_MEDIA_VIDEO

---

## Data Models

### CallLogModel

```dart
class CallLogModel {
  String id;              // Unique identifier
  String number;          // Phone number
  String name;            // Contact name
  int callType;           // 1=incoming, 2=outgoing, 3=missed, 5=rejected, 6=blocked
  int duration;           // Duration in seconds
  int timestamp;          // Unix timestamp in milliseconds
  bool isSynced;          // Server sync status
  String? recordingPath;  // Local file path
  bool isRecordingUploaded; // S3 upload status
  String? recordingUrl;   // S3 file path
}
```

### Call Type Constants

```dart
static const int incoming = 1;
static const int outgoing = 2;
static const int missed = 3;
static const int rejected = 5;
static const int blocked = 6;
static const int voiceMail = 4;
```

### Call Type Mapping for API

| Local Type | API event_type | API direction |
|------------|----------------|---------------|
| Incoming (duration > 0) | answered | inbound |
| Incoming (duration = 0) | missed | inbound |
| Outgoing (duration > 0) | answered | outbound |
| Outgoing (duration = 0) | outgoing | outbound |
| Missed | missed | inbound |
| Rejected | missed | inbound |
| Blocked | missed | inbound |
| VoiceMail | incoming | inbound |

---

## Error Handling

### HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Process response |
| 201 | Created | Resource created successfully |
| 202 | Accepted | Request accepted for processing |
| 204 | No Content | Success (no body) |
| 302 | Redirect | Follow redirect |
| 400 | Bad Request | Check request parameters |
| 401 | Unauthorized | Re-authenticate |
| 403 | Forbidden | Check permissions |
| 404 | Not Found | Check endpoint URL |
| 500+ | Server Error | Retry later |

### Retry Logic

The application implements exponential backoff for network errors:

```
Attempt 1: Wait 1 second
Attempt 2: Wait 2 seconds
Attempt 3: Wait 4 seconds
Max attempts: 3
```

**Retryable Errors:**
- Connection timeout
- Send timeout
- Receive timeout
- Connection error
- DNS resolution failure ("Failed host lookup")

### Common Error Messages

| Error | User Message |
|-------|--------------|
| DNS Failure | "Cannot connect to the server. Check network and server URL." |
| Timeout | "Connection timed out. Server is not responding." |
| Auth Error | "Authentication failed. Please login again." |
| Server Error | "Server error. Please try again later." |

---

## Console Logging Colors

The app uses ANSI color codes for console output:

| Color | Code | Usage |
|-------|------|-------|
| Green | `\x1B[32m` | Success messages, URLs saved |
| Cyan | `\x1B[36m` | Info messages, sync start |
| Yellow | `\x1B[33m` | Warnings, skipped items |
| Red | `\x1B[31m` | Errors, failures |
| Magenta | `\x1B[35m` | Phase 1 (upload) progress |
| Blue | `\x1B[34m` | Phase 2 (sync) progress |
| Reset | `\x1B[0m` | Reset to default |

**Example Console Output:**
```
[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[0m
[32m✅ SUCCESS: Call synced[0m
[32m   Phone: 919876543210[0m
[32m   Recording URL: ✅ recordings/vendor_123/file.mp3[0m
[32m   Status: SYNCED TO SERVER[0m
[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[0m
```

---

## Quick Reference

### API Endpoints Summary

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/gl-dialer/login` | User authentication |
| POST | `/gl-dialer/logout` | User logout |
| POST | `/gl-dialer/voice/presigned-url` | Get S3 upload URL |
| PUT | `<presigned_url>` | Upload file to S3 |
| POST | `/gl-dialer/calls/sync` | Sync call logs |

### Sync Flow Summary

```
1. Login → Get token + vendor_id
2. Upload → Request presigned URL → Upload to S3 → Get file_path
3. Sync → Send call data with recording_url → Mark as synced
```

---

*Document Version: 1.0*
*Last Updated: December 2024*
