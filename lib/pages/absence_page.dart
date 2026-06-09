import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import '../services/grade_service.dart';
import '../services/user_service.dart';
import '../services/permission_service.dart';
import '../services/appwrite_service.dart';
import '../services/data_cache_service.dart';
import '../services/sync_service.dart';
import '../widgets/full_screen_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_translations.dart';

class KidInfo {
  final String name;
  final String address;
  final List<String> phones;
  final Map<String, String> phoneOwners;
  final String? locationUrl;
  final String? photoUrl;

  KidInfo({
    required this.name,
    required this.address,
    required this.phones,
    required this.phoneOwners,
    this.locationUrl,
    this.photoUrl,
  });

  factory KidInfo.fromAppwrite(models.Document doc, String type) {
    final data = doc.data;
    final List<String> phoneList = [];
    final Map<String, String> ownersMap = {};

    if (type == 'students') {
      if (data['phoneRequired']?.toString().isNotEmpty ?? false) {
        final phone = data['phoneRequired'].toString();
        phoneList.add(phone);
        ownersMap[phone] = data['phoneRequiredOwner'] ?? 'guardian';
      }
      if (data['phoneOptional']?.toString().isNotEmpty ?? false) {
        final phone = data['phoneOptional'].toString();
        phoneList.add(phone);
        ownersMap[phone] = data['phoneOptionalOwner'] ?? 'guardian';
      }
    } else {
      // Servants
      if (data['phoneRequired']?.toString().isNotEmpty ?? false) {
        final phone = data['phoneRequired'].toString();
        phoneList.add(phone);
        ownersMap[phone] = 'servant';
      }
    }

    return KidInfo(
      name: data['name'] ?? 'unknown_name',
      address: data['address'] ?? 'no_address',
      phones: phoneList,
      phoneOwners: ownersMap,
      locationUrl: data['locationUrl'],
      photoUrl: data['photoUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'phones': phones,
      'phoneOwners': phoneOwners,
      'locationUrl': locationUrl,
      'photoUrl': photoUrl,
    };
  }

  factory KidInfo.fromJson(Map<String, dynamic> json) {
    return KidInfo(
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      phones: List<String>.from(json['phones'] ?? []),
      phoneOwners: Map<String, String>.from(json['phoneOwners'] ?? {}),
      locationUrl: json['locationUrl'],
      photoUrl: json['photoUrl'],
    );
  }

  String getPhoneWithOwner(BuildContext context, String phone) {
    final owner = phoneOwners[phone];
    final ownerTranslated = owner?.tr(context);
    return ownerTranslated != null ? '$ownerTranslated: $phone' : phone;
  }
}

class AbsentKid {
  final String name;
  final String address;
  final String grade;
  final String note;
  final String recordedBy;
  final String reportName;
  final List<String> phones;
  final Map<String, String> phoneOwners;
  final bool isMissed;
  final String missedBy;
  final String absentReason;
  final String? locationUrl;
  final String reportId; // Needed for updates
  final String? photoUrl;

  AbsentKid({
    required this.name,
    required this.address,
    required this.grade,
    this.note = '',
    this.recordedBy = 'unknown',
    required this.reportName,
    this.phones = const [],
    required this.phoneOwners,
    this.isMissed = false,
    this.missedBy = '',
    this.absentReason = '',
    this.locationUrl,
    required this.reportId,
    this.photoUrl,
  });

  AbsentKid copyWith({bool? isMissed, String? missedBy, String? absentReason}) {
    return AbsentKid(
      name: name,
      address: address,
      grade: grade,
      note: note,
      recordedBy: recordedBy,
      reportName: reportName,
      phones: phones,
      phoneOwners: phoneOwners,
      locationUrl: locationUrl,
      reportId: reportId,
      isMissed: isMissed ?? this.isMissed,
      missedBy: missedBy ?? this.missedBy,
      absentReason: absentReason ?? this.absentReason,
      photoUrl: photoUrl,
    );
  }

  String getPhoneWithOwner(BuildContext context, String phone) {
    final owner = phoneOwners[phone];
    final ownerTranslated = owner?.tr(context);
    return ownerTranslated != null ? '$ownerTranslated: $phone' : phone;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'grade': grade,
      'note': note,
      'recordedBy': recordedBy,
      'reportName': reportName,
      'phones': phones,
      'phoneOwners': phoneOwners,
      'isMissed': isMissed,
      'missedBy': missedBy,
      'absentReason': absentReason,
      'locationUrl': locationUrl,
      'reportId': reportId,
      'photoUrl': photoUrl,
    };
  }

  factory AbsentKid.fromJson(Map<String, dynamic> json) {
    return AbsentKid(
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      grade: json['grade'] ?? '',
      note: json['note'] ?? '',
      recordedBy: json['recordedBy'] ?? '',
      reportName: json['reportName'] ?? '',
      phones: List<String>.from(json['phones'] ?? []),
      phoneOwners: Map<String, String>.from(json['phoneOwners'] ?? {}),
      isMissed: json['isMissed'] ?? false,
      missedBy: json['missedBy'] ?? '',
      absentReason: json['absentReason'] ?? '',
      locationUrl: json['locationUrl'],
      reportId: json['reportId'] ?? '',
      photoUrl: json['photoUrl'],
    );
  }
}

