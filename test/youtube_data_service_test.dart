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
    expect(sections[1].videos.single.itemType, VideoItemType.shorts);
    expect(
      sections[1].videos.single.videoUrl,
      'https://www.youtube.com/shorts/short-1',
    );
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

  test(
    'excludes the known appeal survey renderer without dropping media shelves',
    () {
      final sections = service.parseHomeFeedResponse(
        _homeResponse([
          {
            'appealSurveyShelfRenderer': <String, dynamic>{
              'title': {'simpleText': 'Tell us what you think'},
            },
          },
          _shelf('Recommended', [
            {
              'tileRenderer': _tile(
                videoId: 'recommended-video',
                title: 'Recommended video',
                thumbnailUrl: 'https://example.test/recommended.jpg',
              ),
            },
          ]),
        ]),
      );

      expect(sections.length, 1);
      expect(sections.single.title, 'Recommended');
      expect(sections.single.videos.single.id, 'recommended-video');
    },
  );

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

  test(
    'does not promote a refresh-only grid button to global continuation',
    () {
      final response = _homeResponse([
        _shelf('棒球和更多主题', [
          {
            'tileRenderer': _tile(
              videoId: 'baseball-video',
              title: 'Baseball video',
              thumbnailUrl: 'https://example.test/baseball.jpg',
            ),
          },
        ]),
        _shelf(null, [
          {
            'gridButtonRenderer': {
              'title': {
                'runs': [
                  {'text': '更多...'},
                ],
              },
              'icon': {'iconType': 'ARROW_CIRCLE'},
              'navigationEndpoint': {
                'loadReloadContinuationCommand': {
                  'continuation': 'global-home-token',
                },
              },
            },
          },
        ]),
      ]);
      final sections = service.parseHomeFeedResponse(response);

      expect(sections.map((section) => section.title), ['棒球和更多主题']);
      expect(sections.single.videos.single.id, 'baseball-video');
      expect(service.extractHomeSectionContinuationToken(response), isNull);
    },
  );

  test('loads titled shelves from a global refresh-only continuation', () {
    final response = {
      'continuationContents': {
        'tvSurfaceContentContinuation': {
          'content': {
            'sectionListRenderer': {
              'contents': [
                _shelf('探索更多主题', [
                  {
                    'tileRenderer': _tile(
                      videoId: 'topic-video',
                      title: 'Topic video',
                      thumbnailUrl: 'https://example.test/topic.jpg',
                    ),
                  },
                ]),
                _shelf(null, [
                  {
                    'gridButtonRenderer': {
                      'title': {'simpleText': '刷新'},
                      'icon': {'iconType': 'REFRESH'},
                      'navigationEndpoint': {
                        'loadReloadContinuationCommand': {
                          'continuation': 'next-global-home-token',
                        },
                      },
                    },
                  },
                ]),
              ],
              'continuations': [
                {
                  'nextContinuationData': {
                    'continuation': 'next-global-home-token',
                  },
                },
              ],
            },
          },
        },
      },
    };
    final sections = service.parseHomeContinuationResponse(response);

    expect(sections.map((section) => section.title), ['探索更多主题']);
    expect(sections.single.videos.single.id, 'topic-video');
    expect(
      service.extractHomeSectionContinuationToken(response),
      'next-global-home-token',
    );
  });

  test(
    'ignores signal-service refresh controls in music section continuation',
    () {
      final response = {
        'continuationContents': {
          'sectionListContinuation': {
            'contents': [
              _shelf('More music', [
                {
                  'tileRenderer': _tile(
                    videoId: 'continued-music-video',
                    title: 'Continued music video',
                    thumbnailUrl: 'https://example.test/continued-music.jpg',
                  ),
                },
              ]),
              _shelf(null, [
                {
                  'gridButtonRenderer': {
                    'title': {'simpleText': '刷新'},
                    'icon': {'iconType': 'REFRESH'},
                    'navigationEndpoint': {
                      'clickTrackingParams': 'refresh-click-tracking',
                      'signalServiceEndpoint': {
                        'signal': 'CLIENT_SIGNAL',
                        'actions': <dynamic>[],
                      },
                    },
                  },
                },
              ]),
            ],
            'continuations': [
              {
                'nextContinuationData': {
                  'continuation': 'next-music-section-token',
                },
              },
            ],
          },
        },
      };

      final sections = service.parseHomeContinuationResponse(response);

      expect(sections.length, 1);
      expect(sections.single.title, 'More music');
      expect(sections.single.videos.single.id, 'continued-music-video');
      expect(
        service.extractHomeSectionContinuationToken(response),
        'next-music-section-token',
      );
    },
  );

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

  test('parses SmartTube Music shelves and TV music video renderers', () {
    final response = _homeResponse([
      _shelf('Music for Every Mood', [
        {
          'tvMusicVideoRenderer': {
            'primaryText': {'simpleText': 'Music video title'},
            'secondaryText': {'simpleText': 'Artist name'},
            'tertiaryText': {'simpleText': '98M views • 2 months ago'},
            'lengthText': {'simpleText': '4:36'},
            'navigationEndpoint': {
              'watchEndpoint': {
                'videoId': 'music-video-id',
                'playlistId': 'RDmusic-video-id',
              },
            },
            'thumbnail': {
              'thumbnails': [
                {
                  'url': 'https://example.test/music-video.jpg',
                  'width': 320,
                  'height': 180,
                },
              ],
            },
          },
        },
      ], continuationToken: 'music-row-next'),
      _shelf('New releases', [
        {
          'tvMusicVideoRenderer': {
            'primaryText': {'simpleText': 'Another music video'},
            'navigationEndpoint': {
              'watchEndpoint': {'videoId': 'another-music-video'},
            },
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://example.test/another.jpg'},
              ],
            },
          },
        },
      ]),
    ]);
    final sectionList =
        response['contents']['tvBrowseRenderer']['content']['tvSurfaceContentRenderer']['content']['sectionListRenderer'];
    sectionList['continuations'] = [
      {
        'nextContinuationData': {'continuation': 'music-sections-next'},
      },
    ];

    final page = service.parseMusicBrowseResponse(response);

    expect(page.sections.map((section) => section.title), [
      'Music for Every Mood',
      'New releases',
    ]);
    expect(page.continuationToken, 'music-sections-next');
    expect(page.sections.first.continuationToken, 'music-row-next');

    final musicVideo = page.sections.first.videos.single;
    expect(musicVideo.itemType, VideoItemType.video);
    expect(musicVideo.id, 'music-video-id');
    expect(musicVideo.playlistId, 'RDmusic-video-id');
    expect(musicVideo.title, 'Music video title');
    expect(musicVideo.channelName, 'Artist name');
    expect(musicVideo.views, '98M views • 2 months ago');
    expect(musicVideo.duration, '4:36');
    expect(
      musicVideo.videoUrl,
      'https://www.youtube.com/watch?v=music-video-id&list=RDmusic-video-id',
    );
  });

  test(
    'parses Music section-list continuation independently of row tokens',
    () {
      final page = service.parseMusicBrowseContinuationResponse({
        'continuationContents': {
          'sectionListContinuation': {
            'contents': [
              _shelf('More music', [
                {
                  'tileRenderer': _tile(
                    videoId: 'more-music-video',
                    title: 'More music video',
                    thumbnailUrl: 'https://example.test/more-music.jpg',
                  ),
                },
              ]),
            ],
            'continuations': [
              {
                'nextContinuationData': {'continuation': 'next-music-sections'},
              },
            ],
          },
        },
      });

      expect(page.sections.single.title, 'More music');
      expect(page.sections.single.videos.single.id, 'more-music-video');
      expect(page.continuationToken, 'next-music-sections');
    },
  );

  test(
    'progressively emits Music shelves and stops on an empty page',
    () async {
      final firstSection = VideoSection(
        title: 'First music shelf',
        videos: const [],
      );
      final nextSections = [
        const VideoSection(title: 'Second music shelf', videos: []),
        const VideoSection(title: 'Third music shelf', videos: []),
      ];
      final requestedTokens = <String>[];

      final pages = await service.streamMusicBrowsePages(
        (sections: [firstSection], continuationToken: 'music-page-1'),
        (continuation) async {
          requestedTokens.add(continuation);
          if (continuation == 'music-page-1') {
            return (sections: nextSections, continuationToken: 'music-page-2');
          }
          return (sections: const <VideoSection>[], continuationToken: null);
        },
      ).toList();

      expect(requestedTokens, ['music-page-1', 'music-page-2']);
      expect(pages.map((page) => page.sections.length), [1, 3]);
      expect(
        pages.map(
          (page) => page.sections.map((section) => section.title).toList(),
        ),
        [
          ['First music shelf'],
          ['First music shelf', 'Second music shelf', 'Third music shelf'],
        ],
      );
      expect(pages.last.continuationToken, 'music-page-2');
    },
  );

  test('appends browse destination continuation items', () {
    final initial = VideoSection(
      title: 'Music',
      videos: [
        Video(
          id: 'music-1',
          itemType: VideoItemType.video,
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
          itemType: VideoItemType.video,
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

  test('appends shelves from both TV section-list continuation envelopes', () {
    final original = VideoSection(
      title: 'Recommended',
      videos: [
        Video(
          id: 'existing-video',
          itemType: VideoItemType.video,
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
    final sectionList = {
      'contents': [
        _shelf('Recommended continuation', [
          {
            'tileRenderer': _tile(
              videoId: 'continued-video-1',
              title: 'Continued video one',
              thumbnailUrl: 'https://example.test/continued-1.jpg',
            ),
          },
        ]),
        _shelf('More recommendations', [
          {
            'tileRenderer': _tile(
              videoId: 'continued-video-2',
              title: 'Continued video two',
              thumbnailUrl: 'https://example.test/continued-2.jpg',
            ),
          },
        ]),
      ],
      'continuations': [
        {
          'nextContinuationData': {'continuation': 'next-section-token'},
        },
      ],
    };
    final envelopes = [
      {'sectionListContinuation': sectionList},
      {
        'tvSurfaceContentContinuation': {
          'content': {'sectionListRenderer': sectionList},
        },
      },
    ];

    for (final continuationContent in envelopes) {
      final updated = service.parseHomeSectionContinuationResponse(original, {
        'continuationContents': continuationContent,
      });

      expect(updated.videos.map((video) => video.id), [
        'existing-video',
        'continued-video-1',
        'continued-video-2',
      ]);
      expect(updated.continuationToken, 'next-section-token');
    }
  });

  test('uses grid refresh button as the next section continuation', () {
    final original = VideoSection(
      title: 'Recommended',
      videos: const [],
      continuationToken: 'section-token',
    );

    final updated = service.parseHomeSectionContinuationResponse(original, {
      'continuationContents': {
        'horizontalListContinuation': {
          'items': [
            {
              'tileRenderer': _tile(
                videoId: 'continued-video',
                title: 'Continued video',
                thumbnailUrl: 'https://example.test/continued.jpg',
              ),
            },
            {
              'gridButtonRenderer': {
                'title': {'simpleText': '刷新'},
                'icon': {'iconType': 'REFRESH'},
                'navigationEndpoint': {
                  'clickTrackingParams': 'tracking-value',
                  'loadReloadContinuationCommand': {
                    'continuation': 'reload-next-token',
                  },
                },
                'trackingParams': 'button-tracking-value',
              },
            },
          ],
        },
      },
    });

    expect(updated.videos.map((video) => video.id), ['continued-video']);
    expect(updated.continuationToken, 'reload-next-token');
  });

  test('surfaces a grid refresh button without a continuation token', () {
    final original = VideoSection(
      title: 'Recommended',
      videos: const [],
      continuationToken: 'section-token',
    );

    expect(
      () => service.parseHomeSectionContinuationResponse(original, {
        'continuationContents': {
          'horizontalListContinuation': {
            'items': [
              {
                'gridButtonRenderer': {
                  'title': {'simpleText': '刷新'},
                  'navigationEndpoint': {
                    'loadReloadContinuationCommand': <String, dynamic>{},
                  },
                },
              },
            ],
          },
        },
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('缺少 continuation'),
        ),
      ),
    );
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

  test('uses section-list token, then first shelf continuation for home paging', () {
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

    expect(
      service.extractHomeSectionContinuationToken(response),
      'video-list-token',
    );

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
              contentType: 'TILE_CONTENT_TYPE_PLAYLIST',
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
    expect(track.itemType, VideoItemType.track);
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
    expect(playlist.itemType, VideoItemType.playlist);
    expect(playlist.browseId, 'playlist-browse-id');
    expect(playlist.title, 'Actual playlist');
    expect(playlist.thumbnailUrl, 'https://example.test/playlist.jpg');
  });

  test(
    'classifies VIDEO tiles with playlist browse IDs as playlist entries',
    () {
      final item = service
          .parseHomeFeedResponse(
            _homeResponse([
              _shelf('Mixes', [
                {
                  'tileRenderer': {
                    'contentType': 'TILE_CONTENT_TYPE_VIDEO',
                    'onSelectCommand': {
                      'browseEndpoint': {
                        'browseId': 'VLPLbN6m7HQXaYo',
                        'params': 'playlist-params',
                      },
                    },
                    'metadata': {
                      'tileMetadataRenderer': {
                        'title': {'simpleText': 'Original playlist title'},
                      },
                    },
                    'header': {
                      'tileHeaderRenderer': {
                        'thumbnail': {
                          'thumbnails': [
                            {
                              'url': 'https://example.test/playlist-tile.jpg',
                              'width': 640,
                            },
                          ],
                        },
                      },
                    },
                  },
                },
              ]),
            ]),
          )
          .single
          .videos
          .single;

      expect(item.itemType, VideoItemType.playlist);
      expect(item.id, isNull);
      expect(item.browseId, 'VLPLbN6m7HQXaYo');
      expect(item.browseParams, 'playlist-params');
      expect(item.title, 'Original playlist title');
    },
  );

  test(
    'classifies VIDEO tiles with other browse IDs as browse destinations',
    () {
      final item = service
          .parseHomeFeedResponse(
            _homeResponse([
              _shelf('Explore', [
                {
                  'tileRenderer': {
                    'contentType': 'TILE_CONTENT_TYPE_VIDEO',
                    'onSelectCommand': {
                      'browseEndpoint': {'browseId': 'FEwhat_to_watch'},
                    },
                    'metadata': {
                      'tileMetadataRenderer': {
                        'title': {'simpleText': 'Explore destination'},
                      },
                    },
                    'header': {
                      'tileHeaderRenderer': {
                        'thumbnail': {
                          'thumbnails': [
                            {
                              'url': 'https://example.test/explore.jpg',
                              'width': 640,
                            },
                          ],
                        },
                      },
                    },
                  },
                },
              ]),
            ]),
          )
          .single
          .videos
          .single;

      expect(item.itemType, VideoItemType.browseDestination);
      expect(item.id, isNull);
      expect(item.browseId, 'FEwhat_to_watch');
    },
  );

  test('parses playlist watch endpoints with both video and playlist IDs', () {
    final sections = service.parseHomeFeedResponse(
      _homeResponse([
        _shelf('Mix', [
          {
            'tileRenderer': {
              'contentType': 'TILE_CONTENT_TYPE_PLAYLIST',
              'onSelectCommand': {
                'clickTrackingParams': 'tracking-value',
                'watchEndpoint': {
                  'videoId': 'mix-first-video',
                  'playlistId': 'RDmix-playlist',
                  'params': 'playlist-params',
                  'continuePlayback': true,
                },
              },
              'metadata': {
                'tileMetadataRenderer': {
                  'title': {'simpleText': 'Daily Mix'},
                },
              },
              'header': {
                'tileHeaderRenderer': {
                  'thumbnail': {
                    'thumbnails': [
                      {'url': 'https://example.test/mix.jpg', 'width': 640},
                    ],
                  },
                  'thumbnailOverlays': <dynamic>[],
                },
              },
            },
          },
        ]),
      ]),
    );

    final mix = sections.single.videos.single;
    expect(mix.itemType, VideoItemType.playlist);
    expect(mix.id, 'mix-first-video');
    expect(mix.playlistId, 'RDmix-playlist');
    expect(mix.browseId, isNull);
    expect(
      mix.videoUrl,
      'https://www.youtube.com/watch?v=mix-first-video&list=RDmix-playlist',
    );
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
    expect(channel.itemType, VideoItemType.channel);
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

  test('infers video type only from a single watch endpoint', () {
    final item = service
        .parseHomeFeedResponse(
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
            ]),
          ]),
        )
        .single
        .videos
        .single;

    expect(item.itemType, VideoItemType.video);
    expect(item.id, 'audio-video-id');
  });

  test('unwraps one video endpoint and a feedback sidecar command', () {
    final tile = _tile(
      videoId: 'wrapped-video-id',
      title: 'Wrapped video',
      thumbnailUrl: 'https://example.test/wrapped-video.jpg',
    );
    tile['onSelectCommand'] = {
      'clickTrackingParams': 'tracking-value',
      'commandExecutorCommand': {
        'commands': [
          {
            'clickTrackingParams': 'video-tracking-value',
            'watchEndpoint': {
              'videoId': 'wrapped-video-id',
              'playlistId': 'RDwrapped-video',
              'params': 'playlist-params',
              'playerParams': 'player-params',
              'watchEndpointSupportedOnesieConfig': <String, dynamic>{},
            },
          },
          {
            'clickTrackingParams': 'feedback-tracking-value',
            'feedbackEndpoint': {
              'feedbackToken': 'feedback-token',
              'uiActions': <String, dynamic>{},
            },
          },
        ],
      },
    };

    final item = service
        .parseHomeFeedResponse(
          _homeResponse([
            _shelf('Recommended', [
              {'tileRenderer': tile},
            ]),
          ]),
        )
        .single
        .videos
        .single;

    expect(item.itemType, VideoItemType.video);
    expect(item.id, 'wrapped-video-id');
    expect(item.playlistId, 'RDwrapped-video');
    expect(
      item.videoUrl,
      'https://www.youtube.com/watch?v=wrapped-video-id&list=RDwrapped-video',
    );
  });

  test('rejects multiple endpoints in a video command executor', () {
    final tile = _tile(
      videoId: 'wrapped-video-id',
      title: 'Ambiguous video',
      thumbnailUrl: 'https://example.test/wrapped-video.jpg',
    );
    tile['onSelectCommand'] = {
      'commandExecutorCommand': {
        'commands': [
          {
            'watchEndpoint': {'videoId': 'wrapped-video-id'},
          },
          {
            'browseEndpoint': {'browseId': 'browse-destination'},
          },
        ],
      },
    };

    expect(
      () => service.parseHomeFeedResponse(
        _homeResponse([
          _shelf('Ambiguous', [
            {'tileRenderer': tile},
          ]),
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('识别到 2 个'),
        ),
      ),
    );
  });

  test('rejects unknown sidecar commands in a video command executor', () {
    final tile = _tile(
      videoId: 'wrapped-video-id',
      title: 'Unknown action video',
      thumbnailUrl: 'https://example.test/wrapped-video.jpg',
    );
    tile['onSelectCommand'] = {
      'commandExecutorCommand': {
        'commands': [
          {
            'watchEndpoint': {'videoId': 'wrapped-video-id'},
          },
          {
            'signalAction': {'signal': 'unknown'},
          },
        ],
      },
    };

    expect(
      () => service.parseHomeFeedResponse(
        _homeResponse([
          _shelf('Unknown action', [
            {'tileRenderer': tile},
          ]),
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('signalAction'),
        ),
      ),
    );
  });

  test('treats a video tile with reelWatchEndpoint as Shorts', () {
    final item = service
        .parseHomeFeedResponse(
          _homeResponse([
            _shelf('Shorts continuation', [
              {
                'tileRenderer': _tile(
                  videoId: 'continued-short',
                  title: 'Continued short',
                  thumbnailUrl: 'https://example.test/continued-short.jpg',
                  contentType: 'TILE_CONTENT_TYPE_VIDEO',
                  useReelEndpoint: true,
                ),
              },
            ]),
          ]),
        )
        .single
        .videos
        .single;

    expect(item.itemType, VideoItemType.shorts);
    expect(item.id, 'continued-short');
    expect(item.videoUrl, 'https://www.youtube.com/shorts/continued-short');
  });

  test(
    'classifies a content-type-free browse endpoint as generic navigation',
    () {
      final item = service
          .parseHomeFeedResponse(
            _homeResponse([
              _shelf('Topics', [
                {
                  'tileRenderer': {
                    'onSelectCommand': {
                      'browseEndpoint': {'browseId': 'topic-browse-id'},
                    },
                    'metadata': {
                      'tileMetadataRenderer': {
                        'title': {'simpleText': '主题入口'},
                      },
                    },
                    'header': {
                      'tileHeaderRenderer': {
                        'thumbnail': {
                          'thumbnails': [
                            {
                              'url': 'https://example.test/topic.jpg',
                              'width': 640,
                            },
                          ],
                        },
                      },
                    },
                  },
                },
              ]),
            ]),
          )
          .single
          .videos
          .single;

      expect(item.itemType, VideoItemType.browseDestination);
      expect(item.id, isNull);
      expect(item.browseId, 'topic-browse-id');
    },
  );

  test(
    'surfaces missing content type when endpoint classification is ambiguous',
    () {
      expect(
        () => service.parseHomeFeedResponse(
          _homeResponse([
            _shelf('Invalid tile', [
              {
                'tileRenderer': {
                  'onSelectCommand': {
                    'watchEndpoint': {'videoId': 'video-id'},
                    'browseEndpoint': {'browseId': 'browse-id'},
                  },
                },
              },
            ]),
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('无法从唯一 endpoint 分类'),
          ),
        ),
      );
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

  test('parses live status from a recognized tile badge', () {
    final tile = Map<String, dynamic>.from(
      _tile(
        videoId: 'live-video',
        title: 'Live video',
        thumbnailUrl: 'https://example.test/live.jpg',
      ),
    );
    final header = Map<String, dynamic>.from(tile['header']);
    final tileHeader = Map<String, dynamic>.from(header['tileHeaderRenderer']);
    final overlays = List<dynamic>.from(tileHeader['thumbnailOverlays']);
    overlays.add(<String, dynamic>{
      'thumbnailOverlayTimeStatusRenderer': <String, String>{'style': 'LIVE'},
    });
    tileHeader['thumbnailOverlays'] = overlays;
    header['tileHeaderRenderer'] = tileHeader;
    tile['header'] = header;

    final video = service
        .parseHomeFeedResponse(
          _homeResponse([
            _shelf('Live', [
              {'tileRenderer': tile},
            ]),
          ]),
        )
        .single
        .videos
        .single;

    expect(video.itemType, VideoItemType.video);
    expect(video.isLive, isTrue);
  });

  test(
    'surfaces an unsupported card renderer instead of searching inside it',
    () {
      expect(
        () => service.parseHomeFeedResponse(
          _homeResponse([
            _shelf('Recommended', [
              {
                'unknownCardRenderer': {'videoId': 'hidden-video'},
              },
            ]),
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('不支持的条目 renderer'),
          ),
        ),
      );
    },
  );
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
                  'params': ?browseParams,
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
  'contentType': ?contentType,
  'onSelectCommand': switch (contentType) {
    'TILE_CONTENT_TYPE_TRACK' ||
    'TILE_CONTENT_TYPE_PLAYLIST' ||
    'TILE_CONTENT_TYPE_CHANNEL' => {
      'browseEndpoint': {'browseId': ?browseId},
    },
    _ => {
      if (useReelEndpoint)
        'reelWatchEndpoint': {'videoId': ?videoId}
      else
        'watchEndpoint': {'videoId': ?videoId},
    },
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
