import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:lx_music_flutter/app/respository/wy/crypto_utils.dart';
import 'package:lx_music_flutter/utils/http/http_client.dart';
import 'package:lx_music_flutter/utils/log/logger.dart';

class KWSongList {
  static const int limit_song = 10000;

  static Future getSearch(String text, int page, int pageSize) async {
    String url =
        'http://search.kuwo.cn/r.s?all=${Uri.encodeComponent(text)}&pn=${page - 1}&rn=$pageSize&rformat=json&encoding=utf8&ver=mbox&vipver=MUSIC_8.7.7.0_BCS37&plat=pc&devid=28156413&ft=playlist&pay=0&needliveshow=0';

    var result = await HttpCore.getInstance().get(url);
    result = result.replaceAll(RegExp(r"('(?=(,\s*')))|('(?=:))|((?<=([:,]\s*))')|((?<={)')|('(?=}))"), '"');
    result = json.decode(result);
    List list = [];
    result['abslist'].forEach((e) {
      Logger.debug('$e');
      list.add(e);
    });
    return list;
  }

  static RegExp mInfo = RegExp(r'level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)');
  static RegExp listDetailLink = RegExp(r'^.+\/playlist(?:_detail)?\/(\d+)(?:\?.*|&.*$|#.*$|$)');

  static Future getListDetail(String id, int page) async {
    if (RegExp(r'\/bodian\/').hasMatch(id)) {
      return getListDetailMusicListByBD(id, page);
    }
    if (RegExp(r'[?&:/]').hasMatch(id)) {
      id = id.replaceAll(listDetailLink, '\$1');
    } else if (RegExp(r'^digest-').hasMatch(id)) {
      final parts = id.split('__');
      String digest = parts[0].replaceFirst('digest-', '');
      id = parts[1];
      switch (digest) {
        case '8':
          break;
        case '13':
          return getAlbumListDetail(id, page);
        case '5':
        default:
          return getListDetailDigest5(id, page);
      }
    }
    return getListDetailDigest8(id, page);
  }

  static Future getListDetailDigest5(String id, int page) async {
    final detailId = await getListDetailDigest5Info(id, page);
    return getListDetailDigest5Music(detailId, page);
  }

  static Future getListDetailDigest5Music(String id, int page) async {
    final result = await HttpCore.getInstance().get(
        'http://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=$id&pn=${page - 1}&rn=$limit_song&encode=utf-8&keyset=pl2012&identity=kuwo&pcmp4=1');
    if (result['result'] != 'ok') {
      return getListDetail(id, page);
    }
    return {
      'list': filterListDetail(result['musiclist']),
      'page': page,
      'limit': result['rn'],
      'total': result['total'],
      'source': 'kw',
      'info': {
        'name': result['title'],
        'img': result['pic'],
        'desc': result['info'],
        'author': result['uname'],
        'play_count': formatPlayCount(result['playnum']),
      },
    };
  }

  static Future getListDetailDigest5Info(String id, int page) async {
    final result =
        await HttpCore.getInstance().get('http://qukudata.kuwo.cn/q.k?op=query&cont=ninfo&node=$id&pn=0&rn=1&fmt=json&src=mbox&level=2');
    if (result['child'] == null) {
      return getListDetail(id, page);
    }
    // console.log(body)
    return result['child'].length > 0 ? result['child'][0]['sourceid'] : null;
  }

