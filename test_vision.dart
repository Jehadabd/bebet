import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final apiKey = 'AIzaSyCrEXu3yNoFiupS1oSzjmCwggk6Uk0--vY';
  final url = 'https://vision.googleapis.com/v1/images:annotate?key=\$apiKey';
  
  final requestBody = {
    'requests': [
      {
        'image': {
          'content': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
        },
        'features': [
          {
            'type': 'TEXT_DETECTION',
            'maxResults': 1,
          },
        ],
      },
    ],
  };

  print('Testing API Key...');
  final response = await http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(requestBody),
  );

  print('Status Code: ' + response.statusCode.toString());
  print('Response Body: ' + response.body);
}
