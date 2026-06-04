// Native (no-WebView) CIP-45 transport scaffold — example only.
//
// `BugoutCip45Transport` (cip45_transport.dart) hosts bugout.js in a headless
// WebView and is the live-verified path today. This file is an alternative that
// runs the WebRTC half *natively* via `flutter_webrtc`, with no WebView.
//
// SCOPE / HONESTY: this is a working implementation of the WebRTC data-channel
// half of CIP-45, but it is NOT yet a drop-in replacement for the bugout
// transport against real dApps, because CIP-45 dApps speak bugout's specific
// protocol. Two pieces are deliberately factored out behind interfaces:
//
//   1. [Cip45SignalingChannel] — peer DISCOVERY + SDP/ICE relay. In real CIP-45
//      this is bugout's WebTorrent layer: announce an infohash derived from the
//      connection identifier to WSS trackers, which relay WebRTC offers/answers
//      between peers in the swarm. Implementing a WebTorrent WSS tracker client
//      in Dart is the main remaining work; it has no equivalent in pub.dev today.
//   2. [Cip45RpcCodec] — the on-wire FRAMING of RPC over the data channel. bugout
//      wraps messages in bencode + NaCl (ed25519 sign / box encrypt) keyed by the
//      address. The default [JsonCip45RpcCodec] here is plain JSON — fine for a
//      native-to-native demo, but a `BugoutCip45RpcCodec` is required to talk to
//      a bugout.js dApp.
//
// So: the WebRTC plumbing is real and exercised; the bugout-compatibility seams
// are explicit and documented, not faked. See docs/cip45-transport.md.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Discovers the remote peer and relays WebRTC signaling (SDP offer/answer and
/// trickled ICE candidates) to/from it.
///
/// This is the bugout/WebTorrent gap: a production implementation announces the
/// CIP-45 `identifier` to WSS trackers and relays signaling through the swarm.
/// The transport is agnostic to *how* signaling is delivered — supply any channel
/// (a tracker client, a manual copy-paste channel for testing, an in-process
/// loopback) and the WebRTC negotiation below works unchanged.
abstract class Cip45SignalingChannel {
  /// Join the swarm / locate the peer for [identifier].
  Future<void> open(String identifier);

  /// Relay one signaling message to the remote peer. Shapes used by the
  /// transport: `{'type': 'offer'|'answer', 'sdp': ...}` and
  /// `{'type': 'ice', 'candidate': ..., 'sdpMid': ..., 'sdpMLineIndex': ...}`.
  Future<void> send(Map<String, dynamic> message);

  /// Signaling messages arriving from the remote peer.
  Stream<Map<String, dynamic>> get incoming;

  /// Leave the swarm and release resources.
  Future<void> close();
}

/// Encodes/decodes RPC frames carried over the WebRTC data channel.
///
/// Frame shapes (logical):
///  - inbound request:  `{'id': <int>, 'method': <String>, 'params': <List>}`
///  - outbound response: `{'id': <int>, 'result': <Object?>}` or
///                       `{'id': <int>, 'error': <String>}`
///  - announcement (sent once on connect): `{'type': 'announce', ...apiInfo}`
abstract class Cip45RpcCodec {
  /// Serialize a frame for the wire.
  Uint8List encode(Map<String, dynamic> frame);

  /// Parse a wire payload back into a frame, or `null` if it is not understood.
  Map<String, dynamic>? decode(Uint8List data);
}

/// Default plain-JSON codec — sufficient for native↔native peers. Talking to a
/// bugout.js dApp requires a bugout-compatible codec (bencode + NaCl) instead.
class JsonCip45RpcCodec implements Cip45RpcCodec {
  const JsonCip45RpcCodec();

  @override
  Uint8List encode(Map<String, dynamic> frame) =>
      Uint8List.fromList(utf8.encode(jsonEncode(frame)));

