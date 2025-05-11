import 'dart:convert';
import 'package:http/http.dart' as http;

class DatabaseService {
  static const String databaseUrl =
      "https://homesecurity-dfb93-default-rtdb.firebaseio.com/";

  Future<Map<String, dynamic>> getValues() async {
    try {
      final response = await http.get(Uri.parse('$databaseUrl.json'));
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>? ?? {};
        return {
          'Activation': data['Activation']?.toString() ?? 'OFF',
          'HomeStatus': data['HomeStatus']?.toString() ?? 'Home is Safe',
          'Password': data['Password']?.toString() ?? '1234',
          'Door': data['Door']?.toString() ?? 'OPEN',
        };
      }
      return {};
    } catch (e) {
      print('Error fetching data: $e');
      return {};
    }
  }

  Future<bool> updateValue(String path, String value) async {
    try {
      final response = await http.put(
        Uri.parse('$databaseUrl$path.json'),
        body: json.encode(value),
        headers: {'Content-Type': 'application/json'},
      );

      print('Update $path to $value - Status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('Update error: $e');
      return false;
    }
  }

  // New method to toggle door state
  Future<bool> toggleDoor() async {
    try {
      final currentValues = await getValues();
      String newDoorState = currentValues['Door'] == 'OPEN' ? 'CLOSED' : 'OPEN';
      final response = await http.put(
        Uri.parse('$databaseUrl/Door.json'),
        body: json.encode(newDoorState),
        headers: {'Content-Type': 'application/json'},
      );

      print('Toggle Door to $newDoorState - Status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('Toggle Door error: $e');
      return false;
    }
  }
}
