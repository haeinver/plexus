import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/models/video.dart';
import 'package:plexus/models/video_section.dart';
import 'package:plexus/services/youtube_data_service.dart';

void main() {
  final service = YouTubeDataService();

  test('parses native TV home shelves, video tiles, and Shorts tiles', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('Recommended', [
          {'adSlotRenderer': <String, dynamic>{}},
          {
            'tileRenderer': _tile(
              videoId: 'video-1',
              title: 'Recommended video',
              thumbnailUrl: 'https://example.test/video-1.jpg',
            ),
          },
        ], continuationToken: 'recommended-next'),
        _shelf('Shorts', [
          {
            'tileRenderer': _tile(
              videoId: 'short-1',
              title: 'Shorts title',
              thumbnailUrl: 'https://example.test/short-1.jpg',
              contentType: 'TILE_CONTENT_TYPE_SHORTS',
              useReelEndpoint: true,
              titleInOverlay: true,
            ),
          },
        ]),
      ]),
    );

    expect(sections.map((section) => section.title), ['Recommended', 'Shorts']);
    expect(sections[0].videos.single.id, 'video-1');
    expect(
      sections[0].videos.single.thumbnailUrl,
      'https://example.test/video-1.jpg',
    );
    expect(sections[0].videos.single.duration, '10:11');
    expect(sections[0].videos.single.views, 'Channel One 1.2M views');
    expect(sections[0].continuationToken, 'recommended-next');
    expect(sections[1].continuationToken, isNull);
    expect(sections[1].videos.single.id, 'short-1');
    expect(sections[1].videos.single.title, 'Shorts title');
    expect(sections[1].videos.single.categoryName, 'Shorts');
  });

  test('parses shelves from a TV section-list continuation', () {
    final sections = service.parseHomeContinuationResponse({
      'continuationContents': {
        'sectionListContinuation': {
          'contents': [
            _shelf('More recommendations', [
              {
                'tileRenderer': _tile(
                  videoId: 'continued-video',
                  title: 'Continued video',
                  thumbnailUrl: 'https://example.test/continued-video.jpg',
                ),
              },
            ]),
          ],
        },
      },
    });

    expect(sections.single.title, 'More recommendations');
    expect(sections.single.videos.single.id, 'continued-video');
  });

  test('parses a shelf more button as a browse destination', () {
    final section = service
        .parseHomeFeedResponse(
          _homeResponse([
            _shelf(
              'Music',
              [
                {
                  'tileRenderer': _tile(
                    videoId: 'music-video',
                    title: 'Music video',
                    thumbnailUrl: 'https://example.test/music-video.jpg',
                  ),
                },
              ],
              browseId: 'music-browse-id',
              browseParams: 'music-browse-params',
              browseTitle: 'Browse all',
            ),
          ]),
        )
        .single;

    expect(section.browseId, 'music-browse-id');
    expect(section.browseParams, 'music-browse-params');
    expect(section.browseTitle, 'Browse all');
    expect(section.continuationToken, isNull);
  });

  test('keeps a browse-only shelf without inventing video items', () {
    final section = service
        .parseHomeFeedResponse(
          _homeResponse([
            _shelf(
              'Music',
              const [],
              browseId: 'music-browse-id',
              browseTitle: 'Browse all',
            ),
          ]),
        )
        .single;

    expect(section.videos, isEmpty);
    expect(section.browseId, 'music-browse-id');
    expect(section.browseTitle, 'Browse all');
  });

  test('parses browse destination items and page continuation', () {
    final destination = VideoSection(
      title: 'Music',
      videos: const [],
      browseId: 'music-browse-id',
      browseParams: 'music-browse-params',
      browseTitle: 'Browse all',
    );
    final response = _homeResponse([
      _shelf('Music results', [
        {
          'tileRenderer': _tile(
            videoId: 'music-1',
            title: 'Music result',
            thumbnailUrl: 'https://example.test/music-1.jpg',
          ),
        },
      ]),
    ]);
    final sectionList =
        response['contents']['tvBrowseRenderer']['content']['tvSurfaceContentRenderer']['content']['sectionListRenderer'];
    sectionList['continuations'] = [
      {
        'nextContinuationData': {'continuation': 'browse-next'},
      },
    ];

    final page = service.parseBrowseDestinationResponse(destination, response);

    expect(page.title, 'Music');
    expect(page.videos.single.id, 'music-1');
    expect(page.continuationToken, 'browse-next');
  });

  test('appends browse destination continuation items', () {
    final initial = VideoSection(
      title: 'Music',
      videos: [
        Video(
          id: 'music-1',
          title: 'Music one',
          channelName: '',
          channelAvatar: '',
          views: '',
          uploadTime: '',
          duration: '',
          thumbnailUrl: 'https://example.test/music-1.jpg',
          videoUrl: 'https://www.youtube.com/watch?v=music-1',
          categoryId: 'home',
          categoryName: 'Music',
          description: 'Music one',
          likesCount: 0,
        ),
      ],
      continuationToken: 'browse-next',
    );

    final updated = service.parseBrowseDestinationContinuationResponse(
      initial,
      {
        'continuationContents': {
          'sectionListContinuation': {
            'contents': [
              _shelf('Music results', [
                {
                  'tileRenderer': _tile(
                    videoId: 'music-2',
                    title: 'Music two',
                    thumbnailUrl: 'https://example.test/music-2.jpg',
                  ),
                },
              ]),
            ],
            'continuations': [
              {
                'nextContinuationData': {'continuation': 'browse-last'},
              },
            ],
          },
        },
      },
    );

    expect(updated.videos.map((video) => video.id), ['music-1', 'music-2']);
    expect(updated.continuationToken, 'browse-last');
  });

  test('appends videos from a section horizontal continuation', () {
    final original = VideoSection(
      title: 'Recommended',
      videos: [
        Video(
          id: 'existing-video',
          title: 'Existing video',
          channelName: '',
          channelAvatar: '',
          views: '',
          uploadTime: '',
          duration: '',
          thumbnailUrl: 'https://example.test/existing.jpg',
          videoUrl: 'https://www.youtube.com/watch?v=existing-video',
          categoryId: 'home',
          categoryName: 'Recommended',
          description: 'Existing video',
          likesCount: 0,
        ),
      ],
      continuationToken: 'section-token',
    );

    final updated = service.parseHomeSectionContinuationResponse(original, {
      'continuationContents': {
        'horizontalListContinuation': {
          'items': [
            {
              'tileRenderer': _tile(
                videoId: 'existing-video',
                title: 'Existing video',
                thumbnailUrl: 'https://example.test/existing.jpg',
              ),
            },
            {
              'tileRenderer': _tile(
                videoId: 'next-video',
                title: 'Next video',
                thumbnailUrl: 'https://example.test/next.jpg',
              ),
            },
          ],
          'continuations': [
            {
              'nextContinuationData': {'continuation': 'next-token'},
            },
          ],
        },
      },
    });

    expect(updated.videos.map((video) => video.id), [
      'existing-video',
      'next-video',
    ]);
    expect(updated.continuationToken, 'next-token');
  });

  test('does not request another page when a section has no token', () async {
    final section = VideoSection(title: 'Complete section', videos: const []);

    expect(await service.fetchMoreHomeSectionVideos(section), same(section));
  });

  test(
    'treats horizontal-list continuation as shelf content, not a row error',
    () {
      expect(
        service.parseHomeContinuationResponse({
          'continuationContents': {
            'horizontalListContinuation': {'items': []},
          },
        }),
        isEmpty,
      );
    },
  );

  test('uses section-list tokens, not shelf video-list tokens, for home rows', () {
    final response = _homeResponse([
      _shelf('Recommended', [
        {
          'tileRenderer': _tile(
            videoId: 'video-1',
            title: 'Video title',
            thumbnailUrl: 'https://example.test/video-1.jpg',
          ),
        },
      ]),
    ]);
    final sectionList =
        response['contents']['tvBrowseRenderer']['content']['tvSurfaceContentRenderer']['content']['sectionListRenderer'];
    sectionList['contents'][0]['shelfRenderer']['content']['horizontalListRenderer']['continuations'] =
        [
          {
            'nextContinuationData': {'continuation': 'video-list-token'},
          },
        ];

    expect(service.extractHomeSectionContinuationToken(response), isNull);

    sectionList['continuations'] = [
      {
        'nextContinuationData': {'continuation': 'section-list-token'},
      },
    ];
    expect(
      service.extractHomeSectionContinuationToken(response),
      'section-list-token',
    );
  });

  test('keeps a native shelf with no title without inventing one', () {
    final section = service
        .parseHomeFeedResponse(
          _homeResponse([
            _shelf(null, [
              {
                'tileRenderer': _tile(
                  videoId: 'video-1',
                  title: 'Video title',
                  thumbnailUrl: 'https://example.test/video-1.jpg',
                ),
              },
            ]),
          ]),
        )
        .single;

    expect(section.title, isNull);
    expect(section.videos.single.id, 'video-1');
  });

  test('preserves a browse-only tile without treating browseId as videoId', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('Consumer electronics', [
          {
            'tileRenderer': _tile(
              videoId: null,
              browseId: 'Uw-ETjdGVUk',
              title: 'Browse destination',
              thumbnailUrl: 'https://example.test/browse.jpg',
            ),
          },
        ]),
      ]),
    );

    final item = sections.single.videos.single;
    expect(item.id, isNull);
    expect(item.browseId, 'Uw-ETjdGVUk');
    expect(item.title, 'Browse destination');
    expect(item.thumbnailUrl, 'https://example.test/browse.jpg');
    expect(item.videoUrl, isEmpty);
  });

  test('parses track tiles from their actual track header data', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('Music', [
          {
            'tileRenderer': {
              'contentType': 'TILE_CONTENT_TYPE_TRACK',
              'onSelectCommand': {
                'browseEndpoint': {'browseId': 'track-browse-id'},
              },
              'header': {
                'trackTileHeaderRenderer': {
                  'title': {'simpleText': 'Actual track title'},
                  'thumbnail': {
                    'thumbnails': [
                      {'url': 'https://example.test/track.jpg', 'width': 320},
                    ],
                  },
                },
              },
            },
          },
        ]),
      ]),
    );

    final track = sections.single.videos.single;
    expect(track.id, isNull);
    expect(track.browseId, 'track-browse-id');
    expect(track.title, 'Actual track title');
    expect(track.thumbnailUrl, 'https://example.test/track.jpg');
  });

  test('parses playlist tiles as real browse destinations', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('Music', [
          {
            'tileRenderer': _tile(
              videoId: null,
              browseId: 'playlist-browse-id',
              title: 'Actual playlist',
              thumbnailUrl: 'https://example.test/playlist.jpg',
              contentType: 'TILE_CONTENT_TYPE_PLAYLIST',
            ),
          },
        ]),
      ]),
    );

    final playlist = sections.single.videos.single;
    expect(playlist.id, isNull);
    expect(playlist.browseId, 'playlist-browse-id');
    expect(playlist.title, 'Actual playlist');
    expect(playlist.thumbnailUrl, 'https://example.test/playlist.jpg');
  });

  test('keeps channel tiles as browse destinations', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('影之刃零', [
          {
            'tileRenderer': _tile(
              videoId: null,
              browseId: 'channel-browse-id',
              title: '影之刃零',
              thumbnailUrl: null,
              contentType: 'TILE_CONTENT_TYPE_CHANNEL',
            ),
          },
        ]),
      ]),
    );

    final channel = sections.single.videos.single;
    expect(channel.id, isNull);
    expect(channel.browseId, 'channel-browse-id');
    expect(channel.title, '影之刃零');
    expect(channel.thumbnailUrl, isEmpty);
  });

  test('keeps browse-only tiles without thumbnails as navigable entries', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('Music', [
          {
            'tileRenderer': _tile(
              videoId: null,
              browseId: 'browse-only-id',
              title: 'Browse-only entry',
              thumbnailUrl: null,
              contentType: 'TILE_CONTENT_TYPE_PLAYLIST',
            ),
          },
        ]),
      ]),
    );

    final entry = sections.single.videos.single;
    expect(entry.id, isNull);
    expect(entry.browseId, 'browse-only-id');
    expect(entry.title, 'Browse-only entry');
    expect(entry.thumbnailUrl, isEmpty);
  });

  test(
    'parses continuation tiles without contentType from their endpoints',
    () {
      final sections = service.parseHomeFeedResponse(
        _homeResponse([
          _shelf('Original audio', [
            {
              'tileRenderer': _tile(
                videoId: 'audio-video-id',
                title: 'Original audio video',
                thumbnailUrl: 'https://example.test/audio-video.jpg',
                contentType: null,
              ),
            },
            {
              'tileRenderer': _tile(
                videoId: null,
                browseId: 'audio-playlist-browse-id',
                title: 'Original audio playlist',
                thumbnailUrl: 'https://example.test/audio-playlist.jpg',
                contentType: null,
              ),
            },
          ]),
        ]),
      );

      expect(sections.single.videos.map((video) => video.id), [
        'audio-video-id',
        null,
      ]);
      expect(sections.single.videos.last.browseId, 'audio-playlist-browse-id');
    },
  );

  test('surfaces unsupported tile content types instead of dropping them', () {
    expect(
      () => service.parseHomeFeedResponse(
        _homeResponse([
          _shelf('Music', [
            {
              'tileRenderer': _tile(
                videoId: null,
                browseId: 'unknown-tile',
                title: 'Unknown tile',
                thumbnailUrl: 'https://example.test/unknown.jpg',
                contentType: 'TILE_CONTENT_TYPE_UNKNOWN',
              ),
            },
          ]),
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('TILE_CONTENT_TYPE_UNKNOWN'),
        ),
      ),
    );
  });

  test('surfaces a missing thumbnail on a video tile', () {
    expect(
      () => service.parseHomeFeedResponse(
        _homeResponse([
          _shelf('Recommended', [
            {
              'tileRenderer': _tile(
                videoId: 'video-1',
                title: 'Video title',
                thumbnailUrl: null,
              ),
            },
          ]),
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('缺少缩略图地址'),
        ),
      ),
    );
  });

  test('surfaces a missing ID on a video tile', () {
    expect(
      () => service.parseHomeFeedResponse(
        _homeResponse([
          _shelf('Recommended', [
            {
              'tileRenderer': _tile(
                videoId: null,
                title: 'Video title',
                thumbnailUrl: 'https://example.test/video.jpg',
              ),
            },
          ]),
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('缺少 videoId'),
        ),
      ),
    );
  });
}

Map<String, dynamic> _homeResponse(List<Map<String, dynamic>> sections) => {
  'contents': {
    'tvBrowseRenderer': {
      'content': {
        'tvSurfaceContentRenderer': {
          'content': {
            'sectionListRenderer': {'contents': sections},
          },
        },
      },
    },
  },
};

Map<String, dynamic> _shelf(
  String? title,
  List<Map<String, dynamic>> items, {
  String? continuationToken,
  String? browseId,
  String? browseParams,
  String? browseTitle,
}) => {
  'shelfRenderer': {
    'headerRenderer': {
      'shelfHeaderRenderer': {
        if (title != null) 'title': {'simpleText': title},
        if (browseId != null)
          'moreContentButton': {
            'buttonRenderer': {
              if (browseTitle != null) 'text': {'simpleText': browseTitle},
              'navigationEndpoint': {
                'browseEndpoint': {
                  'browseId': browseId,
                  if (browseParams != null) 'params': browseParams,
                },
              },
            },
          },
      },
    },
    'content': {
      'horizontalListRenderer': {
        'items': items,
        if (continuationToken != null)
          'continuations': [
            {
              'nextContinuationData': {'continuation': continuationToken},
            },
          ],
      },
    },
  },
};

Map<String, dynamic> _tile({
  required String? videoId,
  required String title,
  required String? thumbnailUrl,
  String? contentType = 'TILE_CONTENT_TYPE_VIDEO',
  bool useReelEndpoint = false,
  bool titleInOverlay = false,
  String? browseId,
}) => {
  if (contentType != null) 'contentType': contentType,
  'onSelectCommand': {
    if (browseId != null) 'browseEndpoint': {'browseId': browseId},
    if (useReelEndpoint)
      'reelWatchEndpoint': {if (videoId != null) 'videoId': videoId}
    else
      'watchEndpoint': {if (videoId != null) 'videoId': videoId},
  },
  if (!titleInOverlay)
    'metadata': {
      'tileMetadataRenderer': {
        'title': {'simpleText': title},
        'lines': [
          {
            'lineRenderer': {
              'items': [
                {
                  'lineItemRenderer': {
                    'text': {'simpleText': 'Channel One'},
                  },
                },
                {
                  'lineItemRenderer': {
                    'text': {'simpleText': '1.2M views'},
                  },
                },
              ],
            },
          },
        ],
      },
    },
  'header': {
    'tileHeaderRenderer': {
      if (thumbnailUrl != null)
        'thumbnail': {
          'thumbnails': [
            {'url': thumbnailUrl, 'width': 1280},
          ],
        },
      'thumbnailOverlays': [
        if (titleInOverlay)
          {
            'tileMetadataRenderer': {
              'title': {'simpleText': title},
            },
          },
        {
          'thumbnailOverlayTimeStatusRenderer': {
            'text': {'simpleText': '10:11'},
          },
        },
      ],
    },
  },
};
