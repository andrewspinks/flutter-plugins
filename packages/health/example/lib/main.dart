import 'dart:async';
import 'dart:math';
import "package:collection/collection.dart";
import 'package:permission_handler/permission_handler.dart';

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:workmanager/workmanager.dart';

HealthFactory health = HealthFactory();

Future<List<HealthDataPoint>> fetchHealthhData() async {
  var types = Platform.isIOS ? iosTypes : androidTypes;

  print("Fetching health data");

  // get data within the last 24 hours
  final fiveDaysAgo = DateTime.now().subtract(Duration(days: 5));
  final last5Days = DateTime(fiveDaysAgo.year, fiveDaysAgo.month, fiveDaysAgo.day);

    try {
      // fetch health data
      List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
          last5Days, DateTime.now(), types);
      // save all the new data points (only the first 100)

      print("heath data retrieved");
      var itemsByDay =
          groupBy(healthData, (HealthDataPoint point) => point.dateFrom.day);

      var itemsByDayAndType = itemsByDay.entries.map((e) {
        var groupedByType = groupBy(e.value, (HealthDataPoint point) => point.type);
        var workouts = groupedByType[HealthDataType.WORKOUT];
        return {
            e.key: [...groupBy(e.value, (HealthDataPoint point) => point.type)
                .entries
                .where((e) => e.key != HealthDataType.WORKOUT)
                .map((e) => {
                      e.key: e.value
                          .map((element) =>
                              (element.value as NumericHealthValue)
                                  .numericValue)
                          .reduce((value, element) => element + value)
                    }),
                ...workouts == null ? [] : workouts
            ]
          };
        });

      print("items ${itemsByDayAndType.length}");
      itemsByDayAndType.forEach((x) => print(x));

      // healthData.forEach((x) => print(x));
      return healthData;
    } catch (error) {
      print("Exception in getHealthDataFromTypes: $error");
    }
    return [];
  }

@pragma('vm:entry-point') // Mandatory if the App is obfuscated or using Flutter 3.1+
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized(); // https://github.com/flutter/flutter/issues/98473#issuecomment-1060952450
    // Still getting these errors, even when setting the above:
    // Exception in getHealthDataFromTypes: MissingPluginException(No implementation found for method getIosDeviceInfo on channel dev.fluttercommunity.plus/device_info)

    print("Native called background task: $task"); //simpleTask will be emitted here.
    await fetchHealthhData();
    return Future.value(true);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(
    callbackDispatcher, // The top level function, aka callbackDispatcher
    isInDebugMode: true // If enabled it will post a notification whenever the task is running. Handy for debugging tasks
  );
  runApp(HealthApp());
}

// void main() {
//   runApp(HealthApp());
// }


class HealthApp extends StatefulWidget {
  @override
  _HealthAppState createState() => _HealthAppState();
}

enum AppState {
  DATA_NOT_FETCHED,
  FETCHING_DATA,
  DATA_READY,
  NO_DATA,
  AUTH_NOT_GRANTED,
  DATA_ADDED,
  DATA_NOT_ADDED,
  STEPS_READY,
}

final androidTypes = [
  HealthDataType.STEPS,
  HealthDataType.WEIGHT,
  HealthDataType.BLOOD_GLUCOSE,
  HealthDataType.WORKOUT,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.BLOOD_GLUCOSE,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
  HealthDataType.MOVE_MINUTES, // Android only
  HealthDataType.DISTANCE_DELTA, // Android only
  HealthDataType.WORKOUT,
  HealthDataType.BODY_FAT_PERCENTAGE
];

// with coresponsing permissions
final androidPermissions = [
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
];

final iosTypes = [
  HealthDataType.STEPS,
  HealthDataType.WEIGHT,
  HealthDataType.BLOOD_GLUCOSE,
  HealthDataType.WORKOUT,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.BLOOD_GLUCOSE,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
  HealthDataType.EXERCISE_TIME, // iOS only
  HealthDataType.WORKOUT,
  HealthDataType.BASAL_ENERGY_BURNED, // iOS only
  HealthDataType.BODY_FAT_PERCENTAGE,
  HealthDataType.DISTANCE_WALKING_RUNNING // iOS only
];

// with coresponsing permissions
final iosPermissions = [
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
  HealthDataAccess.READ,
];

