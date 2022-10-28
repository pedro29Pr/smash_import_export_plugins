part of smash_import_export_plugins;
/*
 * Copyright (c) 2019-2020. Antonello Andrea (www.hydrologis.com). All rights reserved.
 * Use of this source code is governed by a GPL3 license that can be
 * found in the LICENSE file.
 */

/// @author hydrologis
class GssUtilities {
  static final int DEFAULT_BYTE_ARRAY_READ = 8192;

  static final String MASTER_GSS_PASSWORD = "gss_Master_Survey_Forever_2018";

  static final int MPR_TIMEOUT = 5 * 60 * 1000; // 5 minutes timeout

  static final String LAST_DB_PATH = "GSS_LAST_DB_PATH";
  static final String SERVER_URL = "GSS_SERVER_URL";

  static final String SYNCH_PATH = "/upload";
  static final String DATA_DOWNLOAD_PATH = "/datadownload";
  static final String TAGS_DOWNLOAD_PATH = "/tagsdownload";

  static final String DATA_DOWNLOAD_MAPS = "maps";
  static final String DATA_DOWNLOAD_PROJECTS = "projects";
  static final String DATA_DOWNLOAD_NAME = "name";

  static final String TAGS_DOWNLOAD_TAGS = "tags";
  static final String TAGS_DOWNLOAD_TAG = "tag";
  static final String TAGS_DOWNLOAD_NAME = "name";

//     static String NATIVE_BROWSER_USE = "GSS_NATIVE_BROWSER_USE";
  static final double ICON_SIZE = 4;
  static final double BIG_ICON_SIZE = 8;
  static final String YES = "Yes";
  static final String NO = "No";

  static Future<String?> getAuthHeader(String? password) async {
    String? deviceId =
        GpPreferences().getStringSync(SmashPreferencesKeys.DEVICE_ID_OVERRIDE);
    deviceId ??= GpPreferences().getStringSync(
        SmashPreferencesKeys.DEVICE_ID, await Device().getDeviceId());
    if (deviceId == null) {
      return null;
    }
    String authCode =
        deviceId + ":" + (password ?? GssUtilities.MASTER_GSS_PASSWORD);
    String authHeader =
        "Basic " + const Base64Encoder().convert(authCode.codeUnits);
    return authHeader;
  }

  static final String NOTE_OBJID = "note";
  static final String IMAGE_OBJID = "image";
  static final String LOG_OBJID = "gpslog";
  static final String OBJID_TYPE_KEY = "type";
}

/// Widget to trace upload of geopaparazzi items upload.
///
/// These can be notes, images or gpslogs.
class ProjectDataUploadListTileProgressWidget extends StatefulWidget {
  final String _uploadUrl;
  final dynamic _item;
  final String? authHeader;
  final ProjectDb _projectDb;
  final Dio _dio;
  final ValueNotifier? orderNotifier;
  final int order;

  ProjectDataUploadListTileProgressWidget(
      this._dio, this._projectDb, this._uploadUrl, this._item,
      {this.authHeader, this.orderNotifier, required this.order});

  @override
  State<StatefulWidget> createState() {
    return ProjectDataUploadListTileProgressWidgetState();
  }
}

