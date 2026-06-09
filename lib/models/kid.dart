import 'package:appwrite/models.dart' as models;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_translations.dart';

class Kid {
  final String id;
  final String name;
  final String address;
  final String? phoneRequired;
  final String? phoneOptional;
  final String? phoneRequiredOwner;
  final String? phoneOptionalOwner;
  final DateTime? dateOfBirth;
  final bool isVisited;
  final String visitedBy;
  final DateTime? createdAt;
  final String? locationUrl;
  final String? grade;
  final String? photoUrl;
  final String? localImagePath; // ⚡ Local Path for Optimistic UI
  final int points; // 🏆 Points System

  Kid({
    required this.id,
    required this.name,
    required this.address,
    this.phoneRequired,
    this.phoneOptional,
    this.phoneRequiredOwner,
    this.phoneOptionalOwner,
    this.dateOfBirth,
    this.isVisited = false,
    this.visitedBy = '',
    this.createdAt,
    this.locationUrl,
    this.grade,
    this.photoUrl,
    this.localImagePath,
    this.points = 0,
  });

  Kid copyWithStatus({
    bool? isVisited,
    String? visitedBy,
    String? photoUrl,
    String? name,
    String? address,
    String? phoneRequired,
    String? phoneOptional,
    String? phoneRequiredOwner,
    String? phoneOptionalOwner,
    DateTime? dateOfBirth,
    String? locationUrl,
    String? localImagePath,
    String? grade,
    int? points,
  }) {
    return Kid(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      phoneRequired: phoneRequired ?? this.phoneRequired,
      phoneOptional: phoneOptional ?? this.phoneOptional,
      phoneRequiredOwner: phoneRequiredOwner ?? this.phoneRequiredOwner,
      phoneOptionalOwner: phoneOptionalOwner ?? this.phoneOptionalOwner,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      isVisited: isVisited ?? this.isVisited,
      visitedBy: visitedBy ?? this.visitedBy,
      createdAt: createdAt,
      locationUrl: locationUrl ?? this.locationUrl,
      grade: grade ?? this.grade,
      photoUrl: photoUrl ?? this.photoUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      points: points ?? this.points,
    );
  }

  factory Kid.fromMap(Map<String, dynamic> data, String id) {
    DateTime? dob;
    final dobData = data['dateOfBirth'];
    if (dobData != null) {
      dob = DateTime.tryParse(dobData.toString());
    }

    DateTime? createdAt;
    final createdAtData = data['createdAt'];
    if (createdAtData != null) {
      createdAt = DateTime.tryParse(createdAtData.toString());
    }

    final phonesList = List<String>.from(data['phones'] ?? []);
    final requiredPhone =
        data['phoneRequired'] ??
        (phonesList.isNotEmpty ? phonesList.first : null);
    final optionalPhone =
        data['phoneOptional'] ?? (phonesList.length > 1 ? phonesList[1] : null);

    return Kid(
      id: id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      phoneRequired: requiredPhone,
      phoneOptional: optionalPhone,
      phoneRequiredOwner: data['phoneRequiredOwner'],
      phoneOptionalOwner: data['phoneOptionalOwner'],
      dateOfBirth: dob,
      isVisited: data['isVisited'] ?? false,
      visitedBy: data['visitedBy'] ?? '',
      createdAt: createdAt,
      locationUrl: data['locationUrl'],
      grade: data['grade'],
      photoUrl: data['photoUrl'],
      points: data['points'] ?? 0,
    );
  }

  factory Kid.fromAppwrite(models.Document doc) {
    return Kid.fromMap(doc.data, doc.$id);
  }

  List<String> get phones {
    final List<String> list = [];
    if (phoneRequired?.isNotEmpty == true) {
      list.add(phoneRequired!);
    }
    if (phoneOptional?.isNotEmpty == true) {
      list.add(phoneOptional!);
    }
    return list;
  }

