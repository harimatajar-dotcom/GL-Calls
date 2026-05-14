# Voice Note / File Upload Flow — Lead Notes

End-to-end flow for attaching a voice recording (or any file) to a lead note. Same pattern works for images, documents, and attachments — only the `resource_type` and `mime_type` change.

## Architecture

The upload is a **3-step server-coordinated flow**: the mobile app never sends the file body to your backend. Instead, the backend hands out a short-lived, signed S3 URL that the app uploads to directly. After the upload succeeds, the app tells the backend "the file is at this path — attach it to this note."

```
┌───────────┐                ┌────────────┐                 ┌──────┐
│  Mobile   │                │  Backend   │                 │  S3  │
└─────┬─────┘                └─────┬──────┘                 └───┬──┘
      │                            │                            │
      │ 1. POST /upload/           │                            │
      │    presigned-url           │                            │
      ├───────────────────────────►│                            │
      │  { file_name, mime_type,   │                            │
      │    file_size, resource_type│                            │
      │  }                         │                            │
      │                            │                            │
      │  { upload_url, file_path } │                            │
      │◄───────────────────────────┤                            │
      │                            │                            │
      │ 2. PUT upload_url          │                            │
      │    Content-Type: <mime>    │                            │
      │    Body: <raw file bytes>  │                            │
      ├────────────────────────────┼───────────────────────────►│
      │                            │                            │
      │  200 OK / 204 No Content   │                            │
      │◄───────────────────────────┼────────────────────────────┤
      │                            │                            │
      │ 3. POST /leads/{id}/notes  │                            │
      │    { content, type, file_  │                            │
      │      path, file_name,      │                            │
      │      file_mime_type,       │                            │
      │      metadata: {duration}} │                            │
      ├───────────────────────────►│                            │
      │                            │                            │
      │  201 Created               │                            │
      │◄───────────────────────────┤                            │
```

**Why this pattern?** S3 PUT is the only large body the device sends. Your backend stays small and fast (no multipart middleware, no proxy traffic). The presigned URL expires (typically minutes), so it's safe to hand out.

---

## Step 1 — Request a presigned upload URL

### Endpoint

```
POST /api/mobile/businesses/{businessId}/upload/presigned-url
Authorization: Bearer {token}
Content-Type: application/json
```

### Request body