  static Future getAlbumListDetail(
    String id,
    int page,
  ) async {
    List<Map<String, dynamic>> filterListDetail(List<dynamic> rawList, String albumName, String albumId) {
      return rawList.map((item) {
        List<String> formats = item['formats'].split('|');
        List<Map<String, dynamic>> types = [];
        Map<String, dynamic> _types = {};
        if (formats.contains('MP3128')) {
          types.add({'type': '128k', 'size': null});
          _types['128k'] = {'size': null};
        }
        // if (formats.includes('MP3192')) {
        //   types.push({ type: '192k', size: null })
        //   _types['192k'] = {
        //     size: null,
        //   }
        // }
        if (formats.contains('MP3H')) {
          types.add({'type': '320k', 'size': null});
          _types['320k'] = {'size': null};
        }
        // if (formats.includes('AL')) {
        //   types.push({ type: 'ape', size: null })
        //   _types.ape = {
        //     size: null,
        //   }
        // }
        if (formats.contains('ALFLAC')) {
          types.add({'type': 'flac', 'size': null});
          _types['flac'] = {'size': null};
        }
        if (formats.contains('HIRFLAC')) {
          types.add({'type': 'flac24bit', 'size': null});
          _types['flac24bit'] = {'size': null};
        }
        // types.reverse()
        return {
          'singer': formatSinger(decodeName(item['artist'])),
          'name': decodeName(item['name']),
          'albumName': albumName,
          'albumId': albumId,
          'songmid': item['id'],
          'source': 'kw',
          'interval': null,
          'img': item['pic'],
          'lrc': null,
          'otherSource': null,
          'types': types,
          '_types': _types,
          'typeUrl': {},
        };
      }).toList();
    }

    var result = await HttpCore.getInstance().get(
        'http://search.kuwo.cn/r.s?pn=${page - 1}&rn=${limit_song}&stype=albuminfo&albumid=$id&show_copyright_off=0&encoding=utf&vipver=MUSIC_9.1.0');

    result = result.replaceAll(RegExp(r"('(?=(,\s*')))|('(?=:))|((?<=([:,]\s*))')|((?<={)')|('(?=}))"), '"');
    var body = json.decode(result);

    if (body['musiclist'] == null) {
      return getAlbumListDetail(id, page);
    }
    body['name'] = decodeName(body['name']);
    return {
      'list': filterListDetail(body['musiclist'], body['name'], body['albumid']),
      'page': page,
      'limit': limit_song,
      'total': int.parse(body['songnum']),
      'source': 'kw',
      'info': {
        'name': body['name'],
        'img': body['img'] ?? body['hts_img'],
        'desc': decodeName(body['info']),
        'author': decodeName(body['artist']),
        // 'play_count': formatPlayCount(body['playnum']),
      },
    };
  }

  static Future getListDetailDigest8(String id, int page) async {
    final result = await HttpCore.getInstance().get(getListDetailUrl(id, page));
    if (result['result'] != 'ok') {
      return getListDetail(id, page);
    }
    return {
      'list': filterListDetail(result['musiclist']),
      'page': page,
      'limit': result['rn'],
      'total': result['total'],
      'source': 'kw',
      'info': {
        'name': result['title'],
        'img': result['pic'],
        'desc': result['info'],
        'author': result['uname'],
        'play_count': formatPlayCount(result['playnum']),
      },
    };
  }

  static String formatPlayCount(int num) {
    if (num > 100000000) {
      return '${(num / 10000000).truncateToDouble() / 10}亿';
    }
    if (num > 10000) {
      return '${(num / 1000).truncateToDouble() / 10}万';
    }
    return num.toString();
  }

  static List<Map<String, dynamic>> filterListDetail(List<dynamic> rawData) {
    return rawData.map((item) {
      List<String> infoArr = item['N_MINFO'].split(';');
      List<Map<String, dynamic>> types = [];
      Map<String, dynamic> _types = {};
      for (var info in infoArr) {
        RegExpMatch? match = mInfo.firstMatch(info);
        if (match != null) {
          switch (match.group(2)) {
            case '4000':
              types.add({'type': 'flac24bit', 'size': match.group(4)});
              _types['flac24bit'] = {'size': match.group(4)?.toUpperCase()};
              break;
            case '2000':
              types.add({'type': 'flac', 'size': match.group(4)});
              _types['flac'] = {'size': match.group(4)?.toUpperCase()};
              break;
            case '320':
              types.add({'type': '320k', 'size': match.group(4)});
              _types['320k'] = {'size': match.group(4)?.toUpperCase()};
              break;
            case '192':
            case '128':
              types.add({'type': '128k', 'size': match.group(4)});
              _types['128k'] = {'size': match.group(4)?.toUpperCase()};
              break;
          }
        }
      }
      types = types.reversed.toList();

      return {
        'singer': formatSinger(decodeName(item['artist'])),
        'name': decodeName(item['name']),
        'albumName': decodeName(item['album']),
        'albumId': item['albumid'],
        'songmid': item['id'],
        'source': 'kw',
        'interval': formatPlayTime(int.parse(item['duration'])),
        'img': null,
        'lrc': null,
        'otherSource': null,
        'types': types,
        '_types': _types,
        'typeUrl': {},
      };
    }).toList();
  }

