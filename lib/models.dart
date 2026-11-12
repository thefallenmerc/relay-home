enum Reachability { checking, online, offline }

enum PairingStage { sending, waiting, checking, complete }

const _unset = Object();

class RelayChannel {
  final int channel;
  final String name, preset;
  final String? customImagePath;
  final bool? lastState;
  final DateTime? lastSentAt;
  final bool uncertain;
  const RelayChannel({
    required this.channel,
    required this.name,
    this.preset = 'switch',
    this.customImagePath,
    this.lastState,
    this.lastSentAt,
    this.uncertain = false,
  });
  RelayChannel copyWith({
    int? channel,
    String? name,
    String? preset,
    String? customImagePath,
    bool clearCustomImage = false,
    Object? lastState = _unset,
    DateTime? lastSentAt,
    bool? uncertain,
  }) => RelayChannel(
    channel: channel ?? this.channel,
    name: name ?? this.name,
    preset: preset ?? this.preset,
    customImagePath: clearCustomImage
        ? null
        : customImagePath ?? this.customImagePath,
    lastState: identical(lastState, _unset)
        ? this.lastState
        : lastState as bool?,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    uncertain: uncertain ?? this.uncertain,
  );
  Map<String, dynamic> toJson() => {
    'channel': channel,
    'name': name,
    'preset': preset,
    'customImagePath': customImagePath,
    'lastState': lastState,
    'lastSentAt': lastSentAt?.toIso8601String(),
    'uncertain': uncertain,
  };
  factory RelayChannel.fromJson(Map<String, dynamic> json) => RelayChannel(
    channel: json['channel'] as int,
    name: json['name'] as String,
    preset: json['preset'] as String? ?? 'switch',
    customImagePath: json['customImagePath'] as String?,
    lastState: json['lastState'] as bool?,
    lastSentAt: DateTime.tryParse(json['lastSentAt'] as String? ?? ''),
    uncertain: json['uncertain'] == true,
  );
}

class RelayDevice {
  final String id, name, room, preset, ip;
  final int port;
  final String? mac;
  final List<RelayChannel> relays;
  final Reachability reachability;
  final DateTime? lastSeen;
  final bool demo;
  const RelayDevice({
    required this.id,
    required this.name,
    required this.room,
    required this.ip,
    required this.relays,
    this.preset = 'board',
    this.port = 8080,
    this.mac,
    this.reachability = Reachability.offline,
    this.lastSeen,
    this.demo = false,
  });
  RelayDevice copyWith({
    String? id,
    String? name,
    String? room,
    String? preset,
    String? ip,
    int? port,
    String? mac,
    List<RelayChannel>? relays,
    Reachability? reachability,
    DateTime? lastSeen,
    bool? demo,
  }) => RelayDevice(
    id: id ?? this.id,
    name: name ?? this.name,
    room: room ?? this.room,
    preset: preset ?? this.preset,
    ip: ip ?? this.ip,
    port: port ?? this.port,
    mac: mac ?? this.mac,
    relays: relays ?? this.relays,
    reachability: reachability ?? this.reachability,
    lastSeen: lastSeen ?? this.lastSeen,
    demo: demo ?? this.demo,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'room': room,
    'preset': preset,
    'ip': ip,
    'port': port,
    'mac': mac,
    'relays': relays.map((r) => r.toJson()).toList(),
    'lastSeen': lastSeen?.toIso8601String(),
    'demo': demo,
  };
  factory RelayDevice.fromJson(Map<String, dynamic> json) => RelayDevice(
    id: json['id'] as String,
    name: json['name'] as String,
    room: json['room'] as String,
    ip: json['ip'] as String,
    preset: json['preset'] as String? ?? 'board',
    port: json['port'] as int? ?? 8080,
    mac: json['mac'] as String?,
    relays: (json['relays'] as List)
        .map((r) => RelayChannel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
    demo: json['demo'] == true,
  );
}

class NetworkSnapshot {
  final String? ssid, ipv4, subnetMask, bssid;
  final int? frequencyMhz;
  final bool isWifi, permissionGranted;
  const NetworkSnapshot({
    this.ssid,
    this.ipv4,
    this.subnetMask,
    this.bssid,
    this.frequencyMhz,
    this.isWifi = false,
    this.permissionGranted = false,
  });
  factory NetworkSnapshot.fromMap(Map<dynamic, dynamic> map) => NetworkSnapshot(
    ssid: map['ssid'] as String?,
    ipv4: map['ipv4'] as String?,
    subnetMask: map['subnetMask'] as String?,
    bssid: map['bssid'] as String?,
    frequencyMhz: (map['frequencyMhz'] as num?)?.toInt(),
    isWifi: map['isWifi'] == true,
    permissionGranted: map['permissionGranted'] == true,
  );
}

class DiscoveredDevice {
  final String ip;
  final String? mac;
  final bool reachable, verified;
  const DiscoveredDevice({
    required this.ip,
    this.mac,
    this.reachable = false,
    this.verified = false,
  });
}

class CommandResult {
  final bool success, uncertain;
  final String message;
  const CommandResult({
    required this.success,
    required this.message,
    this.uncertain = false,
  });
}
