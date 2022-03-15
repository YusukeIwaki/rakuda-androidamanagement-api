import 'package:googleapis_auth/auth_io.dart';
import 'package:rakuda/rakuda.dart';
import "package:http/http.dart" as http;

import 'dart:io' show File, Platform;
import 'dart:convert' show jsonDecode;

Future<void> saveCredentials(String keyFilename) async {
  final serviceAccountJson = await File(keyFilename).readAsString();
  final token = await fetchAccessToken(serviceAccountJson);
  await Future.wait([
    _ServiceAccountCredentialsCache().put(serviceAccountJson).then((_) {
      print('credentials are stored in ~/.androidmanagement');
    }),
    _AccessTokenCache().put(token).then((_) {
      print('access token is stored in ~/.androidmanagement');
    }),
  ]);
}

class _ServiceAccountCredentialsCache {
  final FileCache _cache;
  _ServiceAccountCredentialsCache()
      : _cache = FileCache('androidmanagement', 'credentials');

  Future<String?> get() => _cache.get();
  Future<void> put(String json) => _cache.put(json);
}

class _AccessTokenCache {
  final FileCache _cache;
  _AccessTokenCache() : _cache = FileCache('androidmanagement', 'access_token');

  Future<String?> get() => _cache.get();
  Future<void> put(String token) => _cache.put(token);
  Future<void> delete() => _cache.delete();
}

Future<String> fetchAccessToken(String serviceAccountJson) async {
  final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
  final httpClient = http.Client();
  final accessCredentials = await obtainAccessCredentialsViaServiceAccount(
    credentials,
    ["https://www.googleapis.com/auth/androidmanagement"],
    httpClient,
  );
  httpClient.close();

  return accessCredentials.accessToken.data;
}

Future<Response> auth(PerformRequest performRequest, Request request) async {
  final keyJson = await _ServiceAccountCredentialsCache().get();
  if (keyJson == null) {
    throw Exception('configure is required');
  }
  final cachedAccessToken = await _AccessTokenCache().get();
  final accessToken = cachedAccessToken ?? await fetchAccessToken(keyJson);
  request.replaceQueryParameter(
    (entry) => entry.value.contains('{projectId}'),
    (entry) => MapEntry(
        entry.key,
        entry.value.replaceAll(
          '{projectId}',
          jsonDecode(keyJson)['project_id'],
        )),
  );
  request.setHeader('Authorization', 'Bearer $accessToken');
  var response = await performRequest(request);

  if (response.status < 300) {
    if (cachedAccessToken == null) {
      await _AccessTokenCache().put(accessToken);
    }
  } else if (response.status == 401) {
    if (cachedAccessToken != null) {
      _AccessTokenCache().delete();

      final accessToken2 = await fetchAccessToken(keyJson);
      request.setHeader('Authorization', 'Bearer $accessToken2');
      response = await performRequest(request);

      if (response.status < 300) {
        await _AccessTokenCache().put(accessToken2);
      }
    }
  }

  return response;
}

Future<Response> logging(PerformRequest performRequest, Request request) async {
  print(
      ">> ${request.method} ${request.path} ${request.queryParameters.map((e) => "${e.key}=${e.value}").join('&')}");
  final response = await performRequest(request);
  print(">> HTTP ${response.status}");
  final body = response.body;
  if (body != null) {
    print(body);
  }
  return response;
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.first == 'configure') {
    if (arguments.length != 2) {
      throw Exception('configure path/to/service_account.json');
    }

    await saveCredentials(arguments[1]);
  } else {
    if (Platform.environment['DEBUGP'] == '1') {
      await createJSONClient(
        arguments,
        baseURL: 'https://androidmanagement.googleapis.com/v1',
        interceptors: [logging, auth],
        printResponse: false,
      );
    } else {
      await createJSONClient(
        arguments,
        baseURL: 'https://androidmanagement.googleapis.com/v1',
        interceptors: [auth],
        printResponse: true,
      );
    }
  }
}
