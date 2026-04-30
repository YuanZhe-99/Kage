# MessagePack Protocol Schema

## Overview

This document defines the binary protocol used for communication between the Agent (controlled device) and Controller (remote operator). All messages are serialized using MessagePack for efficient binary encoding.

## Message Types

### 1. Video Frame (0x01)

Sent from Agent to Controller. Contains encoded video frame data.

```
{
  "type": 0x01,
  "frame_id": uint32,
  "timestamp": uint64,
  "codec": uint8,          // 0=H264, 1=HEVC
  "width": uint16,
  "height": uint16,
  "data": bytes            // Encoded NAL units
}
```

### 2. Input Event (0x02)

Sent from Controller to Agent. Contains input commands.

```
{
  "type": 0x02,
  "event_type": uint8,     // 0=mouse_click, 1=mouse_move, 2=key_down, 3=key_up
  "timestamp": uint64,
  "x": float32,            // Normalized coordinates (0.0-1.0)
  "y": float32,
  "button": uint8,         // 0=left, 1=right, 2=middle
  "key_code": uint16,      // Virtual key code
  "modifiers": uint8       // Bitmask: cmd=1, ctrl=2, alt=4, shift=8
}
```

### 3. Control Command (0x03)

Bidirectional control messages.

```
{
  "type": 0x03,
  "command": uint8,
  "payload": dynamic
}
```

#### Command Subtypes:

- **0x01 - Request Refresh**: Request full screen refresh
- **0x02 - Change Resolution**: Change capture resolution
  ```
  {
    "width": uint16,
    "height": uint16
  }
  ```
- **0x03 - Change Frame Rate**: Adjust frame rate
  ```
  {
    "fps": uint8
  }
  ```
- **0x04 - Pause Stream**: Pause video transmission
- **0x05 - Resume Stream**: Resume video transmission
- **0x06 - Switch Window**: Capture specific window
  ```
  {
    "window_id": uint32
  }
  ```

### 4. Heartbeat (0x04)

Bidirectional keepalive message.

```
{
  "type": 0x04,
  "timestamp": uint64,
  "sequence": uint32
}
```

### 5. Session Key Exchange (0x05)

Used during initial handshake for key exchange.

```
{
  "type": 0x05,
  "public_key": bytes,     // X25519 public key (32 bytes)
  "nonce": bytes,          // 24 bytes
  "encrypted_payload": bytes
}
```

### 6. Error (0xFF)

Error notification.

```
{
  "type": 0xFF,
  "error_code": uint16,
  "message": string
}
```

## Error Codes

| Code | Description |
|------|-------------|
| 0x0001 | Invalid message format |
| 0x0002 | Authentication failed |
| 0x0003 | Session expired |
| 0x0004 | Permission denied |
| 0x0005 | Resource unavailable |
| 0x0006 | Rate limited |

## Encoding Rules

1. All multi-byte integers are big-endian
2. Floating point values use IEEE 754
3. Strings are UTF-8 encoded
4. Byte arrays are length-prefixed (uint32)
5. Timestamps are Unix nanoseconds (uint64)

## Chunking

Messages larger than 16KB must be split into chunks:

```
{
  "type": 0x06,
  "message_id": uint32,
  "chunk_index": uint16,
  "total_chunks": uint16,
  "data": bytes
}
```

## Compression

Optional LZ4 compression for video frames:

```
{
  "type": 0x01,
  "frame_id": uint32,
  "timestamp": uint64,
  "codec": uint8,
  "compressed": true,
  "original_size": uint32,
  "data": bytes  // LZ4 compressed
}
```

## Security

All messages are encrypted with ChaCha20-Poly1305 after session key exchange. The encryption is transparent to the application layer.