class ProjectDataUploadListTileProgressWidgetState
    extends State<ProjectDataUploadListTileProgressWidget> {
  bool _uploading = true;
  dynamic _item;
  String _progressString = "";
  String _errorString = "";
  CancelToken cancelToken = CancelToken();

  @override
  void initState() {
    _item = widget._item;
    super.initState();

    if (widget.orderNotifier == null) {
      // if no order notifier is available, start the upload directly
      upload();
    } else {
      if (widget.orderNotifier?.value == widget.order) {
        upload();
      } else {
        widget.orderNotifier?.addListener(() {
          if (widget.orderNotifier?.value == widget.order) {
            upload();
          }
        });
      }
    }
  }

  Future<void> upload() async {
    bool hasError = false;
    Options? options;
    if (widget.authHeader != null) {
      options = Options(headers: {"Authorization": widget.authHeader});
    } else {
      hasError = true;
      handleError("Auth header missing!");
      return;
    }

    var dbPath = widget._projectDb.getPath();
    var projectName = FileUtilities.nameFromFile(dbPath, false);
    try {
      if (_item is Note) {
        hasError = await handleNote(options, projectName, hasError);
      } else if (_item is DbImage) {
        hasError = await handleImage(options, projectName, hasError);
      } else if (_item is Log) {
        hasError = await handleLog(options, projectName, hasError);
      }
    } catch (e) {
      hasError = true;
      handleError(e);
    }
    if (widget.orderNotifier == null) {
      setState(() {
        _uploading = false;
        _progressString = cancelToken.isCancelled
            ? IEL.of(context).network_cancelledByUser //"Cancelled by user."
            : IEL.of(context).network_completed; //"Completed."
      });
    } else {
      _uploading = false;
      _progressString = cancelToken.isCancelled
          ? IEL.of(context).network_cancelledByUser //"Cancelled by user."
          : IEL.of(context).network_completed; //"Completed."
      if (!hasError) {
        widget.orderNotifier?.value = widget.orderNotifier?.value + 1;
      } else {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String name = "no name";
    String description = "no description";
    if (_item is Note) {
      name = _item.form == null || _item.form.length == 0
          ? "simple note"
          : "form note";
      description = _item.text;
    } else if (_item is DbImage) {
      name = "image";
      description = _item.text;
    } else if (_item is Log) {
      name = "gps log";
      description = _item.text;
    }
    if (widget.orderNotifier == null) {
      return getTile(name, description);
    } else {
      return ValueListenableBuilder<dynamic>(
        valueListenable: widget.orderNotifier!,
        builder: (context, value, child) {
          return getTile(name, description);
        },
      );
    }
  }

  Widget getTile(String name, String description) {
    return ListTile(
      leading: _uploading
          ? CircularProgressIndicator()
          : _errorString.length > 0
              ? Icon(
                  SmashIcons.finishedError,
                  color: SmashColors.mainSelection,
                )
              : Icon(
                  SmashIcons.finishedOk,
                  color: SmashColors.mainDecorations,
                ),
      title: Text(name),
      subtitle: _errorString.length == 0
          ? (_uploading ? Text(_progressString) : Text(description))
          : SmashUI.normalText(_errorString,
              bold: true, color: SmashColors.mainSelection),
//      trailing: Icon(
//        ICONS.SmashIcons.upload,
//        color: SmashColors.mainDecorations,
//      ),
      onTap: () {},
    );
  }

  Future<bool> handleLog(
      Options options, String projectName, bool hasError) async {
    Log log = _item;
    LogProperty? props = widget._projectDb.getLogProperties(log.id!);

    var formData = FormData();
    formData.fields
      ..add(MapEntry(GssUtilities.OBJID_TYPE_KEY, GssUtilities.LOG_OBJID))
      ..add(MapEntry(PROJECT_NAME, projectName))
      ..add(MapEntry(LOGS_COLUMN_ID, "${log.id}"))
      ..add(MapEntry(LOGS_COLUMN_TEXT, log.text ?? ""))
      ..add(MapEntry(LOGS_COLUMN_STARTTS, "${log.startTime}"))
      ..add(MapEntry(LOGS_COLUMN_ENDTS, "${log.endTime}"))
      ..add(MapEntry(LOGSPROP_COLUMN_WIDTH, "${props!.width ?? 3}"))
      ..add(MapEntry(LOGSPROP_COLUMN_VISIBLE, "${props.isVisible ?? 1}"))
      ..add(MapEntry(LOGSPROP_COLUMN_COLOR, "${props.color ?? "#FF0000"}"));

    List<LogDataPoint> logPoints = widget._projectDb.getLogDataPoints(log.id!);
    List<Map<String, dynamic>> logPointsList = [];
    for (var logPoint in logPoints) {
      logPointsList.add(logPoint.toMap());
    }
    var logsJson = jsonEncode(logPointsList);
    formData.fields.add(MapEntry(TABLE_GPSLOG_DATA, logsJson));

    await widget._dio.post(
      widget._uploadUrl,
      data: formData,
      options: options,
      onSendProgress: (received, total) {
        var msg;
        if (total <= 0) {
          msg =
              "${IEL.of(context).network_uploading} ${(received / 1024.0 / 1024.0).round()}MB, ${IEL.of(context).network_pleaseWait}"; //Uploading //please wait...
        } else {
          msg = ((received / total) * 100.0).toStringAsFixed(0) + "%";
        }
        setState(() {
          _uploading = true;
          _progressString = msg;
        });
      },
      cancelToken: cancelToken,
    ).catchError((err) {
      hasError = true;
      handleError(err);
    });
    if (!cancelToken.isCancelled && !hasError) {
      log.isDirty = 0;
      widget._projectDb.updateLogDirty(log.id!, false);
    }
    return hasError;
  }

  Future<bool> handleImage(
      Options options, String projectName, bool hasError) async {
    DbImage image = _item;
    var formData = FormData();
    formData.fields
      ..add(MapEntry(GssUtilities.OBJID_TYPE_KEY, GssUtilities.IMAGE_OBJID))
      ..add(MapEntry(PROJECT_NAME, projectName))
      ..add(MapEntry(IMAGES_COLUMN_ID, "${image.id}"))
      ..add(MapEntry(IMAGES_COLUMN_TEXT, image.text))
      ..add(MapEntry(IMAGES_COLUMN_IMAGEDATA_ID, "${image.imageDataId}"))
      ..add(MapEntry(IMAGES_COLUMN_TS, "${image.timeStamp}"))
      ..add(MapEntry(IMAGES_COLUMN_LON, "${image.lon}"))
      ..add(MapEntry(IMAGES_COLUMN_LAT, "${image.lat}"))
      ..add(MapEntry(IMAGES_COLUMN_ALTIM, "${image.altim}"));
    if (image.noteId != null) {
      formData.fields..add(MapEntry(IMAGES_COLUMN_NOTE_ID, "${image.noteId}"));
    }
    var imageBytes = widget._projectDb.getImageDataBytes(image.imageDataId!);
    formData.files.add(MapEntry(
      TABLE_IMAGE_DATA + "_" + IMAGESDATA_COLUMN_IMAGE,
      MultipartFile.fromBytes(imageBytes!, filename: image.text),
    ));

    var thumbBytes = widget._projectDb.getThumbnailBytes(image.imageDataId!);
    formData.files.add(MapEntry(
      TABLE_IMAGE_DATA + "_" + IMAGESDATA_COLUMN_THUMBNAIL,
      MultipartFile.fromBytes(thumbBytes!, filename: image.text),
    ));

    await widget._dio.post(
      widget._uploadUrl,
      data: formData,
      options: options,
      onSendProgress: (received, total) {
        print("$received / $total");
        var msg;
        if (total <= 0) {
          msg =
              "${IEL.of(context).network_uploading} ${(received / 1024.0 / 1024.0).round()}MB, ${IEL.of(context).network_pleaseWait}"; //Uploading //please wait...
        } else {
          msg = ((received / total) * 100.0).toStringAsFixed(0) + "%";
        }
        setState(() {
          _uploading = true;
          _progressString = msg;
        });
      },
      cancelToken: cancelToken,
    ).catchError((err) {
      hasError = true;
      handleError(err);
    });
    if (!cancelToken.isCancelled && !hasError) {
      image.isDirty = 0;
      widget._projectDb.updateImageDirty(image.id!, false);
    }
    return hasError;
  }

  Future<bool> handleNote(
      Options options, String projectName, bool hasError) async {
    Note note = _item;
    var formData = FormData();
    formData.fields
      ..add(MapEntry(GssUtilities.OBJID_TYPE_KEY, GssUtilities.NOTE_OBJID))
      ..add(MapEntry(PROJECT_NAME, projectName))
      ..add(MapEntry(NOTES_COLUMN_ID, "${note.id}"))
      ..add(MapEntry(NOTES_COLUMN_TEXT, note.text))
      ..add(MapEntry(NOTES_COLUMN_DESCRIPTION, note.description ?? ""))
      ..add(MapEntry(NOTES_COLUMN_TS, "${note.timeStamp}"))
      ..add(MapEntry(NOTES_COLUMN_LON, "${note.lon}"))
      ..add(MapEntry(NOTES_COLUMN_LAT, "${note.lat}"))
      ..add(MapEntry(NOTES_COLUMN_ALTIM, "${note.altim}"));
    if (note.form != null) {
      formData.fields.add(MapEntry(NOTES_COLUMN_FORM, note.form!));

      List<String> imageIds = FormUtilities.getImageIds(note.form);

      if (imageIds.isNotEmpty) {
        for (var imageId in imageIds) {
          var dbImage = widget._projectDb.getImageById(int.parse(imageId));
          var imageBytes =
              widget._projectDb.getImageDataBytes(dbImage.imageDataId!);
          var thumbBytes =
              widget._projectDb.getThumbnailBytes(dbImage.imageDataId!);
          var key =
              "${TABLE_IMAGE_DATA}_${IMAGESDATA_COLUMN_IMAGE}_${dbImage.id}";
          formData.files.add(MapEntry(
            key,
            MultipartFile.fromBytes(imageBytes!, filename: dbImage.text),
          ));
          key =
              "${TABLE_IMAGE_DATA}_${IMAGESDATA_COLUMN_THUMBNAIL}_${dbImage.id}";
          formData.files.add(MapEntry(
            key,
            MultipartFile.fromBytes(thumbBytes!, filename: dbImage.text),
          ));
        }
      }
    }

    NoteExt? noteExt = note.noteExt;
    if (noteExt != null) {
      formData.fields
        ..add(MapEntry(NOTESEXT_COLUMN_MARKER, noteExt.marker))
        ..add(MapEntry(NOTESEXT_COLUMN_SIZE, "${noteExt.size}"))
        ..add(MapEntry(NOTESEXT_COLUMN_ROTATION, "${noteExt.rotation}"))
        ..add(MapEntry(NOTESEXT_COLUMN_COLOR, noteExt.color))
        ..add(MapEntry(NOTESEXT_COLUMN_ACCURACY, "${noteExt.accuracy}"))
        ..add(MapEntry(NOTESEXT_COLUMN_HEADING, "${noteExt.heading}"))
        ..add(MapEntry(NOTESEXT_COLUMN_SPEED, "${noteExt.speed}"))
        ..add(MapEntry(
            NOTESEXT_COLUMN_SPEEDACCURACY, "${noteExt.speedaccuracy}"));
    }

    await widget._dio.post(
      widget._uploadUrl,
      data: formData,
      options: options,
      onSendProgress: (received, total) {
        var msg;
        if (total <= 0) {
          msg =
              "${IEL.of(context).network_uploading} ${(received / 1024.0 / 1024.0).round()}MB, ${IEL.of(context).network_pleaseWait}"; //Uploading //please wait...
        } else {
          msg = ((received / total) * 100.0).toStringAsFixed(0) + "%";
        }
        setState(() {
          _uploading = true;
          _progressString = msg;
        });
      },
      cancelToken: cancelToken,
    ).catchError((err) {
      hasError = true;
      handleError(err);
    });
    if (!cancelToken.isCancelled && !hasError) {
      widget._projectDb.updateNoteDirty(note.id!, false);
    }
    return hasError;
  }

  void handleError(err) {
    if (err is DioError) {
      if (err.message.contains("403")) {
        _errorString = IEL
            .of(context)
            .network_permissionOnServerDenied; //"Permission on server denied."
      } else if (err.message.contains("Connection refused")) {
        _errorString = IEL
            .of(context)
            .network_couldNotConnectToServer; //"Could not connect to the server. Is it online? Check your address."
      } else {
        _errorString = err.message;
      }
    } else {
      _errorString = err.toString();
    }
  }
}

class GssSettings extends StatefulWidget {
  @override
  GssSettingsState createState() {
    return GssSettingsState();
  }
}

class GssSettingsState extends State<GssSettings> with AfterLayoutMixin {
  //static final title = "GSS";
  //static final subtitle = "Geopaparazzi Survey Server";
  static final iconData = MdiIcons.cloudLock;

  String? _gssUrl;
  String? _gssUser; // Rigth now unused, since the deviceid is the user
  String? _gssPwd;
  bool? _allowSelfCert;

  @override
  void afterFirstLayout(BuildContext context) {
    getData();
  }

  Future<void> getData() async {
    String? gssUrl = await GpPreferences()
        .getString(SmashPreferencesKeys.KEY_GSS_SERVER_URL, "");
    String? gssUser = await GpPreferences()
        .getString(SmashPreferencesKeys.KEY_GSS_SERVER_USER, "");
    String? gssPwd = await GpPreferences()
        .getString(SmashPreferencesKeys.KEY_GSS_SERVER_PWD, "dummy");
    bool? allowSelfCert = await GpPreferences().getBoolean(
        SmashPreferencesKeys.KEY_GSS_SERVER_ALLOW_SELFCERTIFICATE, true);

    setState(() {
      _gssUrl = gssUrl;
      _gssUser = gssUser;
      _gssPwd = gssPwd;
      _allowSelfCert = allowSelfCert;
    });
  }

  @override
  Widget build(BuildContext context) {
    var p = SmashUI.DEFAULT_PADDING;
    return Scaffold(
      appBar: new AppBar(
        title: Row(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(
                iconData,
                color: SmashColors.mainBackground,
              ),
            ),
            Text(IEL.of(context).settings_gss),
          ],
        ),
      ),
      body: _gssUrl == null
          ? Center(
              child: SmashCircularProgress(),
            )
          : SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    child: Card(
                      margin: SmashUI.defaultMargin(),
                      color: SmashColors.mainBackground,
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: SmashUI.defaultPadding(),
                            child: SmashUI.normalText(
                                IEL.of(context).settings_serverUrl,
                                bold: true), //"Server URL"
                          ),
                          Padding(
                              padding: EdgeInsets.only(
                                  top: p, bottom: p, right: p, left: 2 * p),
                              child: EditableTextField(
                                IEL
                                    .of(context)
                                    .settings_serverUrl, //"server url"
                                _gssUrl!,
                                (res) async {
                                  if (res == null || res.trim().length == 0) {
                                    res = _gssUrl;
                                  }
                                  await GpPreferences().setString(
                                      SmashPreferencesKeys.KEY_GSS_SERVER_URL,
                                      res);
                                  setState(() {
                                    _gssUrl = res;
                                  });
                                },
                                validationFunction: (text) {
                                  if (text.startsWith("http://") ||
                                      text.startsWith("https://")) {
                                    return null;
                                  } else {
                                    return IEL
                                        .of(context)
                                        .settings_serverUrlStartWithHttp; //"Server url needs to start with http or https."
                                  }
                                },
                              )),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    child: Card(
                      margin: SmashUI.defaultMargin(),
                      color: SmashColors.mainBackground,
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: SmashUI.defaultPadding(),
                            child: SmashUI.normalText(
                                IEL
                                    .of(context)
                                    .settings_serverPassword, //"Server Password"
                                bold: true),
                          ),
                          Padding(
                              padding: EdgeInsets.only(
                                  top: p, bottom: p, right: p, left: 2 * p),
                              child: EditableTextField(
                                IEL
                                    .of(context)
                                    .settings_serverPassword, //"server password",
                                _gssPwd!,
                                (res) async {
                                  if (res == null || res.trim().length == 0) {
                                    res = _gssPwd;
                                  }
                                  await GpPreferences().setString(
                                      SmashPreferencesKeys.KEY_GSS_SERVER_PWD,
                                      res);
                                  setState(() {
                                    _gssPwd = res;
                                  });
                                },
                                validationFunction: (text) {
                                  if (text.toString().trim().isNotEmpty) {
                                    return null;
                                  } else {
                                    return IEL
                                        .of(context)
                                        .settings_pleaseEnterValidPassword; //"Please enter a valid server password."
                                  }
                                },
                                isPassword: true,
                              )),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    child: Card(
                      margin: SmashUI.defaultMargin(),
                      color: SmashColors.mainBackground,
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: SmashUI.defaultPadding(),
                            child: SmashUI.normalText(
                                IEL
                                    .of(context)
                                    .settings_allowSelfSignedCert, //"Allow self signed certificates"
                                bold: true),
                          ),
                          Padding(
                              padding: EdgeInsets.only(
                                  top: p, bottom: p, right: p, left: 2 * p),
                              child: Checkbox(
                                value: _allowSelfCert,
                                onChanged: (newValue) async {
                                  await GpPreferences().setBoolean(
                                      SmashPreferencesKeys
                                          .KEY_GSS_SERVER_ALLOW_SELFCERTIFICATE,
                                      newValue!);
                                  await getData();
                                },
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