// TODO: create common data type for iOS and Android
// TODO: check for duplicates in each platform. Should we aggregate in the app, or in the api?
// TODO: Do we need to get things like ACTIVE_ENERGY_BURNED when they are also included on an exercise? Does that lead to double counting?
// How do we pass that to the API? Seems like in the app everything is associated to a workout except for steps.
// TODO: can we access the data in the background?

class _HealthAppState extends State<HealthApp> with WidgetsBindingObserver {
  List<HealthDataPoint> _healthDataList = [];
  AppState _state = AppState.DATA_NOT_FETCHED;
  int _nofSteps = 10;
  double _mgdl = 10.0;

  // create a HealthFactory for use in the app
  late AppLifecycleState _notification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print(state);

    if(state == AppLifecycleState.resumed) {
      _notification = state;
      Workmanager().registerOneOffTask(
        "task-identifier",
        "simpleTask",
        constraints: Constraints(
        // connected or metered mark the task as requiring internet
        networkType: NetworkType.connected
      ));
    }
  }

  /// Fetch data points from the health plugin and show them in the app.
  Future fetchData() async {
    setState(() => _state = AppState.FETCHING_DATA);
    //
    // The location permission is requested for Workouts using the Distance information.
    await Permission.activityRecognition.request();
    await Permission.location.request();

    var healthData = await fetchHealthhData();

      // healthData.forEach((x) => print(x));

    _healthDataList.addAll((healthData.length < 100)
        ? healthData
        : healthData.sublist(0, 100));

    // filter out duplicates
    _healthDataList = HealthFactory.removeDuplicates(_healthDataList);

    // update the UI to display the results
    setState(() {
      _state =
          _healthDataList.isEmpty ? AppState.NO_DATA : AppState.DATA_READY;
    });
  }

  /// Add some random health data.
  Future addData() async {
    final now = DateTime.now();
    final earlier = now.subtract(Duration(minutes: 20));

    final types = [
      HealthDataType.STEPS,
      HealthDataType.HEIGHT,
      HealthDataType.BLOOD_GLUCOSE,
      HealthDataType.WORKOUT, // Requires Google Fit on Android
      // Uncomment these lines on iOS - only available on iOS
      // HealthDataType.AUDIOGRAM,
    ];
    final rights = [
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
      // HealthDataAccess.WRITE
    ];
    final permissions = [
      HealthDataAccess.READ_WRITE,
      HealthDataAccess.READ_WRITE,
      HealthDataAccess.READ_WRITE,
      HealthDataAccess.READ_WRITE,
      // HealthDataAccess.READ_WRITE,
    ];
    late bool perm;
    bool? hasPermissions =
        await HealthFactory.hasPermissions(types, permissions: rights);
    if (hasPermissions == false) {
      perm = await health.requestAuthorization(types, permissions: permissions);
    }

    // Store a count of steps taken
    _nofSteps = Random().nextInt(10);
    bool success = await health.writeHealthData(
        _nofSteps.toDouble(), HealthDataType.STEPS, earlier, now);

    // Store a height
    success &=
        await health.writeHealthData(1.93, HealthDataType.HEIGHT, earlier, now);

    // Store a Blood Glucose measurement
    _mgdl = Random().nextInt(10) * 1.0;
    success &= await health.writeHealthData(
        _mgdl, HealthDataType.BLOOD_GLUCOSE, now, now);

    // Store a workout eg. running
    success &= await health.writeWorkoutData(
      HealthWorkoutActivityType.RUNNING, earlier, now,
      // The following are optional parameters
      // and the UNITS are functional on iOS ONLY!
      totalEnergyBurned: 230,
      totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      totalDistance: 1234,
      totalDistanceUnit: HealthDataUnit.FOOT,
    );

    // Store an Audiogram
    // Uncomment these on iOS - only available on iOS
    // const frequencies = [125.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0];
    // const leftEarSensitivities = [49.0, 54.0, 89.0, 52.0, 77.0, 35.0];
    // const rightEarSensitivities = [76.0, 66.0, 90.0, 22.0, 85.0, 44.5];

    // success &= await health.writeAudiogram(
    //   frequencies,
    //   leftEarSensitivities,
    //   rightEarSensitivities,
    //   now,
    //   now,
    //   metadata: {
    //     "HKExternalUUID": "uniqueID",
    //     "HKDeviceName": "bluetooth headphone",
    //   },
    // );

    setState(() {
      _state = success ? AppState.DATA_ADDED : AppState.DATA_NOT_ADDED;
    });
  }

  /// Fetch steps from the health plugin and show them in the app.
  Future fetchStepData() async {
    int? steps;

    // get steps for today (i.e., since midnight)
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    final now = DateTime.now();
    final yesterday_midnight = DateTime(yesterday.year, yesterday.month, yesterday.day);
    final today_midnight = DateTime(now.year, now.month, now.day);

    bool requested = await health.requestAuthorization([HealthDataType.STEPS]);

    if (requested) {
      try {
        steps = await health.getTotalStepsInInterval(yesterday_midnight, today_midnight);
      } catch (error) {
        print("Caught exception in getTotalStepsInInterval: $error");
      }

      print('Total number of steps: $steps');

      setState(() {
        _nofSteps = (steps == null) ? 0 : steps;
        _state = (steps == null) ? AppState.NO_DATA : AppState.STEPS_READY;
      });
    } else {
      print("Authorization not granted - error in authorization");
      setState(() => _state = AppState.DATA_NOT_FETCHED);
    }
  }

  Widget _contentFetchingData() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(
              strokeWidth: 10,
            )),
        Text('Fetching data...')
      ],
    );
  }

  Widget _contentDataReady() {
    return ListView.builder(
        itemCount: _healthDataList.length,
        itemBuilder: (_, index) {
          HealthDataPoint p = _healthDataList[index];
          if (p.value is AudiogramHealthValue) {
            return ListTile(
              title: Text("${p.typeString}: ${p.value}"),
              trailing: Text('${p.unitString}'),
              subtitle: Text('${p.dateFrom} - ${p.dateTo}'),
            );
          }
          if (p.value is WorkoutHealthValue) {
            return ListTile(
              title: Text(
                  "${p.typeString}: ${(p.value as WorkoutHealthValue).totalEnergyBurned} ${(p.value as WorkoutHealthValue).totalEnergyBurnedUnit?.typeToString()}"),
              trailing: Text(
                  '${(p.value as WorkoutHealthValue).workoutActivityType.typeToString()}'),
              subtitle: Text('${p.dateFrom} - ${p.dateTo}'),
            );
          }
          return ListTile(
            title: Text("${p.typeString}: ${p.value}"),
            trailing: Text('${p.unitString}'),
            subtitle: Text('${p.dateFrom} - ${p.dateTo}'),
          );
        });
  }

  Widget _contentNoData() {
    return Text('No Data to show');
  }

  Widget _contentNotFetched() {
    return Column(
      children: [
        Text('Press the download button to fetch data.'),
        Text('Press the plus button to insert some random data.'),
        Text('Press the walking button to get total step count.'),
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }

  Widget _authorizationNotGranted() {
    return Text('Authorization not given. '
        'For Android please check your OAUTH2 client ID is correct in Google Developer Console. '
        'For iOS check your permissions in Apple Health.');
  }

  Widget _dataAdded() {
    return Text('Data points inserted successfully!');
  }

  Widget _stepsFetched() {
    return Text('Total number of steps: $_nofSteps');
  }

  Widget _dataNotAdded() {
    return Text('Failed to add data');
  }

  Widget _content() {
    if (_state == AppState.DATA_READY)
      return _contentDataReady();
    else if (_state == AppState.NO_DATA)
      return _contentNoData();
    else if (_state == AppState.FETCHING_DATA)
      return _contentFetchingData();
    else if (_state == AppState.AUTH_NOT_GRANTED)
      return _authorizationNotGranted();
    else if (_state == AppState.DATA_ADDED)
      return _dataAdded();
    else if (_state == AppState.STEPS_READY)
      return _stepsFetched();
    else if (_state == AppState.DATA_NOT_ADDED) return _dataNotAdded();

    return _contentNotFetched();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Health Example'),
            actions: <Widget>[
              IconButton(
                icon: Icon(Icons.file_download),
                onPressed: () {
                  fetchData();
                },
              ),
              IconButton(
                onPressed: () {
                  addData();
                },
                icon: Icon(Icons.add),
              ),
              IconButton(
                onPressed: () {
                  fetchStepData();
                },
                icon: Icon(Icons.nordic_walking),
              )
            ],
          ),
          body: Center(
            child: _content(),
          )),
    );
  }
}
