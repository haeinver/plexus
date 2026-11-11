import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/models/video.dart';
import 'package:plexus/models/video_section.dart';
import 'package:plexus/pages/home/item_destination_pages.dart';
import 'package:plexus/pages/player/special_video_pages.dart';
import 'package:plexus/pages/player/video_detail_page.dart';
import 'package:plexus/services/youtube_data_service.dart';

void main() {
  final service = YouTubeDataService();

  test('includes TV browse check flags in continuation requests', () {
    final context = <String, dynamic>{
      'client': {'clientName': 'TVHTML5'},
    };

    expect(service.createContinuationRequestBody(context, 'next-token'), {
      'context': context,
      'continuation': 'next-token',
      'racyCheckOk': true,
      'contentCheckOk': true,
    });
  });

  test('builds the original SmartTube YouTube completion request', () {
    final uri = service.createSearchSuggestionsUri('王', region: 'CN');

    expect(uri.host, 'clients1.google.com');
    expect(uri.path, '/complete/search');
    expect(uri.queryParameters, {
      'client': 'youtube-lr',
      'ds': 'yt',
      'xhr': 't',
      'oe': 'utf-8',
      'xssi': 't',
      'gl': 'CN',
      'q': '王',
    });
  });

  test('parses and deduplicates YouTube search suggestions', () {
    expect(
      service.parseSearchSuggestionsResponse(
        ")]}',\n[\"王\",[[\"王者荣耀\",0],[\"王一博\",0],[\"王者荣耀\",0]]]",
      ),
      ['王者荣耀', '王一博'],
    );
  });

  test('rejects malformed YouTube search suggestion entries', () {
    expect(
      () => service.parseSearchSuggestionsResponse('["王",[[0,0]]]'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('[1][0][0]'),
        ),
      ),
    );
  });

  test('builds browse destination request with its endpoint fields', () {
    final context = <String, dynamic>{
      'client': {'clientName': 'TVHTML5'},
    };
    final destination = VideoSection(
      title: 'Music',
      videos: const [],
      browseId: 'music-browse-id',
      browseParams: 'music-browse-params',
    );

    expect(service.createBrowseDestinationRequestBody(context, destination), {
      'context': context,
      'browseId': 'music-browse-id',
      'params': 'music-browse-params',
    });
  });

  test('rejects browse destination requests without a browse ID', () {
    final destination = VideoSection(title: 'Music', videos: const []);

    expect(
      () => service.createBrowseDestinationRequestBody({}, destination),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('browseId'),
        ),
      ),
    );
  });

  test(
    'builds the TV browse context with app capabilities and visitor data',
    () {
      final context = service.createTVBrowseContext(
        language: 'en',
        region: 'US',
        utcOffsetMinutes: '0',
        visitorData: 'visitor-data',
      );

      expect(context['client'], {
        'clientName': 'TVHTML5',
        'clientVersion': '7.20260901.15.00',
        'clientScreen': 'WATCH',
        'userAgent': isNotEmpty,
        'acceptLanguage': 'en',
        'acceptRegion': 'US',
        'utcOffsetMinutes': '0',
        'visitorData': 'visitor-data',
        'tvAppInfo': {
          'appQuality': 'TV_APP_QUALITY_FULL_ANIMATION',
          'zylonLeftNav': true,
        },
        'webpSupport': false,
        'animatedWebpSupport': true,
      });
    },
  );

  test('reuses visitor data from a browse response in the request context', () {
    final context = service.createTVBrowseContext(
      language: 'en',
      region: 'US',
      utcOffsetMinutes: '0',
    );

    service.captureVisitorData({
      'responseContext': {'visitorData': 'response-visitor-data'},
    }, context);

    expect(context['client']['visitorData'], 'response-visitor-data');
  });

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
    expect(sections[0].videos.single.thumbnailBadgeText, '10:11');
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

  test('ignores a sign-in prompt grid button without creating a section', () {
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
                  'title': {'simpleText': '登录即可查看更多符合你的喜好的推荐内容'},
                  'navigationEndpoint': {
                    'clickTrackingParams': 'sign-in-prompt-tracking',
                    'clientActionEndpoint': {
                      'action': {'actionType': 'OPEN_SIGN_IN_PROMPT'},
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
  });

  test('rejects unknown client actions on grid buttons', () {
    final response = _homeResponse([
      _shelf(null, [
        {
          'gridButtonRenderer': {
            'title': {'simpleText': 'Unknown action'},
            'navigationEndpoint': {
              'clientActionEndpoint': {
                'action': {'actionType': 'UNKNOWN_ACTION'},
              },
            },
          },
        },
      ]),
    ]);

    expect(
      () => service.parseHomeFeedResponse(response),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('未知 clientActionEndpoint'),
        ),
      ),
    );
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
    expect(musicVideo.categoryId, 'music');
    expect(musicVideo.id, 'music-video-id');
    expect(musicVideo.playlistId, 'RDmusic-video-id');
    expect(musicVideo.title, 'Music video title');
    expect(musicVideo.channelName, 'Artist name');
    expect(musicVideo.views, '98M views • 2 months ago');
    expect(musicVideo.thumbnailBadgeText, '4:36');
    expect(
      musicVideo.videoUrl,
      'https://www.youtube.com/watch?v=music-video-id&list=RDmusic-video-id',
    );
  });

  test('parses the Gaming TV topic shelf and its native avatar-lockup title', () {
    final response = _homeResponse([
      {
        'shelfRenderer': {
          'headerRenderer': {
            'shelfHeaderRenderer': {
              'avatarLockup': {
                'avatarLockupRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'Gameplay picks'},
                    ],
                  },
                },
              },
            },
          },
          'content': {
            'horizontalListRenderer': {
              'items': [
                {
                  'tileRenderer': _tile(
                    videoId: 'gaming-video',
                    title: 'Gameplay video',
                    thumbnailUrl: 'https://example.test/gaming.jpg',
                  ),
                },
              ],
              'continuations': [
                {
                  'nextContinuationData': {'continuation': 'gaming-row-next'},
                },
              ],
            },
          },
        },
      },
    ]);
    final sectionList =
        response['contents']['tvBrowseRenderer']['content']['tvSurfaceContentRenderer']['content']['sectionListRenderer'];
    sectionList['continuations'] = [
      {
        'nextContinuationData': {'continuation': 'gaming-sections-next'},
      },
    ];

    final page = service.parseGamingBrowseResponse(response);

    expect(page.sections.single.title, 'Gameplay picks');
    final gameVideo = page.sections.single.videos.single;
    expect(gameVideo.id, 'gaming-video');
    expect(gameVideo.itemType, VideoItemType.video);
    expect(gameVideo.categoryId, 'gaming');
    expect(gameVideo.categoryName, 'Gameplay picks');
    expect(gameVideo.videoUrl, 'https://www.youtube.com/watch?v=gaming-video');
    expect(buildVideoItemDestination(gameVideo), isA<VideoDetailPage>());
    expect(page.sections.single.continuationToken, 'gaming-row-next');
    expect(page.continuationToken, 'gaming-sections-next');

    final globalContinuation = service.parseGamingBrowseContinuationResponse({
      'continuationContents': {
        'sectionListContinuation': {
          'contents': [
            _shelf('More gameplay', [
              {
                'tileRenderer': _tile(
                  videoId: 'gaming-next-video',
                  title: 'More gameplay',
                  thumbnailUrl: 'https://example.test/gaming-next.jpg',
                ),
              },
            ]),
          ],
          'continuations': [
            {
              'nextContinuationData': {
                'continuation': 'gaming-sections-next-2',
              },
            },
          ],
        },
      },
    });
    expect(
      globalContinuation.sections.single.videos.single.categoryId,
      'gaming',
    );
    expect(globalContinuation.continuationToken, 'gaming-sections-next-2');

    final horizontalContinuation = service.parseHomeSectionContinuationResponse(
      page.sections.single,
      {
        'continuationContents': {
          'horizontalListContinuation': {
            'items': [
              {
                'tileRenderer': _tile(
                  videoId: 'gaming-row-video',
                  title: 'More games in this row',
                  thumbnailUrl: 'https://example.test/gaming-row.jpg',
                ),
              },
            ],
            'continuations': [
              {
                'nextContinuationData': {'continuation': 'gaming-row-next-2'},
              },
            ],
          },
        },
      },
      categoryId: 'gaming',
    );
    expect(horizontalContinuation.videos.last.categoryId, 'gaming');
    expect(horizontalContinuation.continuationToken, 'gaming-row-next-2');
  });

  test('parses TV search lockups and their section continuation', () {
    Map<String, dynamic> lockupVideo(
      String videoId,
      String title, {
      String? badgeText,
      String? badgeStyle,
    }) => {
      'lockupViewModel': {
        'contentImage': {
          'thumbnailViewModel': {
            'image': {
              'thumbnails': [
                {
                  'url': 'https://example.test/$videoId.jpg',
                  'width': 640,
                  'height': 360,
                },
              ],
            },
            'overlays': badgeText == null
                ? <dynamic>[]
                : [
                    {
                      'thumbnailBottomOverlayViewModel': {
                        'badges': [
                          {
                            'thumbnailBadgeViewModel': {
                              'badgeStyle':
                                  badgeStyle ??
                                  (badgeText == 'LIVE'
                                      ? 'BADGE_STYLE_TYPE_LIVE_NOW'
                                      : 'BADGE_STYLE_TYPE_UPCOMING'),
                              'icon': {
                                'sources': [
                                  {
                                    'clientResource': {
                                      'imageName': 'LIVE_BADGE',
                                    },
                                  },
                                ],
                              },
                              'rendererContext': {
                                'accessibilityContext': {'label': badgeText},
                              },
                            },
                          },
                        ],
                      },
                    },
                  ],
          },
        },
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {
              'runs': [
                {'text': title},
              ],
            },
            'metadata': {
              'contentMetadataViewModel': {
                'metadataRows': [
                  {
                    'metadataParts': [
                      {
                        'text': {'simpleText': 'Search channel'},
                      },
                    ],
                  },
                  {
                    'metadataParts': [
                      {
                        'text': {'simpleText': '1M views'},
                      },
                      {
                        'text': {'simpleText': '2 days ago'},
                      },
                    ],
                  },
                ],
              },
            },
          },
        },
        'rendererContext': {
          'commandContext': {
            'onTap': {
              'innertubeCommand': {
                'clickTrackingParams': 'synthetic-tracking',
                'watchEndpoint': {
                  'videoId': videoId,
                  'playlistId': 'RDsearch-playlist',
                },
              },
            },
          },
        },
      },
    };

    final page = service.parseSearchResponse({
      'estimatedResults': '42',
      'contents': {
        'sectionListRenderer': {
          'contents': [
            _shelf('Search results', [
              lockupVideo(
                'search-video',
                'Search result video',
                badgeText: 'LIVE',
              ),
            ], continuationToken: 'search-next'),
          ],
        },
      },
    });

    expect(page.estimatedResults, '42');
    expect(page.sections.single.title, 'Search results');
    expect(page.sections.single.continuationToken, 'search-next');
    final video = page.sections.single.videos.single;
    expect(video.itemType, VideoItemType.video);
    expect(video.categoryId, 'search');
    expect(video.id, 'search-video');
    expect(video.playlistId, 'RDsearch-playlist');
    expect(video.title, 'Search result video');
    expect(video.channelName, 'Search channel');
    expect(video.views, '1M views • 2 days ago');
    expect(video.thumbnailUrl, 'https://example.test/search-video.jpg');
    expect(video.thumbnailBadgeText, 'LIVE');
    expect(video.isLive, isTrue);
    expect(
      video.videoUrl,
      'https://www.youtube.com/watch?v=search-video&list=RDsearch-playlist',
    );
    expect(buildVideoItemDestination(video), isA<LiveEventDetailPage>());

    final localizedLivePage = service.parseSearchResponse({
      'contents': {
        'sectionListRenderer': {
          'contents': [
            _shelf('Live results', [
              lockupVideo(
                'search-live-localized',
                'Localized live result',
                badgeText: '直播',
                badgeStyle: 'BADGE_STYLE_TYPE_SIMPLE',
              ),
            ]),
          ],
        },
      },
    });
    final localizedLive = localizedLivePage.sections.single.videos.single;
    expect(localizedLive.thumbnailBadgeText, '直播');
    expect(localizedLive.isLive, isTrue);
    expect(
      buildVideoItemDestination(localizedLive),
      isA<LiveEventDetailPage>(),
    );

    final upcomingPage = service.parseSearchResponse({
      'contents': {
        'sectionListRenderer': {
          'contents': [
            _shelf('Upcoming', [
              lockupVideo(
                'search-upcoming',
                'Upcoming result',
                badgeText: '即将直播',
                badgeStyle: 'BADGE_STYLE_TYPE_SIMPLE',
              ),
            ]),
          ],
        },
      },
    });
    final upcoming = upcomingPage.sections.single.videos.single;
    expect(upcoming.thumbnailBadgeText, '即将直播');
    expect(upcoming.isUpcoming, isTrue);

    final nextPage = service.parseSearchContinuationResponse(
      page.sections.single,
      {
        'continuationContents': {
          'sectionListContinuation': {
            'contents': [
              _shelf('Search results', [
                lockupVideo('search-video-next', 'Next result'),
              ], continuationToken: 'search-next-2'),
            ],
          },
        },
      },
    );

    expect(nextPage.videos.map((item) => item.id), [
      'search-video',
      'search-video-next',
    ]);
    expect(nextPage.continuationToken, 'search-next-2');
    expect(nextPage.videos.last.categoryId, 'search');
  });

  test('search result endpoint types keep search labels and shared routes', () {
    final browseDestinationTile = _tile(
      videoId: null,
      title: 'Search browse result',
      thumbnailUrl: 'https://example.test/search-browse.jpg',
    );
    browseDestinationTile['onSelectCommand'] = {
      'browseEndpoint': {'browseId': 'FEsearch-browse'},
    };

    final page = service.parseSearchResponse({
      'contents': {
        'sectionListRenderer': {
          'contents': [
            _shelf('Search results', [
              {
                'tileRenderer': _tile(
                  videoId: 'search-video',
                  title: 'Search video',
                  thumbnailUrl: 'https://example.test/search-video.jpg',
                ),
              },
              {
                'tileRenderer': _tile(
                  videoId: 'search-shorts',
                  title: 'Search Shorts',
                  thumbnailUrl: 'https://example.test/search-shorts.jpg',
                  contentType: 'TILE_CONTENT_TYPE_SHORTS',
                  useReelEndpoint: true,
                ),
              },
              {
                'tileRenderer': _tile(
                  videoId: null,
                  browseId: 'track-browse-id',
                  title: 'Search track',
                  thumbnailUrl: 'https://example.test/search-track.jpg',
                  contentType: 'TILE_CONTENT_TYPE_TRACK',
                ),
              },
              {
                'tileRenderer': _tile(
                  videoId: null,
                  browseId: 'VLsearch-playlist',
                  title: 'Search playlist',
                  thumbnailUrl: 'https://example.test/search-playlist.jpg',
                  contentType: 'TILE_CONTENT_TYPE_PLAYLIST',
                ),
              },
              {
                'tileRenderer': _tile(
                  videoId: null,
                  browseId: 'search-channel-id',
                  title: 'Search channel',
                  thumbnailUrl: 'https://example.test/search-channel.jpg',
                  contentType: 'TILE_CONTENT_TYPE_CHANNEL',
                ),
              },
              {'tileRenderer': browseDestinationTile},
            ]),
          ],
        },
      },
    });

    final videos = page.sections.single.videos;
    expect(videos.map((video) => video.itemType), [
      VideoItemType.video,
      VideoItemType.shorts,
      VideoItemType.track,
      VideoItemType.playlist,
      VideoItemType.channel,
      VideoItemType.browseDestination,
    ]);
    expect(videos.map((video) => video.categoryId), everyElement('search'));
    expect(
      videos.map((video) => video.categoryName),
      everyElement('Search results'),
    );
    expect(
      videos.map((video) => buildVideoItemDestination(video).runtimeType),
      [
        VideoDetailPage,
        ShortsDetailPage,
        TrackDetailPage,
        PlaylistDetailPage,
        ChannelDetailPage,
        BrowseEntryDetailPage,
      ],
    );
  });

  test('parses cluster shelf browse and search endpoint groups', () {
    final page = service.parseSearchResponse({
      'contents': {
        'sectionListRenderer': {
          'contents': [
            {
              'clusterShelfRenderer': {
                'clusters': [
                  {
                    'clusterRenderer': {
                      'headerRenderer': {
                        'buttonViewModel': {
                          'title': '王剑相关内容',
                          'onTap': {
                            'innertubeCommand': {
                              'browseEndpoint': {
                                'browseId': 'cluster-browse-id',
                                'params': 'cluster-params',
                              },
                            },
                          },
                        },
                      },
                      'items': [
                        {
                          'tileRenderer': _tile(
                            videoId: 'cluster-video',
                            title: 'Cluster result',
                            thumbnailUrl: 'https://example.test/cluster.jpg',
                          ),
                        },
                      ],
                      'loggingDirectives': <String, dynamic>{},
                    },
                  },
                  {
                    'clusterRenderer': {
                      'headerRenderer': {
                        'buttonViewModel': {
                          'title': '更多王剑结果',
                          'onTap': {
                            'innertubeCommand': {
                              'searchEndpoint': {'query': '王剑相关搜索'},
                            },
                          },
                        },
                      },
                      'items': [
                        {
                          'tileRenderer': _tile(
                            videoId: 'cluster-video-2',
                            title: 'Second cluster result',
                            thumbnailUrl:
                                'https://example.test/cluster-video-2.jpg',
                          ),
                        },
                      ],
                      'loggingDirectives': <String, dynamic>{},
                    },
                  },
                ],
                'loggingDirectives': <String, dynamic>{},
              },
            },
          ],
        },
      },
    });

    expect(page.sections, hasLength(2));
    expect(page.sections[0].title, '王剑相关内容');
    expect(page.sections[0].videos.single.title, 'Cluster result');
    expect(page.sections[0].browseId, 'cluster-browse-id');
    expect(page.sections[0].browseParams, 'cluster-params');
    expect(page.sections[0].browseTitle, '王剑相关内容');
    expect(page.sections[1].title, '更多王剑结果');
    expect(page.sections[1].videos.single.title, 'Second cluster result');
    expect(page.sections[1].searchQuery, '王剑相关搜索');
  });

  test('parses the Live TV topic feed and preserves live event routing', () {
    Map<String, dynamic> tileWithStatus(
      String videoId,
      String title,
      String status,
    ) {
      final tile = Map<String, dynamic>.from(
        _tile(
          videoId: videoId,
          title: title,
          thumbnailUrl: 'https://example.test/$videoId.jpg',
        ),
      );
      final header = Map<String, dynamic>.from(tile['header']);
      final tileHeader = Map<String, dynamic>.from(
        header['tileHeaderRenderer'],
      );
      final overlays = List<dynamic>.from(tileHeader['thumbnailOverlays']);
      overlays.add({
        'thumbnailOverlayTimeStatusRenderer': {'style': status},
      });
      tileHeader['thumbnailOverlays'] = overlays;
      header['tileHeaderRenderer'] = tileHeader;
      tile['header'] = header;
      return tile;
    }

    final response = _homeResponse([
      _shelf('Live now', [
        {'tileRenderer': tileWithStatus('live-video', 'Live event', 'LIVE')},
      ], continuationToken: 'live-row-next'),
      _shelf('Upcoming', [
        {
          'tileRenderer': tileWithStatus(
            'upcoming-video',
            'Upcoming event',
            'UPCOMING',
          ),
        },
      ]),
    ]);
    final sectionList =
        response['contents']['tvBrowseRenderer']['content']['tvSurfaceContentRenderer']['content']['sectionListRenderer'];
    sectionList['continuations'] = [
      {
        'nextContinuationData': {'continuation': 'live-sections-next'},
      },
    ];

    final page = service.parseLiveBrowseResponse(response);
    final liveVideo = page.sections.first.videos.single;
    final upcomingVideo = page.sections.last.videos.single;

    expect(page.sections.map((section) => section.title), [
      'Live now',
      'Upcoming',
    ]);
    expect(page.continuationToken, 'live-sections-next');
    expect(page.sections.first.continuationToken, 'live-row-next');
    expect(liveVideo.itemType, VideoItemType.video);
    expect(liveVideo.categoryId, 'live');
    expect(liveVideo.categoryName, 'Live now');
    expect(liveVideo.isLive, isTrue);
    expect(buildVideoItemDestination(liveVideo), isA<LiveEventDetailPage>());
    expect(upcomingVideo.categoryId, 'live');
    expect(upcomingVideo.isUpcoming, isTrue);
    expect(
      buildVideoItemDestination(upcomingVideo),
      isA<LiveEventDetailPage>(),
    );

    final globalContinuation = service.parseLiveBrowseContinuationResponse({
      'continuationContents': {
        'sectionListContinuation': {
          'contents': [
            _shelf('More live', [
              {
                'tileRenderer': tileWithStatus(
                  'more-live-video',
                  'More live',
                  'LIVE',
                ),
              },
            ]),
          ],
          'continuations': [
            {
              'nextContinuationData': {'continuation': 'live-sections-next-2'},
            },
          ],
        },
      },
    });
    expect(globalContinuation.sections.single.videos.single.categoryId, 'live');
    expect(globalContinuation.continuationToken, 'live-sections-next-2');

    final horizontalContinuation = service.parseHomeSectionContinuationResponse(
      page.sections.first,
      {
        'continuationContents': {
          'horizontalListContinuation': {
            'items': [
              {
                'tileRenderer': tileWithStatus(
                  'live-row-video',
                  'Another live event',
                  'LIVE',
                ),
              },
            ],
            'continuations': [
              {
                'nextContinuationData': {'continuation': 'live-row-next-2'},
              },
            ],
          },
        },
      },
      categoryId: 'live',
    );
    expect(horizontalContinuation.videos.last.categoryId, 'live');
    expect(horizontalContinuation.videos.last.isLive, isTrue);
    expect(horizontalContinuation.continuationToken, 'live-row-next-2');
  });

  test(
    'extracts the first Music shelf title from its hero carousel header',
    () {
      final response = _homeResponse([
        {
          'shelfRenderer': {
            'headerRenderer': {
              'heroCarouselHeaderRenderer': {
                'header': {
                  'shelfHeaderRenderer': {
                    'avatarLockup': {
                      'avatarLockupRenderer': {
                        'title': {
                          'runs': [
                            {'text': 'Music spotlight'},
                          ],
                        },
                      },
                    },
                  },
                },
                'spotlight': {'entityMetadataRenderer': <String, dynamic>{}},
              },
            },
            'content': {
              'horizontalListRenderer': {
                'items': [
                  {
                    'tvMusicVideoRenderer': {
                      'primaryText': {'simpleText': 'Spotlight song'},
                      'navigationEndpoint': {
                        'watchEndpoint': {'videoId': 'spotlight-video'},
                      },
                      'thumbnail': {
                        'thumbnails': [
                          {'url': 'https://example.test/spotlight.jpg'},
                        ],
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      ]);

      final page = service.parseMusicBrowseResponse(response);

      expect(page.sections.single.title, 'Music spotlight');
      expect(page.sections.single.videos.single.title, 'Spotlight song');
    },
  );

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

  test('surfaces a metadata-only horizontal continuation response', () {
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

    expect(
      () => service.parseHomeSectionContinuationResponse(original, {
        'responseContext': {
          'visitorData': 'visitor-data',
          'serviceTrackingParams': <dynamic>[],
        },
        'trackingParams': 'tracking-data',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('缺少 continuationContents'),
        ),
      ),
    );
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