  Map<String, String> get phoneOwners {
    final Map<String, String> map = {};
    if (phoneRequired != null && phoneRequiredOwner != null) {
      map[phoneRequired!] = phoneRequiredOwner!;
    }
    if (phoneOptional != null && phoneOptionalOwner != null) {
      map[phoneOptional!] = phoneOptionalOwner!;
    }
    return map;
  }

  String getPhoneWithOwner(BuildContext context, String phone) {
    String? owner;
    if (phone == phoneRequired) {
      owner = phoneRequiredOwner;
    } else if (phone == phoneOptional) {
      owner = phoneOptionalOwner;
    }

    if (owner == null || owner.isEmpty) return phone;

    // 🗺️ Map common roles (including legacy Arabic) to translation keys
    String key = owner;
    switch (owner) {
      case 'الاب':
      case 'Father':
        key = 'phone_owner_father';
        break;
      case 'الام':
      case 'Mother':
        key = 'phone_owner_mother';
        break;
      case 'الاخ':
      case 'Brother':
        key = 'phone_owner_brother';
        break;
      case 'الاخت':
      case 'Sister':
        key = 'phone_owner_sister';
        break;
      case 'المخدوم':
      case 'Kid':
      case 'Student':
        key = 'phone_owner_kid';
        break;
      case 'الخادم':
      case 'Servant':
        key = 'phone_owner_servant';
        break;
    }

    final translatedOwner = key.tr(context);
    return '$translatedOwner: $phone';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phoneRequired': phoneRequired,
      'phoneOptional': phoneOptional,
      'phoneRequiredOwner': phoneRequiredOwner,
      'phoneOptionalOwner': phoneOptionalOwner,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'isVisited': isVisited,
      'visitedBy': visitedBy,
      'createdAt': createdAt?.toIso8601String(),
      'locationUrl': locationUrl,
      'grade': grade,
      'photoUrl': photoUrl,
      'points': points,
    };
  }

  factory Kid.fromJson(Map<String, dynamic> map) {
    return Kid(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      phoneRequired: map['phoneRequired'],
      phoneOptional: map['phoneOptional'],
      phoneRequiredOwner: map['phoneRequiredOwner'],
      phoneOptionalOwner: map['phoneOptionalOwner'],
      dateOfBirth: map['dateOfBirth'] != null
          ? DateTime.tryParse(map['dateOfBirth'])
          : null,
      isVisited: map['isVisited'] ?? false,
      visitedBy: map['visitedBy'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'])
          : null,
      locationUrl: map['locationUrl'],
      grade: map['grade'],
      photoUrl: map['photoUrl'],
      points: map['points'] ?? 0,
    );
  }

  bool matchesQuery(String query) {
    final lowerCaseQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowerCaseQuery) ||
        address.toLowerCase().contains(lowerCaseQuery) ||
        phones.any((phone) => phone.contains(lowerCaseQuery));
  }

  bool isBirthdayToday() {
    if (dateOfBirth == null) return false;
    final now = DateTime.now();
    final localBirth = dateOfBirth!.toLocal();

    // 🎂 Robust comparison using MM-DD format to ignore time/timezone shifts
    final nowStr = "${now.month}-${now.day}";
    final birthStr = "${localBirth.month}-${localBirth.day}";

    return nowStr == birthStr;
  }

  static Future<void> openMap(
    BuildContext context,
    String? locationUrl,
    String address,
  ) async {
    String? finalUrl = locationUrl?.trim();

    if (finalUrl != null && finalUrl.isNotEmpty) {
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        finalUrl = 'https://$finalUrl';
      }
      try {
        final Uri uri = Uri.parse(finalUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (e) {
        debugPrint("Error parsing/launching URL: $e");
      }
    }

    final String query = Uri.encodeComponent(address);
    final String googleMapsUrl =
        "https://www.google.com/maps/search/?api=1&query=$query";
    try {
      final Uri uri = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('cannot_open_map'.tr(context))),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('address_link_error'.tr(context))),
        );
      }
    }
  }
}
