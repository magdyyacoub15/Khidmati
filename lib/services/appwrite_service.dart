import 'package:appwrite/appwrite.dart';

class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();

  final Client client = Client();
  late final Account account;
  late final Databases databases;
  late final Storage storage;
  late final Messaging messaging;
  late final Realtime realtime;

  // ⚠️ يرجى استبدال هذه القيم ببيانات مشروعك
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const String projectId = '6985ed63000aee473464';
  static const String databaseId = 'main_db'; // معرف قاعدة البيانات
  static const String notificationsCollectionId = 'notifications';
  static const String membershipsCollectionId = 'memberships';
  static const String usersCollectionId = 'users_info';
  static const String groupsCollectionId = 'groups';
  static const String appConfigCollectionId = 'app_config';
  static const String subscriptionPricesDocId = 'subscription_prices';
  static const String attendanceBucketId = 'attendance_photos';

  void init() {
    client
        .setEndpoint(endpoint)
        .setProject(projectId)
        .setSelfSigned(status: true); // للمشاريع المحلية أو التجريبية

    account = Account(client);
    databases = Databases(client);
    storage = Storage(client);
    messaging = Messaging(client);
    realtime = Realtime(client);
  }
}