  static String formatSinger(String rawData) {
    return rawData.replaceAll('&', '、');
  }

  static String decodeName(String? str) {
    final encodeNames = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': '\'',
      '&#039;': '\'',
      '&nbsp;': ' ',
    };

    return str?.replaceAllMapped(RegExp('(?:&amp;|&lt;|&gt;|&quot;|&apos;|&#039;|&nbsp;)'), (match) {
          return encodeNames[match.group(0)]!;
        }) ??
        '';
  }

  static Future getListDetailMusicListByBD(String id, int page) async {
    final uid = RegExp(r'uid=(\d+)').firstMatch(id)?.group(1);
    final listId = RegExp(r'playlistId=(\d+)').firstMatch(id)?.group(1);
    final source = RegExp(r'source=(\d+)').firstMatch(id)?.group(1);
    if (listId == null) {
      throw Exception('failed');
    }
    final tasks = [getListDetailMusicListByBDList(listId, source!, page)];
    switch (source) {
      case '4':
        tasks.add(getListDetailMusicListByBDListInfo(listId, source));
        break;
      case '5':
        tasks.add(getListDetailMusicListByBDUserPub(uid ?? listId));
        break;
    }
    final results = await Future.wait(tasks);
    final listData = results[0];
    final info = results[1];
    listData.info = info ??
        {
          'name': '',
          'img': '',
          'desc': '',
          'author': '',
          'play_count': '',
        };
    // print(listData);
    return listData;
  }

  static Future<Map<String, dynamic>?> getListDetailMusicListByBDUserPub(String id) async {
    final url = 'https://bd-api.kuwo.cn/api/ucenter/users/pub/$id?reqId=${getReqId()}';
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36',
      'plat': 'h5',
    };

    try {
      final response = await HttpCore.getInstance().get(url, headers: headers);
      final infoData = json.decode(response.body);

      if (infoData['code'] != 200) {
        return null;
      }

      return {
        'name': infoData['data']['userInfo']['nickname'] + '喜欢的音乐',
        'img': infoData['data']['userInfo']['headImg'],
        'desc': '',
        'author': infoData['data']['userInfo']['nickname'],
        'play_count': '',
      };
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getListDetailMusicListByBDListInfo(String id, String source) async {
    final url = 'https://bd-api.kuwo.cn/api/service/playlist/info/$id?reqId=${getReqId()}&source=$source';
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36',
      'plat': 'h5',
    };

    try {
      final response = await HttpCore.getInstance().get(url, headers: headers);
      final infoData = json.decode(response.body);

      if (infoData['code'] != 200) {
        return null;
      }

      return {
        'name': infoData['data']['name'],
        'img': infoData['data']['pic'],
        'desc': infoData['data']['description'],
        'author': infoData['data']['creatorName'],
        'play_count': infoData['data']['playNum'],
      };
    } catch (e) {
      return null;
    }
  }

  static String getReqId() {
    String t() {
      return (65536 * (1 + Random().nextDouble()) ~/ 1).toRadixString(16).substring(1);
    }

    return t() + t() + t() + t() + t() + t() + t() + t();
  }

  static Future getListDetailMusicListByBDList(String id, String source, int page, {int tryNum = 0}) async {
    final url = 'https://bd-api.kuwo.cn/api/service/playlist/$id/musicList?reqId=${getReqId()}&source=$source&pn=$page&rn=${limit_song}';
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36',
      'plat': 'h5',
    };

    try {
      final response = await HttpCore.getInstance().get(url, headers: headers);
      final listData = json.decode(response.body);

      if (listData['code'] != 200) {
        throw Exception('failed');
      }

      return {
        'list': filterBDListDetail(listData['data']['list']),
        'page': page,
        'limit': listData['data']['pageSize'],
        'total': listData['data']['total'],
        'source': 'kw',
      };
    } catch (e) {
      if (tryNum > 2) {
        throw Exception('try max num');
      }
      return getListDetailMusicListByBDList(id, source, page, tryNum: tryNum + 1);
    }
  }

  static List<Map<String, dynamic>> filterBDListDetail(List<dynamic> rawList) {
    return rawList.map((item) {
      List<Map<String, dynamic>> types = [];
      Map<String, dynamic> _types = {};
      for (var info in item['audios']) {
        info['size'] = info['size']?.toString()?.toUpperCase();
        switch (info['bitrate']) {
          case '4000':
            types.add({'type': 'flac24bit', 'size': info['size']});
            _types['flac24bit'] = {'size': info['size']};
            break;
          case '2000':
            types.add({'type': 'flac', 'size': info['size']});
            _types['flac'] = {'size': info['size']};
            break;
          case '320':
            types.add({'type': '320k', 'size': info['size']});
            _types['320k'] = {'size': info['size']};
            break;
          case '192':
          case '128':
            types.add({'type': '128k', 'size': info['size']});
            _types['128k'] = {'size': info['size']};
            break;
        }
      }
      types = types.reversed.toList();

      return {
        'singer': item['artists'].map((s) => s['name']).join('、'),
        'name': item['name'],
        'albumName': item['album'],
        'albumId': item['albumId'],
        'songmid': item['id'],
        'source': 'kw',
        'interval': formatPlayTime(item['duration']),
        'img': item['albumPic'],
        'releaseDate': item['releaseDate'],
        'lrc': null,
        'otherSource': null,
        'types': types,
        '_types': _types,
        'typeUrl': {},
      };
    }).toList();
  }

  static String formatPlayTime(int time) {
    int m = (time / 60).truncate();
    int s = (time % 60).truncate();
    return m == 0 && s == 0 ? '--/--' : '${numFix(m)}:${numFix(s)}';
  }

  static String numFix(int num) {
    return num.toString().padLeft(2, '0');
  }

  static String getListDetailUrl(String id, int page) {
    String url =
        'http://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=${id}&pn=${page - 1}&rn=${limit_song}&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1';
    return url;
  }

  static String? token;

  static Future getToken() async {
    if(token != null) {
      return token;
    }
    String url = 'http://www.kuwo.cn/';

    var result = await HttpCore.getInstance().get(url);
    print('=====  $result');
  }

  /// 返回热门歌单标签
  ///
  /// {
  ///   'key': '',
  ///   'describe': '',
  ///   'type': '',
  ///   'popularity': '',
  /// }
  static Future<List> getHotTagList() async {
    String url =
        'http://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=kwplayer_ar&rformat=json&encoding=utf8&tabid=1';
    var result = await HttpCore.getInstance().get(url);
    Logger.debug('$result');
    return result['tagvalue'];
  }


  static Future getMusicUrlDirect(String songmid, String type) async {
    final targetUrl = 'http://www.kuwo.cn/api/v1/www/music/playUrl?mid=${songmid}&type=convert_url3&br=128kmp3';
    final result = await HttpCore.getInstance().get(targetUrl, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:82.0) Gecko/20100101 Firefox/82.0',
      'Referer': 'http://kuwo.cn/',
    });
    if (result['success'] == false) {
      return {'type': type, 'url': ''};
    }
    return {'type': type, 'url': result['data']['url']};
  }

  static Future getMusicUrlTemp(String songmid, String type) async {
    final result = await HttpCore.getInstance().get('http://tm.tempmusics.tk/url/kw/${songmid}/$type', options: Options(
      headers: {
        'family': 4,
      },
    ));
    return result != null && result['code'] == 0 ? {'type': type, 'url': result['data']} : Future.error(Exception(result['msg']));
  }

  static Future getMusicUrlTest(String songmid, String type) async {
    final result = await HttpCore.getInstance().get('http://ts.tempmusics.tk/url/kw/${songmid}/$type');
    return result['code'] == 0 ? {'type': type, 'url': result['data']} : Future.error(Exception(result.fail));
  }


  static Future getPic(String songmid) async {
    String url = 'http://artistpicserver.kuwo.cn/pic.web?corp=kuwo&type=rid_pic&pictype=500&size=500&rid=${songmid}';
    var result = await HttpCore.getInstance().get(url);
    return result;
  }


}
