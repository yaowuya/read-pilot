import 'package:sembast_web/sembast_web.dart';

Future<Database> openAppDatabase() =>
    databaseFactoryWeb.openDatabase('read-pilot-v1');
