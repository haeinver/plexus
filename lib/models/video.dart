enum VideoItemType {
  video,
  shorts,
  track,
  playlist,
  channel,
  browseDestination,
}

/// A YouTube home-feed item. Some items navigate to a browse destination.
class Video {
  final String? id;
  final VideoItemType itemType;
  final bool isLive;
  final bool isUpcoming;
  final String? browseId;
  final String? browseParams;
  final String? playlistId;
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
    required this.itemType,
    this.isLive = false,
    this.isUpcoming = false,
    this.browseId,
    this.browseParams,
    this.playlistId,
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
