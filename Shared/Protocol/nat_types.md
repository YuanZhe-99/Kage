# NAT Types and ICE Candidate Extensions

## Overview

This document defines the NAT type classification system and ICE candidate extensions used for NAT traversal in the GhostCursor/ContextHelper P2P network.

## NAT Types

### Classification

| Type | Name | Description | P2P Difficulty |
|------|------|-------------|----------------|
| 0 | Unknown | NAT type not yet determined | N/A |
| 1 | Open | No NAT, public IP address | Easy |
| 2 | Full Cone | All internal mappings preserved | Easy |
| 3 | Restricted Cone | Address-restricted mapping | Medium |
| 4 | Port Restricted | Address and port-restricted mapping | Medium |
| 5 | Symmetric | Different mapping for each destination | Hard |

### Detection Algorithm

```
function detectNATType():
    // Step 1: Check for local IP
    localIP = getLocalIP()
    if isPublicIP(localIP):
        return NAT_OPEN

    // Step 2: STUN test from same address
    stunResult1 = stunRequest(STUN_SERVER_1)
    if stunResult1 == null:
        return NAT_UNKNOWN

    // Step 3: STUN test from different address
    stunResult2 = stunRequest(STUN_SERVER_2)
    if stunResult2 == null:
        return NAT_UNKNOWN

    // Step 4: Compare external addresses
    if stunResult1.ip != stunResult2.ip:
        return NAT_UNKNOWN  // Multiple public IPs

    if stunResult1.port == stunResult2.port:
        // Same mapping for different destinations
        return NAT_FULL_CONE

    // Step 5: Port restriction test
    if canReceiveFromDifferentPort(stunResult1.port):
        return NAT_RESTRICTED_CONE

    return NAT_PORT_RESTRICTED

    // Step 6: Symmetric detection
    stunResult3 = stunRequest(STUN_SERVER_3)
    if stunResult3.port != stunResult2.port:
        return NAT_SYMMETRIC

    return NAT_PORT_RESTRICTED
```

## ICE Candidate Extensions

### Standard Candidates

| Type | Foundation | Description |
|------|-----------|-------------|
| host | "host" | Local interface address |
| srflx | "srflx" | Server reflexive (STUN) |
| relay | "relay" | TURN relay address |

### Extended Candidates

#### Predicted Candidate

For symmetric NAT traversal using port prediction:

```
{
  "foundation": "pred-<hash>",
  "component": 1,
  "protocol": "udp",
  "priority": <calculated>,
  "ip": "<predicted_ip>",
  "port": <predicted_port>,
  "type": "prflx",
  "extensions": {
    "prediction_method": "incremental|birthday|pattern",
    "confidence": 0.0-1.0,
    "source_observations": 3
  }
}
```

#### IPv6 Candidate

Prioritized when available:

```
{
  "foundation": "host6",
  "component": 1,
  "protocol": "udp",
  "priority": <high_priority>,
  "ip": "2001:db8::1",
  "port": 12345,
  "type": "host",
  "extensions": {
    "ipv6_native": true
  }
}
```

## Port Prediction Methods

### 1. Incremental Prediction

Some NAT devices increment port numbers sequentially:

```
observe port sequence: 5000, 5001, 5002
predicted next: 5003
confidence: high if 3+ consecutive observations
```

### 2. Birthday Attack

For random port allocation, use birthday paradox:

```
target_port_range = [min_observed, max_observed]
probe_count = sqrt(port_range_size) * 1.5
send_probes_to all candidate ports simultaneously
```

### 3. Pattern Detection

Detect patterns in port allocation:

```
- Fixed offset: base_port + constant
- Hash-based: hash(src_ip, dst_ip) % range
- Time-based: port changes at fixed intervals
```

## Priority Calculation

Candidate priority follows RFC 8445 with extensions:

```
priority = (2^24) * type_preference +
           (2^8) * local_preference +
           (2^0) * (256 - component_id)

Type preferences:
- host: 126
- srflx: 110
- prflx: 100 (predicted)
- relay: 0

Local preference adjustments:
- IPv6: +100
- Predicted with high confidence: +50
- Low RTT path: +30
```

## STUN Multi-Probe Strategy

### Probe Configuration

```
STUN_SERVERS = [
    "stun.l.google.com:19302",
    "stun1.l.google.com:19302",
    "stun2.l.google.com:19302",
    "stun.antisip.com:3478",
    "stun.counterpath.com:3478"
]

PROBE_TIMEOUT = 500ms
MAX_PROBES_PER_SERVER = 3
PARALLEL_PROBES = 3
```

### NAT Type Confidence

```
confidence = 0.0

if all_probes_agree:
    confidence = 0.95
elif majority_agree:
    confidence = 0.75
elif conflicting_results:
    confidence = 0.5
    // Trigger additional probes
```

## Simultaneous Open Strategy

When both peers are behind NAT:

1. Exchange all candidates via signaling
2. Both peers start sending DTLS Hello to all candidate pairs simultaneously
3. Use short timeout (100ms) between attempts
4. First successful DTLS handshake wins

```
for each candidate_pair in sorted_by_priority:
    send_dtls_hello(candidate_pair, timeout=100ms)
    if received_response:
        establish_connection(candidate_pair)
        break
```

## TURN Relay Fallback

Triggered when:
- All P2P candidates fail after 30 seconds
- Both peers are behind symmetric NAT
- No IPv6 available

TURN allocation:
```
{
  "transport": "udp",
  "server": "turn.example.com:443",
  "username": "<peer_id>:<expiry>",
  "credential": "<hmac_credential>"
}
```

## Implementation Notes

1. **Thread Safety**: All NAT detection and candidate gathering must be thread-safe
2. **Cancellation**: Support cancellation of ongoing probes
3. **Caching**: Cache NAT type for 5 minutes to avoid repeated detection
4. **Fallback Order**: IPv6 → P2P → Predicted → TURN Relay
5. **Logging**: Log all probe results for debugging
