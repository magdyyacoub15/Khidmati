// ignore_for_file: avoid_print
import 'package:appwrite/appwrite.dart';

Future<void> main() async {
  final client = Client()
      .setEndpoint('https://fra.cloud.appwrite.io/v1')
      .setProject('6985ed63000aee473464');

  final databases = Databases(client);

  try {
    final result = await databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'attendance_status',
      queries: [Query.limit(10), Query.orderDesc('\$createdAt')],
    );

    for (var doc in result.documents) {
      print('ID: ${doc.$id}');
      print('Name: "${doc.data['name']}"');
      print('Type: "${doc.data['type']}"');
      print('Grade: "${doc.data['grade']}"');
      print('IsPresent: ${doc.data['isPresent']}');
      print('Permissions: ${doc.$permissions}');
      print('---');
    }
  } catch (e) {
    print('Error: $e');
  }
}
