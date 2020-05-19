import 'dart:convert';
import 'dart:io';
import 'package:cmp/services/FileUploadRequest.dart';
import 'package:http/http.dart' as http;
import 'package:cmp/models/ApiResult.dart';

const API_URL = 'http://192.168.43.48/cmp-api/';

enum RequestMethod { Get, Post }

class ApiHelper {
  static getUrl(String url) {
    return API_URL + url;
  }

  static Future<ApiResult> get(String url) {
    return request(RequestMethod.Get, API_URL + url);
  }

  static Future<ApiResult> post(String url, dynamic data) {
    return request(RequestMethod.Post, API_URL + url, body: data);
  }

  static Future<ApiResult> request(
    RequestMethod method,
    String url, {
    dynamic body,
  }) async {
    var headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      // Response handler
      http.Response response;

      if (method == RequestMethod.Post) {
        response = await http.post(
          url,
          body: jsonEncode(body),
          headers: headers,
        );
      } else {
        response = await http.get(url, headers: headers);
      }

      // Parse result
      var result = ApiResult.parse(jsonDecode(response.body));
      return result;
    } catch (ex) {
      return ApiResult(
        isError: true,
        message: 'Error unexpected',
      );
    }
  }

  static Future<http.Response> uploadFile(
    String url,
    File file, {
    Function(int, int) onProgress,
  }) async {
    if (file == null) return null;

    final uri = Uri.parse(API_URL + url);
    final request = new FileUploadRequest(uri, onProgress: onProgress);
    await request.addFile('media', file);

    // Send response
    final response = await request.send();
    final data = await http.Response.fromStream(response);
    return data;
  }
}