  @override
  Map<String, dynamic>? decode(Uint8List data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// A native CIP-45 transport: WebRTC data channel + pluggable
/// [Cip45SignalingChannel] (discovery) and [Cip45RpcCodec] (framing).
///
/// The wallet acts as the WebRTC *answerer*: it waits for the dApp's offer
/// (delivered via the signaling channel), answers, and once the data channel
/// opens it sends the API announcement and serves RPC requests through the
/// handler registered with [onRequest].
class WebrtcCip45Transport implements Cip45Transport {
  /// The dApp's connection identifier (from the scanned/pasted URI).
  final String identifier;

  /// Discovery + signaling relay (the bugout/WebTorrent seam).
  final Cip45SignalingChannel signaling;

  /// On-wire RPC framing (the bugout NaCl/bencode seam).
  final Cip45RpcCodec codec;

  /// API-announcement payload sent to the dApp once connected (typically
  /// `Cip45WalletHandler.apiAnnouncement()`).
  final Map<String, dynamic> announcement;

  /// ICE servers for NAT traversal. Defaults to a public STUN server.
  final List<Map<String, dynamic>> iceServers;

  /// Transport state changes: ready / connecting / connected / closed / error.
  final void Function(String status)? onStatus;

  /// Diagnostic log lines.
  final void Function(String level, String message)? onLog;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  StreamSubscription<Map<String, dynamic>>? _sigSub;
  Future<Object?> Function(String method, List<dynamic> params)? _handler;

  WebrtcCip45Transport({
    required this.identifier,
    required this.signaling,
    required this.announcement,
    this.codec = const JsonCip45RpcCodec(),
    this.iceServers = const [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    this.onStatus,
    this.onLog,
  });

  @override
  void onRequest(
    Future<Object?> Function(String method, List<dynamic> params) handler,
  ) {
    _handler = handler;
  }

  @override
  Future<void> start() async {
    onStatus?.call('connecting');
    await signaling.open(identifier);

    final pc = await createPeerConnection({'iceServers': iceServers});
    _pc = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      signaling.send({
        'type': 'ice',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onConnectionState = (state) {
      onLog?.call('webrtc', 'connection: ${state.name}');
      if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onStatus?.call('connected');
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onStatus?.call('closed');
      }
    };

    // As answerer, the dApp opens the data channel; we receive it here.
    pc.onDataChannel = (channel) {
      _channel = channel;
      _wireDataChannel(channel);
    };

    _sigSub = signaling.incoming.listen(
      _onSignal,
      onError: (e) => onLog?.call('error', 'signaling: $e'),
    );

    onStatus?.call('ready');
    onLog?.call('info', 'awaiting dApp offer for $identifier');
  }

  Future<void> _onSignal(Map<String, dynamic> message) async {
    final pc = _pc;
    if (pc == null) return;
    switch (message['type']) {
      case 'offer':
        await pc.setRemoteDescription(
          RTCSessionDescription(message['sdp'] as String, 'offer'),
        );
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await signaling.send({'type': 'answer', 'sdp': answer.sdp});
        onLog?.call('webrtc', 'answered offer');
        break;
      case 'ice':
        await pc.addCandidate(RTCIceCandidate(
          message['candidate'] as String?,
          message['sdpMid'] as String?,
          (message['sdpMLineIndex'] as num?)?.toInt(),
        ));
        break;
      default:
        onLog?.call('warn', 'unknown signal: ${message['type']}');
    }
  }

  void _wireDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      onLog?.call('webrtc', 'datachannel: ${state.name}');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        // Announce our API to the dApp on connect.
        final frame = {'type': 'announce', ...announcement};
        channel.send(RTCDataChannelMessage.fromBinary(codec.encode(frame)));
        onStatus?.call('connected');
      }
    };
    channel.onMessage = (msg) => _onMessage(channel, msg);
  }

  Future<void> _onMessage(
      RTCDataChannel channel, RTCDataChannelMessage msg) async {
    final bytes =
        msg.isBinary ? msg.binary : Uint8List.fromList(utf8.encode(msg.text));
    final frame = codec.decode(bytes);
    if (frame == null) {
      onLog?.call('warn', 'undecodable frame dropped');
      return;
    }
    final id = frame['id'];
    final method = frame['method'];
    if (method is! String) return; // not a request
    final params = (frame['params'] is List)
        ? List<dynamic>.from(frame['params'] as List)
        : const <dynamic>[];

    onLog?.call('rpc', '→ $method');
    final handler = _handler;
    Map<String, dynamic> response;
    if (handler == null) {
      response = {'id': id, 'error': 'no handler registered'};
    } else {
      try {
        response = {'id': id, 'result': await handler(method, params)};
      } catch (e) {
        response = {'id': id, 'error': '$e'};
      }
    }
    channel.send(RTCDataChannelMessage.fromBinary(codec.encode(response)));
    onLog?.call('rpc', '← $method');
  }

  @override
  Future<void> close() async {
    await _sigSub?.cancel();
    _sigSub = null;
    await _channel?.close();
    _channel = null;
    await _pc?.close();
    _pc = null;
    await signaling.close();
    onStatus?.call('closed');
  }
}
