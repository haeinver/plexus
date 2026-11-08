import 'dart:convert';

/// Representation of a YouTube account signed in via SmartTube V2 OAuth 2.0 & Innertube API
class YouTubeAccount {
  final String id;
  final String? name;
  final String? email;
  final String? channelHandle;
  final String? avatarImageUrl;
  final String refreshToken;
  final String? pageIdToken;
  final bool isSelected;
  final bool hasChannel;

  const YouTubeAccount({
    required this.id,
    this.name,
    this.email,
    this.channelHandle,
    this.avatarImageUrl,
    required this.refreshToken,
    this.pageIdToken,
    this.isSelected = false,
    this.hasChannel = true,
  });

  YouTubeAccount copyWith({
    String? id,
    String? name,
    String? email,
    String? channelHandle,
    String? avatarImageUrl,
    String? refreshToken,
    String? pageIdToken,
    bool? isSelected,
    bool? hasChannel,
  }) {
    return YouTubeAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      channelHandle: channelHandle ?? this.channelHandle,
      avatarImageUrl: avatarImageUrl ?? this.avatarImageUrl,
      refreshToken: refreshToken ?? this.refreshToken,
      pageIdToken: pageIdToken ?? this.pageIdToken,
      isSelected: isSelected ?? this.isSelected,
      hasChannel: hasChannel ?? this.hasChannel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'channelHandle': channelHandle,
      'avatarImageUrl': avatarImageUrl,
      'refreshToken': refreshToken,
      'pageIdToken': pageIdToken,
      'isSelected': isSelected,
      'hasChannel': hasChannel,
    };
  }

  factory YouTubeAccount.fromJson(Map<String, dynamic> json) {
    return YouTubeAccount(
      id: json['id'] as String? ?? json['refreshToken'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      channelHandle: json['channelHandle'] as String?,
      avatarImageUrl: json['avatarImageUrl'] as String?,
      refreshToken: json['refreshToken'] as String? ?? '',
      pageIdToken: json['pageIdToken'] as String?,
      isSelected: json['isSelected'] as bool? ?? false,
      hasChannel: json['hasChannel'] as bool? ?? true,
    );
  }

  String serialize() => jsonEncode(toJson());

  factory YouTubeAccount.deserialize(String raw) =>
      YouTubeAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is YouTubeAccount &&
        other.id == id &&
        other.refreshToken == refreshToken &&
        other.pageIdToken == pageIdToken;
  }

  @override
  int get hashCode => Object.hash(id, refreshToken, pageIdToken);
}
