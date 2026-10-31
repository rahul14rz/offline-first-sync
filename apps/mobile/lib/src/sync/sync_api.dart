import 'dart:convert';

import 'package:http/http.dart' as http;

import 'protocol.dart';

/// The request did not get an answer: no connection, a timeout, or a lost response. The
/// server may or may not have applied it, so the caller must send the same request again.
class SyncUnreachable implements Exception {
  const SyncUnreachable(this.cause);
  final Object cause;

  @override
  String toString() => 'Server unreachable: $cause';
}

/// The server answered with an error status.
class SyncHttpError implements Exception {
  const SyncHttpError(this.statusCode, this.body);
  final int statusCode;
  final String body;

  /// 5xx and 429 can succeed on a later attempt. Other 4xx mean the request itself is wrong.
  bool get retryable => statusCode >= 500 || statusCode == 429;

  @override
  String toString() => 'Server returned $statusCode: $body';
}

class SyncApi {
  SyncApi({required this.baseUrl, http.Client? client, this.timeout = const Duration(seconds: 15)})
    : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<List<MutationResult>> push(List<Mutation> mutations) async {
    final json = await _send(
      http.Request('POST', baseUrl.resolve('sync/push'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'mutations': [for (final m in mutations) m.toJson()],
        }),
    );
    return [
      for (final result in json['results']! as List<Object?>)
        MutationResult.fromJson(result! as Map<String, Object?>),
    ];
  }

  Future<PullPage> pull({required String cursor, required int limit}) async {
    final url = baseUrl
        .resolve('sync/pull')
        .replace(queryParameters: {'cursor': cursor, 'limit': '$limit'});
    return PullPage.fromJson(await _send(http.Request('GET', url)));
  }

  Future<Map<String, Object?>> _send(http.Request request) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on Exception catch (error) {
      throw SyncUnreachable(error);
    }
    if (response.statusCode != 200) throw SyncHttpError(response.statusCode, response.body);
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  void close() => _client.close();
}