class AbsentKidCard extends StatelessWidget {
  final AbsentKid kid;
  final String currentServerName;
  final VoidCallback onMissed;
  final String personType;
  final VoidCallback onReasonEdit;

  const AbsentKidCard({
    required this.kid,
    required this.currentServerName,
    required this.onMissed,
    required this.personType,
    required this.onReasonEdit,
    super.key,
  });

  Future<void> _openMap(
    BuildContext context,
    String? locationUrl,
    String address,
  ) async {
    if (locationUrl == null || locationUrl.trim().isEmpty) {
      return;
    }

    String url = locationUrl.trim();
    if (!url.startsWith('http') && !url.startsWith('geo:')) {
      url = 'https://$url';
    }

    try {
      final uri = Uri.parse(url);
      bool launched = false;

      try {
        if (!context.mounted) {
          return;
        }
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint("Error launching in externalApplication: $e");
      }

      if (!launched) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
        } catch (e) {
          debugPrint("Error launching in platformDefault: $e");
        }
      }

      if (!launched) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('link_open_error'.tr(context))),
          );
        }
      }
    } catch (e) {
      debugPrint("Error parsing or launching locationUrl: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${'link_error'.tr(context)} $e")),
        );
      }
    }
  }

  void _showPhoneOptions(BuildContext context, AbsentKid kid, String phone) {
    final phoneWithOwner = kid.getPhoneWithOwner(context, phone);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 15,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width * 0.04,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(
                        MediaQuery.of(context).size.width * 0.015,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.phone,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width * 0.05,
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.025),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'call_options'.tr(context),
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.04,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFB71C1C),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.005,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              kid.name,
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.035,
                                color: Colors.red.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.005,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              phoneWithOwner,
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.03,
                                color: Colors.red.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width * 0.04,
                ),
                child: Column(
                  children: [
                    _buildOptionButton(
                      context,
                      'call_number'.tr(context),
                      Icons.phone,
                      Colors.green,
                      () {
                        Navigator.pop(context);
                        launchUrl(Uri.parse("tel:$phone"));
                      },
                    ),
                    _buildOptionButton(
                      context,
                      'whatsapp_message'.tr(context),
                      Icons.message,
                      const Color(0xFF25D366),
                      () {
                        Navigator.pop(context);
                        launchUrl(Uri.parse("https://wa.me/$phone"));
                      },
                    ),
                    _buildOptionButton(
                      context,
                      'copy_number'.tr(context),
                      Icons.content_copy,
                      Colors.orange,
                      () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: phone));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "${'number_copied'.tr(context)}: $phone",
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.04,
                  vertical: MediaQuery.of(context).size.height * 0.01,
                ),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: EdgeInsets.symmetric(
                      vertical: MediaQuery.of(context).size.height * 0.012,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'cancel'.tr(context),
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.035,
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height * 0.01,
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Colors.white,
          size: MediaQuery.of(context).size.width * 0.04,
        ),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width * 0.035,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.016,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPhones = kid.phones.isNotEmpty;
    final Color buttonColor = kid.isMissed
        ? Colors.grey.shade500
        : Colors.red.shade700;
    final String buttonText = kid.isMissed
        ? 'missed_status'.tr(context)
        : 'miss_him'.tr(context);

    return Container(
      margin: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.005,
        horizontal: MediaQuery.of(context).size.width * 0.02,
      ),
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.1,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade50, Colors.pink.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(
              vertical: MediaQuery.of(context).size.height * 0.008,
              horizontal: MediaQuery.of(context).size.width * 0.025,
            ),

            leading: GestureDetector(
              onTap: () {
                if (kid.photoUrl?.isNotEmpty ?? false) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenImage(
                        imageUrl: kid.photoUrl,
                        tag:
                            'absent_kid_${kid.name}', // Use name as tag since ID might not be unique across lists
                      ),
                    ),
                  );
                }
              },
              child: Hero(
                tag: 'absent_kid_${kid.name}',
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.1,
                  height: MediaQuery.of(context).size.width * 0.1,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade700, width: 2),
                  ),
                  child: ClipOval(
                    child: (kid.photoUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: kid.photoUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: Colors.red.shade100,
                              child: Icon(
                                Icons.person,
                                color: Colors.red.shade300,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.red.shade100,
                              child: Icon(
                                Icons.error_outline,
                                color: Colors.red.shade900,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.red.shade100,
                            child: Icon(
                              personType == 'servants'
                                  ? Icons.people_alt
                                  : Icons.person_off,
                              color: Colors.red.shade900,
                              size: MediaQuery.of(context).size.width * 0.05,
                            ),
                          ),
                  ),
                ),
              ),
            ),

            title: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                kid.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                  color: Colors.red.shade900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    personType == 'servants'
                        ? "🌟 ${'service_grade'.tr(context)}: ${kid.grade}"
                        : "📚 ${'grade'.tr(context)}: ${kid.grade}",
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.03,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.005),

                // ✅ عرض سبب الغياب إذا كان موجوداً
                if (kid.absentReason.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(
                      bottom: MediaQuery.of(context).size.height * 0.005,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: MediaQuery.of(context).size.width * 0.03,
                          color: Colors.orange.shade700,
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.01,
                        ),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "${'absence_reason'.tr(context)}: ${kid.absentReason}",
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.028,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (hasPhones)
                  Wrap(
                    spacing: MediaQuery.of(context).size.width * 0.015,
                    runSpacing: MediaQuery.of(context).size.height * 0.005,
                    children: kid.phones.map((phone) {
                      final phoneWithOwner = kid.getPhoneWithOwner(
                        context,
                        phone,
                      );
                      return InkWell(
                        onTap: () => _showPhoneOptions(context, kid, phone),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                MediaQuery.of(context).size.width * 0.015,
                            vertical:
                                MediaQuery.of(context).size.height * 0.003,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone,
                                size: MediaQuery.of(context).size.width * 0.03,
                                color: Colors.blue.shade700,
                              ),
                              SizedBox(
                                width:
                                    MediaQuery.of(context).size.width * 0.008,
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  phoneWithOwner,
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.w500,
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                        0.028,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'no_phone_available'.tr(context),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: MediaQuery.of(context).size.width * 0.03,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.006),

                // ✅ سطر العنوان قابلاً للضغط
                GestureDetector(
                  onTap: () => _openMap(context, kid.locationUrl, kid.address),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: MediaQuery.of(context).size.width * 0.03,
                        color:
                            (kid.locationUrl != null &&
                                kid.locationUrl!.isNotEmpty)
                            ? Colors.blue.shade700
                            : Colors.grey.shade600,
                      ),
                      SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                      Flexible(
                        child: Text(
                          kid.address,
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.028,
                            color: (kid.locationUrl?.isNotEmpty ?? false)
                                ? Colors.blue.shade700
                                : Colors.grey.shade700,
                            decoration: (kid.locationUrl?.isNotEmpty ?? false)
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),

                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ✅ زر تعديل سبب الغياب
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: MediaQuery.of(context).size.height * 0.01,
            start: MediaQuery.of(context).size.width * 0.015,
            child: Tooltip(
              message: 'edit_absence_reason'.tr(context),
              child: InkWell(
                onTap: onReasonEdit,
                child: Container(
                  padding: EdgeInsets.all(
                    MediaQuery.of(context).size.width * 0.015,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade300, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        kid.absentReason.isEmpty ? Icons.add : Icons.edit,
                        size: MediaQuery.of(context).size.width * 0.03,
                        color: Colors.orange.shade800,
                      ),
                      if (kid.absentReason.isEmpty)
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.005,
                        ),
                      if (kid.absentReason.isEmpty)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'reason'.tr(context),
                            style: TextStyle(
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.025,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (kid.isMissed)
            Positioned.directional(
              textDirection: Directionality.of(context),
              bottom: 0,
              end: 0,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.025,
                  vertical: MediaQuery.of(context).size.height * 0.005,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: const BorderRadiusDirectional.only(
                    topEnd: Radius.circular(12),
                    bottomStart: Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.shade900.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: MediaQuery.of(context).size.width * 0.035,
                      color: Colors.white,
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "${'missed_by'.tr(context)}: ${kid.missedBy.contains('@') ? kid.missedBy.split('@')[0] : kid.missedBy}",
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width * 0.028,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ✅ زر "افتقده" في الأسفل من الجهة اليمين
          if (!kid.isMissed)
            Positioned.directional(
              textDirection: Directionality.of(context),
              bottom: MediaQuery.of(context).size.height * 0.01,
              end: MediaQuery.of(context).size.width * 0.025,
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.23,
                child: ElevatedButton(
                  onPressed: onMissed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.02,
                      vertical: MediaQuery.of(context).size.height * 0.006,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 4,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.03,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AbsencePage extends StatefulWidget {
  const AbsencePage({super.key});

  @override
  State<AbsencePage> createState() => _AbsencePageState();
}

class _AbsencePageState extends State<AbsencePage> {
  String _selectedType = "attendees";

  // Appwrite
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Realtime _realtime = AppwriteService().realtime;
  RealtimeSubscription? _actionsSubscription;
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String attendanceRecordsCollectionId = 'attendance_records';
  static const String absenceActionsCollectionId = 'absence_actions';
  static const String studentsCollectionId = 'students';
  static const String servantsCollectionId = 'servants';
  static const String usersCollectionId = 'users_info';

  models.Document? _latestReport;
  List<AbsentKid> _absentKids = [];
  bool _isLoading = true;
  String _errorMessage = '';
  bool _canWrite = true;
  String? _teamId;
  Map<String, KidInfo> _allKidsInfoMap = {};
  String _currentServerName = "جاري التحميل...";
  String _myGroupId = '';
  List<String> _gradeOrder = [];
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _actionsSubscription?.close();
    _userSubscription?.close();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    // _loadUserData calls _loadLatest report when ready
  }

  Future<void> _loadUserData() async {
    // Immediate attempt to get cached name for better UI state
    UserService().getCurrentUserName().then((name) {
      if (mounted) setState(() => _currentServerName = name);
    });

    // 🚀 1. Cache First (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedGroupData = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedGroupData != null && cachedGroupData['groupId'] != null) {
        if (mounted) {
          setState(() {
            _myGroupId = cachedGroupData['groupId']!;
            _teamId = cachedGroupData['teamId'];
          });
        }

        // Load data乐观地
        if (_myGroupId.isNotEmpty) {
          final canWrite = await PermissionService.canWrite(_myGroupId);
          if (mounted) setState(() => _canWrite = canWrite);

          // Fire these off without await to not block UI
          _fetchAllKidsInfo();
          _fetchGradeOrder();
          _loadLatestReport();
        }
      }
    }

    // 🚀 2. Background Refresh
    try {
      final user = await _account.get();
      _handleUserUpdate(user.$id); // Live fetch

      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);
      _userSubscription!.stream.listen((event) {
        if (mounted) _handleUserUpdate(user.$id); // Refresh on update
      });
    } catch (e) {
      debugPrint("Error loading user from network: $e");
      // If we completely failed network AND cache was empty earlier, show error
      if (_myGroupId.isEmpty && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'load_error'.tr(context);
        });
      }
    }
  }

  Future<void> _handleUserUpdate(String userId) async {
    try {
      final userDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );
      final prevGroupId = _myGroupId;
      if (mounted) {
        setState(() {
          _myGroupId = userDoc.data['groupId'] ?? '';
          _currentServerName = userDoc.data['username'] ?? 'user'.tr(context);
          _teamId = userDoc.data['teamId'];
        });
        final canWrite = await PermissionService.canWrite(_myGroupId);
        if (mounted) setState(() => _canWrite = canWrite);
      }

      // Cache User Group data for offline support
      if (userId.isNotEmpty) {
        final role = userDoc.data['role'] ?? 'user';
        await DataCacheService().cacheUserGroupId(
          userId,
          _myGroupId,
          _teamId,
          role,
        );
      }

      if (_myGroupId.isNotEmpty && prevGroupId != _myGroupId) {
        await _fetchAllKidsInfo();
        await _fetchGradeOrder();
        _loadLatestReport();
      }
    } catch (e) {
      debugPrint("Error fetching user doc from network: $e");
      // If we completely failed network AND cache was empty earlier, show error
      if (_myGroupId.isEmpty && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'load_error'.tr(context);
        });
      }
    }
  }

  Future<void> _fetchGradeOrder() async {
    try {
      final grades = await GradeService(groupId: _myGroupId).getGrades();
      if (mounted) setState(() => _gradeOrder = grades);
      // Cache grades for offline fallback
      await DataCacheService().cacheGrades(_myGroupId, grades);
    } catch (e) {
      debugPrint("Error fetching grades: $e");
      // Fallback to cache when offline
      final cachedGrades = await DataCacheService().getCachedGrades(_myGroupId);
      if (cachedGrades.isNotEmpty && mounted) {
        setState(() => _gradeOrder = cachedGrades);
      }
    }
  }

  Future<void> _fetchAllKidsInfo({bool forceRefresh = false}) async {
    final requestType = _selectedType;
    if (_myGroupId.isEmpty) return;
    try {
      final collectionId = (_selectedType == "servants")
          ? servantsCollectionId
          : studentsCollectionId;
      final typeForCache = (_selectedType == "servants")
          ? 'servants'
          : 'students';

      // 1. Try Loading from Cache
      if (!forceRefresh) {
        final cachedMap = await DataCacheService().getCachedContactMap(
          _myGroupId,
          typeForCache,
        );
        if (cachedMap.isNotEmpty) {
          if (requestType != _selectedType) return; // 🛡️ Guard
          if (mounted) {
            setState(() {
              _allKidsInfoMap = cachedMap.map(
                (key, value) => MapEntry(key, KidInfo.fromJson(value)),
              );
            });
          }
          return;
        }
      }

      // 2. Fetch from Network if Cache is Empty
      final List<models.Document> allDocs = [];
      String? lastId;
      bool hasMore = true;

      while (hasMore) {
        List<String> queries = [
          Query.equal('groupId', _myGroupId),
          Query.limit(100),
        ];
        if (lastId != null) {
          queries.add(Query.cursorAfter(lastId));
        }

        final result = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: collectionId,
          queries: queries,
        );

        allDocs.addAll(result.documents);
        if (result.documents.length < 100) {
          hasMore = false;
        } else {
          lastId = result.documents.last.$id;
        }
      }

      final Map<String, KidInfo> tempMap = {};
      final Map<String, dynamic> jsonMapForCache = {};

      for (var doc in allDocs) {
        final info = KidInfo.fromAppwrite(
          doc,
          (_selectedType == "servants") ? 'servants' : 'students',
        );
        tempMap[info.name] = info;
        jsonMapForCache[info.name] = info.toJson();
      }

      // Save to Cache
      await DataCacheService().cacheContactMap(
        _myGroupId,
        typeForCache,
        jsonMapForCache,
      );

      if (requestType != _selectedType) return; // 🛡️ Guard
      if (mounted) setState(() => _allKidsInfoMap = tempMap);
    } catch (e) {
      debugPrint("Error fetching kids info: $e");
    }
  }

  Future<void> _loadLatestReport() async {
    final requestType = _selectedType;
    if (_myGroupId.isEmpty) return;

    if (mounted) {
      setState(() {
        _isLoading = _absentKids.isEmpty;
        _errorMessage = '';
      });
    }

    // 1. Load SIMPLE UI STATE Cache instantly
    bool loadedFromState = false;
    final cachedState = await DataCacheService().getCachedAbsenceState(
      _myGroupId,
      _selectedType,
    );
    if (cachedState.isNotEmpty && _absentKids.isEmpty) {
      if (requestType != _selectedType) return; // 🛡️ Guard
      if (mounted) {
        setState(() {
          _absentKids = cachedState.map((e) => AbsentKid.fromJson(e)).toList();
          _isLoading = false;
        });
      }
      loadedFromState = true;
    }

    // 2. Load cached report metadata (always, so we have reportName/date)
    final cachedReport = await DataCacheService().getCachedAbsenceReport(
      _myGroupId,
      _selectedType,
    );
    if (cachedReport != null) {
      try {
        final cachedDoc = models.Document.fromMap(cachedReport);
        if (requestType == _selectedType) {
          if (mounted) setState(() => _latestReport = cachedDoc);

          // If we didn't have a simple state cache, process this report data
          if (!loadedFromState && _absentKids.isEmpty) {
            await _processAbsenceData(
              cachedDoc,
              requestType,
              isFromCache: true,
            );
          }
        }
      } catch (e) {
        debugPrint("Error reconstructing cached doc: $e");
      }
    }

    // 3. Refresh kid info silently
    if (_allKidsInfoMap.isEmpty) await _fetchAllKidsInfo();

    try {
      final isOnline = await SyncService().isOnline();
      if (!isOnline) {
        if (mounted && _absentKids.isEmpty) {
          setState(() {
            _errorMessage = 'no_internet'.tr(context);
            _isLoading = false;
          });
        }
        return;
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceRecordsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('type', _selectedType),
          Query.orderDesc('timestamp'),
          Query.limit(1),
        ],
      );

      if (requestType != _selectedType) return; // 🛡️ Guard

      if (result.documents.isNotEmpty) {
        final reportDoc = result.documents.first;

        // 🚀 ONLY process if it's a NEW report or we have no data
        if (reportDoc.$id != _latestReport?.$id || _absentKids.isEmpty) {
          if (mounted) setState(() => _latestReport = reportDoc);

          await DataCacheService().cacheAbsenceReport(
            _myGroupId,
            _selectedType,
            reportDoc.toMap(),
          );

          if (requestType != _selectedType) return; // 🛡️ Guard
          await _processAbsenceData(reportDoc, requestType);
          _subscribeToActions(reportDoc.$id);
        } else {
          // Same report, just ensure we are subbed
          _subscribeToActions(reportDoc.$id);
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        if (mounted) {
          setState(() {
            _latestReport = null;
            _absentKids = [];
            final localizedType = _selectedType.tr(context);
            _errorMessage =
                "${'no_recent_absence_report'.tr(context)} $localizedType.";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading latest report: $e");
      if (mounted) {
        if (_absentKids.isEmpty && _latestReport == null) {
          setState(() {
            _errorMessage = "${'load_error'.tr(context)}: $e";
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchAllKidsInfo(forceRefresh: true);
    await _loadLatestReport();
  }

  Future<void> _processAbsenceData(
    models.Document reportDoc,
    String requestType, {
    bool isFromCache = false,
  }) async {
    final String reportId = reportDoc.$id;
    try {
      Map<String, dynamic> rawMap = {};
      final String? fileId = reportDoc.data['fileId'];

      if (fileId != null && fileId.isNotEmpty) {
        // Try getting from cache if it was already processed
        if (!isFromCache) {
          try {
            // First check if network is available to avoid hanging
            final isOnline = await SyncService()
                .isOnline(); // Assuming this is available, if not, wait for timeout
            if (!isOnline) throw Exception('Offline');

            final res = await AppwriteService().storage.getFileDownload(
              bucketId: AppwriteService.attendanceBucketId,
              fileId: fileId,
            );
            final jsonString = utf8.decode(res);
            rawMap = jsonDecode(jsonString);
            // Cache the content for offline use
            await DataCacheService().cacheReportContent(reportId, rawMap);
          } catch (e) {
            debugPrint('Error downloading report file: $e');
            // Fallback to cache on download error
            rawMap =
                await DataCacheService().getCachedReportContent(reportId) ?? {};
          }
        } else {
          // If we are loading from cache, try to get the full content first
          rawMap =
              await DataCacheService().getCachedReportContent(reportId) ??
              reportDoc.data;
        }
      } else {
        final dataField = reportDoc.data['data'];
        if (dataField is String) {
          rawMap = jsonDecode(dataField);
        } else if (dataField is Map) {
          rawMap = Map<String, dynamic>.from(dataField);
        } else {
          rawMap = {};
        }
      }

      final List<AbsentKid> baseAbsents = [];
      final String reportName = reportDoc.data['reportName'] ?? '';

      rawMap.forEach((grade, listDynamic) {
        if (listDynamic is! List) return;

        // 🚀 Ignore custom pages if we only want 'attendees' list
        // Custom pages are saved as "GradeName - PageName"
        if (requestType == 'attendees' && grade.contains(' - ')) {
          return;
        }

        final list = listDynamic;
        for (var item in list) {
          if (item is Map && !(item['isPresent'] == true)) {
            final String name = item['name'] ?? 'unknown_name'.tr(context);
            final String note = item['note'] ?? '';
            final String markedBy = item['markedBy'] ?? '';

            final info = _allKidsInfoMap[name];

            baseAbsents.add(
              AbsentKid(
                name: name,
                address: info?.address ?? 'no_address'.tr(context),
                grade: grade,
                note: note,
                recordedBy: markedBy,
                reportName: reportName,
                phones: info?.phones ?? [],
                phoneOwners: info?.phoneOwners ?? {},
                locationUrl: info?.locationUrl,
                reportId: reportId,
                isMissed: false,
                missedBy: '',
                absentReason: '',
                photoUrl: info?.photoUrl,
              ),
            );
          }
        }
      });

      // Fetch Actions from Cache first, then Network
      List<Map<String, dynamic>> actionsList = await DataCacheService()
          .getCachedAbsenceActions(reportId);

      if (!isFromCache) {
        try {
          final isOnline = await SyncService().isOnline();
          if (!isOnline) throw Exception('Offline');

          final actionsResult = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: absenceActionsCollectionId,
            queries: [Query.equal('reportId', reportId), Query.limit(1000)],
          );
          actionsList = actionsResult.documents.map((d) => d.data).toList();

          // 🚀 CRITICAL: Replay pending offline edits on top of fresh network data!
          // This prevents network fetches from overwriting offline edits before sync is complete.
          final pendingOps = await DataCacheService().getPendingOperations();
          for (var op in pendingOps) {
            if (op['type'] == 'absence_action_upsert') {
              final opData = op['data'] as Map<String, dynamic>;
              if (opData['reportId'] == reportId) {
                final String kidName = opData['kidName'];
                final Map<String, dynamic> updates = opData['updates'] ?? {};
                final int idx = actionsList.indexWhere(
                  (a) => a['kidName'] == kidName,
                );
                if (idx != -1) {
                  actionsList[idx] = {...actionsList[idx], ...updates};
                } else {
                  actionsList.add({
                    'reportId': reportId,
                    'kidName': kidName,
                    'grade': opData['grade'],
                    ...updates,
                  });
                }
              }
            }
          }

          await DataCacheService().cacheAbsenceActions(reportId, actionsList);
        } catch (e) {
          debugPrint("Error fetching actions from network: $e");
        }
      }

      final Map<String, Map<String, dynamic>> actionsMap = {};
      for (var action in actionsList) {
        actionsMap[action['kidName']] = action;
      }

      // Merge
      final List<AbsentKid> mergedAbsents = baseAbsents.map((kid) {
        if (actionsMap.containsKey(kid.name)) {
          final action = actionsMap[kid.name]!;
          return kid.copyWith(
            isMissed: action['isMissed'] ?? false,
            missedBy: action['missedBy'] ?? '',
            absentReason: action['absentReason'] ?? '',
          );
        }
        return kid;
      }).toList();

      // Sort safely
      try {
        mergedAbsents.sort((a, b) {
          final gradeCmp = _compareGrades(a.grade, b.grade);
          if (gradeCmp != 0) return gradeCmp;
          return a.name.compareTo(b.name);
        });
      } catch (e) {
        debugPrint("Sorting failed, ignoring: $e");
      }

      if (requestType != _selectedType) return; // 🛡️ Guard
      if (mounted) {
        setState(() {
          _absentKids = mergedAbsents;
          _isLoading = false;
        });
        _saveAbsenceState(); // 🚀 Simplify Cache Call
      }
    } catch (e) {
      debugPrint("Error processing absence data: $e");
      // Don't show error if we already loaded it successfully from cache once
      if (mounted && _absentKids.isEmpty) {
        setState(() {
          _errorMessage = "${'data_processing_error'.tr(context)}: $e";
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper method to sync the UI list explicitly to cache
  Future<void> _saveAbsenceState() async {
    if (_myGroupId.isEmpty) return;
    await DataCacheService().cacheAbsenceState(
      _myGroupId,
      _selectedType,
      _absentKids.map((k) => k.toJson()).toList(),
    );
  }

  int _compareGrades(String a, String b) {
    final idxA = _gradeOrder.indexOf(a);
    final idxB = _gradeOrder.indexOf(b);
    if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
    if (idxA != -1) return -1;
    if (idxB != -1) return 1;
    return a.compareTo(b);
  }

  void _subscribeToActions(String reportId) {
    _actionsSubscription?.close();
    _actionsSubscription = _realtime.subscribe([
      'databases.$databaseId.collections.$absenceActionsCollectionId.documents',
    ]);

    _actionsSubscription!.stream.listen((event) {
      final payload = event.payload;
      if (payload['reportId'] == reportId) {
        final String kidName = payload['kidName'] ?? '';
        final bool isMissed = payload['isMissed'] ?? false;
        final String missedBy = payload['missedBy'] ?? '';
        final String absentReason = payload['absentReason'] ?? '';

        // Incremental Update to avoid ANR
        if (mounted) {
          setState(() {
            final index = _absentKids.indexWhere((k) => k.name == kidName);
            if (index != -1) {
              _absentKids[index] = _absentKids[index].copyWith(
                isMissed: isMissed,
                missedBy: missedBy,
                absentReason: absentReason,
              );
            }
            // Call _saveAbsenceState() inside setState as per instruction
            _saveAbsenceState(); // 🚀 Keep Cache in Sync
          });

          // Update action cache too
          DataCacheService().updateSingleAbsenceActionInCache(
            reportId,
            kidName,
            payload,
          );
        }
      }
    });
  }

  void _recordMissedStatus(AbsentKid kid) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('subscription_expired'.tr(context))),
        );
      }
      return;
    }

    // Optimistic Update (UI Refresh immediately)
    if (mounted) {
      setState(() {
        final index = _absentKids.indexWhere((k) => k.name == kid.name);
        if (index != -1) {
          _absentKids[index] = _absentKids[index].copyWith(
            isMissed: true,
            missedBy: _currentServerName,
          );
        }
        _saveAbsenceState(); // 🚀 Cache optimistic update
      });
    }

    _upsertAction(kid.reportId, kid.name, kid.grade, {
      'isMissed': true,
      'missedBy': _currentServerName,
      'missedAt': DateTime.now().toIso8601String(),
    });
  }

  void _editAbsentReason(AbsentKid kid) async {
    final TextEditingController reasonController = TextEditingController(
      text: kid.absentReason,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              children: [
                Text(
                  'miss_absentees'.tr(context),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (!_canWrite)
                  Text(
                    'read_only_mode'.tr(context),
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'absence_reason'.tr(context),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (!_canWrite) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('subscription_expired'.tr(context)),
                      ),
                    );
                  }
                  return;
                }
                final newReason = reasonController.text.trim();
                if (context.mounted) {
                  setState(() {
                    final index = _absentKids.indexWhere(
                      (k) => k.name == kid.name,
                    );
                    if (index != -1) {
                      _absentKids[index] = _absentKids[index].copyWith(
                        absentReason: newReason,
                      );
                    }
                    _saveAbsenceState(); // 🚀 Cache Optimistic Update
                  });
                }

                _upsertAction(kid.reportId, kid.name, kid.grade, {
                  'absentReason': newReason,
                  'reasonUpdatedBy': _currentServerName,
                  'reasonUpdatedAt': DateTime.now().toIso8601String(),
                });
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text('save'.tr(context)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _upsertAction(
    String reportId,
    String kidName,
    String grade,
    Map<String, dynamic> updates,
  ) async {
    // 2. Update Cache immediately
    await DataCacheService().updateSingleAbsenceActionInCache(
      reportId,
      kidName,
      updates,
    );

    try {
      // Check if action exists
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: absenceActionsCollectionId,
        queries: [
          Query.equal('reportId', reportId),
          Query.equal('kidName', kidName),
          Query.limit(1),
        ],
      );

      if (result.documents.isNotEmpty) {
        await _databases.updateDocument(
          databaseId: databaseId,
          collectionId: absenceActionsCollectionId,
          documentId: result.documents.first.$id,
          data: updates,
        );
      } else {
        await _databases.createDocument(
          databaseId: databaseId,
          collectionId: absenceActionsCollectionId,
          documentId: ID.unique(),
          data: {
            'reportId': reportId,
            'kidName': kidName,
            'grade': grade,
            'groupId': _myGroupId,
            ...updates,
          },
          permissions: _teamId != null
              ? [
                  Permission.read(Role.team(_teamId!)),
                  Permission.update(Role.team(_teamId!)),
                  Permission.delete(Role.team(_teamId!)),
                ]
              : null,
        );
      }
    } catch (e) {
      debugPrint("Error upserting action: $e");
      // If error (e.g. offline), add to pending operations
      await DataCacheService().addPendingOperation({
        'type': 'absence_action_upsert',
        'data': {
          'reportId': reportId,
          'kidName': kidName,
          'grade': grade,
          'updates': updates,
          'groupId': _myGroupId,
          'teamId': _teamId,
        },
      });
    }
  }

  // UI Construction

  Map<String, List<AbsentKid>> _getAbsentKidsByGrade() {
    final Map<String, List<AbsentKid>> groupedAbsence = {};
    for (var kid in _absentKids) {
      if (_searchText.isNotEmpty &&
          !kid.name.toLowerCase().contains(_searchText.toLowerCase())) {
        continue;
      }
      if (!groupedAbsence.containsKey(kid.grade)) {
        groupedAbsence[kid.grade] = [];
      }
      groupedAbsence[kid.grade]!.add(kid);
    }

    final sortedKeys = groupedAbsence.keys.toList();
    sortedKeys.sort((a, b) {
      final indexA = _gradeOrder.indexOf(a);
      final indexB = _gradeOrder.indexOf(b);

      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(indexB);
      } else if (indexA != -1) {
        return -1;
      } else if (indexB != -1) {
        return 1;
      }
      return a.compareTo(b);
    });

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, groupedAbsence[key]!)),
    );
  }

  Widget _buildGradeSection(String grade, List<AbsentKid> kids) {
    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height * 0.02,
      ),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ExpansionTile(
            initiallyExpanded: true,
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            tilePadding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.05,
              vertical: MediaQuery.of(context).size.height * 0.01,
            ),
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(
                    MediaQuery.of(context).size.width * 0.02,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school,
                    color: Colors.red.shade700,
                    size: MediaQuery.of(context).size.width * 0.05,
                  ),
                ),
                SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      grade,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: MediaQuery.of(context).size.width * 0.045,
                        color: Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width * 0.03,
                    vertical: MediaQuery.of(context).size.height * 0.008,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${kids.length}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                        fontSize: MediaQuery.of(context).size.width * 0.035,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            children: kids.map((kid) {
              return AbsentKidCard(
                kid: kid,
                currentServerName: _currentServerName,
                onMissed: () => _recordMissedStatus(kid),
                personType: _selectedType,
                onReasonEdit: () => _editAbsentReason(kid),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    final int totalAbsent = _absentKids.length;
    final int totalMissed = _absentKids.where((kid) => kid.isMissed).length;
    final int remaining = totalAbsent - totalMissed;
    final int withReason = _absentKids
        .where((kid) => kid.absentReason.isNotEmpty)
        .length;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: MediaQuery.of(context).size.height * 0.01,
      ),
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.03),
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.08,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'total'.tr(context),
            totalAbsent.toString(),
            Colors.blue,
          ),
          _buildStatItem(
            'missed'.tr(context),
            totalMissed.toString(),
            Colors.green,
          ),
          _buildStatItem(
            'remaining'.tr(context),
            remaining.toString(),
            Colors.orange,
          ),
          _buildStatItem(
            'with_reason'.tr(context),
            withReason.toString(),
            Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width * 0.045,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.005),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width * 0.03,
              color: Colors.grey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _currentServerName == "جاري التحميل..." ||
                          _currentServerName.isEmpty
                      ? 'loading_server_and_report'.tr(context)
                      : 'loading_latest_report'.tr(context),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: MediaQuery.of(context).size.width * 0.04,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasAbsence = _absentKids.isNotEmpty;
    final groupedAbsence = _getAbsentKidsByGrade();

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: Colors.red.shade700,
        backgroundColor: Colors.white,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: MediaQuery.of(context).size.height * 0.15,
              floating: true,
              pinned: true,
              backgroundColor: Colors.red.shade700,
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                title: Container(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "${'absence_register_for'.tr(context)} ${_selectedType.tr(context)}",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width * 0.038,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(blurRadius: 10, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                      if (_latestReport != null) ...[
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.assignment,
                                size: 10,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _latestReport!.data['reportName'] ?? '',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (_latestReport!.data['date'] != null) ...[
                                const Icon(
                                  Icons.calendar_today,
                                  size: 9,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _latestReport!.data['date'],
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE57373), Color(0xFFB71C1C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.025,
                  bottom: MediaQuery.of(context).size.height * 0.015,
                  left: MediaQuery.of(context).size.width * 0.04,
                  right: MediaQuery.of(context).size.width * 0.04,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage.isNotEmpty)
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            "❌ ${'error_occurred'.tr(context).replaceFirst('%s', _errorMessage)}",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.035,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.9,
                        ),
                        child: Container(
                          margin: EdgeInsets.only(
                            bottom: MediaQuery.of(context).size.height * 0.02,
                          ),
                          constraints: BoxConstraints(
                            minHeight:
                                MediaQuery.of(context).size.height * 0.06,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: ToggleButtons(
                            isSelected: [
                              _selectedType == "attendees",
                              _selectedType == "servants",
                            ],
                            onPressed: (int index) {
                              if (mounted) {
                                setState(() {
                                  _selectedType = index == 0
                                      ? "attendees"
                                      : "servants";
                                  _allKidsInfoMap.clear();
                                  _absentKids.clear();
                                  _latestReport = null;
                                  _errorMessage = '';
                                  _isLoading = true;
                                });
                                _fetchAllKidsInfo().then((_) {
                                  _loadLatestReport();
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(15),
                            selectedColor: Colors.white,
                            color: Colors.red.shade900,
                            fillColor: Colors.red.shade700,
                            borderColor: Colors.transparent,
                            selectedBorderColor: Colors.transparent,
                            constraints: BoxConstraints(
                              minHeight:
                                  MediaQuery.of(context).size.height * 0.05,
                            ),
                            children: [
                              _buildToggleItem('attendees'.tr(context)),
                              _buildToggleItem('servants'.tr(context)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _buildStatistics(),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (v) => setState(() => _searchText = v),
                      decoration: InputDecoration(
                        hintText: 'search_in_absentees'.tr(context),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.red.shade700,
                        ),
                        filled: true,
                        fillColor: Colors.red.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                            color: Colors.red.shade700,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            hasAbsence
                ? SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.02,
                      vertical: MediaQuery.of(context).size.height * 0.01,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final grades = groupedAbsence.keys.toList();
                        if (index >= grades.length) return null;
                        final grade = grades[index];
                        return _buildGradeSection(
                          grade,
                          groupedAbsence[grade]!,
                        );
                      }, childCount: groupedAbsence.length),
                    ),
                  )
                : SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(
                          MediaQuery.of(context).size.width * 0.08,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _latestReport != null
                                ? "🎉 ${'no_absence_recorded_for'.tr(context)} ${_selectedType.tr(context)} ${'in_this_report'.tr(context)}"
                                : "⚠️ ${'please_save_attendance_first'.tr(context)}",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.04,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem(String label) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.35,
      child: Center(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
