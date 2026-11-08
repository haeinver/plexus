/// Model representing a Subscribed Channel / Creator
class Channel {
  final String id;
  final String name;
  final String avatarUrl;
  final String subscriberCount;
  final String videoCount;
  final String description;
  bool isSubscribed;
  final bool hasUnreadUpdate;

  Channel({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.subscriberCount,
    required this.videoCount,
    required this.description,
    this.isSubscribed = true,
    this.hasUnreadUpdate = false,
  });
}
