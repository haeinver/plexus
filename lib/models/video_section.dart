import 'video.dart';

class VideoSection {
  final String? title;
  final List<Video> videos;
  final String? continuationToken;
  final String? browseId;
  final String? browseParams;
  final String? browseTitle;

  const VideoSection({
    required this.title,
    required this.videos,
    this.continuationToken,
    this.browseId,
    this.browseParams,
    this.browseTitle,
  });
}