```json
{
  "file_name": "voice_note_1717842300000.m4a",
  "mime_type": "audio/mp4",
  "file_size": 24576,
  "resource_type": "voice_recordings"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `file_name` | string | yes | Original file name. Backend may rewrite this; only the extension matters for S3 key. |
| `mime_type` | string | yes | Must match what you'll send in the S3 `Content-Type` header in step 2 — mismatches cause S3 to reject. |
| `file_size` | int | yes | Bytes. Backend uses this to enforce per-resource limits (e.g. 10 MB voice cap). |
| `resource_type` | string | yes | One of: `voice_recordings`, `notes`, `avatars`, `documents`, `attachments`. Determines S3 prefix and ACL. |

### Response `200 OK`

```json
{
  "upload_url": "https://s3.amazonaws.com/bucket/voice_recordings/biz_123/abc.m4a?X-Amz-Algorithm=...&X-Amz-Signature=...",
  "file_path": "voice_recordings/biz_123/abc.m4a",
  "expires_at": "2026-04-29T12:30:00Z",
  "method": "PUT"
}
```

| Field | Type | Description |
|---|---|---|
| `upload_url` | string | Pre-signed URL — send the file body to this URL via PUT in step 2. **Do not** send the auth token to this URL. |
| `file_path` | string | The persistent S3 key/path. Save this when creating the note in step 3 — it's how the backend finds the file later. |
| `expires_at` | string \| null | ISO 8601 expiry. Typically 5–15 min. |
| `method` | string | Always `"PUT"` for uploads. |

### Errors

| Code | Cause |
|---|---|
| `401` | Missing/invalid token |
| `403` | `resource_type` not allowed for this user/role |
| `413` | `file_size` exceeds limit for the resource type |
| `422` | Invalid mime type for the resource type (e.g. sending `.exe` to `voice_recordings`) |

---

## Step 2 — Upload the file body to S3

```
PUT {upload_url}
Content-Type: {same mime_type as step 1}
Body: <raw file bytes>
```

**Critical rules:**

- **No Authorization header.** The signature is in the query string of `upload_url`. Adding `Authorization` will cause S3 to reject with `400 Bad Request: Only one auth mechanism allowed`.
- **`Content-Type` must equal the `mime_type` you sent in step 1.** S3 includes it in the signature.
- Body is **raw bytes**, not multipart/form-data.

### Response

| Code | Meaning |
|---|---|
| `200 OK` | Upload succeeded |
| `204 No Content` | Upload succeeded (depending on bucket config) |
| `400` | Almost always: `Content-Type` mismatch with step 1 |
| `403` | URL expired, or `Authorization` header was sent by mistake |

The body in success cases is empty or an XML acknowledgment — you don't need to parse it. Treat any 2xx as success.

---

## Step 3 — Create the note with the file reference

### Endpoint

```
POST /api/mobile/businesses/{businessId}/leads/{leadId}/notes
Authorization: Bearer {token}
Content-Type: application/json
```

### Request body

For a **voice note**:

```json
{
  "content": "Voice note",
  "type": "voice",
  "file_path": "voice_recordings/biz_123/abc.m4a",
  "file_name": "voice_note_1717842300000.m4a",
  "file_mime_type": "audio/mp4",
  "metadata": {
    "duration": 12,
    "recorded_at": "2026-04-29T11:42:18.273Z"
  }
}
```

For an **image / document**:

```json
{
  "content": "Photo from site visit",
  "type": "image",
  "file_path": "notes/biz_123/photo.jpg",
  "file_name": "photo.jpg",
  "file_mime_type": "image/jpeg"
}
```

For a **plain text note** (no file):

```json
{
  "content": "Customer asked for a callback next week",
  "type": "note"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `content` | string | yes | Display text. For voice notes, `"Voice note"` is a reasonable placeholder. |
| `type` | string | yes | `note` (text-only), `voice`, `image`, `document` |
| `file_path` | string | when `type != note` | The exact `file_path` returned in step 1 |
| `file_name` | string | optional | Original file name, used in download UI |
| `file_mime_type` | string | optional | Used by the player/preview to pick a renderer |
| `metadata.duration` | int | voice only | Seconds. Used by the audio player to render the seek bar before the file is loaded. |
| `metadata.recorded_at` | string | voice only | ISO 8601 |

### Response `201 Created`

Returns the created note (shape matches the `GET /leads/{id}/notes` list item). Save the `id` so you can re-fetch the file URL later (step 4).

---

## Step 4 — Get a fresh download URL for playback

S3 download URLs are also signed and short-lived. **Don't** store the original `upload_url` and reuse it for playback — that signature is for PUT only and will be expired by then. Instead, ask the backend to issue a fresh GET-signed URL each time you want to play the note.

### Endpoint

```
GET /api/mobile/businesses/{businessId}/leads/{leadId}/notes/{noteId}/download
Authorization: Bearer {token}
```

### Response variant A — JSON (preferred)

```json
{
  "url": "https://s3.amazonaws.com/bucket/voice_recordings/biz_123/abc.m4a?X-Amz-Signature=...",
  "expires_at": "2026-04-29T12:00:00Z",
  "file_name": "voice_note_1717842300000.m4a",
  "mime_type": "audio/mp4"
}
```

### Response variant B — HTTP redirect

Some backends respond with `302 Found` and a `Location` header pointing at the signed URL. Your HTTP client should be ready to either follow the redirect *or* read the `Location` header without following (so you get the URL itself, not the binary).

The reference code handles both: if the response is a 3xx, it reads `Location`; if it's 200 with `application/json`, it parses the body.

| Field | Type | Notes |
|---|---|---|
| `url` | string | Signed GET URL — drop into your audio player |
| `expires_at` | string \| null | When the URL stops working |
| `file_name` | string \| null | For "download" buttons in UI |
| `mime_type` | string \| null | For player codec selection |

### Playback rule of thumb

Fetch a new download URL **every time the user taps play** rather than caching. The cost of one extra GET is negligible; the cost of "audio doesn't play after 15 minutes" is a support ticket.

---

## Recording configuration (Flutter `record` package)

What the reference app uses for voice notes — produces ~10 KB/s, plays on iOS/Android natively:

```dart
const RecordConfig(
  encoder: AudioEncoder.aacLc,   // AAC-LC in MP4 container
  bitRate: 128000,                // 128 kbps
  sampleRate: 44100,
)
```

| Output | Value |
|---|---|
| File extension | `.m4a` |
| MIME type | `audio/mp4` |
| Container | MP4 |
| Codec | AAC-LC |
| Approx size | ~16 KB per second |

iOS, Android, and modern browsers all play `audio/mp4` natively, so no transcoding is needed.

---

## Validation gates the client should enforce

Before kicking off step 1:

```dart
final fileSize = await file.length();
if (fileSize < 1000) throw 'Recording too short';   // <1 KB = empty/glitched
if (fileSize > 10 * 1024 * 1024) throw 'Too large'; // 10 MB voice cap example
```

The "too short" check catches the case where the user taps record-then-stop instantly and produces a header-only file that won't decode.

---

## Reference implementation (Dart)

End-to-end, condensed from the production code:

```dart
Future<void> uploadVoiceNote({
  required String leadId,
  required File file,
  required int durationSeconds,
}) async {
  final fileSize = await file.length();
  if (fileSize < 1000) throw Exception('Recording too short');

  const mimeType = 'audio/mp4';
  final fileName = 'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

  // Step 1: presigned URL
  final presignRes = await http.post(
    Uri.parse('$baseUrl/api/mobile/businesses/$businessId/upload/presigned-url'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'file_name': fileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'resource_type': 'voice_recordings',
    }),
  );
  if (presignRes.statusCode != 200 && presignRes.statusCode != 201) {
    throw Exception('Presign failed: ${presignRes.body}');
  }
  final presign = jsonDecode(presignRes.body);
  final uploadUrl = presign['upload_url'] as String;
  final filePath = presign['file_path'] as String;

  // Step 2: PUT to S3 — NO Authorization header, Content-Type must match
  final s3Res = await http.put(
    Uri.parse(uploadUrl),
    headers: {'Content-Type': mimeType},
    body: await file.readAsBytes(),
  );
  if (s3Res.statusCode != 200 && s3Res.statusCode != 204) {
    throw Exception('S3 upload failed: ${s3Res.statusCode}');
  }

  // Step 3: attach to a note
  final noteRes = await http.post(
    Uri.parse('$baseUrl/api/mobile/businesses/$businessId/leads/$leadId/notes'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'content': 'Voice note',
      'type': 'voice',
      'file_path': filePath,
      'file_name': fileName,
      'file_mime_type': mimeType,
      'metadata': {
        'duration': durationSeconds,
        'recorded_at': DateTime.now().toIso8601String(),
      },
    }),
  );
  if (noteRes.statusCode != 200 && noteRes.statusCode != 201) {
    throw Exception('Note save failed: ${noteRes.body}');
  }
}

Future<String> getPlaybackUrl(String leadId, String noteId) async {
  final res = await http.get(
    Uri.parse('$baseUrl/api/mobile/businesses/$businessId/leads/$leadId/notes/$noteId/download'),
    headers: {'Authorization': 'Bearer $token'},
  );

  // Handle both JSON and redirect responses
  if (res.statusCode == 302 || res.statusCode == 307) {
    return res.headers['location']!;
  }
  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    return (data['url'] ?? data['file_url']) as String;
  }
  throw Exception('Failed to get playback URL: ${res.statusCode}');
}
```

---

## Common implementation mistakes to avoid

1. **Sending `Authorization` to the S3 URL** → S3 rejects with `400`. The signature in the query string IS the auth.
2. **Mismatched `Content-Type` between step 1 and step 2** → S3 rejects with `403 SignatureDoesNotMatch`. Recompute the value once, use the same constant in both places.
3. **Reusing the `upload_url` for playback** → The signature is bound to PUT and a short expiry. Always call the download endpoint when you want a GET URL.
4. **Caching the download URL** → Same expiry problem. Re-fetch on every playback.
5. **Sending `multipart/form-data` to S3** → It expects a raw body. Multipart will upload, but the bytes will be wrapped in MIME boundaries and the file will be corrupt.
6. **Skipping step 3 after a successful S3 upload** → File sits in S3 unreferenced. Backend has no record of it. To the user, it looks like nothing happened.
7. **Calling step 3 before step 2 finishes** → Note exists pointing at a non-existent S3 key. Playback returns 404.

---

## Resource type quick reference

| `resource_type` | Used for | Typical extensions |
|---|---|---|
| `voice_recordings` | Voice notes | `.m4a` |
| `notes` | Image attachments on notes | `.jpg`, `.png`, `.heic` |
| `documents` | PDF / Office files | `.pdf`, `.docx`, `.xlsx` |
| `attachments` | General attachments | any |
| `avatars` | Profile pictures | `.jpg`, `.png` |

The S3 path prefix and per-type size/MIME constraints differ — check with backend before sending unfamiliar combos.
