/// Model representing a Video in Plexus
class Video {
  final String? id;
  final String? browseId;
  final String? browseParams;
  final String title;
  final String channelName;
  final String channelAvatar;
  final String views;
  final String uploadTime;
  final String duration;
  final String thumbnailUrl;
  final String videoUrl;
  final String categoryId;
  final String categoryName;
  final String description;
  final int likesCount;
  bool isLiked;
  bool isFavorited;

  Video({
    required this.id,
    this.browseId,
    this.browseParams,
    required this.title,
    required this.channelName,
    required this.channelAvatar,
    required this.views,
    required this.uploadTime,
    required this.duration,
    required this.thumbnailUrl,
    required this.videoUrl,
    required this.categoryId,
    required this.categoryName,
    required this.description,
    required this.likesCount,
    this.isLiked = false,
    this.isFavorited = false,
  });
}
